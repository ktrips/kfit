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

    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private var baselineAcceleration: Double = 0.0
    private var accelerationBuffer: [Double] = []
    private var peakDetected = false
    private let peakThreshold: Double = 0.15  // さらに下げて検出しやすく
    private let bufferSize = 3  // バッファサイズを小さくして反応を早く
    private var lastRepTime: Date = Date.distantPast  // 前回のrep時刻（連続検出防止）
    private let minRepInterval: TimeInterval = 0.5  // 最小rep間隔（秒）

    func startDetection(for exerciseType: ExerciseType) {
        guard motionManager.isAccelerometerAvailable && motionManager.isGyroAvailable else {
            print("⚠️ Motion sensors not available")
            return
        }

        print("🔵 WatchMotion: startDetection for \(exerciseType.rawValue)")
        isDetecting = true
        repCount = 0
        formScore = 100.0
        accelerationBuffer = []
        peakDetected = false

        // デフォルトのベースライン（重力加速度: 1G = 9.81 m/s²）
        // Apple Watchの加速度は重力の倍数で表現される（1.0 = 1G）
        if baselineAcceleration == 0.0 {
            baselineAcceleration = 1.0  // 静止時の重力
            print("🔵 WatchMotion: Using default baseline = 1.0G")
        }

        motionManager.accelerometerUpdateInterval = 0.05 // 20 Hz (lower for watch battery)
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

        // Also start gyro for form quality
        motionManager.gyroUpdateInterval = 0.05
        motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else {
                if let error = error {
                    print("❌ WatchMotion: Gyro error: \(error)")
                }
                return
            }
            self.analyzeFormQuality(gyroData: data)
        }

        print("✅ WatchMotion: Detection started successfully")
    }


    func stopDetection() {
        print("🔵 WatchMotion: stopDetection - finalRepCount=\(repCount)")
        isDetecting = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }

    private func detectRepWatch(acceleration: Double, exerciseType: ExerciseType) {
        // 前回との加速度変化を計算
        let change = abs(acceleration - previousAcceleration)

        // 最低2サンプルあれば検出開始（より早く反応）
        guard accelerationBuffer.count >= 2 else { return }

        // Calculate moving average
        let avgAcceleration = accelerationBuffer.reduce(0, +) / Double(accelerationBuffer.count)

        // より単純な検出ロジック：絶対値の変化を見る
        let delta = abs(avgAcceleration - baselineAcceleration)

        // 連続検出防止：前回のrepから最小間隔が経過しているか
        let now = Date()
        let timeSinceLastRep = now.timeIntervalSince(lastRepTime)

        // 動きの変化が閾値を超え、かつ最小間隔が経過している
        if delta > peakThreshold && timeSinceLastRep > minRepInterval {
            // ピーク/谷の区別なく、大きな変化があればカウント
            if !peakDetected {
                peakDetected = true
            } else {
                // 2回目の大きな変化 = 1rep完了
                repCount += 1
                formScore = max(60, min(100, 100 - (delta * 20)))
                peakDetected = false
                lastRepTime = now

                print("✅ WatchMotion: Rep #\(repCount) detected! delta=\(String(format: "%.2f", delta)), acc=\(String(format: "%.2f", avgAcceleration))")

                // Haptic feedback
                WKInterfaceDevice.current().play(.notification)
            }
        }

        // デバッグ：加速度の値を頻繁にログ（5回に1回）
        if accelerationBuffer.count % 5 == 0 {
            print("📊 WatchMotion: acc=\(String(format: "%.2f", avgAcceleration)), baseline=\(String(format: "%.2f", baselineAcceleration)), delta=\(String(format: "%.2f", delta)), peak=\(peakDetected), reps=\(repCount)")
        }
    }

    private func analyzeFormQuality(gyroData: CMGyroData) {
        let gyroMagnitude = sqrt(
            gyroData.rotationRate.x * gyroData.rotationRate.x +
            gyroData.rotationRate.y * gyroData.rotationRate.y +
            gyroData.rotationRate.z * gyroData.rotationRate.z
        )

        // Lower rotation = better form stability
        let rotationPenalty = min(50, gyroMagnitude * 10)
        formScore = max(60, 100 - rotationPenalty)
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

enum ExerciseType: String, CaseIterable {
    case pushup = "Push-up"
    case squat  = "Squat"
    case situp  = "Sit-up"
    case lunge  = "Lunge"
    case burpee = "Burpee"
    // plank は時間計測のため除外

    var icon: String {
        switch self {
        case .pushup: return "💪"
        case .squat:  return "🏋️"
        case .situp:  return "🔥"
        case .lunge:  return "🦵"
        case .burpee: return "⚡"
        }
    }

    var xpPerRep: Int {
        switch self {
        case .pushup, .squat, .lunge: return 2
        case .situp:                  return 1
        case .burpee:                 return 5
        }
    }
}
