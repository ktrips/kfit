import CoreMotion
import WatchKit
import Combine

@MainActor
class WatchMotionDetectionManager: NSObject, ObservableObject {
    @Published var repCount: Int = 0
    @Published var formScore: Double = 100.0
    @Published var isDetecting: Bool = false
    @Published var currentAcceleration: Double = 0.0
    @Published var heartRate: Int = 0
    @Published var plankElapsedSeconds: Int = 0  // プランクの経過秒数
    @Published var plankCompleted: Bool = false  // 45秒達成フラグ

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private var previousAcceleration: Double = 1.0  // 前回の加速度
    private var lastRepTime: Date = Date.distantPast  // 前回のrep時刻（連続検出防止）
    private var minRepInterval: TimeInterval = 0.8  // 最小rep間隔（秒）- スクワット/腹筋に適した間隔
    private var changeThreshold: Double = 0.08  // 加速度変化の閾値 - 適度な感度
    private var currentExerciseType: ExerciseType = .squat

    // プランク用タイマー
    private var plankTimer: Timer?
    private var plankStartTime: Date?
    private let plankTargetSeconds = 45

    func startDetection(for exerciseType: ExerciseType) {
        print("🔵 WatchMotion: startDetection for \(exerciseType.rawValue)")

        isDetecting = true
        currentExerciseType = exerciseType

        // プランクの場合はタイマーモード
        if exerciseType == .plank {
            startPlankTimer()
            return
        }

        // 通常の種目: モーションセンサー使用
        print("🔵 WatchMotion: Accelerometer available: \(motionManager.isAccelerometerAvailable)")
        print("🔵 WatchMotion: Gyro available: \(motionManager.isGyroAvailable)")
        print("🔵 WatchMotion: Device motion available: \(motionManager.isDeviceMotionAvailable)")

        if !motionManager.isAccelerometerAvailable {
            print("⚠️ Accelerometer not available - attempting to start anyway")
        }

        repCount = 0
        formScore = 100.0
        previousAcceleration = 1.0
        lastRepTime = Date.distantPast

        // iOSから受信した感度設定を適用（なければデフォルト）
        let exerciseIdString = exerciseTypeToId(exerciseType)
        if let customSensitivity = WatchConnectivityManager.shared.motionSensitivity[exerciseIdString] {
            minRepInterval = customSensitivity.minInterval
            changeThreshold = customSensitivity.threshold
            print("🔵 WatchMotion: Using custom sensitivity from iOS")
        } else {
            // デフォルト感度
            switch exerciseType {
            case .pushup:
                minRepInterval = 0.6
                changeThreshold = 0.06
            case .squat:
                minRepInterval = 0.7
                changeThreshold = 0.08
            case .situp:
                minRepInterval = 0.8
                changeThreshold = 0.10
            case .lunge:
                minRepInterval = 1.2
                changeThreshold = 0.15
            case .burpee:
                minRepInterval = 2.0
                changeThreshold = 0.20
            case .plank:
                break
            }
        }

        print("🔵 WatchMotion: Reset detection state - interval=\(minRepInterval)s, threshold=\(changeThreshold)")

        // デバイスモーションAPIを優先的に使用（Apple Watchでより安定）
        if motionManager.isDeviceMotionAvailable {
            print("🔵 WatchMotion: Using DeviceMotion API")
            motionManager.deviceMotionUpdateInterval = 0.02 // 50 Hz
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else {
                    if let error = error {
                        print("❌ WatchMotion: DeviceMotion error: \(error)")
                    }
                    return
                }

                let acceleration = sqrt(
                    data.userAcceleration.x * data.userAcceleration.x +
                    data.userAcceleration.y * data.userAcceleration.y +
                    data.userAcceleration.z * data.userAcceleration.z
                )

                self.currentAcceleration = acceleration
                self.detectRepWatch(acceleration: acceleration, exerciseType: exerciseType)

                // ジャイロも同時に取得
                let gyroMagnitude = sqrt(
                    data.rotationRate.x * data.rotationRate.x +
                    data.rotationRate.y * data.rotationRate.y +
                    data.rotationRate.z * data.rotationRate.z
                )
                let rotationPenalty = min(50, gyroMagnitude * 10)
                self.formScore = max(60, 100 - rotationPenalty)
            }
            print("✅ WatchMotion: DeviceMotion updates started")
        } else {
            // フォールバック: 従来の加速度計API
            print("🔵 WatchMotion: Using Accelerometer API (fallback)")
            motionManager.accelerometerUpdateInterval = 0.02
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else {
                    if let error = error {
                        print("❌ WatchMotion: Accelerometer error: \(error)")
                    }
                    return
                }

                let acceleration = sqrt(
                    data.acceleration.x * data.acceleration.x +
                    data.acceleration.y * data.acceleration.y +
                    data.acceleration.z * data.acceleration.z
                )

                self.currentAcceleration = acceleration
                self.detectRepWatch(acceleration: acceleration, exerciseType: exerciseType)
            }
            print("✅ WatchMotion: Accelerometer updates started")
        }

        print("✅ WatchMotion: Detection started successfully")
    }


    func stopDetection() {
        print("🔵 WatchMotion: stopDetection - finalRepCount=\(repCount), plankSeconds=\(plankElapsedSeconds)")
        isDetecting = false
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        accelerationBuffer.removeAll()
        peakDetected = false

        // プランクタイマー停止
        stopPlankTimer()
    }

    // MARK: - Plank Timer

    private func startPlankTimer() {
        print("🔵 WatchMotion: Starting plank timer")
        plankElapsedSeconds = 0
        plankCompleted = false
        plankStartTime = Date()

        // 1秒ごとに更新
        plankTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updatePlankTimer()
            }
        }
    }

    private func updatePlankTimer() {
        guard let startTime = plankStartTime else { return }
        plankElapsedSeconds = Int(Date().timeIntervalSince(startTime))

        print("⏱️ Plank: \(plankElapsedSeconds)s / \(plankTargetSeconds)s")

        // 45秒達成
        if plankElapsedSeconds >= plankTargetSeconds && !plankCompleted {
            plankCompleted = true
            print("🎉 Plank completed! Good job!")

            // Haptic feedback - 強力なフィードバック（4回連続）
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                WKInterfaceDevice.current().play(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.success)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func stopPlankTimer() {
        plankTimer?.invalidate()
        plankTimer = nil
        plankStartTime = nil
    }

    private var accelerationBuffer: [Double] = []
    private var peakDetected: Bool = false
    private let bufferSize = 5  // 0.1秒分のバッファ（50Hz × 0.1 = 5サンプル）← より反応を早く

    private func detectRepWatch(acceleration: Double, exerciseType: ExerciseType) {
        let now = Date()
        let timeSinceLastRep = now.timeIntervalSince(lastRepTime)

        // バッファに追加
        accelerationBuffer.append(acceleration)
        if accelerationBuffer.count > bufferSize {
            accelerationBuffer.removeFirst()
        }

        // バッファが満たされてから検出開始
        guard accelerationBuffer.count >= bufferSize else { return }

        // 移動平均で平滑化（ノイズ除去）
        let smoothedAcceleration = accelerationBuffer.reduce(0, +) / Double(accelerationBuffer.count)
        let change = abs(smoothedAcceleration - previousAcceleration)

        // ピーク検出を緩和: 現在値が直前より大きいだけでOK（スクワット・腕立て用）
        let isLocalPeak: Bool
        if exerciseType == .squat || exerciseType == .pushup {
            // より緩い条件: 直前のサンプルより大きければOK
            isLocalPeak = accelerationBuffer.count >= 2 &&
                          smoothedAcceleration > accelerationBuffer[accelerationBuffer.count - 2]
        } else {
            // 他の種目: 従来通り
            isLocalPeak = accelerationBuffer.count >= 3 &&
                          smoothedAcceleration > accelerationBuffer[accelerationBuffer.count - 2] &&
                          smoothedAcceleration > accelerationBuffer[accelerationBuffer.count - 3]
        }

        // 十分な変化 + ピーク + 最小間隔が経過
        if change > changeThreshold && isLocalPeak && timeSinceLastRep > minRepInterval && !peakDetected {
            repCount += 1
            peakDetected = true

            // フォームスコア: 変化量と一貫性で評価（緩く）
            let consistency = calculateConsistency(buffer: accelerationBuffer)
            formScore = max(75, min(100, 100 - (change * 10) + (consistency * 5)))

            lastRepTime = now

            print("✅ WatchMotion: Rep #\(repCount) (\(exerciseType.rawValue)) | change=\(String(format: "%.3f", change)) | smooth=\(String(format: "%.3f", smoothedAcceleration)) | score=\(Int(formScore))")

            // Haptic feedback
            WKInterfaceDevice.current().play(.success)
        }

        // ピーク後に加速度が下がったらリセット（より敏感に）
        if peakDetected && smoothedAcceleration < previousAcceleration - 0.02 {
            peakDetected = false
        }

        // 現在の加速度を保存
        previousAcceleration = smoothedAcceleration

        // デバッグログ（2秒に1回）
        let currentTime = now.timeIntervalSince1970
        if Int(currentTime * 5) % 10 == 0 {
            print("📊 WatchMotion: acc=\(String(format: "%.3f", smoothedAcceleration)), change=\(String(format: "%.3f", change)), threshold=\(String(format: "%.3f", changeThreshold)), reps=\(repCount), peak=\(peakDetected)")
        }
    }

    private func calculateConsistency(buffer: [Double]) -> Double {
        guard buffer.count > 1 else { return 1.0 }
        let mean = buffer.reduce(0, +) / Double(buffer.count)
        let variance = buffer.map { pow($0 - mean, 2) }.reduce(0, +) / Double(buffer.count)
        let stdDev = sqrt(variance)
        return max(0.0, 1.0 - stdDev)
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }

    // ExerciseTypeをIDに変換
    private func exerciseTypeToId(_ type: ExerciseType) -> String {
        switch type {
        case .pushup: return "pushup"
        case .squat: return "squat"
        case .situp: return "situp"
        case .lunge: return "lunge"
        case .burpee: return "burpee"
        case .plank: return "plank"
        }
    }
}

enum ExerciseType: String, CaseIterable {
    case pushup = "Push-up"
    case squat  = "Squat"
    case situp  = "Sit-up"
    case lunge  = "Lunge"
    case burpee = "Burpee"
    case plank  = "Plank"

    var icon: String {
        switch self {
        case .pushup: return "💪"
        case .squat:  return "🏋️"
        case .situp:  return "🔥"
        case .lunge:  return "🦵"
        case .burpee: return "⚡"
        case .plank:  return "🧘"
        }
    }

    var xpPerRep: Int {
        switch self {
        case .pushup, .squat, .lunge: return 2
        case .situp:                  return 1
        case .burpee:                 return 5
        case .plank:                  return 3  // 45秒で3 XP
        }
    }

    var isTimeBased: Bool {
        return self == .plank
    }
}
