import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import WidgetKit

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    private static var lastWidgetPayloadHash = ""
    private static var pendingWidgetReload: DispatchWorkItem?
    /// DashboardView.updateWidgetData() がアプリ内記録（Firestore）の摂取カロリーをここに保存。
    /// syncWidgetData() はこの値を優先して HealthKit 値より正確なkcalをウィジェットに書き込む。
    static var cachedAppIntakeCalories: Int = 0
    /// DashboardView.updateWidgetData() が計算した今週（月〜日）の合計XPをここに保存。
    /// syncWidgetData() はこの値を weeklyPoints として書き込み、フル更新間でも値を保つ。
    static var cachedWeeklyPoints: Int = 0

    // LOW(M-8): DateFormatter を static let でキャッシュ（毎呼び出しで生成しない）
    static let yyyyMMddFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let iso8601Fmt: ISO8601DateFormatter = ISO8601DateFormatter()

    @Published var isSignedIn = false
    @Published var userProfile: UserProfile?
    @Published var exercises: [Exercise] = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?

    // パフォーマンス最適化: キャッシュ
    private var cachedTodayExercises: [CompletedExercise] = []
    private var lastTodayExercisesFetch: Date?
    private let cacheExpiry: TimeInterval = 30 // 30秒キャッシュ
    private var cachedDailySets: DailySets = DailySets(amSets: 0, pmSets: 0)
    private var lastDailySetsCache: Date? = nil

    init() {
        setupAuthStateListener()
        // Firestoreキャッシュ設定
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
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
                if let name = self.userProfile?.username, !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: "cachedCurrentUserName")
                }
                if let photoURL = Auth.auth().currentUser?.photoURL?.absoluteString {
                    UserDefaults.standard.set(photoURL, forKey: "cachedCurrentUserPhotoURL")
                }
                // TOMO の友達検索・ランキング用に公開プロフィールを同期
                // ポイント加算ごとに毎回書き込まないよう 5 分 debounce
                if let profile = self.userProfile {
                    self.scheduleSyncPublicProfile(profile)
                }
            }
    }

    /// publicProfile 同期の debounce キャンセルトークン
    private var publicProfileDebounceWork: DispatchWorkItem?

    /// profileListener が変化するたびに呼ばれるが、実際の Firestore 書き込みは
    /// 最後の呼び出しから 5 分後に1回だけ実行する（書き込み嵐を防止）
    private func scheduleSyncPublicProfile(_ profile: UserProfile) {
        publicProfileDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.syncPublicProfile(profile) }
        }
        publicProfileDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
    }

    /// 友達検索（メール）・ランキング表示のための公開プロフィールを publicProfiles/{uid} に同期する。
    /// `email` は大文字小文字を無視して検索できるよう `emailLower` として正規化保存する。
    func syncPublicProfile(_ profile: UserProfile) async {
        let uid = profile.uid
        guard !uid.isEmpty else { return }
        let photoURL = Auth.auth().currentUser?.photoURL?.absoluteString
            ?? UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        let data: [String: Any] = [
            "uid": uid,
            "email": profile.email,
            "emailLower": profile.email.lowercased(),
            "username": profile.username,
            "totalPoints": profile.totalPoints,
            "streak": profile.streak,
            "photoURL": photoURL,
            "updatedAt": Timestamp(date: Date())
        ]
        try? await db.collection("publicProfiles").document(uid).setData(data, merge: true)
    }

    private func loadExercises() async {
        // まずキャッシュ or ローカルデフォルトで即時設定
        if let cached = try? await db.collection("exercises").getDocuments(source: .cache),
           !cached.documents.isEmpty {
            self.exercises = cached.documents.compactMap { try? $0.data(as: Exercise.self) }
            return
        }
        // キャッシュなし → デフォルトをセットしてバックグラウンドでサーバー取得
        self.exercises = Self.defaultExerciseData.map { Exercise(name: $0.name, basePoints: $0.pts) }
        Task {
            do {
                let snapshot = try await db.collection("exercises").getDocuments(source: .server)
                let loaded = snapshot.documents.compactMap { try? $0.data(as: Exercise.self) }
                if !loaded.isEmpty { self.exercises = loaded }
            } catch {}
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
            appendTodayExerciseCache(
                CompletedExercise(
                    id: nil,
                    exerciseId: exercise.id ?? exercise.name.lowercased(),
                    exerciseName: exercise.name,
                    reps: reps,
                    points: points,
                    formScore: formScore,
                    timestamp: now
                )
            )
            await updateSummaryForExercise(userId: userId, exerciseId: exercise.id ?? exercise.name.lowercased(), reps: reps, points: points, timestamp: now)

            // クライアント側でストリーク・ポイントを更新（Cloud Functions 未デプロイでも動作）
            await updateStreakAndPoints(userId: userId, points: points, now: now)

            // トレーニング記録 → 今日不要な通知をキャンセル + Watch通知 + Apple Health
            NotificationManager.shared.handleWorkoutRecorded()
            iOSWatchBridge.shared.notifyWatchAfterDirectRecord()

            // 時間帯の進捗を更新
            let hour = Calendar.current.component(.hour, from: now)
            let timeSlot = TimeSlot.forHour(hour)
            await TimeSlotManager.shared.recordTrainingCompleted(at: timeSlot)

            // Widget更新（データを書いてからリロード）
            AuthenticationManager.syncWidgetData()

            // Apple Health書き込み（権限確認）
            if HealthKitManager.shared.isAvailable {
                if !HealthKitManager.shared.isAuthorized {
                    await HealthKitManager.shared.requestAuthorization()
                }
                if HealthKitManager.shared.isAuthorized {
                    await HealthKitManager.shared.saveExercise(
                        exerciseId: exercise.id ?? exercise.name.lowercased(),
                        reps: reps, startDate: now, endDate: now
                    )
                    dlog("✅ HealthKit: Exercise saved - \(exercise.name) \(reps)rep")
                } else {
                    dlog("⚠️ HealthKit: Authorization denied")
                }
            }
        } catch {
            errorMessage = "Failed to record exercise: \(error.localizedDescription)"
        }
    }

    private func updateStreakAndPoints(userId: String, points: Int, now: Date) async {
        // M3: addSnapshotListener で維持されている userProfile キャッシュを使用し
        //     不要な Firestore getDocument() 読み取りを排除
        let userRef = db.collection("users").document(userId)
        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: now)

        var newStreak: Int
        if let cached = userProfile {
            newStreak = cached.streak
            let lastDay  = calendar.startOfDay(for: cached.lastActiveDate)
            let diffDays = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diffDays == 0 {
                // 同日 — streak はそのまま、ポイントだけ加算
            } else if diffDays <= 3 {
                newStreak += 1
            } else {
                newStreak = 1
            }
        } else {
            // キャッシュ未取得の場合のみフォールバック読み取り
            guard let doc = try? await userRef.getDocument(), doc.exists else { return }
            let profile = doc.data() ?? [:]
            newStreak = profile["streak"] as? Int ?? 1
        }

        try? await userRef.updateData([
            "streak":         newStreak,
            "totalPoints":    FieldValue.increment(Int64(points)),
            "lastActiveDate": Timestamp(date: now),
        ])
    }

    // MARK: - アクティビティポイント付与

    func awardPoints(_ points: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(userId).updateData([
            "totalPoints": FieldValue.increment(Int64(points))
        ])
        dlog("[XP] Awarded \(points)pts")
    }

    /// マインドフルネスセッションにXPを付与（セッション開始日時で重複防止）
    /// Breathe（1分瞑想）= +10 XP、Reflect（3分ストレッチ）= +30 XP
    func awardXPForMindfulSessions(_ sessions: [MindfulSession]) async {
        let today = Self.yyyyMMddFmt.string(from: Date())
        let key = "fitingo.mindful.xp.\(today)"

        var awarded = Set<String>(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let iso = Self.iso8601Fmt
        var totalNew = 0

        for session in sessions {
            let sid = iso.string(from: session.startDate)
            guard !awarded.contains(sid) else { continue }
            let isReflect = session.sessionTypeLabel == "Reflect"
            totalNew += isReflect ? 30 : 10
            awarded.insert(sid)
            dlog("[XP] Mindful session \(isReflect ? "Reflect" : "Breathe") +\(isReflect ? 30 : 10)pts")
        }

        if totalNew > 0 {
            await awardPoints(totalNew)
        }
        UserDefaults.standard.set(Array(awarded), forKey: key)
    }

    /// 1日1回限りのボーナス（UserDefaultsで重複防止）
    func checkAndAwardDailyBonus(type: String, points: Int) async {
        let today = Self.yyyyMMddFmt.string(from: Date())
        let key = "fitingo.bonus.\(type).\(today)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        await awardPoints(points)
        dlog("[XP] Daily bonus: \(type) +\(points)pts")
    }

    /// 今週（月曜〜本日）の合計XP
    func getThisWeekXP() async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun, 2=Mon...
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                         to: calendar.startOfDay(for: today)) else { return 0 }
        let snap = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: monday))
            .getDocuments()
        return snap?.documents.compactMap { $0.data()["points"] as? Int }.reduce(0, +) ?? 0
    }

    /// 過去 `days` 日分の日別運動XPを返す（Firestore summaries から取得）
    func getWeeklyDailyStats(days: Int = 7) async -> [(date: Date, exerciseXP: Int)] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(date: Date, exerciseXP: Int)] = []
        await withTaskGroup(of: (Date, Int).self) { group in
            for offset in 0..<days {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let key = Self.yyyyMMddFmt.string(from: date)
                group.addTask {
                    let snap = try? await self.db
                        .collection("users").document(userId)
                        .collection("summaries").document("daily-\(key)")
                        .getDocument()
                    let xp = snap?.data()?["exercisePoints"] as? Int ?? 0
                    return (date, xp)
                }
            }
            for await pair in group { result.append(pair) }
        }
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - キャッシュから即時取得（ブロックしない）
    func getTodayExercisesFromCache() async -> [CompletedExercise] {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ getTodayExercisesFromCache: userId is nil")
            return []
        }
        dlog("🔵 getTodayExercisesFromCache: userId=\(userId)")
        let (startOfDay, endOfDay) = todayRange()
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("completed-exercises")
                .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
                .whereField("timestamp", isLessThan: endOfDay)
                .getDocuments(source: .cache)
            dlog("✅ getTodayExercisesFromCache: \(snapshot.documents.count) docs from cache")
            return snapshot.documents.compactMap { try? $0.data(as: CompletedExercise.self) }
        } catch {
            dlog("❌ getTodayExercisesFromCache error: \(error)")
            return []
        }
    }

    // MARK: - サーバーから最新取得（バックグラウンド用）
    func getTodayExercises() async -> [CompletedExercise] {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ getTodayExercises: userId is nil")
            return []
        }

        // キャッシュチェック
        if let lastFetch = lastTodayExercisesFetch,
           Date().timeIntervalSince(lastFetch) < cacheExpiry {
            dlog("⚡ getTodayExercises: returning cached data (\(cachedTodayExercises.count) items)")
            return cachedTodayExercises
        }

        dlog("🔵 getTodayExercises: userId=\(userId), fetching from server...")
        let (startOfDay, endOfDay) = todayRange()
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("completed-exercises")
                .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
                .whereField("timestamp", isLessThan: endOfDay)
                .getDocuments(source: .default) // キャッシュ優先、必要時のみサーバー
            dlog("✅ getTodayExercises: \(snapshot.documents.count) docs")
            let exercises = snapshot.documents.compactMap { try? $0.data(as: CompletedExercise.self) }

            // キャッシュ更新
            cachedTodayExercises = exercises
            lastTodayExercisesFetch = Date()

            return exercises
        } catch {
            dlog("❌ getTodayExercises error: \(error)")
            return cachedTodayExercises // エラー時はキャッシュを返す
        }
    }

    // キャッシュを無効化（新規記録時に呼び出す）
    func invalidateTodayExercisesCache() {
        lastTodayExercisesFetch = nil
        cachedTodayExercises = []
    }

    private func appendTodayExerciseCache(_ exercise: CompletedExercise) {
        let calendar = Calendar.current
        if calendar.isDateInToday(exercise.timestamp) {
            cachedTodayExercises.append(exercise)
            lastTodayExercisesFetch = Date()
        } else {
            invalidateTodayExercisesCache()
        }
    }

    private func todayRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end   = cal.date(byAdding: .day, value: 1, to: start) ?? Date()
        return (start, end)
    }

    // MARK: - Summary Snapshots

    private func dayKey(for date: Date) -> String {
        Self.yyyyMMddFmt.string(from: date)
    }

    private func weekKey(for date: Date) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? calendar.startOfDay(for: date)
        return dayKey(for: weekStart)
    }

    private func summaryDocument(userId: String, id: String) -> DocumentReference {
        db.collection("users").document(userId).collection("summaries").document(id)
    }

    private func updateSummaryForExercise(userId: String, exerciseId: String, reps: Int, points: Int, timestamp: Date) async {
        let calories = Int((HealthKitManager.caloriesPerRep[exerciseId.lowercased()] ?? 0.25) * Double(reps))
        let safeExerciseId = exerciseId.replacingOccurrences(of: ".", with: "_")
        let dailyId = "daily-\(dayKey(for: timestamp))"
        let weeklyId = "weekly-\(weekKey(for: timestamp))"
        let dailyBase: [String: Any] = [
            "kind": "daily",
            "dateKey": dayKey(for: timestamp),
            "date": Timestamp(date: Calendar.current.startOfDay(for: timestamp)),
            "updatedAt": FieldValue.serverTimestamp(),
            "exerciseReps": FieldValue.increment(Int64(reps)),
            "exercisePoints": FieldValue.increment(Int64(points)),
            "exerciseCalories": FieldValue.increment(Int64(calories)),
            "exerciseCount": FieldValue.increment(Int64(1)),
            "exerciseBreakdown.\(safeExerciseId).reps": FieldValue.increment(Int64(reps)),
            "exerciseBreakdown.\(safeExerciseId).points": FieldValue.increment(Int64(points))
        ]
        let weeklyBase: [String: Any] = [
            "kind": "weekly",
            "weekKey": weekKey(for: timestamp),
            "updatedAt": FieldValue.serverTimestamp(),
            "exerciseReps": FieldValue.increment(Int64(reps)),
            "exercisePoints": FieldValue.increment(Int64(points)),
            "exerciseCalories": FieldValue.increment(Int64(calories)),
            "exerciseCount": FieldValue.increment(Int64(1)),
            "exerciseBreakdown.\(safeExerciseId).reps": FieldValue.increment(Int64(reps)),
            "exerciseBreakdown.\(safeExerciseId).points": FieldValue.increment(Int64(points))
        ]
        do {
            try await summaryDocument(userId: userId, id: dailyId).setData(dailyBase, merge: true)
            try await summaryDocument(userId: userId, id: weeklyId).setData(weeklyBase, merge: true)
        } catch {
            dlog("❌ Summary exercise update failed: \(error)")
        }
    }

    private func updateSummaryForSet(userId: String, totalReps: Int, totalXP: Int, timestamp: Date) async {
        let hour = Calendar.current.component(.hour, from: timestamp)
        let periodField = hour < 12 ? "amSets" : "pmSets"
        let dailyId = "daily-\(dayKey(for: timestamp))"
        let weeklyId = "weekly-\(weekKey(for: timestamp))"
        let dailyData: [String: Any] = [
            "kind": "daily",
            "dateKey": dayKey(for: timestamp),
            "date": Timestamp(date: Calendar.current.startOfDay(for: timestamp)),
            "updatedAt": FieldValue.serverTimestamp(),
            "completedSets": FieldValue.increment(Int64(1)),
            periodField: FieldValue.increment(Int64(1)),
            "setReps": FieldValue.increment(Int64(totalReps)),
            "setXP": FieldValue.increment(Int64(totalXP))
        ]
        let weeklyData: [String: Any] = [
            "kind": "weekly",
            "weekKey": weekKey(for: timestamp),
            "updatedAt": FieldValue.serverTimestamp(),
            "completedSets": FieldValue.increment(Int64(1)),
            "setReps": FieldValue.increment(Int64(totalReps)),
            "setXP": FieldValue.increment(Int64(totalXP))
        ]
        do {
            try await summaryDocument(userId: userId, id: dailyId).setData(dailyData, merge: true)
            try await summaryDocument(userId: userId, id: weeklyId).setData(weeklyData, merge: true)
        } catch {
            dlog("❌ Summary set update failed: \(error)")
        }
    }

    private func updateSummaryForIntake(
        userId: String,
        calories: Int = 0,
        waterMl: Int = 0,
        caffeineMg: Int = 0,
        alcoholG: Double = 0,
        mealType: MealType? = nil,
        timestamp: Date
    ) async {
        var dailyData: [String: Any] = [
            "kind": "daily",
            "dateKey": dayKey(for: timestamp),
            "date": Timestamp(date: Calendar.current.startOfDay(for: timestamp)),
            "updatedAt": FieldValue.serverTimestamp(),
            "intakeCalories": FieldValue.increment(Int64(calories)),
            "intakeWaterMl": FieldValue.increment(Int64(waterMl)),
            "intakeCaffeineMg": FieldValue.increment(Int64(caffeineMg)),
            "intakeAlcoholG": FieldValue.increment(alcoholG)
        ]
        if let mealType {
            dailyData["mealCalories.\(mealType.rawValue)"] = FieldValue.increment(Int64(calories))
            dailyData["mealCount"] = FieldValue.increment(Int64(1))
        }
        let weeklyData: [String: Any] = [
            "kind": "weekly",
            "weekKey": weekKey(for: timestamp),
            "updatedAt": FieldValue.serverTimestamp(),
            "intakeCalories": FieldValue.increment(Int64(calories)),
            "intakeWaterMl": FieldValue.increment(Int64(waterMl)),
            "intakeCaffeineMg": FieldValue.increment(Int64(caffeineMg)),
            "intakeAlcoholG": FieldValue.increment(alcoholG)
        ]
        do {
            try await summaryDocument(userId: userId, id: "daily-\(dayKey(for: timestamp))").setData(dailyData, merge: true)
            try await summaryDocument(userId: userId, id: "weekly-\(weekKey(for: timestamp))").setData(weeklyData, merge: true)
        } catch {
            dlog("❌ Summary intake update failed: \(error)")
        }
    }

    func getTodayActivitySummary() async -> DailyActivitySummary {
        guard let userId = Auth.auth().currentUser?.uid else { return DailyActivitySummary() }
        let doc = try? await summaryDocument(userId: userId, id: "daily-\(dayKey(for: Date()))").getDocument(source: .default)
        guard let data = doc?.data() else {
            return await rebuildDailyActivitySummary(userId: userId, date: Date())
        }
        return DailyActivitySummary(data: data)
    }

    private func getDailyActivitySummary(for date: Date, userId: String) async -> DailyActivitySummary {
        let doc = try? await summaryDocument(userId: userId, id: "daily-\(dayKey(for: date))").getDocument(source: .default)
        guard let data = doc?.data() else { return DailyActivitySummary() }
        return DailyActivitySummary(data: data)
    }

    private func rebuildDailyActivitySummary(userId: String, date: Date) async -> DailyActivitySummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        var summary = DailyActivitySummary()
        var mealCalories: [String: Int] = [:]

        // M7: 6件の Firestore クエリを async let で並列発行して待機時間を削減
        let baseQ = db.collection("users").document(userId)
        let pred: (Query) -> Query = {
            $0.whereField("timestamp", isGreaterThanOrEqualTo: start)
              .whereField("timestamp", isLessThan: end)
        }
        async let exerciseSnapTask = try? pred(baseQ.collection("completed-exercises"))
            .getDocuments(source: .default)
        async let setSnapTask = try? pred(baseQ.collection("completed-sets"))
            .getDocuments(source: .default)
        async let mealSnapTask = try? pred(baseQ.collection("daily-intake").document("meals").collection("logs"))
            .getDocuments(source: .default)
        async let waterSnapTask = try? pred(baseQ.collection("daily-intake").document("water").collection("logs"))
            .getDocuments(source: .default)
        async let coffeeSnapTask = try? pred(baseQ.collection("daily-intake").document("coffee").collection("logs"))
            .getDocuments(source: .default)
        async let alcoholSnapTask = try? pred(baseQ.collection("daily-intake").document("alcohol").collection("logs"))
            .getDocuments(source: .default)

        let (exerciseSnap, setSnap, mealSnap, waterSnap, coffeeSnap, alcoholSnap) =
            await (exerciseSnapTask, setSnapTask, mealSnapTask, waterSnapTask, coffeeSnapTask, alcoholSnapTask)

        if let exerciseSnap {
            for doc in exerciseSnap.documents {
                let data = doc.data()
                let reps = DailyActivitySummary.readInt(data["reps"])
                let points = DailyActivitySummary.readInt(data["points"])
                let exerciseId = data["exerciseId"] as? String ?? ""
                summary.exerciseReps += reps
                summary.exercisePoints += points
                summary.exerciseCalories += Int((HealthKitManager.caloriesPerRep[exerciseId.lowercased()] ?? 0.25) * Double(reps))
                summary.exerciseCount += 1
            }
        }

        if let setSnap {
            for doc in setSnap.documents {
                let data = doc.data()
                let ts = (data["timestamp"] as? Timestamp)?.dateValue() ?? start
                summary.completedSets += 1
                if calendar.component(.hour, from: ts) < 12 {
                    summary.amSets += 1
                } else {
                    summary.pmSets += 1
                }
                summary.setReps += DailyActivitySummary.readInt(data["totalReps"])
                summary.setXP += DailyActivitySummary.readInt(data["totalXP"])
            }
        }

        if let mealSnap {
            for doc in mealSnap.documents {
                let data = doc.data()
                let calories = DailyActivitySummary.readInt(data["calories"])
                let mealType = data["mealType"] as? String ?? "meal"
                summary.intakeCalories += calories
                summary.mealCount += 1
                mealCalories[mealType, default: 0] += calories
            }
        }

        if let waterSnap {
            for doc in waterSnap.documents {
                summary.intakeWaterMl += DailyActivitySummary.readInt(doc.data()["amountMl"])
            }
        }

        if let coffeeSnap {
            for doc in coffeeSnap.documents {
                let data = doc.data()
                summary.intakeWaterMl += DailyActivitySummary.readInt(data["amountMl"])
                summary.intakeCaffeineMg += DailyActivitySummary.readInt(data["caffeineMg"])
            }
        }

        if let alcoholSnap {
            for doc in alcoholSnap.documents {
                let data = doc.data()
                summary.intakeWaterMl += DailyActivitySummary.readInt(data["amountMl"])
                summary.intakeAlcoholG += DailyActivitySummary.readDouble(data["alcoholG"])
            }
        }

        summary.mealCalories = mealCalories
        let docData: [String: Any] = [
            "kind": "daily",
            "dateKey": dayKey(for: date),
            "date": Timestamp(date: start),
            "updatedAt": FieldValue.serverTimestamp(),
            "exerciseReps": summary.exerciseReps,
            "exercisePoints": summary.exercisePoints,
            "exerciseCalories": summary.exerciseCalories,
            "exerciseCount": summary.exerciseCount,
            "completedSets": summary.completedSets,
            "amSets": summary.amSets,
            "pmSets": summary.pmSets,
            "setReps": summary.setReps,
            "setXP": summary.setXP,
            "intakeCalories": summary.intakeCalories,
            "intakeWaterMl": summary.intakeWaterMl,
            "intakeCaffeineMg": summary.intakeCaffeineMg,
            "intakeAlcoholG": summary.intakeAlcoholG,
            "mealCount": summary.mealCount,
            "mealCalories": mealCalories
        ]
        try? await summaryDocument(userId: userId, id: "daily-\(dayKey(for: date))").setData(docData, merge: true)
        return summary
    }

    // MARK: - Apple Watch からのワークアウトを Firestore に記録（種目ごと通知キャンセル用）
    func recordWatchWorkout(_ workout: WatchWorkoutData) async {
        // 種目ごとの Firestore 書き込みは recordWatchCompletedSet で一括処理する。
        // updateApplicationContext はキーを上書きするため、個別送信では最後の種目しか残らない。
        NotificationManager.shared.handleWorkoutRecorded()
    }

    // MARK: - Apple Watch セット完了 → completed-sets に記録 + stats 更新
    /// 戻り値: (streak, todayReps, todayXP) を Watch へ逆同期するために返す
    @discardableResult
    func recordWatchCompletedSet(_ set: WatchSetData) async -> (streak: Int, todayReps: Int, todayXP: Int) {
        guard let userId = Auth.auth().currentUser?.uid else { return (0, 0, 0) }
        let now = set.timestamp
        if let setId = set.setId {
            let existing = try? await db.collection("users").document(userId)
                .collection("completed-sets")
                .whereField("setId", isEqualTo: setId)
                .limit(to: 1)
                .getDocuments()
            if existing?.documents.isEmpty == false {
                dlog("✅ Watch set already recorded, skipping duplicate: \(setId)")
                let snap = try? await db.collection("users").document(userId).getDocument()
                let streak = snap?.data()?["streak"] as? Int ?? (userProfile?.streak ?? 0)
                let totalXP = snap?.data()?["totalPoints"] as? Int ?? (userProfile?.totalPoints ?? 0)
                let todayReps = await getTodayActivitySummary().exerciseReps
                return (streak, todayReps, totalXP)
            }
        }

        // セット構成を取得して目標達成を確認
        let setConfig = await getSetConfiguration()
        let isValidSet = validateSetCompletion(exercises: set.exercises, config: setConfig)

        // セットとしてカウントする場合のみ completed-sets に記録
        if isValidSet {
            let exercisesData: [[String: Any]] = set.exercises.map { [
                "exerciseId":   $0.exerciseId,
                "exerciseName": $0.exerciseName,
                "reps":         $0.reps,
                "points":       $0.points,
            ] }
            let setDoc: [String: Any] = [
                "setId":      set.setId ?? "\(Int(now.timeIntervalSince1970))-\(set.totalReps)-\(set.totalXP)",
                "timestamp":  now,
                "exercises":  exercisesData,
                "totalXP":    set.totalXP,
                "totalReps":  set.totalReps,
                "source":     "watch",
                "isValidSet": true
            ]
            try? await db.collection("users").document(userId)
                .collection("completed-sets").addDocument(data: setDoc)
            await updateSummaryForSet(userId: userId, totalReps: set.totalReps, totalXP: set.totalXP, timestamp: now)
            dlog("✅ Valid set recorded: All exercises met target reps")
        } else {
            dlog("⚠️ Set not counted: Some exercises did not meet target reps")
        }

        // 各種目を completed-exercises に書き込む（履歴表示で正しい回数を出すため）
        // recordWatchWorkout では updateApplicationContext の上書き問題で最後の種目しか残らない
        for ex in set.exercises {
            let exData: [String: Any] = [
                "exerciseId":   ex.exerciseId,
                "exerciseName": ex.exerciseName,
                "reps":         ex.reps,
                "points":       ex.points,
                "formScore":    85.0,
                "timestamp":    now,
                "source":       "watch",
                "setId":        set.setId ?? ""
            ]
            try? await db.collection("users").document(userId)
                .collection("completed-exercises").addDocument(data: exData)
            appendTodayExerciseCache(
                CompletedExercise(
                    id: nil,
                    exerciseId: ex.exerciseId,
                    exerciseName: ex.exerciseName,
                    reps: ex.reps,
                    points: ex.points,
                    formScore: 85.0,
                    timestamp: now
                )
            )
            await updateSummaryForExercise(userId: userId, exerciseId: ex.exerciseId, reps: ex.reps, points: ex.points, timestamp: now)
        }

        // ストリーク・ポイントをまとめて更新
        await updateStreakAndPoints(userId: userId, points: set.totalXP, now: now)

        // 時間帯の進捗を更新
        let hour = Calendar.current.component(.hour, from: now)
        let timeSlot = TimeSlot.forHour(hour)
        await TimeSlotManager.shared.recordTrainingCompleted(at: timeSlot)

        // Apple Health にセット全体を記録（権限確認）
        // Watch 側で既に HKWorkout を直接書き込み済みの場合は重複を避けてスキップ。
        // Watch が書き込めなかった（HealthKit 未許可など）場合のみ iPhone がフォールバック書き込みする。
        if set.savedToHealth == true {
            dlog("⏭️ HealthKit: Watch already saved workout to Health (setId=\(set.setId ?? "-")) - skipping duplicate write")
        } else if HealthKitManager.shared.isAvailable {
            if !HealthKitManager.shared.isAuthorized {
                await HealthKitManager.shared.requestAuthorization()
            }
            if HealthKitManager.shared.isAuthorized {
                let setStart = Calendar.current.date(byAdding: .second, value: -max(set.totalReps * 3, 60), to: now) ?? now
                await HealthKitManager.shared.saveCompletedSet(
                    exercises: set.exercises.map { (id: $0.exerciseId, name: $0.exerciseName, reps: $0.reps) },
                    startDate: setStart,
                    setId: set.setId
                )
                dlog("✅ HealthKit: Completed set saved (fallback) - \(set.totalReps)rep / \(set.totalXP)XP")
            } else {
                dlog("⚠️ HealthKit: Authorization denied for set save")
            }
        }

        // 更新後のプロフィールを取得して返す（Watch への逆同期用）
        let snap = try? await db.collection("users").document(userId).getDocument()
        let streak = snap?.data()?["streak"] as? Int ?? (userProfile?.streak ?? 0)
        let totalXP = snap?.data()?["totalPoints"] as? Int ?? (userProfile?.totalPoints ?? 0)

        let todayReps = await getTodayActivitySummary().exerciseReps

        return (streak, todayReps, totalXP)
    }

    // MARK: - Direct record (for WorkoutPlanView)
    func recordExerciseDirect(exerciseId: String, exerciseName: String, reps: Int, points: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // completed-exercises に個別記録
        let data: [String: Any] = [
            "exerciseId": exerciseId, "exerciseName": exerciseName,
            "reps": reps, "points": points, "formScore": 85.0, "timestamp": now
        ]
        try? await db.collection("users").document(userId)
            .collection("completed-exercises").addDocument(data: data)
        appendTodayExerciseCache(
            CompletedExercise(id: nil, exerciseId: exerciseId, exerciseName: exerciseName, reps: reps, points: points, formScore: 85.0, timestamp: now)
        )
        await updateSummaryForExercise(userId: userId, exerciseId: exerciseId, reps: reps, points: points, timestamp: now)

        // completed-sets にも記録（Web互換・セット同期用）
        let setDoc: [String: Any] = [
            "timestamp": now,
            "exercises": [[
                "exerciseId": exerciseId,
                "exerciseName": exerciseName,
                "reps": reps,
                "points": points
            ]],
            "totalXP": points,
            "totalReps": reps,
            "source": "ios-direct"
        ]
        try? await db.collection("users").document(userId)
            .collection("completed-sets").addDocument(data: setDoc)
        await updateSummaryForSet(userId: userId, totalReps: reps, totalXP: points, timestamp: now)

        await updateStreakAndPoints(userId: userId, points: points, now: now)
        NotificationManager.shared.handleWorkoutRecorded()
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()

        // 時間帯の進捗を更新
        let hour = Calendar.current.component(.hour, from: now)
        let timeSlot = TimeSlot.forHour(hour)
        await TimeSlotManager.shared.recordTrainingCompleted(at: timeSlot)

        // Apple Health書き込み（権限確認）
        if HealthKitManager.shared.isAvailable {
            if !HealthKitManager.shared.isAuthorized {
                await HealthKitManager.shared.requestAuthorization()
            }
            if HealthKitManager.shared.isAuthorized {
                await HealthKitManager.shared.saveExercise(
                    exerciseId: exerciseId, reps: reps, startDate: now, endDate: now
                )
                dlog("✅ HealthKit: Direct exercise saved - \(exerciseName) \(reps)rep")
            }
        }

        // キャッシュ無効化
        invalidateTodayExercisesCache()
        invalidateDailySetsCache()

        // Widget更新（データを書いてからリロード）
        AuthenticationManager.syncWidgetData()
    }

    /// 種目のみを記録（セットは記録しない）
    func recordExerciseOnly(exerciseId: String, exerciseName: String, reps: Int, points: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // completed-exercises に個別記録
        let data: [String: Any] = [
            "exerciseId": exerciseId, "exerciseName": exerciseName,
            "reps": reps, "points": points, "formScore": 85.0, "timestamp": now
        ]
        try? await db.collection("users").document(userId)
            .collection("completed-exercises").addDocument(data: data)
        appendTodayExerciseCache(
            CompletedExercise(id: nil, exerciseId: exerciseId, exerciseName: exerciseName, reps: reps, points: points, formScore: 85.0, timestamp: now)
        )
        await updateSummaryForExercise(userId: userId, exerciseId: exerciseId, reps: reps, points: points, timestamp: now)

        // 時間帯の進捗を更新
        let hour = Calendar.current.component(.hour, from: now)
        let timeSlot = TimeSlot.forHour(hour)
        await TimeSlotManager.shared.recordTrainingCompleted(at: timeSlot)

        // Apple Health書き込み
        if HealthKitManager.shared.isAvailable && HealthKitManager.shared.isAuthorized {
            await HealthKitManager.shared.saveExercise(
                exerciseId: exerciseId, reps: reps, startDate: now, endDate: now
            )
        }

        // Widget更新（データを書いてからリロード）
        AuthenticationManager.syncWidgetData()
    }

    /// 完了したセットを1件として記録
    func recordCompletedSet(exercises: [(exerciseId: String, exerciseName: String, reps: Int, points: Int)]) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        let totalXP = exercises.reduce(0) { $0 + $1.points }
        let totalReps = exercises.reduce(0) { $0 + $1.reps }

        // セット構成を取得して目標達成を確認
        let setConfig = await getSetConfiguration()
        let isValidSet = validateSetCompletion(exercises: exercises, config: setConfig)

        // セットとしてカウントする場合のみ completed-sets に記録
        if isValidSet {
            let setDoc: [String: Any] = [
                "timestamp": now,
                "exercises": exercises.map { ex in
                    [
                        "exerciseId": ex.exerciseId,
                        "exerciseName": ex.exerciseName,
                        "reps": ex.reps,
                        "points": ex.points
                    ]
                },
                "totalXP": totalXP,
                "totalReps": totalReps,
                "source": "ios-set",
                "isValidSet": true
            ]
            try? await db.collection("users").document(userId)
                .collection("completed-sets").addDocument(data: setDoc)
            await updateSummaryForSet(userId: userId, totalReps: totalReps, totalXP: totalXP, timestamp: now)
            dlog("✅ Valid set recorded: All exercises met target reps")
        } else {
            dlog("⚠️ Set not counted: Some exercises did not meet target reps")
        }

        await updateStreakAndPoints(userId: userId, points: totalXP, now: now)
        NotificationManager.shared.handleWorkoutRecorded()
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()

        // キャッシュ無効化
        invalidateTodayExercisesCache()
        invalidateDailySetsCache()
    }

    // MARK: - Weekly Set Counts
    func fetchWeeklySetCounts() async -> [String: Int] {
        guard let userId = Auth.auth().currentUser?.uid else { return [:] }
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today

        var counts: [String: Int] = [:]
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let summary = await getDailyActivitySummary(for: date, userId: userId)
            if summary.completedSets > 0 {
                counts[Self.yyyyMMddFmt.string(from: date)] = summary.completedSets
            }
        }
        return counts
    }

    // MARK: - Weekly Intake Data (食事・水分)
    func fetchWeeklyIntakeData() async -> [String: [String: Int]] {
        guard let userId = Auth.auth().currentUser?.uid else { return [:] }
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? today

        var result: [String: [String: Int]] = [:]

        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            guard date < weekEnd else { continue }
            let summary = await getDailyActivitySummary(for: date, userId: userId)
            guard summary.intakeCalories > 0 || summary.intakeWaterMl > 0 else { continue }
            let key = Self.yyyyMMddFmt.string(from: date)
            for (mealType, calories) in summary.mealCalories {
                result[key, default: [:]][mealType, default: 0] += calories
            }
            result[key, default: [:]]["waterMl", default: 0] += summary.intakeWaterMl
        }

        return result
    }

    // MARK: - History
    func getRecentExercises(days: Int = 14) async -> [DayExercises] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        let end   = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()

        guard let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-sets")
            .whereField("timestamp", isGreaterThanOrEqualTo: start)
            .whereField("timestamp", isLessThan: end)
            .limit(to: 200)
            .getDocuments() else { return [] }

        // Group set entries by day (each entry is a timestamp + parsed exercises)
        var byDay: [String: [(ts: Date, exercises: [CompletedExercise])]] = [:]

        for doc in snapshot.documents {
            let data = doc.data()
            guard let ts = (data["timestamp"] as? Timestamp)?.dateValue() else { continue }
            let key = Self.yyyyMMddFmt.string(from: ts)

            let exerciseDicts = data["exercises"] as? [[String: Any]] ?? []
            let exercises: [CompletedExercise] = exerciseDicts.compactMap { exDict in
                guard let exerciseId = exDict["exerciseId"] as? String,
                      let exerciseName = exDict["exerciseName"] as? String,
                      let reps = exDict["reps"] as? Int,
                      let points = exDict["points"] as? Int else { return nil }
                return CompletedExercise(id: nil, exerciseId: exerciseId,
                                        exerciseName: exerciseName, reps: reps,
                                        points: points, formScore: 0.0, timestamp: ts)
            }
            byDay[key, default: []].append((ts: ts, exercises: exercises))
        }

        var result: [DayExercises] = []
        for i in 0..<days {
            let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: Date())) ?? Date()
            let key = Self.yyyyMMddFmt.string(from: date)
            guard let entries = byDay[key], !entries.isEmpty else { continue }

            let month = calendar.component(.month, from: date)
            let day   = calendar.component(.day, from: date)
            let label = i == 0 ? "今日" : i == 1 ? "昨日" : "\(month)/\(day)"

            // Build ExerciseSet objects directly from completed-sets entries
            let sorted = entries.sorted { $0.ts < $1.ts }
            var amCount = 0, pmCount = 0
            let sets: [ExerciseSet] = sorted.map { entry in
                let hour = calendar.component(.hour, from: entry.ts)
                let isAM = hour < 12
                let period = isAM ? "午前" : "午後"
                if isAM { amCount += 1 } else { pmCount += 1 }
                let setNumber = isAM ? amCount : pmCount
                return ExerciseSet(
                    startTime: entry.ts,
                    period: period,
                    setNumber: setNumber,
                    exercises: entry.exercises,
                    totalReps: entry.exercises.reduce(0) { $0 + $1.reps },
                    totalPoints: entry.exercises.reduce(0) { $0 + $1.points }
                )
            }

            result.append(DayExercises(
                date: key,
                label: label,
                sets: sets,
                totalReps: sets.reduce(0) { $0 + $1.totalReps },
                totalPoints: sets.reduce(0) { $0 + $1.totalPoints }
            ))
        }
        return result
    }

    // MARK: - Daily Sets
    /// 今日のセット状況（30分間隔でセッションを分割し、午前/午後を判定）
    func getDailySetsFromCache() async -> DailySets {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ getDailySetsFromCache: userId is nil")
            return DailySets(amSets: 0, pmSets: 0)
        }
        dlog("🔵 getDailySetsFromCache: userId=\(userId)")
        let (startOfDay, endOfDay) = todayRange()
        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("completed-sets")
                .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
                .whereField("timestamp", isLessThan: endOfDay)
                .getDocuments(source: .cache)
            let sets = buildDailySets(from: snapshot)
            dlog("✅ getDailySetsFromCache: amSets=\(sets.amSets), pmSets=\(sets.pmSets)")
            return sets
        } catch {
            dlog("❌ getDailySetsFromCache error: \(error)")
            return DailySets(amSets: 0, pmSets: 0)
        }
    }

    func getDailySets() async -> DailySets {
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("❌ getDailySets: userId is nil")
            return DailySets(amSets: 0, pmSets: 0)
        }
        // 30秒キャッシュ
        if let last = lastDailySetsCache, Date().timeIntervalSince(last) < cacheExpiry {
            dlog("⚡ getDailySets: returning cached data")
            return cachedDailySets
        }
        let summary = await getTodayActivitySummary()
        if summary.completedSets > 0 {
            let sets = summary.dailySets
            cachedDailySets = sets
            lastDailySetsCache = Date()
            return sets
        }
        dlog("🔵 getDailySets: userId=\(userId), fetching from server...")
        let (startOfDay, endOfDay) = todayRange()

        do {
            let snapshot = try await db.collection("users").document(userId)
                .collection("completed-sets")
                .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
                .whereField("timestamp", isLessThan: endOfDay)
                .getDocuments(source: .default)
            let sets = buildDailySets(from: snapshot)
            cachedDailySets = sets
            lastDailySetsCache = Date()
            dlog("✅ getDailySets: amSets=\(sets.amSets), pmSets=\(sets.pmSets)")
            return sets
        } catch {
            dlog("❌ getDailySets error: \(error)")
            return cachedDailySets
        }
    }

    func invalidateDailySetsCache() {
        lastDailySetsCache = nil
    }

    private func buildDailySets(from snapshot: QuerySnapshot) -> DailySets {
        // completed-sets から直接セット情報を取得（Web互換）
        let timestamps: [Date] = snapshot.documents
            .compactMap { $0.data()["timestamp"] as? Timestamp }
            .map { $0.dateValue() }
            .sorted()

        let cal    = Calendar.current
        let noon   = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let amSets = timestamps.filter { $0 < noon }.count
        let pmSets = timestamps.filter { $0 >= noon }.count
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

    // MARK: - Daily Calorie Goal
    func getDailyCalorieGoal() async -> DailyCalorieGoal {
        guard let userId = Auth.auth().currentUser?.uid else {
            return DailyCalorieGoal()
        }

        // 目標カロリーを取得（カスタム設定 → 週間目標から計算 → デフォルト500）
        let goalDoc = try? await db.collection("users").document(userId)
            .collection("settings").document("calorie-goal").getDocument()

        var targetCalories = goalDoc?.data()?["targetCalories"] as? Int

        // カスタム設定がない場合は週間目標から計算
        if targetCalories == nil {
            let weekId = getCurrentWeekId()
            let weeklyDoc = try? await db.collection("users").document(userId)
                .collection("weekly-goals").document(weekId).getDocument()
            if let goals = weeklyDoc?.data()?["goals"] as? [[String: Any]] {
                let dailyTotalReps = goals.reduce(0) { sum, goal in
                    sum + (goal["dailyReps"] as? Int ?? 10)
                }
                // 平均的なカロリー消費率 0.5 kcal/rep
                targetCalories = Int(Double(dailyTotalReps) * 0.5)
            }
        }

        // フォールバック
        let finalTarget = targetCalories ?? 500

        let exerciseCalories = await getTodayActivitySummary().exerciseCalories

        // HealthKitからの消費カロリーも追加
        let healthCalories = Int(HealthKitManager.shared.todayCalories)
        let totalConsumed = exerciseCalories + healthCalories

        return DailyCalorieGoal(target: finalTarget, consumed: totalConsumed)
    }

    func saveDailyCalorieGoal(targetCalories: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(userId)
            .collection("settings").document("calorie-goal")
            .setData(["targetCalories": targetCalories, "updatedAt": Date()])
    }

    /// 今日完了したセット数を取得
    func getTodaySetCount() async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 0 }
        let summary = await getTodayActivitySummary()
        if summary.completedSets > 0 {
            return summary.completedSets
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()

        let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-sets")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments()

        return snapshot?.documents.count ?? 0
    }

    /// 1日の目標セット数を取得
    func getDailySetGoal() async -> Int {
        guard let userId = Auth.auth().currentUser?.uid else { return 2 }

        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("daily-set-goal").getDocument()

        return doc?.data()?["dailySets"] as? Int ?? 2
    }

    /// 1日の目標セット数を保存
    func saveDailySetGoal(_ goal: Int) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(userId)
            .collection("settings").document("daily-set-goal")
            .setData(["dailySets": goal, "updatedAt": Date()])
    }

    // MARK: - セット検証

    /// セットが有効か検証（各メニューが目標回数以上達成されているか）- WatchSetExercise版
    private func validateSetCompletion(exercises: [WatchSetExercise], config: SetConfiguration) -> Bool {
        // 各目標種目が達成されているかチェック
        for targetExercise in config.exercises {
            // 実施した種目から該当する種目を探す
            if let completedExercise = exercises.first(where: { $0.exerciseId == targetExercise.exerciseId }) {
                // 目標回数未達の場合は無効
                if completedExercise.reps < targetExercise.targetReps {
                    dlog("⚠️ \(targetExercise.exerciseName): \(completedExercise.reps)/\(targetExercise.targetReps) - 目標未達")
                    return false
                }
            } else {
                // 目標種目が実施されていない場合は無効
                dlog("⚠️ \(targetExercise.exerciseName): 未実施")
                return false
            }
        }
        return true
    }

    /// セットが有効か検証（各メニューが目標回数以上達成されているか）- Tuple版
    private func validateSetCompletion(exercises: [(exerciseId: String, exerciseName: String, reps: Int, points: Int)], config: SetConfiguration) -> Bool {
        // 各目標種目が達成されているかチェック
        for targetExercise in config.exercises {
            // 実施した種目から該当する種目を探す
            if let completedExercise = exercises.first(where: { $0.exerciseId == targetExercise.exerciseId }) {
                // 目標回数未達の場合は無効
                if completedExercise.reps < targetExercise.targetReps {
                    dlog("⚠️ \(targetExercise.exerciseName): \(completedExercise.reps)/\(targetExercise.targetReps) - 目標未達")
                    return false
                }
            } else {
                // 目標種目が実施されていない場合は無効
                dlog("⚠️ \(targetExercise.exerciseName): 未実施")
                return false
            }
        }
        return true
    }

    // MARK: - セット構成設定

    /// 1セットのメニュー構成を取得
    func getSetConfiguration() async -> SetConfiguration {
        guard let userId = Auth.auth().currentUser?.uid else {
            return SetConfiguration.defaultSet
        }

        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("set-configuration").getDocument()

        guard let data = doc?.data(),
              let exercisesData = try? JSONSerialization.data(withJSONObject: data["exercises"] ?? []),
              let config = try? JSONDecoder().decode(SetConfiguration.self, from: exercisesData)
        else {
            return SetConfiguration.defaultSet
        }

        return config
    }

    /// 1セットのメニュー構成を保存
    func saveSetConfiguration(_ config: SetConfiguration) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let exercisesArray = config.exercises.map { ex in
            [
                "exerciseId": ex.exerciseId,
                "exerciseName": ex.exerciseName,
                "targetReps": ex.targetReps,
                "order": ex.order
            ] as [String: Any]
        }

        try? await db.collection("users").document(userId)
            .collection("settings").document("set-configuration")
            .setData([
                "exercises": exercisesArray,
                "updatedAt": Date()
            ])
    }

    // MARK: - モーションセンサー感度設定

    /// モーションセンサー感度を取得
    func getMotionSensitivity(for exerciseId: String) async -> MotionSensitivity {
        guard let userId = Auth.auth().currentUser?.uid else {
            return MotionSensitivity.defaultSettings[exerciseId] ?? MotionSensitivity(exerciseId: exerciseId, threshold: 0.08, minInterval: 0.8)
        }

        let doc = try? await db.collection("users").document(userId)
            .collection("settings").document("motion-sensitivity-\(exerciseId)").getDocument()

        guard let data = doc?.data() else {
            return MotionSensitivity.defaultSettings[exerciseId] ?? MotionSensitivity(exerciseId: exerciseId, threshold: 0.08, minInterval: 0.8)
        }

        return MotionSensitivity(
            exerciseId: exerciseId,
            threshold: data["threshold"] as? Double ?? 0.08,
            minInterval: data["minInterval"] as? Double ?? 0.8
        )
    }

    /// 全種目のモーションセンサー感度を取得
    func getAllMotionSensitivity() async -> [String: MotionSensitivity] {
        guard let userId = Auth.auth().currentUser?.uid else {
            return MotionSensitivity.defaultSettings
        }

        var result: [String: MotionSensitivity] = [:]

        for (exerciseId, defaultSetting) in MotionSensitivity.defaultSettings {
            let doc = try? await db.collection("users").document(userId)
                .collection("settings").document("motion-sensitivity-\(exerciseId)").getDocument()

            if let data = doc?.data() {
                result[exerciseId] = MotionSensitivity(
                    exerciseId: exerciseId,
                    threshold: data["threshold"] as? Double ?? defaultSetting.threshold,
                    minInterval: data["minInterval"] as? Double ?? defaultSetting.minInterval
                )
            } else {
                result[exerciseId] = defaultSetting
            }
        }

        return result
    }

    /// モーションセンサー感度を保存
    func saveMotionSensitivity(_ sensitivity: MotionSensitivity) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        try? await db.collection("users").document(userId)
            .collection("settings").document("motion-sensitivity-\(sensitivity.exerciseId)")
            .setData([
                "threshold": sensitivity.threshold,
                "minInterval": sensitivity.minInterval,
                "updatedAt": Date()
            ])
    }

    // MARK: - Helper: Week ID
    private func getCurrentWeekId() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) else {
            return Self.yyyyMMddFmt.string(from: today)
        }
        return Self.yyyyMMddFmt.string(from: monday)
    }

    // MARK: - Weekly Set Progress (Web互換)
    func getWeeklySetProgress() async -> WeeklySetProgress {
        guard let userId = Auth.auth().currentUser?.uid else {
            return WeeklySetProgress(completedSets: 0, dailyGoal: 2)
        }
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()

        // 今週のセット数を取得
        let snapshot = try? await db.collection("users").document(userId)
            .collection("completed-sets")
            .whereField("timestamp", isGreaterThanOrEqualTo: weekStart)
            .whereField("timestamp", isLessThan: weekEnd)
            .getDocuments()

        let completedSets = snapshot?.documents.count ?? 0

        // 1日の目標セット数を取得
        let goalDoc = try? await db.collection("users").document(userId)
            .collection("settings").document("weekly-goal").getDocument()
        let dailyGoal = goalDoc?.data()?["dailySets"] as? Int ?? 2

        return WeeklySetProgress(completedSets: completedSets, dailyGoal: dailyGoal)
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

    // MARK: - Daily Intake Settings (摂取記録設定)

    /// 摂取記録の設定を取得
    func getIntakeSettings() async -> IntakeSettings {
        guard let userId = Auth.auth().currentUser?.uid else { return IntakeSettings.defaultSettings }

        let docRef = db.collection("users").document(userId)
            .collection("settings").document("intake-settings")

        guard let doc = try? await docRef.getDocument(),
              let data = doc.data()
        else {
            return IntakeSettings.defaultSettings
        }

        // まず完全デコードを試み、失敗時は既知フィールドをデフォルトにマージ（新フィールド追加時の後方互換）
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let settings = try? JSONDecoder().decode(IntakeSettings.self, from: jsonData) {
            return settings
        }

        var s = IntakeSettings.defaultSettings
        if let v = data["breakfastCalories"] as? Int  { s.breakfastCalories = v }
        if let v = data["lunchCalories"]     as? Int  { s.lunchCalories     = v }
        if let v = data["dinnerCalories"]    as? Int  { s.dinnerCalories    = v }
        if let v = data["snackCalories"]     as? Int  { s.snackCalories     = v }
        if let v = data["waterPerCup"]       as? Int  { s.waterPerCup       = v }
        if let v = data["coffeePerCup"]      as? Int  { s.coffeePerCup      = v }
        if let v = data["caffeinePerCup"]    as? Int  { s.caffeinePerCup    = v }
        if let v = data["dailyCalorieGoal"]  as? Int  { s.dailyCalorieGoal  = v }
        if let v = data["dailyWaterGoal"]    as? Int  { s.dailyWaterGoal    = v }
        if let v = data["dailyCaffeineLimit"] as? Int { s.dailyCaffeineLimit = v }
        if let v = data["dailyAlcoholLimit"] as? Double { s.dailyAlcoholLimit = v }
        return s
    }

    /// 摂取記録の設定を保存
    func saveIntakeSettings(_ settings: IntakeSettings) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        guard let jsonData = try? JSONEncoder().encode(settings),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        try? await db.collection("users").document(userId)
            .collection("settings").document("intake-settings")
            .setData(dict)
    }

    // MARK: - LLM Settings

    /// LLM設定を取得
    func getLLMSettings() async -> LLMSettings {
        guard let userId = Auth.auth().currentUser?.uid else {
            return LLMSettings.defaultSettings
        }

        do {
            let doc = try await db.collection("users").document(userId)
                .collection("settings").document("llm-settings")
                .getDocument()

            if let data = doc.data(),
               let jsonData = try? JSONSerialization.data(withJSONObject: data),
               let settings = try? JSONDecoder().decode(LLMSettings.self, from: jsonData) {
                return settings
            }
        } catch {
            dlog("❌ Failed to load LLM settings: \(error)")
        }

        return LLMSettings.defaultSettings
    }

    /// LLM設定を保存
    func saveLLMSettings(_ settings: LLMSettings) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        guard let jsonData = try? JSONEncoder().encode(settings),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        try? await db.collection("users").document(userId)
            .collection("settings").document("llm-settings")
            .setData(dict)
    }

    // MARK: - Daily Intake (食事・水分・コーヒー・アルコール記録)

    /// 食事を記録
    func recordMeal(mealType: MealType, calories: Int? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // 設定から栄養素情報を取得
        let settings = await getIntakeSettings()
        let nutrition = settings.nutritionFor(mealType: mealType)
        let actualCalories = calories ?? nutrition.calories

        let data: [String: Any] = [
            "mealType": mealType.rawValue,
            "calories": actualCalories,
            "protein": nutrition.protein,
            "fat": nutrition.fat,
            "carbs": nutrition.carbs,
            "sugar": nutrition.sugar,
            "fiber": nutrition.fiber,
            "sodium": nutrition.sodium,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("meals")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, calories: actualCalories, mealType: mealType, timestamp: now)

        // Apple Healthに栄養素を記録
        await HealthKitManager.shared.saveMealNutrition(nutrition, date: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// 任意の栄養素を指定して食事を記録（カツカレー・栄養バーなどの固定メニュー用）
    func recordCustomMeal(name: String, mealType: MealType, nutrition: MealNutrition) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        let data: [String: Any] = [
            "mealType": mealType.rawValue,
            "foodName": name,
            "calories": nutrition.calories,
            "protein": nutrition.protein,
            "fat": nutrition.fat,
            "carbs": nutrition.carbs,
            "sugar": nutrition.sugar,
            "fiber": nutrition.fiber,
            "sodium": nutrition.sodium,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("meals")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, calories: nutrition.calories, mealType: mealType, timestamp: now)

        // Apple Healthに栄養素を記録
        await HealthKitManager.shared.saveMealNutrition(nutrition, date: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// 水を記録
    func recordWater(cups: Int = 1, customMl: Int? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // customMl 指定があればそれを使い、なければ設定値 × カップ数
        let amountMl: Int
        if let ml = customMl {
            amountMl = ml
        } else {
            let settings = await getIntakeSettings()
            amountMl = cups * settings.waterPerCup
        }

        let data: [String: Any] = [
            "amountMl": amountMl,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("water")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, waterMl: amountMl, timestamp: now)

        // Apple Healthに記録
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// フルーツジュースを記録（水分＋カロリー）
    func recordJuice(cups: Int = 1) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let settings = await getIntakeSettings()
        let amountMl = cups * settings.juicePerCup
        let kcal     = cups * settings.juiceCaloriesPerCup

        // 水分ログ
        let waterData: [String: Any] = ["amountMl": amountMl, "timestamp": now]
        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("water")
            .collection("logs").addDocument(data: waterData)

        // サマリー更新（水分＋カロリー）
        await updateSummaryForIntake(userId: userId, calories: kcal,
                                     waterMl: amountMl, timestamp: now)

        // HealthKit: 水分として記録
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// コーヒーを記録
    func recordCoffee(cups: Int = 1) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // 設定から1杯の量を取得
        let settings = await getIntakeSettings()
        let amountMl = cups * settings.coffeePerCup
        let caffeineMg = cups * settings.caffeinePerCup

        let data: [String: Any] = [
            "amountMl": amountMl,
            "caffeineMg": caffeineMg,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("coffee")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, waterMl: amountMl, caffeineMg: caffeineMg, timestamp: now)

        // Apple Healthにカフェイン記録＋コーヒーの液量を水分として記録
        await HealthKitManager.shared.saveCaffeineIntake(caffeineMg: Double(caffeineMg), timestamp: now)
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// フルーツジュースを記録（200ml / 76kcal / 糖質18g 相当）
    func recordFruitJuice() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let amountMl  = 200
        let calorieKcal = 76

        let data: [String: Any] = [
            "amountMl":  amountMl,
            "calories":  calorieKcal,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("juice")
            .collection("logs").addDocument(data: data)

        // カロリー + 水分 の両方をサマリに加算
        await updateSummaryForIntake(
            userId: userId,
            calories: calorieKcal,
            waterMl: amountMl,
            timestamp: now
        )

        // Apple Health に水分として記録
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// エスプレッソダブルを記録（30ml / カフェイン120mg）
    func recordEspresso() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let amountMl  = 30
        let caffeineMg = 120
        let data: [String: Any] = ["amountMl": amountMl, "caffeineMg": caffeineMg, "timestamp": now]
        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("coffee")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, waterMl: amountMl, caffeineMg: caffeineMg, timestamp: now)
        await HealthKitManager.shared.saveCaffeineIntake(caffeineMg: Double(caffeineMg), timestamp: now)
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// 緑茶を記録（150ml / カフェイン30mg）
    func recordGreenTea() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let amountMl  = 150
        let caffeineMg = 30
        let data: [String: Any] = ["amountMl": amountMl, "caffeineMg": caffeineMg, "timestamp": now]
        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("coffee")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, waterMl: amountMl, caffeineMg: caffeineMg, timestamp: now)
        await HealthKitManager.shared.saveCaffeineIntake(caffeineMg: Double(caffeineMg), timestamp: now)
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// スポーツ飲料を記録（300ml / 72kcal / 糖質21g / ナトリウム360mg）
    func recordSportsDrink() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let amountMl   = 300
        let calorieKcal = 72
        let data: [String: Any] = ["amountMl": amountMl, "calories": calorieKcal, "timestamp": now]
        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("juice")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, calories: calorieKcal, waterMl: amountMl, timestamp: now)
        await HealthKitManager.shared.saveWaterIntake(amountMl: Double(amountMl), timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// アルコールを記録
    func recordAlcohol(alcoholType: AlcoholType, servings: Int = 1) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let now = Date()

        // 設定からアルコール量を取得
        let settings = await getIntakeSettings()
        let alcoholSetting = settings.settingFor(alcoholType: alcoholType)
        let amountMl = (alcoholSetting?.amountMl ?? alcoholType.amountMl) * servings
        let alcoholG = (alcoholSetting?.alcoholG ?? alcoholType.alcoholG) * Double(servings)

        let data: [String: Any] = [
            "alcoholType": alcoholType.rawValue,
            "amountMl": amountMl,
            "alcoholG": alcoholG,
            "timestamp": now
        ]

        try? await db.collection("users").document(userId)
            .collection("daily-intake").document("alcohol")
            .collection("logs").addDocument(data: data)
        await updateSummaryForIntake(userId: userId, waterMl: amountMl, alcoholG: alcoholG, timestamp: now)

        // Apple Healthにアルコール記録（純アルコール量も渡す）
        await HealthKitManager.shared.saveAlcoholIntake(amountMl: Double(amountMl), alcoholG: alcoholG, timestamp: now)
        iOSWatchBridge.shared.notifyWatchAfterDirectRecord()
    }

    /// 今日の摂取記録を取得
    func getTodayIntakeSummary() async -> TodayIntakeSummary {
        guard let userId = Auth.auth().currentUser?.uid else { return TodayIntakeSummary() }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        return await getIntakeSummary(userId: userId, startOfDay: startOfDay, endOfDay: endOfDay)
    }

    private func getIntakeSummary(userId: String, startOfDay: Date, endOfDay: Date) async -> TodayIntakeSummary {
        var summary = TodayIntakeSummary()

        // 食事
        if let mealSnapshot = try? await db.collection("users").document(userId)
            .collection("daily-intake").document("meals").collection("logs")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments() {
            for doc in mealSnapshot.documents {
                let data = doc.data()
                if let mealTypeStr = data["mealType"] as? String,
                   let mealType = MealType(rawValue: mealTypeStr),
                   let calories = data["calories"] as? Int,
                   let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() {
                    summary.meals.append(MealLog(mealType: mealType, calories: calories, timestamp: timestamp))
                    summary.totalCalories += calories
                }
            }
        }

        // 水
        if let waterSnapshot = try? await db.collection("users").document(userId)
            .collection("daily-intake").document("water").collection("logs")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments() {
            for doc in waterSnapshot.documents {
                let data = doc.data()
                if let amountMl = data["amountMl"] as? Int,
                   let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() {
                    summary.waterLogs.append(WaterLog(amountMl: amountMl, timestamp: timestamp))
                    summary.totalWaterMl += amountMl
                }
            }
        }

        // コーヒー
        if let coffeeSnapshot = try? await db.collection("users").document(userId)
            .collection("daily-intake").document("coffee").collection("logs")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments() {
            for doc in coffeeSnapshot.documents {
                let data = doc.data()
                if let amountMl = data["amountMl"] as? Int,
                   let caffeineMg = data["caffeineMg"] as? Int,
                   let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() {
                    summary.coffeeLogs.append(CoffeeLog(amountMl: amountMl, caffeineMg: caffeineMg, timestamp: timestamp))
                    summary.totalCaffeineMg += caffeineMg
                }
            }
        }

        // アルコール
        if let alcoholSnapshot = try? await db.collection("users").document(userId)
            .collection("daily-intake").document("alcohol").collection("logs")
            .whereField("timestamp", isGreaterThanOrEqualTo: startOfDay)
            .whereField("timestamp", isLessThan: endOfDay)
            .getDocuments() {
            for doc in alcoholSnapshot.documents {
                let data = doc.data()
                if let alcoholTypeStr = data["alcoholType"] as? String,
                   let alcoholType = AlcoholType(rawValue: alcoholTypeStr),
                   let amountMl = data["amountMl"] as? Int,
                   let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() {
                    // alcoholGを取得（古いデータはalcoholMgの場合があるので互換性を保つ）
                    let alcoholG: Double
                    if let g = data["alcoholG"] as? Double {
                        alcoholG = g
                    } else if let mg = data["alcoholMg"] as? Int {
                        alcoholG = Double(mg) / 1000.0  // mgからgに変換
                    } else {
                        alcoholG = alcoholType.alcoholG  // デフォルト値
                    }
                    summary.alcoholLogs.append(AlcoholLog(alcoholType: alcoholType, amountMl: amountMl, alcoholG: alcoholG, timestamp: timestamp))
                    summary.totalAlcoholG += alcoholG
                }
            }
        }

        // ログコンプリートボーナスをチェック・付与
        if summary.isLogComplete {
            await checkAndAwardLogCompleteBonus(userId: userId, date: startOfDay)
        }

        return summary
    }

    func performEndOfDayCalorieTopUpIfNeeded(now: Date = Date(), targetCalories: Int = 2000) async {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let todayComponents = calendar.dateComponents([.hour, .minute], from: now)
        let isEndOfToday = (todayComponents.hour ?? 0) > 23
            || ((todayComponents.hour ?? 0) == 23 && (todayComponents.minute ?? 0) >= 59)
        guard isEndOfToday else { return }

        let dayKey = Self.yyyyMMddFmt.string(from: startOfToday)
        let defaultsKey = "healthKit.endOfDayCalorieTopUp.\(dayKey)"
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        let healthKit = HealthKitManager.shared
        guard healthKit.isAvailable else { return }
        if !healthKit.isAuthorized {
            await healthKit.requestAuthorization()
        }
        guard healthKit.isAuthorized else { return }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let currentAppleHealthCalories = Int(await healthKit.fetchDietaryEnergyCalories(start: startOfToday, end: min(now, endOfToday)).rounded())
        let gapCalories = targetCalories - currentAppleHealthCalories
        guard gapCalories > 0 else {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            return
        }

        let timestamp = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: startOfToday)
            ?? endOfToday.addingTimeInterval(-60)
        let saved = await healthKit.saveDietaryEnergy(
            calories: Double(gapCalories),
            timestamp: timestamp,
            metadata: [
                "kfitAutoCalorieTopUp": true,
                "kfitTargetCalories": targetCalories,
                "kfitAppleHealthCaloriesBeforeTopUp": currentAppleHealthCalories,
                "kfitDay": dayKey
            ]
        )
        if saved {
            UserDefaults.standard.set(true, forKey: defaultsKey)
            await healthKit.fetchIntakeHealth(force: true)
        }
    }

    private func currentWeekId() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today
        return Self.yyyyMMddFmt.string(from: monday)
    }

    deinit {
        profileListener?.remove()
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

struct WeeklySetProgress {
    var completedSets: Int
    var dailyGoal: Int
}

struct DailyCalorieGoal {
    var targetCalories: Int
    var consumedCalories: Int
    var percentAchieved: Int

    init(target: Int = 500, consumed: Int = 0) {
        self.targetCalories = target
        self.consumedCalories = consumed
        // 100%を超えても計算し続ける（minを削除）
        self.percentAchieved = target > 0 ? Int(Double(consumed) / Double(target) * 100) : 0
    }
}

struct DailyActivitySummary {
    var exerciseReps: Int = 0
    var exercisePoints: Int = 0
    var exerciseCalories: Int = 0
    var exerciseCount: Int = 0
    var completedSets: Int = 0
    var amSets: Int = 0
    var pmSets: Int = 0
    var setReps: Int = 0
    var setXP: Int = 0
    var intakeCalories: Int = 0
    var intakeWaterMl: Int = 0
    var intakeCaffeineMg: Int = 0
    var intakeAlcoholG: Double = 0
    var mealCount: Int = 0
    var mealCalories: [String: Int] = [:]

    init() {}

    init(data: [String: Any]) {
        exerciseReps = Self.readInt(data["exerciseReps"])
        exercisePoints = Self.readInt(data["exercisePoints"])
        exerciseCalories = Self.readInt(data["exerciseCalories"])
        exerciseCount = Self.readInt(data["exerciseCount"])
        completedSets = Self.readInt(data["completedSets"])
        amSets = Self.readInt(data["amSets"])
        pmSets = Self.readInt(data["pmSets"])
        setReps = Self.readInt(data["setReps"])
        setXP = Self.readInt(data["setXP"])
        intakeCalories = Self.readInt(data["intakeCalories"])
        intakeWaterMl = Self.readInt(data["intakeWaterMl"])
        intakeCaffeineMg = Self.readInt(data["intakeCaffeineMg"])
        intakeAlcoholG = Self.readDouble(data["intakeAlcoholG"])
        mealCount = Self.readInt(data["mealCount"])
        if let rawMeals = data["mealCalories"] as? [String: Any] {
            mealCalories = rawMeals.mapValues { Self.readInt($0) }
        }
    }

    var dailySets: DailySets {
        DailySets(amSets: amSets, pmSets: pmSets)
    }

    static func readInt(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    static func readDouble(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }
}

struct WeeklyGoal: Codable, Identifiable {
    var id: String { exerciseId }
    var exerciseId: String
    var exerciseName: String
    var dailyReps: Int
    var targetReps: Int
}

// MARK: - セット構成設定

/// 1セットのメニュー構成
struct SetConfiguration: Codable {
    var exercises: [ExerciseInSet]

    static let defaultSet = SetConfiguration(exercises: [
        ExerciseInSet(exerciseId: "pushup", exerciseName: "腕立て伏せ", targetReps: 10, order: 0),
        ExerciseInSet(exerciseId: "squat", exerciseName: "スクワット", targetReps: 15, order: 1),
        ExerciseInSet(exerciseId: "situp", exerciseName: "腹筋", targetReps: 10, order: 2)
    ])
}

/// セット内の1種目
struct ExerciseInSet: Codable, Identifiable {
    var id: String { exerciseId }
    var exerciseId: String
    var exerciseName: String
    var targetReps: Int
    var order: Int
}

/// モーションセンサー感度設定
struct MotionSensitivity: Codable {
    var exerciseId: String
    var threshold: Double       // 変化閾値（デフォルト: 0.08）
    var minInterval: Double     // 最小rep間隔（デフォルト: 0.8秒）

    static let defaultSettings: [String: MotionSensitivity] = [
        "pushup": MotionSensitivity(exerciseId: "pushup", threshold: 0.06, minInterval: 0.6),
        "squat": MotionSensitivity(exerciseId: "squat", threshold: 0.08, minInterval: 0.7),
        "situp": MotionSensitivity(exerciseId: "situp", threshold: 0.10, minInterval: 0.8),
        "lunge": MotionSensitivity(exerciseId: "lunge", threshold: 0.15, minInterval: 1.2),
        "burpee": MotionSensitivity(exerciseId: "burpee", threshold: 0.20, minInterval: 2.0),
        "plank": MotionSensitivity(exerciseId: "plank", threshold: 0.0, minInterval: 0.0)
    ]
}

struct DayExercises: Identifiable {
    var id: String { date }
    var date: String
    var label: String
    var sets: [ExerciseSet]
    var totalReps: Int
    var totalPoints: Int
}

struct ExerciseSet: Identifiable {
    var id: String { "\(startTime.timeIntervalSince1970)" }
    var startTime: Date
    var period: String  // "午前" or "午後"
    var setNumber: Int  // その時間帯での連番（1, 2, 3...）
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

// MARK: - ログコンプリート（完全記録ボーナス）

extension AuthenticationManager {
    /// ログコンプリートボーナスをチェックして付与
    /// すでに今日付与済みの場合はスキップ
    private func checkAndAwardLogCompleteBonus(userId: String, date: Date) async {
        let calendar = Calendar.current
        let dateKey = calendar.startOfDay(for: date)

        // 今日すでにボーナスを付与済みかチェック
        let bonusDoc = db.collection("users").document(userId)
            .collection("log-complete-bonuses").document(Self.yyyyMMddFmt.string(from: dateKey))

        if let doc = try? await bonusDoc.getDocument(), doc.exists {
            // すでに付与済み
            return
        }

        // ボーナス付与: 100 XP
        let bonusXP = 100
        try? await bonusDoc.setData([
            "date": dateKey,
            "bonusXP": bonusXP,
            "timestamp": FieldValue.serverTimestamp()
        ])

        // プロフィールの totalPoints に加算
        if let profile = userProfile {
            let newTotal = profile.totalPoints + bonusXP
            try? await db.collection("users").document(userId).updateData([
                "totalPoints": newTotal
            ])
            // ローカル更新
            await MainActor.run {
                self.userProfile?.totalPoints = newTotal
            }
        }

        dlog("[LogComplete] ✅ ログコンプリートボーナス付与: +\(bonusXP) XP")
    }

    // dateFormatter は Self.yyyyMMddFmt に統一（computed var による毎回生成を廃止）

    // MARK: - ウィジェット同期（データを書いてからリロード）

    /// SharedUserDefaultsに最新データを書き込んでウィジェットをリロードする。
    /// DashboardView外からWidget更新が必要な場合はこちらを呼ぶ。
    static func syncWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.kfit.app") else { return }
        let tsm = TimeSlotManager.shared
        let hk = HealthKitManager.shared

        // streak / points
        defaults.set(shared.userProfile?.streak ?? 0, forKey: "streak")
        defaults.set(shared.userProfile?.totalPoints ?? 0, forKey: "totalPoints")
        // 今週のポイント（フル更新時にキャッシュされた値を維持）
        defaults.set(cachedWeeklyPoints, forKey: "weeklyPoints")

        // 全時間帯のトレーニング・マインドフル・食事・水分（目標は時間帯設定から）
        var trainingGoal = 0
        var mindfulnessGoal = 0
        var mealGoal = 0, drinkGoal = 0
        for slot in TimeSlot.allCases {
            if let goal = tsm.settings.goalFor(slot),
               tsm.progress.progressFor(slot) != nil {
                trainingGoal      += goal.trainingGoal
                // 20分ポモドーロ（スタンド）も Health 記録時間と同様にマインドフル目標へ合算
                let standGoalMinutes = (goal.standGoal.enabled && goal.timeSlot != .midnight) ? 20 : 0
                mindfulnessGoal   += goal.mindfulnessGoal + standGoalMinutes
                if goal.logGoal.mealGoal  > 0 { mealGoal  += goal.logGoal.mealGoal }
                if goal.logGoal.drinkGoal > 0 { drinkGoal += goal.logGoal.drinkGoal }
            }
        }
        // トレーニング回数・マインドフル分数は Apple Health の計測値を正源とする
        let trainingCompleted = hk.todayWorkoutCount
        let mindfulnessCompleted = Int(hk.todayMindfulnessMinutes.rounded())
        defaults.set(trainingCompleted,    forKey: "trainingCompleted")
        defaults.set(trainingGoal,         forKey: "trainingGoal")
        defaults.set(mindfulnessCompleted, forKey: "mindfulnessCompleted")
        defaults.set(mindfulnessGoal,      forKey: "mindfulnessGoal")
        let mealLoggedKcal = cachedAppIntakeCalories > 0
            ? cachedAppIntakeCalories
            : Int(hk.todayIntakeCalories)
        defaults.set(mealLoggedKcal, forKey: "mealLogged")
        defaults.set(mealGoal,             forKey: "mealGoal")
        defaults.set(Int(hk.todayIntakeWater), forKey: "drinkLogged")
        defaults.set(drinkGoal,            forKey: "drinkGoal")

        // 現在の時間帯
        let hour = Calendar.current.component(.hour, from: Date())
        let currentSlot = TimeSlot.forHour(hour)
        defaults.set(currentSlot.displayName, forKey: "currentTimeSlot")
        if let goal = tsm.settings.goalFor(currentSlot),
           let prog = tsm.progress.progressFor(currentSlot) {
            defaults.set(prog.trainingCompleted, forKey: "timeSlotCompleted")
            defaults.set(goal.trainingGoal,      forKey: "timeSlotGoal")
        }

        // ワークアウト・スタンド（HealthKit実績のみ保存、目標は廃止）
        defaults.set(hk.todayWorkoutMinutes, forKey: "workoutMinutes")
        defaults.set(0, forKey: "workoutGoal")
        defaults.set(hk.todayStandHours, forKey: "standHours")
        defaults.set(0, forKey: "standGoal")

        // カロリー収支：摂取 - 消費
        let burned = Int(hk.todayRestingCalories + hk.todayActiveCalories)
        let intake = Int(hk.todayIntakeCalories)
        defaults.set(intake - burned, forKey: "calorieBalance")

        let payloadHash = [
            trainingCompleted, trainingGoal, mindfulnessCompleted, mindfulnessGoal,
            Int(hk.todayIntakeCalories), mealGoal, Int(hk.todayIntakeWater), drinkGoal,
            hk.todayWorkoutMinutes, hk.todayStandHours, intake - burned,
            shared.userProfile?.streak ?? 0, shared.userProfile?.totalPoints ?? 0, cachedWeeklyPoints
        ].map(String.init).joined(separator: "|")

        guard payloadHash != lastWidgetPayloadHash else {
            dlog("[Widget] ✅ syncWidgetData skipped - payload unchanged")
            return
        }
        lastWidgetPayloadHash = payloadHash
        scheduleWidgetReload()
        dlog("[Widget] ✅ syncWidgetData: training=\(trainingCompleted)/\(trainingGoal) streak=\(shared.userProfile?.streak ?? 0)")
    }

    private static func scheduleWidgetReload() {
        pendingWidgetReload?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
            dlog("[Widget] ✅ reloadAllTimelines debounced")
        }
        pendingWidgetReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }
}

import Foundation
import UIKit

@MainActor
/// 公開投稿を publicProfiles/{uid}/posts に同期するヘルパー（TOMOフィードの友達共有用）。
/// Firestore ドキュメントの 1MiB 制限に収めるため、画像は長辺800px・JPEG0.7 に縮小して埋め込む。
enum PublicFeedPublisher {
    private static var db: Firestore { Firestore.firestore() }
    private static var currentUid: String? { Auth.auth().currentUser?.uid }
    private static var authorName: String {
        UserDefaults.standard.string(forKey: "cachedCurrentUserName") ?? ""
    }
    private static var authorPhotoURL: String {
        UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
    }

    // MARK: - Debounce（同じIDへの書き込みを500ms待ってまとめる）
    // @MainActor コンテキスト専用。EduLogManager は MainActor なので安全。
    nonisolated(unsafe) private static var _pendingEduTasks: [String: Task<Void, Never>] = [:]

    /// デバウンス付き publishEdu。OCR/LLM完了など短時間に複数回呼ばれる場合にまとめる。
    @MainActor
    static func publishEduDebounced(_ item: EduLogHistoryItem) {
        _pendingEduTasks[item.id]?.cancel()
        _pendingEduTasks[item.id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            publishEdu(item)
            _pendingEduTasks[item.id] = nil
        }
    }

    static func sharedThumbnailBase64(from data: Data?) -> String? {
        guard let data else { return nil }
        guard let img = ThumbnailCache.downsample(data: data, maxPixel: 800),
              let jpeg = img.jpegData(compressionQuality: 0.7) else { return nil }
        return jpeg.base64EncodedString()
    }

    /// EDU/体重/Duolingo等の公開投稿を同期。非公開なら既存の共有投稿を削除する。
    static func publishEdu(_ item: EduLogHistoryItem) {
        guard let uid = currentUid else { return }
        guard item.isPublic else { delete(uid: uid, postId: item.id); return }
        var data: [String: Any] = [
            "kind": "edu",
            "id": item.id,
            "activityName": item.activityName,
            "activityEmoji": item.activityEmoji,
            "comment": item.comment,
            "timestamp": Timestamp(date: item.timestamp),
            "likeCount": item.likeCount,
            "authorName": item.authorName.isEmpty ? authorName : item.authorName,
            "authorPhotoURL": item.authorPhotoURL.isEmpty ? authorPhotoURL : item.authorPhotoURL
        ]
        let thumbRawEdu: Data? = item.thumbnailPath.flatMap { ThumbnailFileStore.load(path: $0) } ?? item.thumbnailData
        if let t = sharedThumbnailBase64(from: thumbRawEdu) { data["thumbnail"] = t }
        if let v = item.weightKg { data["weightKg"] = v }
        if let v = item.bodyFatPercent { data["bodyFatPercent"] = v }
        if let v = item.extractedPhrase { data["extractedPhrase"] = v }
        if let v = item.extractedLanguageCode { data["extractedLanguageCode"] = v }
        if let v = item.translationJA { data["translationJA"] = v }
        if let v = item.pronunciation { data["pronunciation"] = v }
        if let v = item.calories { data["calories"] = v }
        if let v = item.grammarNote  { data["grammarNote"]  = v }
        if let v = item.mistakeNote  { data["mistakeNote"]  = v }
        if let ex = item.exampleSentences,
           let encoded = try? JSONEncoder().encode(ex),
           let arr = try? JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] {
            data["exampleSentences"] = arr
        }
        if let v = item.sharedUrl         { data["sharedUrl"]         = v }
        if let v = item.sharedTitle       { data["sharedTitle"]       = v }
        if let v = item.sharedDescription { data["sharedDescription"] = v }
        if let v = item.sharedImageURL    { data["sharedImageURL"]    = v }
        write(uid: uid, postId: item.id, data: data)
    }

    /// 食事フォトログの公開投稿を同期。非公開なら削除する。
    static func publishFood(_ item: PhotoLogHistoryItem) {
        guard let uid = currentUid else { return }
        let postId = "food_\(item.id)"
        guard item.isPublic else { delete(uid: uid, postId: postId); return }
        var data: [String: Any] = [
            "kind": "food",
            "id": item.id,
            "activityName": "食事ログ",
            "activityEmoji": "🍽️",
            "comment": item.displayName,
            "timestamp": Timestamp(date: item.timestamp),
            "likeCount": item.likeCount,
            "calories": item.calories,
            "authorName": authorName,
            "authorPhotoURL": authorPhotoURL
        ]
        let thumbRawFood: Data? = item.thumbnailPath.flatMap { ThumbnailFileStore.load(path: $0) } ?? item.thumbnailData
        if let t = sharedThumbnailBase64(from: thumbRawFood) { data["thumbnail"] = t }
        write(uid: uid, postId: postId, data: data)
    }

    static func deleteEdu(id: String) {
        guard let uid = currentUid else { return }
        delete(uid: uid, postId: id)
    }

    static func deleteFood(id: String) {
        guard let uid = currentUid else { return }
        delete(uid: uid, postId: "food_\(id)")
    }

    private static func write(uid: String, postId: String, data: [String: Any]) {
        Task {
            try? await db.collection("publicProfiles").document(uid)
                .collection("posts").document(postId).setData(data, merge: true)
        }
    }

    private static func delete(uid: String, postId: String) {
        Task {
            try? await db.collection("publicProfiles").document(uid)
                .collection("posts").document(postId).delete()
        }
    }
}

@MainActor
class PhotoLogManager: ObservableObject {
    static let shared = PhotoLogManager()

    @Published var logs: [PhotoLogEntry] = []
    @Published var isAnalyzing = false
    @Published var history: [PhotoLogHistoryItem] = []
    /// history の内容変化（件数変化を含まない更新）を検知するためのバージョンカウンタ
    @Published var historyVersion: Int = 0

    private let historyKey = "photoLogHistory"

    private init() {
        loadHistory()
    }

    // MARK: - History

    /// 履歴をUserDefaultsから読み込む。旧データの thumbnailData はファイルに移行する。
    private func loadHistory() {
        guard let raw = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([PhotoLogHistoryItem].self, from: raw) else { return }

        var needsMigration = false
        history = items.map { item in
            // 旧データ移行: thumbnailData があり thumbnailPath がない場合
            guard let thumbData = item.thumbnailData, item.thumbnailPath == nil else { return item }
            var copy = item
            if let path = ThumbnailFileStore.save(thumbData, id: "photo_\(item.id)") {
                copy.thumbnailPath = path
                copy.thumbnailData = nil
                needsMigration = true
            }
            return copy
        }
        // 移行があった場合は新形式（thumbnailData なし）で保存し直す
        if needsMigration { persistHistory() }
    }

    /// 履歴をUserDefaultsに保存。ファイル保存済みの場合のみ thumbnailData を除外する。
    /// 差分なし（idリスト が前回と同一）の場合はエンコードをスキップして CPU 節約。
    private var _lastPersistedSignature: String = ""
    private func persistHistory() {
        let snapshot = history
        // savedToHealthKit の変化も検知できるようシグネチャに含める
        let sig = snapshot.map { "\($0.id):\($0.savedToHealthKit)" }.joined(separator: ",")
        guard sig != _lastPersistedSignature else { return }  // 変更なし → スキップ
        _lastPersistedSignature = sig
        historyVersion &+= 1  // 変化を監視側に通知
        Task.detached(priority: .utility) {
            let stripped = snapshot.map { item -> PhotoLogHistoryItem in
                guard item.thumbnailPath != nil else { return item }  // ファイル未保存はそのまま保持
                var copy = item
                copy.thumbnailData = nil   // ファイル保存済みなので UserDefaults からは除外
                return copy
            }
            if let data = try? JSONEncoder().encode(stripped) {
                UserDefaults.standard.set(data, forKey: self.historyKey)
            }
        }
    }

    /// 既存の公開投稿をまとめて共有フィードへ同期（機能導入前の投稿のバックフィル用）
    func syncAllPublicPosts() {
        for item in history where item.isPublic {
            PublicFeedPublisher.publishFood(item)
        }
    }

    /// 履歴アイテムを削除
    func deleteHistoryItem(id: String) {
        history.removeAll { $0.id == id }
        persistHistory()
        PublicFeedPublisher.deleteFood(id: id)
        ThumbnailFileStore.delete(id: "photo_\(id)")
    }

    /// TOMOフィードへの公開フラグを切り替える
    func setPublic(id: String, isPublic: Bool) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].isPublic = isPublic
        persistHistory()
        if isPublic {
            PublicFeedPublisher.publishFood(history[idx])
        } else {
            PublicFeedPublisher.deleteFood(id: id)
        }
    }

    /// いいねをトグル
    func toggleLike(id: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        history[idx].isLiked.toggle()
        history[idx].likeCount = max(0, history[idx].likeCount + (history[idx].isLiked ? 1 : -1))
        persistHistory()
        PublicFeedPublisher.publishFood(history[idx])
    }

    /// フィードコメントを追加
    func addFeedComment(id: String, text: String) {
        guard let idx = history.firstIndex(where: { $0.id == id }) else { return }
        let authorName     = AuthenticationManager.shared.userProfile?.username ?? ""
        let authorPhotoURL = UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? ""
        let c = FeedComment(text: text, authorName: authorName, authorPhotoURL: authorPhotoURL)
        history[idx].feedComments.append(c)
        persistHistory()
    }

    /// フィードコメントを削除
    func deleteFeedComment(itemId: String, commentId: String) {
        guard let idx = history.firstIndex(where: { $0.id == itemId }) else { return }
        history[idx].feedComments.removeAll { $0.id == commentId }
        persistHistory()
    }

    /// お気に入りをトグル
    func toggleFavorite(id: String) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            history[idx].isFavorite.toggle()
            persistHistory()
        }
    }

    /// 履歴アイテムを更新（編集）
    func updateHistoryItem(_ item: PhotoLogHistoryItem) {
        if let idx = history.firstIndex(where: { $0.id == item.id }) {
            history[idx] = item
            persistHistory()
            PublicFeedPublisher.publishFood(item)
        }
    }

    /// 写真を分析して栄養情報を取得
    func analyzePhoto(_ image: UIImage, comment: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // 画像をAPI送信用に縮小・圧縮してBase64エンコード
        guard let imageData = compressForAPI(image) else {
            throw PhotoLogError.invalidImage
        }
        let base64Image = imageData.base64EncodedString()

        // プロンプト作成
        let prompt = createAnalysisPrompt(comment: comment)

        // ユーザー API キー未設定時はサーバー代理（aiProxy）経由 — 設定ゼロで動くデフォルト経路
        guard !settings.apiKey.isEmpty else {
            let activeDayCount = UserDefaults.standard.integer(forKey: "retention.activeDayCount")
            let isNinety = activeDayCount < 5
            let text = try await AIProxyClient.call(
                prompt: prompt,
                imageBase64: base64Image,
                category: "food",
                isNinetyMode: isNinety,
                activeDays: activeDayCount
            )
            return try parseNutritionJSON(text)
        }

        // 自分のキーを設定している上級者は従来どおり直接呼び出し（後方互換）
        switch settings.provider {
        case .openAI:
            return try await analyzeWithOpenAI(base64Image: base64Image, prompt: prompt, settings: settings)
        case .anthropic:
            return try await analyzeWithAnthropic(base64Image: base64Image, prompt: prompt, settings: settings)
        case .google:
            return try await analyzeWithGoogle(base64Image: base64Image, prompt: prompt, settings: settings)
        }
    }

    /// フォトログを保存（履歴への追加なし・履歴から再利用した場合）
    func savePhotoLogWithoutHistory(_ entry: PhotoLogEntry) {
        logs.insert(entry, at: 0)
        // TODO: Firestoreに保存
    }

    /// フォトログを保存
    func savePhotoLog(_ entry: PhotoLogEntry) {
        logs.insert(entry, at: 0)
        // TODO: Firestoreに保存

        // 履歴に追加（画像なし軽量アイテム）
        guard let nutrition = entry.analyzedNutrition else { return }
        let foodName = extractFoodName(from: nutrition.description)
        var item = PhotoLogHistoryItem(
            foodName: foodName,
            comment: entry.comment,
            analyzedNutrition: nutrition,
            isFavorite: entry.isFavorite,
            isPublic: entry.isPublic
        )
        // サムネイルをファイルシステムに保存（UserDefaultsに画像バイナリを含めない）
        if let image = entry.image, let thumbData = makeThumbnailHQ(from: image) {
            item.thumbnailPath = ThumbnailFileStore.save(thumbData, id: "photo_\(item.id)")
        }
        history.insert(item, at: 0)
        persistHistory()
        PublicFeedPublisher.publishFood(item)

        // 写真アップロードボーナス: +10 XP
        Task { await AuthenticationManager.shared.awardPoints(10) }

        // HealthKitに栄養素を保存（Apple Healthとの摂取カロリー一致のため）
        // 保存完了後に savedToHealthKit = true をセットして二重計算を防ぐ
        let itemId = item.id
        let mealNutrition = MealNutrition(
            calories: nutrition.calories,
            protein: nutrition.protein,
            fat: nutrition.fat,
            carbs: nutrition.carbs,
            sugar: nutrition.sugar,
            fiber: nutrition.fiber,
            sodium: nutrition.sodium
        )
        let savedAt = item.timestamp
        Task { @MainActor in
            await HealthKitManager.shared.saveMealNutrition(mealNutrition, date: savedAt)
            if let idx = self.history.firstIndex(where: { $0.id == itemId }) {
                self.history[idx].savedToHealthKit = true
                self.persistHistory()
            }
        }
    }

    /// description の最初の文（句読点または改行まで）を料理名として抽出
    private func extractFoodName(from description: String) -> String {
        let separators = CharacterSet(charactersIn: "、。,.\n")
        let name = description.components(separatedBy: separators).first ?? description
        return String(name.prefix(20))
    }

    /// UIImage からサムネイルを生成（固定サイズ版・旧形式互換）
    private func makeThumbnail(from image: UIImage, size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumb.jpegData(compressionQuality: 0.6)
    }

    /// 高画質サムネイル（アスペクト比を保持して最大1200px・Retina対応 + 写真補正）
    private func makeThumbnailHQ(from image: UIImage, maxDimension: CGFloat = 1200) -> Data? {
        // アップロード前に明るさ・コントラスト・彩度を自動補正
        let enhanced = image.enhancedForUpload()
        let size = enhanced.size
        let maxSide = max(size.width, size.height)
        let target: UIImage
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            target = renderer.image { _ in enhanced.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            target = enhanced
        }
        return target.jpegData(compressionQuality: 0.88)
    }

    /// API送信用に最大800px・低品質で圧縮
    private func compressForAPI(_ image: UIImage, maxDimension: CGFloat = 800) -> Data? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        let target: UIImage
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            target = image
        }
        return target.jpegData(compressionQuality: 0.6)
    }

    // MARK: - Private Methods

    private func createAnalysisPrompt(comment: String) -> String {
        var prompt = """
        この画像に写っている食べ物や飲み物を分析して、以下の情報を**必ずJSON形式のみ**で返してください。説明文や追加のテキストは含めず、JSONのみを返してください。

        JSONフォーマット:
        {
          "description": "食品の簡潔な説明（40字以内）",
          "calories": カロリー（kcal、整数）,
          "protein": たんぱく質（g、小数）,
          "fat": 脂質（g、小数）,
          "carbs": 炭水化物（g、小数）,
          "sugar": 糖質（g、小数）,
          "fiber": 食物繊維（g、小数）,
          "sodium": 塩分（g、小数）,
          "water": 水分量（ml、整数）,
          "caffeine": カフェイン（mg、整数）,
          "alcohol": アルコール（g、小数）,
          "confidence": 推定の確度（0.0-1.0）
        }
        """

        if !comment.isEmpty {
            prompt += "\n\nユーザーコメント: \(comment)"
            prompt += "\nコメントから食事タイプ（朝食、昼食、夕食）や飲み物の種類（コーヒー、ワインなど）を推測してください。"
        }

        prompt += "\n\n回答は上記のJSON形式のみで返してください。"

        return prompt
    }

    // MARK: - OpenAI API

    private func analyzeWithOpenAI(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_completion_tokens": 1024,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoLogError.apiError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            dlog("[PhotoLog] OpenAI API error (status \(httpResponse.statusCode)): \(errorMessage)")
            throw PhotoLogError.apiError("OpenAI API error (status \(httpResponse.statusCode)): \(errorMessage)")
        }

        let rawOpenAIResponse = String(data: data, encoding: .utf8) ?? ""
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            dlog("[PhotoLog] Failed to parse OpenAI API response structure: \(rawOpenAIResponse)")
            throw PhotoLogError.invalidResponse("[OpenAI] レスポンス構造が想定外:\n\(rawOpenAIResponse)")
        }

        return try parseNutritionJSON(content)
    }

    // MARK: - Anthropic API

    private func analyzeWithAnthropic(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": settings.effectiveModel,
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]],
                        ["type": "text", "text": prompt]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoLogError.apiError("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            dlog("[PhotoLog] Anthropic API error (status \(httpResponse.statusCode)): \(errorMessage)")
            throw PhotoLogError.apiError("Anthropic API error (status \(httpResponse.statusCode)): \(errorMessage)")
        }

        let rawAnthropicResponse = String(data: data, encoding: .utf8) ?? ""
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            dlog("[PhotoLog] Failed to parse Anthropic API response structure: \(rawAnthropicResponse)")
            throw PhotoLogError.invalidResponse("[Anthropic] レスポンス構造が想定外:\n\(rawAnthropicResponse)")
        }

        return try parseNutritionJSON(text)
    }

    // MARK: - Google Gemini API

    private func analyzeWithGoogle(base64Image: String, prompt: String, settings: LLMSettings) async throws -> AnalyzedNutrition {
        // Google Gemini APIのエンドポイント (v1betaを使用)
        let modelName = settings.effectiveModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(settings.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        dlog("[PhotoLog] Google API URL: \(url.absoluteString.replacingOccurrences(of: settings.apiKey, with: "***"))")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        ["inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64Image
                        ]]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "topP": 1.0,
                "topK": 32,
                "maxOutputTokens": 2048
            ]
        ]

        dlog("[PhotoLog] Google API request payload keys: \(payload.keys)")

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoLogError.apiError("Invalid response")
        }

        // エラーレスポンスをログに出力
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            dlog("[PhotoLog] Google API error (status \(httpResponse.statusCode)): \(errorMessage)")
            throw PhotoLogError.apiError("Google API error (status \(httpResponse.statusCode)): \(errorMessage)")
        }

        let rawGoogleResponse = String(data: data, encoding: .utf8) ?? ""
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // レスポンス構造をログに出力
        dlog("[PhotoLog] Google API response: \(json ?? [:])")

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            dlog("[PhotoLog] Failed to parse Google API response structure: \(rawGoogleResponse)")
            throw PhotoLogError.invalidResponse("[Google] レスポンス構造が想定外:\n\(rawGoogleResponse)")
        }

        return try parseNutritionJSON(text)
    }

    // MARK: - JSON Parsing

    private func parseNutritionJSON(_ jsonString: String) throws -> AnalyzedNutrition {
        dlog("[PhotoLog] Parsing JSON from: \(jsonString.prefix(200))...")

        // JSONの前後にあるテキストを除去
        var cleanedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // ```json で囲まれている場合は除去
        if cleanedString.hasPrefix("```json") {
            cleanedString = cleanedString.replacingOccurrences(of: "```json", with: "")
        }
        if cleanedString.hasPrefix("```") {
            cleanedString = cleanedString.replacingOccurrences(of: "```", with: "")
        }
        if cleanedString.hasSuffix("```") {
            cleanedString = String(cleanedString.dropLast(3))
        }

        // JSONの開始位置を探す
        if let startIndex = cleanedString.firstIndex(of: "{"),
           let endIndex = cleanedString.lastIndex(of: "}") {
            cleanedString = String(cleanedString[startIndex...endIndex])
        }

        // 文字列値内にある改行文字をスペースに置換（LLMが長い説明を複数行で返すとパース失敗するため）
        cleanedString = cleanedString
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        cleanedString = cleanedString.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSONパース（失敗時は末尾に "}" を補完してリトライ — max_tokens 超えで切れた場合の対策）
        func tryParse(_ s: String) -> [String: Any]? {
            guard let d = s.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        }
        let json: [String: Any]
        if let parsed = tryParse(cleanedString) {
            json = parsed
        } else if let parsed = tryParse(cleanedString + "}") {
            json = parsed
        } else {
            dlog("[PhotoLog] Failed to parse JSON: \(cleanedString)")
            throw PhotoLogError.invalidResponse("[JSONパース失敗] モデルの返答:\n\(cleanedString)")
        }

        var nutrition = AnalyzedNutrition()
        let rawDesc = json["description"] as? String ?? ""
        nutrition.description = rawDesc.count > 40 ? String(rawDesc.prefix(40)) : rawDesc
        nutrition.calories = (json["calories"] as? NSNumber).map { Int($0.intValue) } ?? 0
        nutrition.protein = (json["protein"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.fat = (json["fat"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.carbs = (json["carbs"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.sugar = (json["sugar"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.fiber = (json["fiber"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.sodium = (json["sodium"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.water = (json["water"] as? NSNumber).map { Int($0.intValue) } ?? 0
        nutrition.caffeine = (json["caffeine"] as? NSNumber).map { Int($0.intValue) } ?? 0
        nutrition.alcohol = (json["alcohol"] as? NSNumber)?.doubleValue ?? 0.0
        nutrition.confidence = (json["confidence"] as? NSNumber)?.doubleValue ?? 0.8

        dlog("[PhotoLog] Successfully parsed nutrition: \(nutrition.calories)kcal")

        return nutrition
    }
}

// MARK: - AI プロキシクライアント（サーバー代理呼び出し）

/// Cloud Functions の aiProxy callable を REST プロトコルで直接呼ぶ軽量クライアント。
/// FirebaseFunctions SDK に依存しない（kedu など SDK を持たないターゲットとソース共有するため）。
/// ユーザーが自分の API キーを設定していない場合のデフォルト経路（docs/ai_proxy_plan.md 方式B）。
enum AIProxyClient {
    struct ProxyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// aiProxy を呼び出してモデルの応答テキストを返す。
    /// クォータ超過時はサーバーの日本語メッセージ（Plus 誘導文言）をそのまま throw する。
    static func call(
        prompt: String,
        imageBase64: String? = nil,
        category: String = "general",
        isNinetyMode: Bool = false,
        activeDays: Int = 0
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw ProxyError(message: "AI解析にはログインが必要です")
        }
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/aiProxy") else {
            throw ProxyError(message: "AIプロキシのURLを構成できません")
        }
        let token = try await user.getIDToken()

        var payload: [String: Any] = [
            "prompt": prompt,
            "category": category,
            "isNinetyMode": isNinetyMode,
            "activeDays": activeDays,
        ]
        if let imageBase64 { payload["imageBase64"] = imageBase64 }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (data, response) = try await URLSession.shared.data(for: req)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            // callable のエラー形式: { "error": { "message": "...", "status": "RESOURCE_EXHAUSTED" } }
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? "AI解析に失敗しました (HTTP \(status))"
            throw ProxyError(message: message)
        }
        guard let result = json?["result"] as? [String: Any],
              let text = result["text"] as? String, !text.isEmpty else {
            throw ProxyError(message: "AI応答の形式が想定外です")
        }
        return text
    }
}

enum PhotoLogError: LocalizedError {
    case noAPIKey
    case invalidImage
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "APIキーが設定されていません"
        case .invalidImage:
            return "画像の処理に失敗しました"
        case .apiError(let message):
            return "API呼び出しエラー: \(message)"
        case .invalidResponse(let rawContent):
            let snippet = String(rawContent.prefix(300))
            return """
            レスポンスの解析に失敗しました。

            受信内容（先頭300文字）:
            \(snippet)

            【考えられる原因と対処法】
            • APIキーが正しくない → 設定画面でキーを確認
            • モデル名が間違っている → 設定でモデルを変更
            • 安全フィルターで画像がブロック → 別の画像を試す
            • JSONを返さないモデル → Gemini/GPT-4o等に変更
            """
        }
    }
}

