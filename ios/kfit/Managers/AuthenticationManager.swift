import FirebaseAuth
import FirebaseCore
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
    private var profileListener: ListenerRegistration?

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
            profileListener?.remove()
            profileListener = nil
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
        // Cancel any existing listener before creating a new one
        profileListener?.remove()
        profileListener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, snapshot.exists else { return }
                self.userProfile = try? snapshot.data(as: UserProfile.self)
            }
    }

    private func loadExercises() async {
        do {
            let snapshot = try await db.collection("exercises").getDocuments()
            let loaded = snapshot.documents.compactMap { doc -> Exercise? in
                try? doc.data(as: Exercise.self)
            }
            if loaded.isEmpty {
                await seedDefaultExercises()
            } else {
                self.exercises = loaded
            }
        } catch {
            self.exercises = Self.defaultExerciseData.map {
                Exercise(name: $0.name, basePoints: $0.pts)
            }
        }
    }

    private func seedDefaultExercises() async {
        do {
            for item in Self.defaultExerciseData {
                try await db.collection("exercises").document(item.id).setData([
                    "name": item.name,
                    "basePoints": item.pts,
                    "difficulty": "medium",
                    "muscleGroups": []
                ])
            }
            let snapshot = try await db.collection("exercises").getDocuments()
            self.exercises = snapshot.documents.compactMap { try? $0.data(as: Exercise.self) }
        } catch {
            self.exercises = Self.defaultExerciseData.map {
                Exercise(name: $0.name, basePoints: $0.pts)
            }
        }
    }

    static let defaultExerciseData: [(id: String, name: String, pts: Int)] = [
        ("pushup",  "Push-up",     2),
        ("squat",   "Squat",       2),
        ("situp",   "Sit-up",      1),
        ("lunge",   "Lunge",       2),
        ("burpee",  "Burpee",      5),
        ("plank",   "Plank (sec)", 1),
    ]

    // Records exercise and updates streak/points client-side
    // (Cloud Function will override if deployed)
    func recordExercise(_ exercise: Exercise, reps: Int, formScore: Double = 85.0) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let now   = Date()
        let points = reps * exercise.basePoints
        let data: [String: Any] = [
            "exerciseId":   exercise.id as Any,
            "exerciseName": exercise.name,
            "reps":         reps,
            "points":       points,
            "formScore":    formScore,
            "timestamp":    now
        ]

        do {
            try await db.collection("users").document(userId)
                .collection("completed-exercises").addDocument(data: data)

            // クライアント側でストリーク・ポイントを更新（Cloud Functions 未デプロイでも動作）
            await updateStreakAndPoints(userId: userId, points: points, now: now)

            // トレーニング記録 → 今日不要な通知をキャンセル
            NotificationManager.shared.handleWorkoutRecorded()
        } catch {
            errorMessage = "Failed to record exercise: \(error.localizedDescription)"
        }
    }

    private func updateStreakAndPoints(userId: String, points: Int, now: Date) async {
        let userRef = db.collection("users").document(userId)
        guard let doc = try? await userRef.getDocument(), doc.exists else { return }
        let profile = doc.data() ?? [:]

        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: now)

        var newStreak = profile["streak"] as? Int ?? 0

        if let lastTs = profile["lastActiveDate"] as? Timestamp {
            let lastDay  = calendar.startOfDay(for: lastTs.dateValue())
            let diffDays = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if diffDays == 0 {
                // 同日 — streak はそのまま、ポイントだけ加算
            } else if diffDays <= 3 {
                newStreak += 1  // 週2チートデイ許容
            } else {
                newStreak = 1   // streak リセット
            }
        } else {
            newStreak = 1       // 初回記録
        }

        try? await userRef.updateData([
            "streak":         newStreak,
            "totalPoints":    FieldValue.increment(Int64(points)),
            "lastActiveDate": Timestamp(date: now),
        ])
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

    // MARK: - Apple Watch からのワークアウトを Firestore に記録
    func recordWatchWorkout(_ workout: WatchWorkoutData) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "exerciseId":   "watch",
            "exerciseName": workout.exerciseName,
            "reps":         workout.reps,
            "points":       workout.points,
            "formScore":    85.0,
            "timestamp":    workout.timestamp,
            "source":       "watch"
        ]
        try? await db.collection("users").document(userId)
            .collection("completed-exercises").addDocument(data: data)
        await updateStreakAndPoints(userId: userId, points: workout.points, now: workout.timestamp)
    }

    // MARK: - Direct record (for WorkoutPlanView)
    func recordExerciseDirect(exerciseId: String, exerciseName: String, reps: Int, points: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let data: [String: Any] = [
            "exerciseId": exerciseId, "exerciseName": exerciseName,
            "reps": reps, "points": points, "formScore": 85.0, "timestamp": now
        ]
        try? await db.collection("users").document(userId)
            .collection("completed-exercises").addDocument(data: data)
        await updateStreakAndPoints(userId: userId, points: points, now: now)
        NotificationManager.shared.handleWorkoutRecorded()
    }

    // MARK: - History
    func getRecentExercises(days: Int = 14) async -> [DayExercises] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        let end   = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()

        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: start)
            .whereField("timestamp", isLessThan: end)
            .getDocuments() else { return [] }

        var byDay: [String: [CompletedExercise]] = [:]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        for doc in snapshot.documents {
            if let ex = try? doc.data(as: CompletedExercise.self) {
                let key = formatter.string(from: ex.timestamp)
                byDay[key, default: []].append(ex)
            }
        }

        var result: [DayExercises] = []
        for i in 1..<days {
            let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date())) ?? Date()
            let key = formatter.string(from: date)
            let exs = byDay[key] ?? []
            if !exs.isEmpty {
                let month = calendar.component(.month, from: date)
                let day   = calendar.component(.day, from: date)
                let label = i == 1 ? "昨日" : "\(month)/\(day)"
                result.append(DayExercises(date: key, label: label, exercises: exs,
                                           totalReps: exs.reduce(0) { $0 + $1.reps },
                                           totalPoints: exs.reduce(0) { $0 + $1.points }))
            }
        }
        return result
    }

    // MARK: - Daily Sets
    /// 今日のセット状況（30分間隔でセッションを分割し、午前/午後を判定）
    func getDailySets() async -> DailySets {
        guard let userId = Auth.auth().currentUser?.uid else {
            return DailySets(amSets: 0, pmSets: 0)
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay   = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments() else { return DailySets(amSets: 0, pmSets: 0) }

        let timestamps: [Date] = snapshot.documents
            .compactMap { try? $0.data(as: CompletedExercise.self) }
            .map { $0.timestamp }
            .sorted()

        // 30分以上の間隔 → 新セッションとみなす
        var sessions: [Date] = []
        var lastTime: Date? = nil
        for ts in timestamps {
            if let last = lastTime, ts.timeIntervalSince(last) <= 30 * 60 {
                // 同セッション内 — スキップ
            } else {
                sessions.append(ts)
            }
            lastTime = ts
        }

        let noon   = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let amSets = sessions.filter { $0 < noon }.count
        let pmSets = sessions.filter { $0 >= noon }.count
        return DailySets(amSets: amSets, pmSets: pmSets)
    }

    // MARK: - Weekly Goals
    func getWeeklyGoals() async -> [WeeklyGoal] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        let weekId = currentWeekId()
        guard let doc = try? await db.collection("users").document(userId)
            .collection("weekly-goals").document(weekId).getDocument(),
              doc.exists, let arr = doc.data()?["goals"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d -> WeeklyGoal? in
            guard let eid = d["exerciseId"] as? String,
                  let ename = d["exerciseName"] as? String,
                  let daily = d["dailyReps"] as? Int,
                  let target = d["targetReps"] as? Int else { return nil }
            return WeeklyGoal(exerciseId: eid, exerciseName: ename, dailyReps: daily, targetReps: target)
        }
    }

    func setWeeklyGoals(_ goals: [WeeklyGoal]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let weekId = currentWeekId()
        let arr: [[String: Any]] = goals.map { [
            "exerciseId": $0.exerciseId, "exerciseName": $0.exerciseName,
            "dailyReps": $0.dailyReps, "targetReps": $0.targetReps
        ] }
        try? await db.collection("users").document(userId)
            .collection("weekly-goals").document(weekId).setData(["weekId": weekId, "goals": arr])
    }

    func getWeeklyProgress() async -> [String: Int] {
        guard let userId = Auth.auth().currentUser?.uid else { return [:] }
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? today

        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: monday)
            .whereField("timestamp", isLessThan: nextMonday)
            .getDocuments() else { return [:] }

        var progress: [String: Int] = [:]
        for doc in snapshot.documents {
            if let data = try? doc.data(as: CompletedExercise.self) {
                progress[data.exerciseId, default: 0] += data.reps
            }
        }
        return progress
    }

    private func currentWeekId() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: monday)
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
    var description: String?
    var difficulty: String?
    var muscleGroups: [String]?
    var basePoints: Int
    var caloriesPerRep: Double?
    var motionProfile: MotionProfile?
    var formTips: [String]?

    init(name: String, basePoints: Int) {
        self.name = name
        self.basePoints = basePoints
    }
}

struct MotionProfile: Codable {
    var type: String
    var primaryAxis: String
    var detectionMethod: String
    var threshold: Double
}

struct WeeklyGoal: Codable, Identifiable {
    var id: String { exerciseId }
    var exerciseId: String
    var exerciseName: String
    var dailyReps: Int
    var targetReps: Int
}

struct DayExercises: Identifiable {
    var id: String { date }
    var date: String
    var label: String
    var exercises: [CompletedExercise]
    var totalReps: Int
    var totalPoints: Int
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

struct DailySets {
    var amSets: Int   // 午前（0:00〜11:59）のセット数
    var pmSets: Int   // 午後（12:00〜23:59）のセット数

    /// 達成条件: 午前1+午後1 OR 午前0+午後2以上
    var isGoalMet: Bool {
        (amSets >= 1 && pmSets >= 1) || (amSets == 0 && pmSets >= 2)
    }

    /// 午後に必要な追加セット数（午前なし時は2、午前あり時は1）
    var pmSetsNeeded: Int {
        amSets >= 1 ? max(0, 1 - pmSets) : max(0, 2 - pmSets)
    }
}
