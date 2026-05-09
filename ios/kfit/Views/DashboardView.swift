import SwiftUI
import UIKit
import HealthKit


struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var habitManager = HabitStackManager.shared
    @StateObject private var healthKit    = HealthKitManager.shared
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps     = 0
    @State private var totalCalories = 0
    @State private var totalXP      = 0
    @State private var dailySets    = DailySets(amSets: 0, pmSets: 0)
    @State private var weeklySetProgress = WeeklySetProgress(completedSets: 0, dailyGoal: 2)
    @State private var calorieGoal = DailyCalorieGoal()
    @State private var isLoading    = false  // 初期値をfalseに変更
    @State private var mascotBounce = false
    @State private var showTracker  = false
    @State private var showHabits   = false
    @State private var hasLoadedOnce = false  // 1度だけロード実行するフラグ
    @State private var expandedSetId: UUID? = nil  // 展開中のセットID
    @State private var showCalorieGoalEdit = false  // カロリー目標編集モーダル
    @State private var tempCalorieTarget = 500  // 一時的なカロリー目標

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            VStack(spacing: 0) {
                heroSection
                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            dailySetsCard
                            weeklyGoalCard
                            calorieGoalCard
                            habitStackCard
                            todaySummaryCard
                            healthSummaryCard
                            challengeCard
                            quickMenu
                            Spacer(minLength: 5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 0)
                        .padding(.bottom, 0)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .navigationBarHidden(true)
        // 画面下部に固定のCTAボタン（タブバーの上）
        .safeAreaInset(edge: .bottom) {
            if !isLoading { startTrainingButton }
        }
        .fullScreenCover(isPresented: $showTracker) {
            ExerciseTrackerView()
                .environmentObject(authManager)
        }
        .onChange(of: showTracker) { _, newValue in
            if !newValue {
                // ExerciseTrackerViewが閉じられた時にデータを再読み込み
                Task {
                    print("🔄 ExerciseTrackerView閉じた - データ再読み込み")
                    await loadData()
                }
            }
        }
        .sheet(isPresented: $showHabits) {
            NavigationView { HabitStackView() }
        }
        .sheet(isPresented: $showCalorieGoalEdit) {
            calorieGoalEditSheet
        }
        .onAppear {
            withAnimation { mascotBounce = true }
            // 初回のみloadDataを実行
            if !hasLoadedOnce {
                hasLoadedOnce = true
                isLoading = true
                Task {
                    print("🟢 DashboardView.onAppear - loadDataを開始")
                    // HealthKit権限をリクエスト
                    if healthKit.isAvailable && !healthKit.isAuthorized {
                        await healthKit.requestAuthorization()
                    }
                    await loadData()
                }
            } else {
                print("⚠️ DashboardView.onAppear - 既にロード済み、スキップ")
            }
        }
    }

    // MARK: - 常時表示CTAボタン（タブバー上に固定）
    private var startTrainingButton: some View {
        Button { showTracker = true } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 40, height: 40)
                        .scaleEffect(mascotBounce && todayExercises.isEmpty ? 1.12 : 1.0)
                        .animation(
                            todayExercises.isEmpty
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: mascotBounce
                        )
                    Text(todayExercises.isEmpty ? "💪" : "➕")
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(todayExercises.isEmpty
                         ? "今日のトレーニングを始めよう！"
                         : "さらに記録する")
                        .font(.callout).fontWeight(.black)
                        .foregroundColor(.white)
                    Text(todayExercises.isEmpty
                         ? "タップして開始"
                         : "\(todayExercises.count) 種目 · \(totalXP) XP")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.88))
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.duoGreen.opacity(
                    todayExercises.isEmpty ? 0.5 : 0.3
                ), radius: todayExercises.isEmpty ? 10 : 6, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .padding(.bottom, 0)
        .background(
            Color.duoBg
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - ヒーロー（極小1行バー）
    private var heroSection: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack(spacing: 0) {
                    // ── ロゴ ──────────────────
                    HStack(spacing: 4) {
                        Image("mascot")
                            .resizable().scaledToFill()
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                        Text("DuoFit")
                            .font(.system(size: 15, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // ── 統計 3項目（横1列）───
                    HStack(spacing: 6) {
                        miniStat("🔥", "\(authManager.userProfile?.streak ?? 0)", "連続")
                        repCalStat(reps: totalReps, kcal: totalCalories)
                        miniStat("⭐", "\(authManager.userProfile?.totalPoints ?? 0)", "XP")
                    }

                    Spacer()

                    // ── ログアウト ────────────
                    Button { authManager.signOut() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 8).weight(.bold))
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(3)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, max(0, geometry.safeAreaInsets.top - 22))
                .padding(.bottom, 0)
            }
        }
        .frame(height: 2 + (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44))
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Text(icon).font(.system(size: 10))
                Text(value)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.82))
        }
    }

    /// 回数＋カロリーを2行で表示するヘッダー統計アイテム
    @ViewBuilder
    private func repCalStat(reps: Int, kcal: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Text("⚡").font(.system(size: 10))
                Text("\(reps)回")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("\(kcal)kcal")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.white.opacity(0.82))
        }
    }

    // MARK: - 今日のセット状況カード
    private var dailySetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // タイトル行
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("今日のセット状況").fontWeight(.black)
                }
                .font(.headline)
                .foregroundColor(Color.duoDark)

                Spacer()

                if dailySets.isGoalMet {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("達成！")
                            .font(.caption).fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.duoGreen)
                    .cornerRadius(20)
                } else {
                    Text("あと \(dailySets.pmSetsNeeded) セット")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoOrange)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.duoOrange.opacity(0.12))
                        .cornerRadius(20)
                }
            }

            Divider()

            // AM / PM 行
            VStack(spacing: 8) {
                setRow(
                    icon: "🌅",
                    label: "午前（〜12時）",
                    count: dailySets.amSets,
                    needed: 1,
                    isFlexible: true
                )
                setRow(
                    icon: "🌆",
                    label: dailySets.amSets == 0 ? "午後（12時〜）※2セット必要" : "午後（12時〜）",
                    count: dailySets.pmSets,
                    needed: dailySets.amSets == 0 ? 2 : 1,
                    isFlexible: false
                )
            }

            // 達成メッセージ
            if dailySets.isGoalMet {
                HStack(spacing: 6) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 22, height: 22).clipShape(Circle())
                    Text(dailySets.amSets == 0
                         ? "午後2セットで目標クリア！すごい💪"
                         : "午前・午後バッチリ！最高の一日🎉")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                }
                .padding(.top, 2)
            } else if dailySets.amSets + dailySets.pmSets == 0 {
                Text("今日はまだトレーニングしていません。始めましょう！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .padding(.top, 2)
            } else if dailySets.amSets == 0 && dailySets.pmSets == 1 {
                Text("午後あと1セット、または午前1セットで達成！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private func setRow(icon: String, label: String, count: Int, needed: Int, isFlexible: Bool) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.subheadline)
                .frame(width: 24)

            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)

            Spacer()

            // セットアイコン
            HStack(spacing: 4) {
                ForEach(0..<needed, id: \.self) { idx in
                    Image(systemName: idx < count ? "circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(idx < count ? Color.duoGreen : Color(.systemGray3))
                }
            }

            // 状態テキスト
            if count >= needed {
                Text("完了")
                    .font(.caption2).fontWeight(.black).foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoGreen.opacity(0.12)).cornerRadius(6)
            } else if count > 0 {
                Text("\(count)/\(needed)")
                    .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoOrange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoOrange.opacity(0.12)).cornerRadius(6)
            } else {
                Text("未実施")
                    .font(.caption2).fontWeight(.medium).foregroundColor(Color.duoSubtitle)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(.systemGray5)).cornerRadius(6)
            }
        }
    }

    // MARK: - ハビットスタックカード
    private var habitStackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                    Text("ハビットスタック").fontWeight(.black)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Button {
                    showHabits = true
                } label: {
                    Text(habitManager.habits.isEmpty ? "設定する" : "管理")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.duoGreen.opacity(0.12))
                        .cornerRadius(8)
                }
            }

            if habitManager.habits.isEmpty {
                // 未設定状態
                Button { showHabits = true } label: {
                    HStack(spacing: 10) {
                        Text("🔗").font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("日課とトレーニングをリンク")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                            Text("歯磨き後・コーヒー後などに通知")
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    .padding(12)
                    .background(Color.duoGreen.opacity(0.06))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                // 習慣一覧（有効なものだけ表示、最大3件）
                let active = habitManager.habits.filter { $0.isEnabled }.prefix(3)
                ForEach(Array(active)) { habit in
                    HStack(spacing: 10) {
                        Text(habit.emoji).font(.title3)
                        Text(habit.name)
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(habit.timeString)
                                .font(.caption).fontWeight(.bold)
                        }
                        .foregroundColor(Color.duoGreen)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        Image(systemName: "figure.run")
                            .font(.caption2)
                            .foregroundColor(Color.duoGreen)
                    }
                    .padding(.vertical, 4)
                    if habit.id != active.last?.id {
                        Divider()
                    }
                }
                if habitManager.habits.filter({ $0.isEnabled }).count > 3 {
                    Text("他 \(habitManager.habits.filter { $0.isEnabled }.count - 3) 件")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }

    // MARK: - 週間目標カード (Web互換デザイン)
    private var weeklyGoalCard: some View {
        let activeDays = 5
        let weeklyTarget = weeklySetProgress.dailyGoal * activeDays
        let today = Calendar.current.dateComponents([.weekday], from: Date()).weekday ?? 1
        let activeDaysElapsed = max(0, min(today - 1, activeDays)) // 月曜=1, 日曜=0として計算
        let expectedNow = weeklySetProgress.dailyGoal * activeDaysElapsed
        let pct = expectedNow > 0 ? min(Double(weeklySetProgress.completedSets) / Double(expectedNow) * 100, 100) : 0
        let weekPct = weeklyTarget > 0 ? min(Double(weeklySetProgress.completedSets) / Double(weeklyTarget) * 100, 100) : 0
        let isOnTrack = pct >= 100

        return VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundColor(Color.duoGreen)
                Text("週間目標").fontWeight(.black)
                Spacer()
                Text("1日\(weeklySetProgress.dailyGoal)セット × \(activeDays)日")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(6)
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            // 進捗表示
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(weeklySetProgress.completedSets)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
                Text("/ \(weeklyTarget) セット")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 4)
                Spacer()
                Text("\(Int(weekPct))%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 14)
                    Capsule().fill(
                        LinearGradient(
                            colors: isOnTrack ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [Color.duoYellow, Color.duoOrange],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(14, geo.size.width * CGFloat(weekPct / 100)), height: 14)
                }
            }
            .frame(height: 14)

            Text(isOnTrack ? "🎉 ペース通り！" : "今日まで目標 \(expectedNow) セット（\(activeDaysElapsed)日経過）")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: (isOnTrack ? Color.duoGreen : Color.duoYellow).opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - 目標カロリーカード
    private var calorieGoalCard: some View {
        let percent = calorieGoal.percentAchieved
        let isAchieved = percent >= 100

        return VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .foregroundColor(Color.duoOrange)
                Text("今日の目標カロリー").fontWeight(.black)
                Spacer()
                Button {
                    tempCalorieTarget = calorieGoal.targetCalories
                    showCalorieGoalEdit = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            // 進捗表示
            HStack(alignment: .bottom, spacing: 8) {
                Text("\(calorieGoal.consumedCalories)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoOrange)
                Text("/ \(calorieGoal.targetCalories) kcal")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 4)
                Spacer()
                Text("\(percent)%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoOrange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 12)
                    Capsule().fill(
                        LinearGradient(
                            colors: isAchieved ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [Color.duoOrange, Color.duoRed],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, geo.size.width * CGFloat(percent) / 100), height: 12)
                }
            }
            .frame(height: 12)

            Text(isAchieved ? "🎉 目標達成！" : "運動とApple Healthから自動集計")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(isAchieved ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: (isAchieved ? Color.duoGreen : Color.duoOrange).opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - カロリー目標編集シート
    private var calorieGoalEditSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("1日の目標消費カロリーを設定")
                    .font(.headline)
                    .foregroundColor(Color.duoDark)
                    .padding(.top, 20)

                VStack(spacing: 16) {
                    HStack {
                        Button {
                            if tempCalorieTarget > 100 {
                                tempCalorieTarget -= 50
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color.duoOrange)
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            Text("\(tempCalorieTarget)")
                                .font(.system(size: 56, weight: .black, design: .rounded))
                                .foregroundColor(Color.duoGreen)
                            Text("kcal")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Button {
                            tempCalorieTarget += 50
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color.duoGreen)
                        }
                    }
                    .padding(.horizontal, 32)

                    Text("週間目標に基づいたデフォルト値から調整できます")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        await authManager.saveDailyCalorieGoal(targetCalories: tempCalorieTarget)
                        await loadData()
                        showCalorieGoalEdit = false
                    }
                } label: {
                    Text("目標を設定")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("目標カロリー設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        showCalorieGoalEdit = false
                    }
                }
            }
        }
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak   = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                    Text("90日チャレンジ").fontWeight(.black)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 12)
                    Capsule().fill(
                        LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(12, geo.size.width * CGFloat(progress)), height: 12)
                }
            }
            .frame(height: 12)
            Text("毎日続けてフィットネス習慣を身につけよう！")
                .font(.caption).foregroundColor(Color.duoSubtitle)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }

    // MARK: - 今日の記録サマリー（セット別表示）
    @ViewBuilder
    private var todaySummaryCard: some View {
        if !todayExercises.isEmpty {
            let sets = buildTodaySets(todayExercises)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen)
                    Text("今日の記録").fontWeight(.black)
                    Spacer()
                    Text("\(sets.count)セット · \(totalReps)回 · \(totalXP) XP")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.duoYellow.opacity(0.18))
                        .cornerRadius(8)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoDark)

                VStack(spacing: 6) {
                    ForEach(sets) { set in
                        todaySetSummaryButton(set)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - クイックメニュー
    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("メニュー")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(Color.duoDark)

            HStack(spacing: 10) {
                NavigationLink(destination: WeeklyGoalView().environmentObject(authManager)) {
                    quickMenuItem(icon: "🎯", label: "週間目標", color: Color.duoGreen)
                }
                NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                    quickMenuItem(icon: "📅", label: "履歴", color: Color.duoBlue)
                }
                NavigationLink(destination: HelpView()) {
                    quickMenuItem(icon: "❓", label: "ヘルプ", color: Color.duoOrange)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }

    private func quickMenuItem(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(icon).font(.title3)
            Text(label)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(Color.duoDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }

    private func emojiFor(_ name: String) -> String {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        let map = ["pushup": "💪", "push-up": "💪", "squat": "🏋️",
                   "situp": "🔥", "sit-up": "🔥", "lunge": "🦵",
                   "burpee": "⚡", "plank": "🧘"]
        for (k, v) in map { if key.contains(k) { return v } }
        return "🏃"
    }

    // MARK: - 今日のセット構築
    private struct TodaySet: Identifiable {
        let id = UUID()
        let period: String
        let setNumber: Int
        let startTime: Date
        let exercises: [CompletedExercise]
        let totalReps: Int
        let totalPoints: Int
    }

    private func buildTodaySets(_ exercises: [CompletedExercise]) -> [TodaySet] {
        let sorted = exercises.sorted { $0.timestamp < $1.timestamp }
        var sessions: [[CompletedExercise]] = []
        var currentSession: [CompletedExercise] = []
        var lastTime: Date? = nil

        // 30分間隔でセッション分割
        for ex in sorted {
            if let last = lastTime, ex.timestamp.timeIntervalSince(last) <= 30 * 60 {
                currentSession.append(ex)
            } else {
                if !currentSession.isEmpty {
                    sessions.append(currentSession)
                }
                currentSession = [ex]
            }
            lastTime = ex.timestamp
        }
        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }

        let calendar = Calendar.current
        var amCount = 0
        var pmCount = 0

        return sessions.map { session in
            guard let firstTime = session.first?.timestamp else {
                return TodaySet(period: "午後", setNumber: 1, startTime: Date(), exercises: [], totalReps: 0, totalPoints: 0)
            }

            let hour = calendar.component(.hour, from: firstTime)
            let isAM = hour < 12
            let period = isAM ? "午前" : "午後"

            if isAM {
                amCount += 1
            } else {
                pmCount += 1
            }
            let setNumber = isAM ? amCount : pmCount

            return TodaySet(
                period: period,
                setNumber: setNumber,
                startTime: firstTime,
                exercises: session,
                totalReps: session.reduce(0) { $0 + $1.reps },
                totalPoints: session.reduce(0) { $0 + $1.points }
            )
        }
    }

    // MARK: - セットサマリーボタン（折りたたみ可能）
    private func todaySetSummaryButton(_ set: TodaySet) -> some View {
        let isExpanded = expandedSetId == set.id

        return VStack(spacing: 0) {
            // セットサマリー（常に表示）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expandedSetId = isExpanded ? nil : set.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(set.period) セット\(set.setNumber)")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                        HStack(spacing: 8) {
                            Text(timeString(set.startTime))
                                .font(.caption2)
                                .foregroundColor(Color.duoSubtitle)
                            Text("\(set.exercises.count)種目")
                                .font(.caption2)
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Text("\(set.totalReps)回")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                        Text("+\(set.totalPoints)")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGold)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Color.duoGreen)
                }
                .padding(12)
                .background(isExpanded ? Color.duoGreen.opacity(0.08) : Color.duoBg)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // 詳細（展開時のみ表示）
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(set.exercises) { ex in
                        HStack(spacing: 8) {
                            Text(emojiFor(ex.exerciseName))
                                .font(.body)
                                .frame(width: 28, height: 28)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.exerciseName)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoDark)
                                Text("\(ex.reps) 回")
                                    .font(.caption2).fontWeight(.semibold)
                                    .foregroundColor(Color.duoSubtitle)
                            }

                            Spacer()

                            Text("+\(ex.points) XP")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoGold)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.duoYellow.opacity(0.22))
                                .cornerRadius(5)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(Color.duoGreen.opacity(0.05))
                .cornerRadius(10)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 健康サマリーカード（HealthKit）
    @ViewBuilder
    private var healthSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // カードタイトル
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 1.0, green: 0.294, blue: 0.294))
                Text("今日の健康データ")
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Spacer()
                if !healthKit.isAuthorized {
                    Text("連動する →")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .padding(.bottom, 12)

            if !healthKit.isAvailable || !healthKit.isAuthorized {
                // 未連携時のプレースホルダー
                HStack(spacing: 10) {
                    Image(systemName: "heart.text.square")
                        .font(.title3)
                        .foregroundColor(Color.duoSubtitle)
                    Text("Apple Healthと連動するとデータが表示されます")
                        .font(.subheadline).foregroundColor(Color.duoSubtitle)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 10) {
                    // 上段: 歩数 & カロリー
                    HStack(spacing: 8) {
                        healthMetricTile(
                            icon: "figure.walk",
                            value: healthKit.todaySteps > 0 ? "\(healthKit.todaySteps.formatted())" : "0",
                            unit: "歩",
                            bg: Color(red: 0.843, green: 1.0, blue: 0.722) // #D7FFB8
                        )
                        healthMetricTile(
                            icon: "flame.fill",
                            value: healthKit.todayCalories > 0 ? "\(Int(healthKit.todayCalories))" : "0",
                            unit: "kcal",
                            bg: Color(red: 1.0, green: 0.953, blue: 0.878) // #FFF3E0
                        )
                    }

                    // 下段: 心拍数 & 睡眠
                    HStack(spacing: 8) {
                        healthMetricTile(
                            icon: "heart.fill",
                            value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—",
                            unit: "bpm",
                            bg: Color(red: 0.988, green: 0.894, blue: 0.925) // #FCE4EC
                        )
                        healthMetricTile(
                            icon: "bed.double.fill",
                            value: healthKit.lastNightTotalHours > 0.1 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—",
                            unit: "時間",
                            bg: Color(red: 0.918, green: 0.902, blue: 1.0) // #EAE6FF
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        .task {
            // HealthKit権限確認と自動リクエスト
            if healthKit.isAvailable {
                if !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                }
                // 権限取得後、データを必ず取得
                if healthKit.isAuthorized {
                    await healthKit.fetchAll()
                }
            }
        }
        .onAppear {
            // 画面表示時にも再取得（最新データ確保）
            if healthKit.isAvailable && healthKit.isAuthorized {
                Task {
                    await healthKit.fetchAll()
                }
            }
        }
    }

    private func healthMetricTile(icon: String, value: String, unit: String, bg: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.duoDark)
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(Color.duoDark)
            Text(unit)
                .font(.system(size: 9)).fontWeight(.bold)
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(bg)
        .cornerRadius(10)
    }

    /// 種目 ID → 推定 kcal/rep
    private static let kcalPerRep: [String: Double] = [
        "pushup": 0.5, "push-up": 0.5,
        "squat":  0.6,
        "situp":  0.3, "sit-up": 0.3,
        "lunge":  0.5,
        "burpee": 1.0,
        "plank":  0.1,
    ]

    private func loadData() async {
        guard authManager.isSignedIn else {
            isLoading = false
            return
        }

        isLoading = true

        // ① キャッシュから即時取得してスピナーを止める（空でも必ず解除）
        async let cachedEx   = authManager.getTodayExercisesFromCache()
        async let cachedSets = authManager.getDailySetsFromCache()
        todayExercises = await cachedEx
        dailySets      = await cachedSets
        recalcTotals()
        isLoading = false

        // ② バックグラウンドでサーバーから最新値を取得して反映
        Task {
            async let freshEx   = authManager.getTodayExercises()
            async let freshSets = authManager.getDailySets()
            async let weeklyProgress = authManager.getWeeklySetProgress()
            async let calGoal = authManager.getDailyCalorieGoal()
            let (ex, sets, weekProg, calorie) = await (freshEx, freshSets, weeklyProgress, calGoal)
            todayExercises = ex
            dailySets      = sets
            weeklySetProgress = weekProg
            calorieGoal = calorie
            recalcTotals()
        }
    }

    private func recalcTotals() {
        totalReps     = todayExercises.reduce(0) { $0 + $1.reps }
        totalXP       = todayExercises.reduce(0) { $0 + $1.points }
        totalCalories = Int(todayExercises.reduce(0.0) { acc, ex in
            let rate = Self.kcalPerRep[ex.exerciseId.lowercased()] ?? 0.4
            return acc + Double(ex.reps) * rate
        })
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
