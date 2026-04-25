import WatchConnectivity
import Foundation

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var isWatchAppInstalled = false
    @Published var lastWorkout: WorkoutData?

    private var session: WCSession?

    override init() {
        super.init()
        setupWatchConnectivity()
    }

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            isWatchAppInstalled = session?.isPaired ?? false && session?.isWatchAppInstalled ?? false
        }
    }

    func sendWorkout(_ workout: WorkoutData) {
        guard let session = session, session.isReachable else {
            print("Watch not reachable")
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(workout)
            let dict: [String: Any] = ["workout": data]
            session.sendMessage(dict, replyHandler: nil)
        } catch {
            print("Error sending workout: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation error: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let workoutData = message["workout"] as? Data {
            do {
                let decoder = JSONDecoder()
                let workout = try decoder.decode(WorkoutData.self, from: workoutData)
                DispatchQueue.main.async {
                    self.lastWorkout = workout
                }
            } catch {
                print("Error decoding workout: \(error)")
            }
        }
    }
}

struct WorkoutData: Codable {
    let exerciseName: String
    let reps: Int
    let points: Int
    let timestamp: Date
}
