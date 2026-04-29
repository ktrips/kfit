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
    private let peakThreshold: Double = 1.2
    private let bufferSize = 5

    func startDetection(for exerciseType: ExerciseType) {
        guard motionManager.isAccelerometerAvailable && motionManager.isGyroAvailable else {
            print("Motion sensors not available")
            return
        }

        isDetecting = true
        repCount = 0
        formScore = 100.0
        accelerationBuffer = []

        motionManager.accelerometerUpdateInterval = 0.05 // 20 Hz (lower for watch battery)
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            let acceleration = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )

            self.currentAcceleration = acceleration
            self.detectRepWatch(acceleration: acceleration, exerciseType: exerciseType)
        }

        // Also start gyro for form quality
        motionManager.gyroUpdateInterval = 0.05
        motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            self.analyzeFormQuality(gyroData: data)
        }
    }

    func calibrate() {
        guard motionManager.isAccelerometerAvailable else { return }

        var readings: [Double] = []
        var calibrationCount = 0
        let calibrationSamples = 15

        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }

            let acceleration = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )

            readings.append(acceleration)
            calibrationCount += 1

            if calibrationCount >= calibrationSamples {
                self.baselineAcceleration = readings.reduce(0, +) / Double(readings.count)
                self.motionManager.stopAccelerometerUpdates()
                print("Calibration complete. Baseline: \(self.baselineAcceleration)")
            }
        }
    }

    func stopDetection() {
        isDetecting = false
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        accelerationBuffer = []
    }

    private func detectRepWatch(acceleration: Double, exerciseType: ExerciseType) {
        // Use circular buffer for smoother detection
        accelerationBuffer.append(acceleration)
        if accelerationBuffer.count > bufferSize {
            accelerationBuffer.removeFirst()
        }

        // Calculate moving average
        let avgAcceleration = accelerationBuffer.reduce(0, +) / Double(accelerationBuffer.count)

        // Detect peak
        let threshold = baselineAcceleration + peakThreshold
        if avgAcceleration > threshold && !peakDetected {
            peakDetected = true
        } else if avgAcceleration < (baselineAcceleration + 0.3) && peakDetected {
            // Rep completed
            repCount += 1
            formScore = max(50, min(100, 100 - (abs(avgAcceleration - baselineAcceleration) * 5)))
            peakDetected = false

            // Haptic feedback
            WKInterfaceDevice.current().play(.notification)
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
