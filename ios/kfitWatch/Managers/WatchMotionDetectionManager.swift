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
    private var previousAcceleration: Double = 1.0  // 前回の加速度
    private var lastRepTime: Date = Date.distantPast  // 前回のrep時刻（連続検出防止）
    private let minRepInterval: TimeInterval = 0.25  // 最小rep間隔（秒）
    private let changeThreshold: Double = 0.07  // 加速度変化の閾値（感度高め）

    func startDetection(for exerciseType: ExerciseType) {
        guard motionManager.isAccelerometerAvailable && motionManager.isGyroAvailable else {
            print("⚠️ Motion sensors not available")
            return
        }

        print("🔵 WatchMotion: startDetection for \(exerciseType.rawValue)")
        isDetecting = true
        repCount = 0
        formScore = 100.0
        previousAcceleration = 1.0
        lastRepTime = Date.distantPast
        print("🔵 WatchMotion: Reset detection state")

        motionManager.accelerometerUpdateInterval = 0.033 // 30 Hz
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
        motionManager.gyroUpdateInterval = 0.033
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

        let now = Date()
        let timeSinceLastRep = now.timeIntervalSince(lastRepTime)

        // 十分な変化があり、かつ最小間隔が経過している場合にカウント
        if change > changeThreshold && timeSinceLastRep > minRepInterval {
            repCount += 1
            formScore = max(60, min(100, 100 - (change * 30)))
            lastRepTime = now

            print("✅ WatchMotion: Rep #\(repCount) detected! change=\(String(format: "%.3f", change)), acc=\(String(format: "%.3f", acceleration)), prev=\(String(format: "%.3f", previousAcceleration))")

            // Haptic feedback
            WKInterfaceDevice.current().play(.click)
        }

        // 現在の加速度を保存
        previousAcceleration = acceleration

        // 定期的にデバッグログ出力（2秒に1回）
        let currentTime = now.timeIntervalSince1970
        if Int(currentTime * 10) % 20 == 0 {
            print("📊 WatchMotion: acc=\(String(format: "%.3f", acceleration)), change=\(String(format: "%.3f", change)), threshold=\(String(format: "%.3f", changeThreshold)), reps=\(repCount)")
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
