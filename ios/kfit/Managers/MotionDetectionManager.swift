import CoreMotion
import Combine

/// センサーコールバックを専用バックグラウンドキューで受信し、
/// UIスレッド（MainActor）をブロックしない設計。
/// 50Hzのコールバック内では加速度の大きさのみ計算し、
/// 状態更新（@Published 書き込み）だけ DispatchQueue.main で行う。
@MainActor
class MotionDetectionManager: NSObject, ObservableObject {
    @Published var repCount: Int = 0
    @Published var formScore: Double = 100.0
    @Published var isDetecting: Bool = false
    @Published var currentAcceleration: Double = 0.0

    private let motionManager = CMMotionManager()
    private var baselineAcceleration: Double = 0.0
    private var accelerationPeaks: [Double] = []
    private let peakThreshold: Double = 1.15
    private let repThreshold: Double = 0.3

    /// センサーコールバック専用キュー（UIスレッドをブロックしない）
    private let sensorQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.kfit.motionSensor"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()

    func startDetection(for exerciseType: ExerciseType) {
        guard motionManager.isAccelerometerAvailable else { return }

        // 二重起動防止
        motionManager.stopAccelerometerUpdates()

        isDetecting = true
        repCount = 0
        formScore = 100.0
        accelerationPeaks = []

        motionManager.accelerometerUpdateInterval = 0.02 // 50 Hz
        // コールバックをバックグラウンドキューで受信（UIスレッド非ブロック）
        motionManager.startAccelerometerUpdates(to: sensorQueue) { [weak self] data, _ in
            guard let data else { return }
            // 加速度の大きさをバックグラウンドで計算
            let accel = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )
            // 状態更新はメインスレッドで（@Published の要件）
            DispatchQueue.main.async { [weak self] in
                self?.detectRep(acceleration: accel, exerciseType: exerciseType)
            }
        }
    }

    func calibrate() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.stopAccelerometerUpdates()
        motionManager.accelerometerUpdateInterval = 0.1
        var readings: [Double] = []

        motionManager.startAccelerometerUpdates(to: sensorQueue) { [weak self] data, _ in
            guard let data else { return }
            let accel = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )
            readings.append(accel)

            if readings.count > 20 {
                let baseline = readings.reduce(0, +) / Double(readings.count)
                DispatchQueue.main.async { [weak self] in
                    self?.baselineAcceleration = baseline
                    self?.motionManager.stopAccelerometerUpdates()
                }
            }
        }
    }

    func stopDetection() {
        isDetecting = false
        motionManager.stopAccelerometerUpdates()
        accelerationPeaks = []
    }

    private func detectRep(acceleration: Double, exerciseType: ExerciseType) {
        currentAcceleration = acceleration

        let threshold = baselineAcceleration + (peakThreshold * 0.35)

        if acceleration > threshold {
            accelerationPeaks.append(acceleration)
        } else if !accelerationPeaks.isEmpty && acceleration < baselineAcceleration + 0.2 {
            detectRepCompletion()
        }
    }

    private func detectRepCompletion() {
        guard !accelerationPeaks.isEmpty else { return }

        let peak = accelerationPeaks.max() ?? 0
        let consistency = calculateConsistency()

        if peak > peakThreshold * 0.8 {
            repCount += 1
            formScore = max(70.0, min(100.0, consistency * 100))
        }

        accelerationPeaks = []
    }

    private func calculateConsistency() -> Double {
        guard accelerationPeaks.count > 1 else { return 1.0 }

        let mean = accelerationPeaks.reduce(0, +) / Double(accelerationPeaks.count)
        let variance = accelerationPeaks.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerationPeaks.count)
        let stdDev = sqrt(variance)

        return max(0.5, 1.0 - (stdDev / mean * 0.5))
    }
}

enum ExerciseType: String, CaseIterable {
    case pushup  = "pushup"
    case squat   = "squat"
    case situp   = "situp"
    case lunge   = "lunge"
    case burpee  = "burpee"
    // plank は時間計測のため除外

    /// Firestore の exerciseId / 名前から最近似の ExerciseType を返す
    static func from(exerciseId: String) -> ExerciseType {
        let id = exerciseId.lowercased()
        if id.contains("squat")  { return .squat  }
        if id.contains("sit")    { return .situp  }
        if id.contains("lunge")  { return .lunge  }
        if id.contains("burpee") { return .burpee }
        return .pushup  // push-up / その他のデフォルト
    }

    var icon: String {
        switch self {
        case .pushup: return "💪"
        case .squat:  return "🏋️"
        case .situp:  return "🔥"
        case .lunge:  return "🦵"
        case .burpee: return "⚡"
        }
    }
}
