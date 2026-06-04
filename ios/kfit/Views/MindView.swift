import SwiftUI

struct MindView: View {
    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f
    }()
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.openURL) private var openURL
    @State private var showMindfulnessSession = false
    @State private var showStretchSession = false
    @State private var showMindfulHistory = false
    @State private var showHRVHelp = false
    @State private var isRefreshingHealthData = false
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        currentStressCard
                        averageStressCard
                        sleepScoreCard
                        suggestionsCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await healthKit.fetchMindHealth(force: true)
                    await AuthenticationManager.shared.awardXPForMindfulSessions(healthKit.todayMindfulnessSamples)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { mindHeader }
            .sheet(isPresented: $showHRVHelp) {
                HRVStressHelpView()
            }
            .task {
                loadDailyFixedGoals()
                await timeSlotManager.loadTodaySettings()
                if healthKit.isAvailable && !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                } else {
                    await healthKit.fetchMindHealth()
                }
                await AuthenticationManager.shared.awardXPForMindfulSessions(healthKit.todayMindfulnessSamples)
            }
            .fullScreenCover(isPresented: $showMindfulnessSession) {
                MindfulnessSessionView(
                    durationSeconds: 60,
                    title: "1分瞑想",
                    completedButtonTitle: "Breatheとして保存"
                ) { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 60,
                            sessionType: "Breathe"
                        )
                        if saved {
                            await healthKit.refreshMindfulness()
                            await AuthenticationManager.shared.awardXPForMindfulSessions(healthKit.todayMindfulnessSamples)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showStretchSession) {
                MindfulnessSessionView(
                    durationSeconds: 180,
                    title: "3分ストレッチ",
                    completedButtonTitle: "Reflectとして保存",
                    sessionVideos: StretchSessionVideo.defaultStretchVideos
                ) { startDate, endDate in
                    Task {
                        let saved = await healthKit.saveMindfulnessSession(
                            startDate: startDate,
                            endDate: endDate,
                            durationSeconds: 180,
                            sessionType: "Reflect"
                        )
                        if saved {
                            await healthKit.refreshMindfulness()
                            await TimeSlotManager.shared.syncStretchFromHealthKit()
                            await AuthenticationManager.shared.awardXPForMindfulSessions(healthKit.todayMindfulnessSamples)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var mindHeader: some View {
        let totalMindfulness = healthKit.todayMindfulnessSessions
        let totalMindfulnessGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.mindfulnessGoal ?? 0)
        }
        let totalStretch = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.stretchSetsCompleted ?? 0)
        }
        let totalStretchGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            guard let g = timeSlotManager.settings.goalFor(slot), g.stretchGoal.enabled else { return sum }
            return sum + g.stretchGoal.stretchMinutes
        }
        let mindGoalDone = totalMindfulnessGoal > 0 && totalMindfulness >= totalMindfulnessGoal
        let stretchGoalDone = totalStretchGoal > 0 && totalStretch >= totalStretchGoal
        return ZStack {
            LinearGradient(
                colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            HStack(spacing: 0) {
                Text("MIND")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(Color(hex: "#6D5DF6"))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .fixedSize()
                if dailyFixedGoals.sleepEnabled {
                    Spacer(minLength: 6)
                    SleepMiniRingView(
                        hours: healthKit.lastNightTotalHours,
                        goal: Double(dailyFixedGoals.sleepHoursGoal),
                        diameter: 22,
                        lineWidth: 4,
                        ringColor: .white
                    )
                    .fixedSize()
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🧘").font(.system(size: 11))
                    Text(totalMindfulnessGoal > 0 ? "\(totalMindfulness)/\(totalMindfulnessGoal)" : "\(totalMindfulness)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(mindGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🤸").font(.system(size: 11))
                    Text(totalStretchGoal > 0 ? "\(totalStretch)/\(totalStretchGoal)分" : "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(stretchGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("☀️").font(.system(size: 11))
                    Text(healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(healthKit.todayDaylightMinutes >= 30 ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 8)
                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(height: 46)
        .ignoresSafeArea(edges: .top)
    }

    private var headerSection: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        return ZStack {
            LinearGradient(
                colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 6) {
                // 左: Fitingoロゴ + Mindingo + 日付
                Image("mascot")
                    .resizable().scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                HStack(spacing: 0) {
                    Text("Mind").foregroundColor(Color(hex: "#58CC02"))
                    Text("ingo").foregroundColor(.white)
                }
                .font(.system(size: 12, weight: .black, design: .rounded))

                Spacer()

                // 右: 平均HRV + 英語ステータス
                if healthKit.isLoading {
                    ProgressView().tint(.white).scaleEffect(0.65)
                } else {
                    HStack(spacing: 4) {
                        if avgHRV > 0 {
                            Text("平均HRV")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.72))
                            Text("\(Int(avgHRV))")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundColor(stress.color)
                        }
                        if stress.score >= 0 {
                            Text(stress.englishLabel == "Elevated" ? "Elev" : stress.englishLabel)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(stress.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(stress.color.opacity(0.18))
                                .cornerRadius(7)
                        }
                    }
                }

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .cornerRadius(12)
    }

    private var currentStressCard: some View {
        let stress = stressInfo(healthKit.latestHRV)
        return card {
            cardTitleWithHelp(
                "現在のストレスレベル",
                icon: "heart.fill",
                color: stress.color,
                showsRefresh: true
            )
            HStack(spacing: 10) {
                metricTile(label: "心拍数", value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—", unit: "bpm", color: Color(hex: "#FF4B4B"))
                metricTile(label: "HRV", value: healthKit.latestHRV > 0 ? "\(Int(healthKit.latestHRV))" : "—", unit: "ms", color: Color.duoGreen)
                stressTile(stress)
            }
            if stress.score >= 55 {
                suggestionBanner(
                    icon: "🫁",
                    text: "ストレスが高めです。マインドフルネスで深呼吸を1分だけ試してみましょう。",
                    color: stress.color
                )
            } else {
                suggestionBanner(
                    icon: "🌿",
                    text: "今の状態は落ち着いています。こまめな水分補給と短い休憩で維持しましょう。",
                    color: Color.duoGreen
                )
            }
            largeActionButton(
                icon: "🧘",
                title: "1分瞑想タイマー",
                subtitle: "自分の呼吸に集中して1分瞑想でリラックスする",
                color: Color(hex: "#1CB0F6")
            ) {
                showMindfulnessSession = true
            }
            hrvTrendAlways
            mindfulHistorySection
        }
    }

    private var averageStressCard: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        return card {
            cardTitleWithHelp(
                "今日のまとめ",
                icon: "waveform.path.ecg",
                color: stress.color,
                showsRefresh: true
            )
            HStack(spacing: 10) {
                metricTile(
                    label: "平均心拍",
                    value: healthKit.todayAvgHeartRate > 0 ? "\(Int(healthKit.todayAvgHeartRate))" : "—",
                    unit: "bpm",
                    color: Color(hex: "#FF4B4B")
                )
                metricTile(
                    label: "平均HRV",
                    value: avgHRV > 0 ? "\(Int(avgHRV))" : "—",
                    unit: "ms",
                    color: Color.duoGreen
                )
                stressTile(stress)
            }
            HStack(spacing: 10) {
                mindSummaryMetricCard(
                    icon: "bed.double.fill",
                    label: "睡眠時間",
                    value: formatSleepHours(healthKit.lastNightTotalHours),
                    color: Color(red: 0.451, green: 0.369, blue: 0.937)
                )
                mindSummaryMetricCard(
                    icon: "sun.max.fill",
                    label: "日光下時間",
                    value: formatMinutes(Int(healthKit.todayDaylightMinutes)),
                    color: Color(hex: "#FFCC00")
                )
                mindSummaryMetricCard(
                    icon: "figure.run",
                    label: "運動時間",
                    value: formatMinutes(healthKit.todayWorkoutMinutes),
                    color: Color(hex: "#1CB0F6")
                )
            }
            suggestionBanner(
                icon: "🌿",
                text: holisticStressImprovementMessage(stress),
                color: stress.color
            )
            largeActionButton(
                icon: "🤸",
                title: "3分ストレッチ",
                subtitle: "肩・首・背中をゆるめる3分セッションをHealthKitへ保存",
                color: Color.duoGreen
            ) {
                showStretchSession = true
            }
            weeklyHRVAverageSection
        }
    }

    private var weeklyHRVAverageSection: some View {
        VStack(spacing: 10) {
            WeeklyHRVAverageChart(days: healthKit.weeklyHRVAverages)
                .frame(height: 132)
                .padding(10)
                .background(Color(.systemBackground))
                .cornerRadius(14)
        }
        .padding(10)
        .background(Color.duoBg)
        .cornerRadius(14)
        .onTapGesture {
            if let url = URL(string: "x-apple-health://HeartRateVariabilitySDNN") {
                openURL(url)
            }
        }
    }

    private var hrvTrendAlways: some View {
        VStack(spacing: 10) {
            HRVTrendChart(samples: healthKit.hrvSamples)
                .frame(height: 126)
                .padding(10)
                .background(Color(.systemBackground))
                .cornerRadius(14)
        }
        .padding(10)
        .background(Color.duoBg)
        .cornerRadius(14)
        .onTapGesture {
            if let url = URL(string: "x-apple-health://HeartRateVariabilitySDNN") {
                openURL(url)
            }
        }
    }

    private var mindfulHistorySection: some View {
        let sessions = healthKit.todayMindfulnessSamples
            .sorted { $0.startDate > $1.startDate }
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showMindfulHistory.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(Color.duoGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(showMindfulHistory ? "マインドフルを閉じる" : "マインドフル履歴を表示")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(Color.duoGreen)
                        Text("\(sessions.count)回 / \(formatMindfulMinutes(totalMinutes))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: showMindfulHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(Color.duoGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)

            if showMindfulHistory {
                VStack(alignment: .leading, spacing: 8) {
                    if sessions.isEmpty {
                        Text("今日のマインドフルネス記録はまだありません。")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.duoBg)
                            .cornerRadius(12)
                    } else {
                        ForEach(sessions) { session in
                            mindfulHistoryRow(session)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.duoGreen.opacity(0.12), lineWidth: 1)
        )
    }

    private func mindfulHistoryRow(_ session: MindfulSession) -> some View {
        let timeFormatter = MindView.hhmm
        let isReflect = session.sessionTypeLabel == "Reflect"
        let isStand = session.sessionTypeLabel == "Stand"
        let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)
        let typeColor: Color = isStand ? standColor : (isReflect ? Color.duoPurple : Color(hex: "#1CB0F6"))
        let japaneseLabel: String = isStand ? "20分スタンド" : (isReflect ? "3分ストレッチ" : "1分瞑想")
        let xp = isStand ? 50 : (isReflect ? 30 : 10)

        return HStack(spacing: 6) {
            Text(timeFormatter.string(from: session.startDate))
                .font(.system(size: 11)).foregroundColor(Color.duoSubtitle)
                .frame(width: 38, alignment: .leading)
            Text(japaneseLabel)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(typeColor)
            Spacer()
            if session.averageHeartRate > 0 {
                HStack(spacing: 2) {
                    Text("❤️").font(.system(size: 10))
                    Text("\(Int(session.averageHeartRate))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#FF4B4B"))
                }
            }
            if session.averageHRV > 0 {
                Text("HRV \(Int(session.averageHRV))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#1CB0F6"))
            }
            Text("+\(xp) XP")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(Color.duoGold)
            Text(formatMindfulMinutes(session.durationMinutes))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(typeColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(typeColor.opacity(0.07))
        .cornerRadius(8)
    }

    private func formatMindfulMinutes(_ minutes: Double) -> String {
        if minutes < 1 {
            return "\(Int(minutes * 60))秒"
        }
        if abs(minutes.rounded() - minutes) < 0.05 {
            return "\(Int(minutes.rounded()))分"
        }
        return String(format: "%.1f分", minutes)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes <= 0 { return "—" }
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }

    private func formatSleepHours(_ hours: Double) -> String {
        guard hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        return formatMinutes(totalMinutes)
    }

    private func holisticStressImprovementMessage(_ stress: MindStressInfo) -> String {
        let sleepHours = healthKit.lastNightTotalHours
        let daylight = Int(healthKit.todayDaylightMinutes)
        let exercise = healthKit.todayWorkoutMinutes

        if sleepHours > 0 && sleepHours < 6 {
            return "昨晩の睡眠が短めです。今日はカフェインを控えめにして、寝る前の画面時間を減らすと回復しやすくなります。"
        }
        if daylight < 20 {
            return "日光下時間が少なめです。午前中か昼に5〜10分だけ外へ出ると、体内時計とストレス回復を整えやすくなります。"
        }
        if exercise < 20 {
            return "運動時間が少なめです。軽い散歩やストレッチを10分足すと、HRVと気分の回復につながりやすいです。"
        }
        if stress.score >= 55 {
            return "睡眠・日光・運動はある程度取れています。今日は1分瞑想や3分ストレッチで、首肩の緊張を落としてみましょう。"
        }
        return "睡眠・日光・運動のバランスは良好です。今のリズムを保ちつつ、短い休憩をこまめに入れましょう。"
    }

    private func mindDailyMetricTile(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoDark)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func mindSummaryMetricCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private var sleepScoreCard: some View {
        let analysis = healthKit.analyzeSleepScore(
            targetHours: Double(dailyFixedGoals.sleepHoursGoal)
        )

        return Button {
            if let url = URL(string: "x-apple-health://SleepAnalysis") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("昨晩の睡眠")
                        .font(.headline.weight(.black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sleepSectionTitle("睡眠スコア情報", icon: "moon.zzz.fill", color: sleepScoreColor(analysis.score))

                    if analysis.score > 0 {
                        HStack(alignment: .center, spacing: 8) {
                            SleepScoreRingView(sleep: analysis)

                            VStack(alignment: .leading, spacing: 4) {
                                sleepBulletRow(
                                    color: Color(red: 0.44, green: 0.52, blue: 0.90),
                                    label: "睡眠時間",
                                    value: "\(analysis.durationScore)/50",
                                    note: String(format: "%.1fh/%.0fh", analysis.totalHours, analysis.targetHours)
                                )
                                sleepBulletRow(
                                    color: Color(red: 0.22, green: 0.80, blue: 0.72),
                                    label: "就寝時刻",
                                    value: "\(analysis.bedtimeScore)/30",
                                    note: {
                                        if let t = analysis.firstSleepTime {
                                            return MindView.hm.string(from: t)
                                        }
                                        return "—"
                                    }()
                                )
                                sleepBulletRow(
                                    color: Color(red: 0.95, green: 0.48, blue: 0.40),
                                    label: "睡眠中断",
                                    value: "\(analysis.interruptionScore)/20",
                                    note: analysis.awakeHours < 0.1 ? "なし" : String(format: "%.0f分", analysis.awakeHours * 60)
                                )
                            }
                            Spacer(minLength: 0)
                        }
                    } else {
                        HStack(alignment: .bottom, spacing: 2) {
                            Text(healthKit.lastNightTotalHours > 0 ? String(format: "%.1f", healthKit.lastNightTotalHours) : "—")
                                .font(.system(size: 19, weight: .black))
                                .foregroundColor(healthKit.lastNightTotalHours >= 7.0 ? Color.duoGreen : Color.duoOrange)
                            Text("h")
                                .font(.system(size: 9))
                                .foregroundColor(Color.duoSubtitle)
                                .padding(.bottom, 1)
                            Spacer()
                        }
                    }

                    if !healthKit.sleepSegments.isEmpty {
                        sleepStageBar
                    }

                    sleepInsightMessage(sleepScoreInsight(analysis), color: sleepScoreColor(analysis.score))
                }

                sleepVitalsSection(healthKit.sleepVitals)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func sleepVitalsSection(_ vitals: SleepVitalsAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sleepSectionTitle("睡眠中のバイタル情報", icon: "waveform.path.ecg", color: Color(hex: "#1CB0F6"))

            HStack(spacing: 6) {
                sleepVitalTile(
                    label: "心拍",
                    value: vitals.averageHeartRate > 0 ? "\(Int(vitals.averageHeartRate))" : "—",
                    unit: "bpm",
                    color: sleepHeartRateColor(vitals.averageHeartRate)
                )
                sleepVitalTile(
                    label: "呼吸",
                    value: vitals.averageRespiratoryRate > 0 ? String(format: "%.1f", vitals.averageRespiratoryRate) : "—",
                    unit: "回/分",
                    color: sleepRespiratoryColor(vitals.averageRespiratoryRate)
                )
                sleepVitalTile(
                    label: "酸素",
                    value: vitals.averageOxygenSaturation > 0 ? "\(Int(vitals.averageOxygenSaturation))" : "—",
                    unit: "%",
                    color: sleepOxygenColor(vitals.minimumOxygenSaturation > 0 ? vitals.minimumOxygenSaturation : vitals.averageOxygenSaturation)
                )
            }

            if vitals.hasData {
                Text(vitals.minimumOxygenSaturation > 0 ? "最低酸素レベル: \(Int(vitals.minimumOxygenSaturation))%" : "酸素レベルの最低値は未取得です")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }

            if vitals.hasData {
                ForEach(sleepVitalsInsights(vitals), id: \.self) { message in
                    let isAlert = vitals.alertMessages.contains(message)
                    sleepInsightMessage(message, color: isAlert ? Color.duoRed : Color.duoGreen, isAlert: isAlert)
                }
            } else {
                sleepInsightMessage("睡眠中のバイタルデータがまだありません。Apple Watchを装着して睡眠すると、心拍・呼吸・酸素レベルを確認できます。", color: Color.duoSubtitle)
            }
        }
        .padding(.top, 2)
    }

    private func sleepVitalTile(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .cornerRadius(9)
    }

    private func sleepSectionTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func sleepInsightMessage(_ message: String, color: Color, isAlert: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.10))
        .cornerRadius(8)
    }

    private func sleepScoreInsight(_ analysis: SleepScoreAnalysis) -> String {
        guard analysis.score > 0 else {
            return "睡眠データがまだ十分にありません。Apple Watchを装着して寝ると、睡眠時間・就寝時刻・中断を分析できます。"
        }
        if analysis.durationScore < 35 {
            return "睡眠時間が目標より短めです。就寝を30分早める、夕方以降のカフェインを控えるなどで回復時間を増やしましょう。"
        }
        if analysis.bedtimeScore < 20 {
            return "就寝時刻が遅めです。寝る前の画面時間を減らし、同じ時間にベッドへ入る習慣を作るとスコアが安定します。"
        }
        if analysis.interruptionScore < 14 {
            return "睡眠中の覚醒が多めです。寝室の温度・光・音を整え、アルコールや遅い食事を控えると改善しやすいです。"
        }
        if analysis.score >= 80 {
            return "昨晩の睡眠は良好です。今日も同じ就寝リズムを保つと、ストレス回復が安定しやすくなります。"
        }
        return "大きな異常はありませんが、睡眠時間・就寝時刻・中断のうち弱い項目を1つだけ整えると改善しやすいです。"
    }

    private func sleepVitalsInsights(_ vitals: SleepVitalsAnalysis) -> [String] {
        var messages = vitals.alertMessages
        if messages.isEmpty {
            if vitals.averageOxygenSaturation >= 94 || vitals.averageHeartRate > 0 || vitals.averageRespiratoryRate > 0 {
                messages.append("睡眠中のバイタルに大きな注意点はありません。今の睡眠環境を維持しつつ、起床後の体調も合わせて確認しましょう。")
            }
        }
        if vitals.averageHeartRate > 0 && vitals.averageHeartRate > 80 {
            messages.append("睡眠中の心拍が高めです。寝る前の強い運動・飲酒・カフェイン・ストレス負荷を少し下げると落ち着きやすいです。")
        }
        if vitals.averageRespiratoryRate > 0 && vitals.averageRespiratoryRate > 20 {
            messages.append("呼吸数がやや高めです。鼻詰まり、寝室の乾燥、疲労感がないか確認し、就寝前にゆっくり呼吸を整えましょう。")
        }
        if vitals.minimumOxygenSaturation > 0 && vitals.minimumOxygenSaturation < 94 {
            messages.append("酸素レベルが低めの時間があります。横向き寝、寝室の換気、鼻呼吸のしやすさを確認してください。気になる症状があれば医療機関に相談しましょう。")
        }
        return Array(messages.prefix(3))
    }

    private var sleepStageBar: some View {
        let segments = healthKit.sleepSegments
        let total = segments.reduce(0.0) { $0 + $1.durationHours }

        return VStack(alignment: .leading, spacing: 4) {
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(segments) { seg in
                            let width = max(2, geo.size.width * CGFloat(seg.durationHours / total))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: seg.stage.color))
                                .frame(width: width, height: 14)
                        }
                    }
                }
                .frame(height: 14)

                HStack(spacing: 10) {
                    ForEach([
                        (SleepSegment.SleepStage.deep, "深い"),
                        (.rem, "REM"),
                        (.core, "コア"),
                        (.awake, "覚醒"),
                    ], id: \.0.rawValue) { stage, label in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: stage.color))
                                .frame(width: 6, height: 6)
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func sleepBulletRow(color: Color, label: String, value: String, note: String = "") -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Group {
                if note.isEmpty {
                    Text("\(label): \(value)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                } else {
                    Text("\(label): \(value) ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                    + Text("(\(note))")
                        .font(.system(size: 9))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
    }

    private var suggestionsCard: some View {
        card {
            cardTitle("具体的にできること", icon: "sparkles", color: Color(hex: "#CE82FF"))
            VStack(spacing: 8) {
                ForEach(recommendations) { item in
                    recommendationRow(item)
                }
            }
        }
    }

    private func recommendationRow(_ item: MindRecommendation) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Text(item.prefix)
                .font(.system(size: 17))
            Text(item.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if item.actionType != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(item.color.opacity(0.6))
            }
        }
        .padding(10)
        .background(item.color.opacity(item.actionType != nil ? 0.14 : 0.10))
        .cornerRadius(12)

        if let action = item.actionType {
            return AnyView(
                Button {
                    handleRecommendationAction(action)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    private func handleRecommendationAction(_ action: String) {
        switch action {
        case "mindfulness":
            showMindfulnessSession = true
        case "fitness":
            selectedTab = 0
        case "intake":
            selectedTab = 3
        case "health":
            if let url = URL(string: "x-apple-health://") {
                openURL(url)
            }
        default:
            break
        }
    }

    private var recommendations: [MindRecommendation] {
        let stress = stressInfo(healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV)
        var items: [MindRecommendation] = []

        if healthKit.todayMindfulnessMinutes < 1 {
            items.append(MindRecommendation(prefix: "🫁", text: "まだ深呼吸やマインドフルネスをしていません。1分だけ呼吸を整えてみましょう。", color: Color(hex: "#1CB0F6"), actionType: "mindfulness"))
        }
        if healthKit.todayMindfulnessSamples.filter({ $0.sessionTypeLabel == "Reflect" }).isEmpty {
            items.append(MindRecommendation(prefix: "🤸", text: "Reflectや軽いストレッチで、肩・首・背中をゆるめてみましょう。", color: Color.duoGreen, actionType: "mindfulness"))
        }
        if healthKit.todayStandHours < 6 || healthKit.todaySteps < 5000 {
            items.append(MindRecommendation(prefix: "🚶", text: "スタンド時間や歩数が少なめです。5分だけ外を歩く、階段を使うなどがおすすめです。", color: Color(hex: "#FF9600"), actionType: "health"))
        }
        if stress.score >= 55 {
            items.append(MindRecommendation(prefix: "💆", text: "こめかみ・首・肩を軽くマッサージして、体の緊張を落としてみましょう。", color: Color(hex: "#CE82FF"), actionType: "mindfulness"))
        }

        items.append(MindRecommendation(prefix: "☕", text: "コーヒーを淹れる、水を飲む、歯磨きをするなど、小さな切り替えを入れましょう。", color: Color(hex: "#1CB0F6"), actionType: "intake"))
        items.append(MindRecommendation(prefix: "🌤️", text: "遠くを見る、ぼおっとする、軽く息継ぎをするなど、いつもと違う休み方を試しましょう。", color: Color.duoGreen))
        items.append(MindRecommendation(prefix: "🍃", text: "息抜きの時間を予定に入れて、通知や画面から少し離れてみましょう。", color: Color.duoOrange))
        return Array(items.prefix(6))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func cardTitleWithHelp(_ title: String, icon: String, color: Color, showsRefresh: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(Color.duoDark)
            Spacer()
            Button {
                showHRVHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.duoSubtitle.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshMindHealthData() {
        guard !isRefreshingHealthData else { return }
        isRefreshingHealthData = true
        Task {
            if healthKit.isAvailable && !healthKit.isAuthorized {
                await healthKit.requestAuthorization()
            } else {
                await healthKit.fetchMindHealth(force: true)
            }
            await MainActor.run {
                isRefreshingHealthData = false
            }
        }
    }

    private func metricTile(label: String, value: String, unit: String, detail: String? = nil, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            if let detail {
                Text(detail)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private func stressTile(_ stress: MindStressInfo, detail: String? = nil) -> some View {
        VStack(spacing: 3) {
            Text("ストレス")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(stress.label)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stress.englishLabel)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
            if let detail {
                Text(detail)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundColor(stress.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(stress.color.opacity(0.12))
        .cornerRadius(12)
    }

    private func sleepScoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .duoGreen
        case 80..<90:  return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 70..<80:  return Color(red: 0.451, green: 0.369, blue: 0.937)
        case 50..<70:  return .duoOrange
        default:       return .duoRed
        }
    }

    private func sleepHeartRateColor(_ value: Double) -> Color {
        guard value > 0 else { return Color.duoSubtitle }
        return (value < 40 || value > 100) ? Color.duoRed : Color.duoGreen
    }

    private func sleepRespiratoryColor(_ value: Double) -> Color {
        guard value > 0 else { return Color.duoSubtitle }
        return (value < 10 || value > 24) ? Color.duoRed : Color.duoGreen
    }

    private func sleepOxygenColor(_ value: Double) -> Color {
        guard value > 0 else { return Color.duoSubtitle }
        if value < 90 { return Color.duoRed }
        if value < 94 { return Color.duoOrange }
        return Color.duoGreen
    }

    private struct SleepScoreRingView: View {
        let sleep: SleepScoreAnalysis
        var size: CGFloat = 52

        private var lineWidth: CGFloat { size * 0.11 }
        private let gap: Double = 0.018

        private let durationColor = Color(red: 0.44, green: 0.52, blue: 0.90)
        private let bedtimeColor = Color(red: 0.22, green: 0.80, blue: 0.72)
        private let interruptionColor = Color(red: 0.95, green: 0.48, blue: 0.40)

        private var durationExtent: Double { 0.50 - gap }
        private var bedtimeExtent: Double { 0.30 - gap }
        private var interruptionExtent: Double { 0.20 - gap }

        private var durationRatio: Double { min(Double(sleep.durationScore) / 50.0, 1.0) }
        private var bedtimeRatio: Double { min(Double(sleep.bedtimeScore) / 30.0, 1.0) }
        private var interruptionRatio: Double { min(Double(sleep.interruptionScore) / 20.0, 1.0) }

        private var scoreColor: Color {
            switch sleep.score {
            case 90...100: return Color(red: 0.27, green: 0.76, blue: 0.20)
            case 80..<90:  return Color(red: 0.27, green: 0.76, blue: 0.20)
            case 70..<80:  return Color(red: 0.45, green: 0.37, blue: 0.94)
            case 50..<70:  return Color(red: 1.00, green: 0.60, blue: 0.00)
            default:       return Color(red: 0.95, green: 0.25, blue: 0.25)
            }
        }

        var body: some View {
            ZStack {
                ZStack {
                    Circle().trim(from: 0.0, to: durationExtent)
                        .stroke(durationColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    if durationRatio > 0.001 {
                        Circle().trim(from: 0.0, to: durationExtent * durationRatio)
                            .stroke(durationColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    Circle().trim(from: 0.50, to: 0.50 + bedtimeExtent)
                        .stroke(bedtimeColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    if bedtimeRatio > 0.001 {
                        Circle().trim(from: 0.50, to: 0.50 + bedtimeExtent * bedtimeRatio)
                            .stroke(bedtimeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    Circle().trim(from: 0.80, to: 0.80 + interruptionExtent)
                        .stroke(interruptionColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    if interruptionRatio > 0.001 {
                        Circle().trim(from: 0.80, to: 0.80 + interruptionExtent * interruptionRatio)
                            .stroke(interruptionColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
                .rotationEffect(.degrees(-30))

                Text("\(sleep.score)")
                    .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor)
            }
            .frame(width: size, height: size)
        }
    }

    private func suggestionBanner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private func largeActionButton(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 32))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: color.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func averageStressMessage(_ stress: MindStressInfo) -> String {
        switch stress.score {
        case ..<0: return "Apple HealthのHRVデータがまだありません。Apple Watchの計測後に更新されます。"
        case ..<30: return "平均ストレスは低めです。今のリズムを保ちながら、こまめに休憩しましょう。"
        case ..<55: return "平均ストレスは普通です。水分補給や短い散歩で整えていきましょう。"
        case ..<75: return "平均ストレスがやや高めです。深呼吸、軽いストレッチ、画面から離れる時間を作りましょう。"
        default: return "平均ストレスが高い状態です。無理せず休憩し、呼吸・散歩・マッサージで回復を優先しましょう。"
        }
    }

    private func stressInfo(_ hrv: Double) -> MindStressInfo {
        guard hrv > 0 else {
            return MindStressInfo(score: -1, label: "不明", englishLabel: "Unknown", color: Color.duoSubtitle)
        }
        let score: Int = {
            if hrv >= 100 { return 5 }
            if hrv >= 80  { return Int(5  + (100 - hrv) / 20 * 10) }
            if hrv >= 60  { return Int(15 + (80  - hrv) / 20 * 20) }
            if hrv >= 40  { return Int(35 + (60  - hrv) / 20 * 25) }
            if hrv >= 20  { return Int(60 + (40  - hrv) / 20 * 20) }
            return Int(min(95, 80 + (20 - hrv) / 20 * 15))
        }()
        switch score {
        case ..<30: return MindStressInfo(score: score, label: "低い", englishLabel: "Low", color: Color.duoGreen)
        case ..<55: return MindStressInfo(score: score, label: "普通", englishLabel: "Normal", color: Color(red: 0.4, green: 0.75, blue: 0.1))
        case ..<75: return MindStressInfo(score: score, label: "やや高", englishLabel: "Elevated", color: Color.duoOrange)
        default:    return MindStressInfo(score: score, label: "高い", englishLabel: "High", color: Color(hex: "#FF4B4B"))
        }
    }

    private func loadDailyFixedGoals() {
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let saved = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            dailyFixedGoals = saved
        }
    }

    // MARK: - MINDサマリー行

    private var mindSummaryRow: some View {
        let mindColor = Color.duoPurple
        let gg = timeSlotManager.settings.globalGoals
        let totalMindfulness = healthKit.todayMindfulnessSessions
        let totalMindfulnessGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.mindfulnessGoal ?? 0)
        }
        let totalStretch = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.stretchSetsCompleted ?? 0)
        }
        let totalStretchGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            guard let g = timeSlotManager.settings.goalFor(slot), g.stretchGoal.enabled else { return sum }
            return sum + g.stretchGoal.stretchMinutes
        }
        return HStack(spacing: 6) {
            Text("MIND")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(mindColor)
                .cornerRadius(4)
            if gg.sleepEnabled || dailyFixedGoals.sleepEnabled {
                SleepMiniRingView(
                    hours: healthKit.lastNightTotalHours,
                    goal: Double(dailyFixedGoals.sleepHoursGoal),
                    diameter: 22,
                    lineWidth: 4,
                    ringColor: mindColor
                )
            }
            if gg.mindfulnessEnabled {
                HStack(spacing: 2) {
                    Text("🧘").font(.system(size: 13))
                    Text(totalMindfulnessGoal > 0 ? "\(totalMindfulness)/\(totalMindfulnessGoal)" : "\(totalMindfulness)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(totalMindfulnessGoal > 0 && totalMindfulness >= totalMindfulnessGoal ? mindColor : Color.duoDark)
                }
                HStack(spacing: 2) {
                    Text("🤸").font(.system(size: 13))
                    Text(totalStretchGoal > 0 ? "\(totalStretch)/\(totalStretchGoal)分" : "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(totalStretchGoal > 0 && totalStretch >= totalStretchGoal ? mindColor : Color.duoDark)
                }
                HStack(spacing: 2) {
                    Text("☀️").font(.system(size: 13))
                    Text(healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(healthKit.todayDaylightMinutes >= 30 ? mindColor : Color.duoDark)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

private struct MindStressInfo {
    let score: Int
    let label: String
    let englishLabel: String
    let color: Color
}

private struct HRVTrendChart: View {
    let samples: [HRVSample]

    private var sortedSamples: [HRVSample] {
        samples.sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = sortedSamples
        let values = data.map(\.value)
        let minValue = max(0, (values.min() ?? 0) - 5)
        let hrvLowerLimit = 20.0
        let maxValue = max((values.max() ?? 80) + 5, minValue + 20, hrvLowerLimit + 10)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日のHRV推移")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                if let latest = data.last {
                    Text("\(Int(latest.value)) ms")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                }
            }

            if data.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.55))
                    Text("今日のHRVサンプルがまだ少ないです")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let range = max(maxValue - minValue, 1)
                    let startOfDay = Calendar.current.startOfDay(for: Date())

                    ZStack {
                        ForEach(0..<4, id: \.self) { index in
                            let y = height * CGFloat(index) / 3
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: width, y: y))
                            }
                            .stroke(Color(.systemGray5), lineWidth: 0.7)
                        }

                        if hrvLowerLimit >= minValue && hrvLowerLimit <= maxValue {
                            let limitY = height * (1 - CGFloat((hrvLowerLimit - minValue) / range))
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: limitY))
                                path.addLine(to: CGPoint(x: width, y: limitY))
                            }
                            .stroke(Color(hex: "#FF4B4B"), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))

                            Text("20ms")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "#FF4B4B"))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.85))
                                .clipShape(Capsule())
                                .position(x: width - 22, y: max(10, limitY - 10))
                        }

                        Path { path in
                            for (index, sample) in data.enumerated() {
                                let dayProgress = min(max(sample.date.timeIntervalSince(startOfDay) / 86_400.0, 0), 1)
                                let x = width * CGFloat(dayProgress)
                                let y = height * (1 - CGFloat((sample.value - minValue) / range))
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.element.id) { _, sample in
                            let dayProgress = min(max(sample.date.timeIntervalSince(startOfDay) / 86_400.0, 0), 1)
                            let x = width * CGFloat(dayProgress)
                            let y = height * (1 - CGFloat((sample.value - minValue) / range))
                            Circle()
                                .fill(Color.white)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                                .position(x: x, y: y)
                        }
                    }
                }
            }

            HStack {
                Text("0:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(Color.duoSubtitle)
        }
    }
}

private struct WeeklyHRVAverageChart: View {
    private static let dayOfWeek: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        return f
    }()

    let days: [DailyHRVAverage]
    private let lowerLimit = 20.0

    private var validDays: [DailyHRVAverage] {
        days.filter { $0.value > 0 }.sorted { $0.date < $1.date }
    }

    private var sortedDays: [DailyHRVAverage] {
        days.sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = sortedDays
        let values = validDays.map(\.value)
        let minValue = max(0, min(values.min() ?? lowerLimit, lowerLimit) - 5)
        let maxValue = max(values.max() ?? 60, lowerLimit + 10, minValue + 20)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("過去7日のHRV平均")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("赤ラインはストレス高めの目安 20ms")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                if let latest = validDays.last {
                    Text("\(Int(latest.value)) ms")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(latest.value < lowerLimit ? Color(hex: "#FF4B4B") : Color.duoGreen)
                }
            }

            if validDays.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.55))
                    Text("過去7日のHRV平均データがまだ少ないです")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    let range = max(maxValue - minValue, 1)
                    let xStep = data.count > 1 ? width / CGFloat(data.count - 1) : 0

                    ZStack {
                        ForEach(0..<4, id: \.self) { index in
                            let y = height * CGFloat(index) / 3
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: width, y: y))
                            }
                            .stroke(Color(.systemGray5), lineWidth: 0.7)
                        }

                        let limitY = height * (1 - CGFloat((lowerLimit - minValue) / range))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: limitY))
                            path.addLine(to: CGPoint(x: width, y: limitY))
                        }
                        .stroke(Color(hex: "#FF4B4B"), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))

                        Text("20ms")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#FF4B4B"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                            .position(x: width - 22, y: max(10, limitY - 10))

                        Path { path in
                            var hasStarted = false
                            for (index, day) in data.enumerated() where day.value > 0 {
                                let x = CGFloat(index) * xStep
                                let y = height * (1 - CGFloat((day.value - minValue) / range))
                                if !hasStarted {
                                    path.move(to: CGPoint(x: x, y: y))
                                    hasStarted = true
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.element.id) { index, day in
                            if day.value > 0 {
                                let x = CGFloat(index) * xStep
                                let y = height * (1 - CGFloat((day.value - minValue) / range))
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(day.value < lowerLimit ? Color(hex: "#FF4B4B") : Color.duoGreen, lineWidth: 2))
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
            }

            HStack {
                ForEach(data) { day in
                    Text(dayLabel(day.date))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        WeeklyHRVAverageChart.dayOfWeek.string(from: date)
    }
}

private struct HRVStressHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    helpSection(
                        title: "HRVとは",
                        text: "HRV（心拍変動）は、心拍と心拍の間隔のゆらぎです。一般的にはHRVが高いほど回復力やリラックス状態が高く、低いほど疲労・緊張・ストレスが出やすい状態と考えます。"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("この画面の判定基準")
                            .font(.headline.weight(.black))
                            .foregroundColor(Color.duoDark)
                        thresholdRow("低い / Low", detail: "HRV 60ms以上", color: Color.duoGreen)
                        thresholdRow("普通 / Normal", detail: "HRV 40〜59ms", color: Color(red: 0.4, green: 0.75, blue: 0.1))
                        thresholdRow("やや高 / Elevated", detail: "HRV 20〜39ms", color: Color.duoOrange)
                        thresholdRow("高い / High", detail: "HRV 20ms未満", color: Color(hex: "#FF4B4B"))
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)

                    helpSection(
                        title: "見方のポイント",
                        text: "HRVは個人差が大きいため、1回の数値だけで判断せず、自分の普段の平均からの変化を見るのが大切です。睡眠不足、飲酒、疲労、体調不良でも低くなることがあります。"
                    )
                }
                .padding(16)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("HRVとストレス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
    }

    private func helpSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(Color.duoDark)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    private func thresholdRow(_ label: String, detail: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(color)
            Spacer()
            Text(detail)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
        }
    }
}

private struct MindRecommendation: Identifiable {
    let id = UUID()
    let prefix: String
    let text: String
    let color: Color
    var actionType: String? = nil  // "mindfulness" | "fitness" | "intake" | "health"
}
