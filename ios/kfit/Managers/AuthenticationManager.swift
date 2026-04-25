import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isSignedIn = false
    @Published var userProfile: UserProfile?
    @Published var exercises: [Exercise] = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        setupAuthStateListener()
    }

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    self?.isSignedIn = true
                    await self?.loadUserProfile(userId: user.uid)
                    await self?.loadExercises()
                } else {
                    self?.isSignedIn = false
                    self?.userProfile = nil
                }
            }
        }
    }

    func signInWithGoogle() async -> Bool {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Firebase Client ID"
            return false
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let window = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            errorMessage = "No window scene"
            return false
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window.windows.first?.rootViewController ?? UIViewController())
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Failed to get ID token"
                return false
            }

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            let authResult = try await Auth.auth().signIn(with: credential)

            await createOrUpdateUserProfile(user: authResult.user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            isSignedIn = false
            userProfile = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createOrUpdateUserProfile(user: User) async {
        let userRef = db.collection("users").document(user.uid)

        do {
            let doc = try await userRef.getDocument()
            if !doc.exists {
                let profile = UserProfile(
                    uid: user.uid,
                    email: user.email ?? "",
                    username: user.displayName ?? "User",
                    totalPoints: 0,
                    streak: 0,
                    joinDate: Date(),
                    lastActiveDate: Date()
                )
                try await userRef.setData(from: profile)
            }
            await loadUserProfile(userId: user.uid)
        } catch {
            errorMessage = "Failed to create user profile: \(error.localizedDescription)"
        }
    }

    private func loadUserProfile(userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            if let profile = try doc.data(as: UserProfile.self) {
                self.userProfile = profile
            }
        } catch {
            errorMessage = "Failed to load user profile: \(error.localizedDescription)"
        }
    }

    private func loadExercises() async {
        do {
            let snapshot = try await db.collection("exercises").getDocuments()
            self.exercises = try snapshot.documents.compactMap { doc in
                try doc.data(as: Exercise.self)
            }
        } catch {
            errorMessage = "Failed to load exercises: \(error.localizedDescription)"
        }
    }

    func recordExercise(_ exercise: Exercise, reps: Int, formScore: Double = 85.0) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let data: [String: Any] = [
            "exerciseId": exercise.id,
            "exerciseName": exercise.name,
            "reps": reps,
            "points": reps * exercise.basePoints,
            "formScore": formScore,
            "timestamp": Date()
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("completed-exercises").addDocument(data: data)

            if var profile = userProfile {
                profile.totalPoints += reps * exercise.basePoints
                profile.lastActiveDate = Date()
                self.userProfile = profile
            }
        } catch {
            errorMessage = "Failed to record exercise: \(error.localizedDescription)"
        }
    }

    func getTodayExercises() async -> [CompletedExercise] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("completed-exercises")
                .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
                .whereField("timestamp", isLessThan: endOfDay)
                .getDocuments()

            return try snapshot.documents.compactMap { doc in
                try doc.data(as: CompletedExercise.self)
            }
        } catch {
            errorMessage = "Failed to load today's exercises: \(error.localizedDescription)"
            return []
        }
    }

    deinit {
        if let authStateHandle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }
}

// MARK: - Models
struct UserProfile: Codable {
    @DocumentID var id: String?
    var uid: String
    var email: String
    var username: String
    var totalPoints: Int
    var streak: Int
    var joinDate: Date
    var lastActiveDate: Date
}

struct Exercise: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var description: String
    var difficulty: String
    var muscleGroups: [String]
    var basePoints: Int
    var caloriesPerRep: Double
    var motionProfile: MotionProfile?
    var formTips: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, description, difficulty, muscleGroups, basePoints, caloriesPerRep, motionProfile, formTips
    }
}

struct MotionProfile: Codable {
    var type: String
    var primaryAxis: String
    var detectionMethod: String
    var threshold: Double
}

struct CompletedExercise: Codable, Identifiable {
    @DocumentID var id: String?
    var exerciseId: String
    var exerciseName: String
    var reps: Int
    var points: Int
    var formScore: Double
    var timestamp: Date
}
