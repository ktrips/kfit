import CoreMotion
import Combine

@MainActor
class MotionDetectionManager: NSObject, ObservableObject {
    @Published var repCount: Int = 0
    @Published var formScore: Double = 100.0
    @Published var isDetecting: Bool = false
    @Published var currentAcceleration: Double = 0.0

    private let motionManager = CMMotionManager()
    private var baselineAcceleration: Double = 0.0
    private var accelerationPeaks: [Double] = []
    private let peakThreshold: Double = 1.15  // 1.5から大幅に下げて高感度化
    private let repThreshold: Double = 0.3    // 0.5から下げて小さな動きも検出

    func startDetection(for exerciseType: ExerciseType) {
        guard motionManager.isAccelerometerAvailable else { return }

        isDetecting = true
        repCount = 0
        formScore = 100.0
        accelerationPeaks = []

        motionManager.accelerometerUpdateInterval = 0.02 // 50 Hz
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            let acceleration = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )

            self.detectRep(acceleration: acceleration, exerciseType: exerciseType)
        }
    }

    func calibrate() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.1
        var readings: [Double] = []

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }

            let acceleration = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )

            readings.append(acceleration)

            if readings.count > 20 {
                self.baselineAcceleration = readings.reduce(0, +) / Double(readings.count)
                self.motionManager.stopAccelerometerUpdates()
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

        // Detect if acceleration exceeds threshold（より低い閾値で検出）
        let threshold = baselineAcceleration + (peakThreshold * 0.35)  // 0.5から0.35に下げる

        if acceleration > threshold {
            accelerationPeaks.append(acceleration)
        } else if !accelerationPeaks.isEmpty && acceleration < baselineAcceleration + 0.2 {  // 0.3から0.2に
            // Peak detected and acceleration returned to baseline
            detectRepCompletion()
        }
    }

    private func detectRepCompletion() {
        guard !accelerationPeaks.isEmpty else { return }

        let peak = accelerationPeaks.max() ?? 0
        let consistency = calculateConsistency()

        // より低い閾値でもカウント
        if peak > peakThreshold * 0.8 {  // 完全な閾値でなく80%でもOK
            repCount += 1

            // Calculate form score based on consistency（緩めに評価）
            formScore = max(70.0, min(100.0, consistency * 100))

            // Reset for next rep
            accelerationPeaks = []
        }
    }

    private func calculateConsistency() -> Double {
        guard accelerationPeaks.count > 1 else { return 1.0 }

        let mean = accelerationPeaks.reduce(0, +) / Double(accelerationPeaks.count)
        let variance = accelerationPeaks.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerationPeaks.count)
        let stdDev = sqrt(variance)

        // Lower std dev = better consistency
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
