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
    @State private var todaySetCount = 0  // 今日完了したセット数
    @State private var dailySetGoal  = 2  // 1日の目標セット数
    @State private var dailySets    = DailySets(amSets: 0, pmSets: 0)  // 元の型を保持
    @State private var weeklySetProgress = WeeklySetProgress(completedSets: 0, dailyGoal: 2)
    @State private var calorieGoal = DailyCalorieGoal()
    @State private var isLoading    = false  // 初期値をfalseに変更
    @State private var mascotBounce = false
    @State private var showTracker  = false
    @State private var showHabits   = false
    @State private var hasLoadedOnce = false  // 1度だけロード実行するフラグ
    @State private var expandedSetId: String? = nil  // 展開中のセットID
    @State private var showCalorieGoalEdit = false  // カロリー目標編集モーダル
    @State private var tempCalorieTarget = 500  // 一時的なカロリー目標
    @State private var showTodayRecords = false  // 今日の記録を表示するか
    @State private var showMenu = false  // ハンバーガーメニューの表示状態

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.duoBg.ignoresSafeArea()

                // メインコンテンツ
                VStack(spacing: 0) {
                    if isLoading {
                        Spacer()
                        ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 10) {
                                dailySetsAndWeeklyGoalCard
                                calorieAndWeightCard
                                habitStackCard
                                healthSummaryCard
                                challengeCard
                                quickMenu
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 0)
                            .padding(.bottom, 60)
                        }
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    }
                }

                // 固定ヘッダー（最上部）
                VStack(spacing: 0) {
                    heroSection
                    Spacer()
                }
                .zIndex(1)

                // 固定CTAボタン（最下部）
                VStack(spacing: 0) {
                    Spacer()
                    if !isLoading {
                        startTrainingButton
                            .padding(.bottom, 0)
                    }
                }

                // ハンバーガーメニュー（オーバーレイ）
                if showMenu {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showMenu = false
                            }
                        }

                    VStack {
                        Spacer()
                        floatingMenuPanel
                    }
                    .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarHidden(true)
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

    // MARK: - 常時表示CTAボタン（画面最下部に固定）
    private var startTrainingButton: some View {
        GeometryReader { geometry in
            Button { showTracker = true } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 30, height: 30)
                            .scaleEffect(mascotBounce && todayExercises.isEmpty ? 1.1 : 1.0)
                            .animation(
                                todayExercises.isEmpty
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .default,
                                value: mascotBounce
                            )
                        Text(todayExercises.isEmpty ? "💪" : "➕")
                            .font(.callout)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(todayExercises.isEmpty
                             ? "今日のトレーニングを始めよう！"
                             : "さらに記録する")
                            .font(.caption).fontWeight(.black)
                            .foregroundColor(.white)
                        Text(todayExercises.isEmpty
                             ? "タップして開始"
                             : "\(todayExercises.count) 種目 · \(totalXP) XP")
                            .font(.caption2)
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.callout)
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
            .padding(.top, 2)
            .background(
                Color.duoBg
                    .shadow(color: Color.black.opacity(0.05), radius: 3, y: -1)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .frame(height: 55)
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
                    HStack(spacing: 2) {
                        Image("mascot")
                            .resizable().scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                        Text("DuoFit")
                            .font(.system(size: 12, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // ── 統計 3項目（横1列）- 統一指標 ───
                    HStack(spacing: 3) {
                        miniStat("🔥", "\(authManager.userProfile?.streak ?? 0)", "連続")
                        miniStat("📊", "\(todaySetCount)/\(dailySetGoal)", "セット")
                        miniStat("🔥", "\(calorieGoal.percentAchieved)%", "Cal")
                    }

                    Spacer()

                    // ── ハンバーガーメニュー ────────────
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showMenu.toggle()
                        }
                    } label: {
                        Image(systemName: showMenu ? "xmark" : "line.3.horizontal")
                            .font(.system(size: 9).weight(.bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.bottom, 0)
            }
        }
        .frame(height: (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44) + 8)
    }

    private func miniStat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 11))
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.7))
        }
    }

    /// 回数＋カロリーを2行で表示するヘッダー統計アイテム
    @ViewBuilder
    private func repCalStat(reps: Int, kcal: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("⚡").font(.system(size: 9))
                Text("\(reps)回")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("\(kcal)kcal")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.white.opacity(0.8))
        }
    }

    // MARK: - 今日のセット状況 & 週間目標カード（統合）
    private var dailySetsAndWeeklyGoalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー（タップで展開）
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showTodayRecords.toggle()
                }
            } label: {
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

                        Image(systemName: showTodayRecords ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(Color.duoGreen)
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
            }
            .buttonStyle(.plain)

            // 週間目標セクション（小さく表示）
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 16)

                weeklyGoalSection
            }

            // 今日の記録（展開時のみ表示）
            if showTodayRecords && !todayExercises.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 16)

                    todayRecordsSection
                }
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    // MARK: - 週間目標セクション（コンパクト）
    private var weeklyGoalSection: some View {
        let activeDays = 5
        let weeklyTarget = weeklySetProgress.dailyGoal * activeDays
        let today = Calendar.current.dateComponents([.weekday], from: Date()).weekday ?? 1
        // 月曜日=2, 火曜日=3, ..., 金曜日=6, 土日=1として、月〜金の経過日数を計算
        let activeDaysElapsed = today == 1 ? 0 : max(0, min(today - 2, activeDays))
        let expectedNow = weeklySetProgress.dailyGoal * activeDaysElapsed
        let weekPct = weeklyTarget > 0 ? min(Double(weeklySetProgress.completedSets) / Double(weeklyTarget) * 100, 100) : 0
        let isOnTrack = expectedNow > 0 ? weeklySetProgress.completedSets >= expectedNow : true

        return VStack(alignment: .leading, spacing: 6) {
            // ヘッダー
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundColor(Color.duoGreen)
                Text("週間目標").fontWeight(.bold)
                    .font(.caption)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("1日\(weeklySetProgress.dailyGoal)セット × \(activeDays)日")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(5)
            }

            // 進捗表示
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(weeklySetProgress.completedSets)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
                Text("/ \(weeklyTarget) セット")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
                Spacer()
                Text("\(Int(weekPct))%")
                    .font(.callout).fontWeight(.black)
                    .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoOrange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 8)
                    Capsule().fill(
                        LinearGradient(
                            colors: isOnTrack ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [Color.duoYellow, Color.duoOrange],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * CGFloat(weekPct / 100)), height: 8)
                }
            }
            .frame(height: 8)

            Text(isOnTrack ? "🎉 ペース通り！" : "今日まで目標 \(expectedNow) セット（\(activeDaysElapsed)日経過）")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(isOnTrack ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 今日の記録セクション（セット一覧）
    private var todayRecordsSection: some View {
        let sets = buildTodaySets(todayExercises)

        return VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "list.bullet.circle.fill")
                    .foregroundColor(Color.duoGold)
                Text("今日の記録").fontWeight(.bold)
                Spacer()
                Text("\(sets.count)セット · \(totalReps)回 · \(totalXP) XP")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(Color.duoGold)
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // セット一覧
            VStack(spacing: 6) {
                ForEach(sets) { set in
                    todaySetButton(set)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - セットボタン（展開式）
    private func todaySetButton(_ set: TodaySet) -> some View {
        let isExpanded = expandedSetId == set.id

        return VStack(spacing: 0) {
            // セットサマリー
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    expandedSetId = isExpanded ? nil : set.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(set.period) セット\(set.setNumber)")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                        Text(timeString(set.startTime))
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("\(set.exercises.count)種目")
                            .font(.caption2)
                            .foregroundColor(Color.duoSubtitle)
                        Text("\(set.totalReps)回")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                        Text("+\(set.totalPoints)")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGold)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(Color.duoGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isExpanded ? Color.duoGreen.opacity(0.08) : Color.duoBg)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // 詳細（展開時のみ表示）
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(set.exercises) { ex in
                        HStack(spacing: 8) {
                            Text(emojiFor(ex.exerciseName))
                                .font(.callout)
                                .frame(width: 28, height: 28)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.exerciseName)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoDark)
                                if ex.exerciseId.lowercased().contains("plank") {
                                    Text("\(ex.reps) 秒")
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(Color.duoSubtitle)
                                } else {
                                    Text("\(ex.reps) 回")
                                        .font(.caption2).fontWeight(.semibold)
                                        .foregroundColor(Color.duoSubtitle)
                                }
                            }

                            Spacer()

                            Text("+\(ex.points) XP")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundColor(Color.duoGold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.duoYellow.opacity(0.22))
                                .cornerRadius(5)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.white)
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(Color.duoGreen.opacity(0.05))
                .cornerRadius(10)
            }
        }
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


    // MARK: - カロリー目標 & 体重測定カード
    private var calorieAndWeightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // カロリー目標セクション
            calorieGoalSection

            Divider()

            // 体重・体脂肪測定セクション
            weightMeasurementSection
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private var calorieGoalSection: some View {
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
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoOrange)
                Text("/ \(calorieGoal.targetCalories) kcal")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(.bottom, 2)
                Spacer()
                Text("\(percent)%")
                    .font(.title3).fontWeight(.black)
                    .foregroundColor(isAchieved ? Color.duoGreen : Color.duoOrange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule().fill(
                        LinearGradient(
                            colors: isAchieved ? [Color.duoGreen, Color(red: 0.57, green: 0.9, blue: 0.16)] : [Color.duoOrange, Color.duoRed],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, geo.size.width * CGFloat(percent) / 100), height: 10)
                }
            }
            .frame(height: 10)

            Text(isAchieved ? "🎉 目標達成！" : "運動とApple Healthから自動集計")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(isAchieved ? Color.duoGreen : Color.duoSubtitle)
        }
    }

    private var weightMeasurementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "scalemass.fill")
                    .foregroundColor(Color.duoBlue)
                Text("今日の体重測定").fontWeight(.black)
                    .font(.subheadline)
                Spacer()
                Text("\(healthKit.todayBodyMassMeasurements)/2")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(healthKit.todayBodyMassMeasurements >= 2 ? Color.duoGreen : Color.duoOrange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((healthKit.todayBodyMassMeasurements >= 2 ? Color.duoGreen : Color.duoOrange).opacity(0.12))
                    .cornerRadius(8)
            }
            .foregroundColor(Color.duoDark)

            // 測定結果
            HStack(spacing: 12) {
                // 体重
                HStack(spacing: 4) {
                    Image(systemName: "scalemass")
                        .font(.caption)
                        .foregroundColor(Color.duoBlue)
                    if healthKit.latestBodyMass > 0 {
                        Text(String(format: "%.1f kg", healthKit.latestBodyMass))
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    } else {
                        Text("未測定")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(red: 0.878, green: 0.941, blue: 1.0))
                .cornerRadius(8)

                // 体脂肪
                HStack(spacing: 4) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundColor(Color.duoOrange)
                    if healthKit.latestBodyFatPercentage > 0 {
                        Text(String(format: "%.1f%%", healthKit.latestBodyFatPercentage))
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(Color.duoDark)
                    } else {
                        Text("未測定")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(red: 1.0, green: 0.925, blue: 0.878))
                .cornerRadius(8)
            }

            if healthKit.todayBodyMassMeasurements < 2 {
                Text(healthKit.todayBodyMassMeasurements == 0
                     ? "⚖️ 朝と夜の2回測定しましょう"
                     : "⚖️ あと1回測定しましょう")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color.duoSubtitle)
            } else {
                Text("✅ 今日の測定完了！")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color.duoGreen)
            }
        }
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


    // MARK: - フローティングメニューパネル
    private var floatingMenuPanel: some View {
        VStack(spacing: 0) {
            // メニュータイトル
            HStack {
                Text("メニュー")
                    .font(.headline).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showMenu = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color.duoSubtitle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // メニュー項目
            VStack(spacing: 0) {
                NavigationLink(destination: WeeklyGoalView().environmentObject(authManager)) {
                    menuRow(icon: "🎯", label: "週間目標", color: Color.duoGreen)
                }

                Divider().padding(.leading, 60)

                NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                    menuRow(icon: "📅", label: "履歴", color: Color.duoBlue)
                }

                Divider().padding(.leading, 60)

                NavigationLink(destination: HelpView()) {
                    menuRow(icon: "❓", label: "ヘルプ", color: Color.duoOrange)
                }

                Divider().padding(.leading, 60)

                Button {
                    authManager.signOut()
                    showMenu = false
                } label: {
                    menuRow(icon: "🚪", label: "ログアウト", color: Color.duoRed)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.2), radius: 20, y: -5)
        .ignoresSafeArea(edges: .bottom)
    }

    private func menuRow(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Text(icon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .cornerRadius(10)

            Text(label)
                .font(.body).fontWeight(.semibold)
                .foregroundColor(Color.duoDark)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: - クイックメニュー（非表示）
    private var quickMenu: some View {
        EmptyView()
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
        let id: String  // "am1", "pm2" などの固定ID
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
                return TodaySet(
                    id: "empty",
                    period: "午後",
                    setNumber: 1,
                    startTime: Date(),
                    exercises: [],
                    totalReps: 0,
                    totalPoints: 0
                )
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

            // 固定IDを生成（例: "am1", "pm2"）
            let setId = "\(isAM ? "am" : "pm")\(setNumber)"

            return TodaySet(
                id: setId,
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
            async let setCount = authManager.getTodaySetCount()
            async let setGoal = authManager.getDailySetGoal()
            let (ex, sets, weekProg, calorie, count, goal) = await (freshEx, freshSets, weeklyProgress, calGoal, setCount, setGoal)
            todayExercises = ex
            dailySets      = sets
            weeklySetProgress = weekProg
            calorieGoal = calorie
            todaySetCount = count
            dailySetGoal = goal
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

// MARK: - View Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
