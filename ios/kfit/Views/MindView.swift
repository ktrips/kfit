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
    // V1: 共有シングルトンは kfitApp から EnvironmentObject で受け取る
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var timeSlotManager: TimeSlotManager
    @EnvironmentObject private var plus: PlusManager
    @Environment(\.openURL) private var openURL
    @State private var showMindfulnessSession = false
    @State private var showStretchSession = false
    @State private var showMindfulHistory = false
    @State private var showHRVHelp = false
    @State private var isRefreshingHealthData = false
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()
    // V25: reduce 集計結果を @State にキャッシュ（mindHeader と mindSummaryRow の二重計算を排除）
    @State private var cachedTotalMindfulness: Int = 0
    @State private var cachedTotalMindfulnessGoal: Int = 0
    @State private var cachedTotalStretch: Int = 0
    @State private var cachedTotalStretchGoal: Int = 0

    private func rebuildMindTotals() {
        cachedTotalMindfulness = healthKit.todayMindfulnessSessions
        cachedTotalMindfulnessGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.settings.goalFor(slot)?.mindfulnessGoal ?? 0)
        }
        cachedTotalStretch = TimeSlot.allCases.reduce(0) { sum, slot in
            sum + (timeSlotManager.progress.progressFor(slot)?.stretchSetsCompleted ?? 0)
        }
        cachedTotalStretchGoal = TimeSlot.allCases.reduce(0) { sum, slot in
            guard let g = timeSlotManager.settings.goalFor(slot), g.stretchGoal.enabled else { return sum }
            return sum + g.stretchGoal.stretchMinutes
        }
    }

    @State private var showPlusViewFromMind = false
    @State private var showMoominQuotes    = false  // ムーミン名言一覧シート
    @ObservedObject private var ttsEngine  = DuolingoTextExtractor.shared
    @State private var speakingQuoteText: String? = nil  // 読み上げ中の名言テキスト
    @State private var quoteRefreshSeed: Int = Int.random(in: 0..<10000)  // 頻繁ローテーション用シード

    private static let quoteTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                if plus.isPlus {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            currentStressCard
                            averageStressCard
                            sleepScoreCard
                            suggestionsCard
                            moominQuoteLinkButton
                            mindBookSection
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
                } else {
                    // Free ユーザー: ロック画面 + Smartfulness バナー
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            PlusFullLockView(
                                tabIcon: "brain.head.profile",
                                tabName: "MIND",
                                features: [
                                    "ストレス分析（HRVモニタリング）",
                                    "今日のまとめ（心拍・HRV）",
                                    "昨晩の睡眠スコア詳細",
                                    "健康改善の提案"
                                ],
                                onUpgrade: { showPlusViewFromMind = true }
                            )
                            smartfulnessBanner
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { mindHeader }
            .sheet(isPresented: $showPlusViewFromMind) { PlusView() }
            .sheet(isPresented: $showHRVHelp) {
                HRVStressHelpView()
            }
            .sheet(isPresented: $showMoominQuotes) {
                MoominQuoteListSheet()
            }
            .onReceive(MindView.quoteTimer) { _ in
                quoteRefreshSeed = Int.random(in: 0..<10000)
            }
            .task {
                loadDailyFixedGoals()
                await timeSlotManager.loadTodaySettings()
                rebuildMindTotals()
                if healthKit.isAvailable && !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                } else {
                    await healthKit.fetchMindHealth()
                }
                rebuildMindTotals()
                await AuthenticationManager.shared.awardXPForMindfulSessions(healthKit.todayMindfulnessSamples)
            }
            .onChange(of: healthKit.todayMindfulnessSessions) { _, _ in rebuildMindTotals() }
            // DailyTimeSlotSettings/Progress は Equatable 非準拠のため objectWillChange で監視
            .onReceive(timeSlotManager.objectWillChange) { _ in rebuildMindTotals() }
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
        // V25: キャッシュ済み値を参照（body 評価ごとの reduce を排除）
        let totalMindfulness = cachedTotalMindfulness
        let totalMindfulnessGoal = cachedTotalMindfulnessGoal
        let totalStretch = cachedTotalStretch
        let totalStretchGoal = cachedTotalStretchGoal
        let mindGoalDone = totalMindfulnessGoal > 0 && totalMindfulness >= totalMindfulnessGoal
        let stretchGoalDone = totalStretchGoal > 0 && totalStretch >= totalStretchGoal
        return ZStack {
            LinearGradient(
                colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            HStack(spacing: 0) {
                Text("MIND")
                    .font(.system(size: 8 * UIScale.font, weight: .black))
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
                        diameter: 26,
                        lineWidth: 4.5,
                        ringColor: .white
                    )
                    .fixedSize()
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🧘").font(.system(size: 15 * UIScale.font))
                    Text(totalMindfulnessGoal > 0 ? "\(totalMindfulness)/\(totalMindfulnessGoal)" : "\(totalMindfulness)")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(mindGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🤸").font(.system(size: 15 * UIScale.font))
                    Text(totalStretchGoal > 0 ? "\(totalStretch)/\(totalStretchGoal)分" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(stretchGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("☀️").font(.system(size: 15 * UIScale.font))
                    Text(healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(healthKit.todayDaylightMinutes >= 30 ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 8)
                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(height: 50)
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
                .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))

                Spacer()

                // 右: 平均HRV + 英語ステータス
                if healthKit.isLoading {
                    ProgressView().tint(.white).scaleEffect(0.65)
                } else {
                    HStack(spacing: 4) {
                        if avgHRV > 0 {
                            Text("平均HRV")
                                .font(.system(size: 7 * UIScale.font, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.72))
                            Text("\(Int(avgHRV))")
                                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(stress.color)
                        }
                        if stress.score >= 0 {
                            Text(stress.englishLabel == "Elevated" ? "Elev" : stress.englishLabel)
                                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
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
        let quote = moominQuoteForStress(stress, seed: quoteRefreshSeed)
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
            // ── ムーミン「あなたへの一言」──────────────────────────────────
            moominQuoteCard(quote: quote, accentColor: stress.score < 0 ? Color.duoPurple : stress.color)
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

    // MARK: - ムーミン名言カード（タップで名言集へ）
    private func moominQuoteCard(quote: MoominQuote, accentColor: Color) -> some View {
        let isSpeaking = speakingQuoteText == quote.text && ttsEngine.isSpeaking
        return Button { showMoominQuotes = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("🌿").font(.system(size: 13))
                    Text("あなたへの一言")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(accentColor)
                    Spacer()
                    // 読み上げボタン（タップ伝播を止める）
                    Button {
                        if isSpeaking {
                            ttsEngine.stopSpeaking()
                            speakingQuoteText = nil
                        } else {
                            speakingQuoteText = quote.text
                            ttsEngine.speak(phrase: quote.text, languageCode: "ja")
                        }
                    } label: {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isSpeaking ? .red : accentColor)
                            .frame(width: 28, height: 28)
                            .background((isSpeaking ? Color.red : accentColor).opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    // 名言集リンクアイコン
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.5))
                }
                Text("「\(quote.text)」")
                    .font(.system(size: 13 * UIScale.font, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.duoDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
                HStack {
                    Text("— \(quote.speaker)")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(accentColor.opacity(0.8))
                        .italic()
                    Spacer()
                    Text("名言集を見る →")
                        .font(.system(size: 10 * UIScale.font, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(accentColor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accentColor.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
                        .font(.system(size: 15 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoGreen)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(showMindfulHistory ? "マインドフルを閉じる" : "マインドフル履歴を表示")
                            .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(Color.duoGreen)
                        Text("\(sessions.count)回 / \(formatMindfulMinutes(totalMinutes))")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: showMindfulHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14 * UIScale.font, weight: .black))
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
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
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
                .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                .frame(width: 38, alignment: .leading)
            Text(japaneseLabel)
                .font(.system(size: 11 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(typeColor)
            Spacer()
            if session.averageHeartRate > 0 {
                HStack(spacing: 2) {
                    Text("❤️").font(.system(size: 10 * UIScale.font))
                    Text("\(Int(session.averageHeartRate))")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(Color(hex: "#FF4B4B"))
                }
            }
            if session.averageHRV > 0 {
                Text("HRV \(Int(session.averageHRV))")
                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color(hex: "#1CB0F6"))
            }
            Text("+\(xp) XP")
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoGold)
            Text(formatMindfulMinutes(session.durationMinutes))
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(typeColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(typeColor.opacity(0.07))
        .cornerRadius(8)
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
                .font(.system(size: 15 * UIScale.font, weight: .black))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
                Text(value)
                    .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
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
                .font(.system(size: 13 * UIScale.font, weight: .black))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
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
                        .font(.system(size: 14 * UIScale.font, weight: .bold))
                        .foregroundColor(Color(red: 0.451, green: 0.369, blue: 0.937))
                    Text("昨晩の睡眠")
                        .font(.headline.weight(.black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
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
                                .font(.system(size: 19 * UIScale.font, weight: .black))
                                .foregroundColor(healthKit.lastNightTotalHours >= 7.0 ? Color.duoGreen : Color.duoOrange)
                            Text("h")
                                .font(.system(size: 9 * UIScale.font))
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
                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
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
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 7 * UIScale.font, weight: .bold))
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
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func sleepInsightMessage(_ message: String, color: Color, isAlert: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 10 * UIScale.font, weight: .bold))
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
                                .font(.system(size: 9 * UIScale.font))
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
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                } else {
                    Text("\(label): \(value) ")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                    + Text("(\(note))")
                        .font(.system(size: 9 * UIScale.font))
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

    // MARK: - ムーミン名言リンクボタン
    private var moominQuoteLinkButton: some View {
        Button { showMoominQuotes = true } label: {
            HStack(spacing: 12) {
                Text("🌿")
                    .font(.system(size: 24))
                    .frame(width: 46, height: 46)
                    .background(Color(hex: "#CE82FF").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ムーミンの名言集")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("ストレスレベル別 · キャラクター別に整理した全名言")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color(hex: "#CE82FF").opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: "#CE82FF").opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                Color(hex: "#CE82FF").opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var mindBookSection: some View {
        let bookURL = URL(string: "https://amzn.to/4xODH4z")!
        return Link(destination: bookURL) {
            HStack(spacing: 12) {
                Text("🧘")
                    .font(.system(size: 26 * UIScale.font))
                    .frame(width: 50, height: 50)
                    .background(Color(hex: "#CE82FF").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smartfulness")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("AppleWatchで簡単、手軽にマインドフルなライフ&ワーク")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color(hex: "#CE82FF"))
                        Text("Amazonで見る →")
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color(hex: "#CE82FF"))
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color(hex: "#CE82FF").opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: "#CE82FF").opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                Color(hex: "#CE82FF").opacity(0.25), lineWidth: 1))
        }
    }

    /// Free ユーザー向け Smartfulness Kindle バナー
    private var smartfulnessBanner: some View {
        let bookURL = URL(string: "https://amzn.to/4xODH4z")!
        return Link(destination: bookURL) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("📚")
                        .font(.system(size: 12 * UIScale.font))
                    Text("Kindle書籍でマインドフルネスを学ぶ")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text("🧘")
                        .font(.system(size: 26 * UIScale.font))
                        .frame(width: 50, height: 50)
                        .background(Color(hex: "#CE82FF").opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smartfulness")
                            .font(.system(size: 13 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text("AppleWatchで簡単、手軽にマインドフルなライフ&ワーク")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            Text("kindle")
                                .font(.system(size: 8 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(hex: "#FF9900"))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text("Kindleで読む →")
                                .font(.system(size: 10 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color(hex: "#FF9900"))
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9900").opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(hex: "#FF9900").opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                    Color(hex: "#FF9900").opacity(0.2), lineWidth: 1))
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
    }

    private func recommendationRow(_ item: MindRecommendation) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Text(item.prefix)
                .font(.system(size: 17 * UIScale.font))
            Text(item.text)
                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if item.actionType != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
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
                .font(.system(size: 13 * UIScale.font, weight: .bold))
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
                .font(.system(size: 13 * UIScale.font, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.headline.weight(.black))
                .foregroundColor(Color.duoDark)
            Spacer()
            Button {
                showHRVHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 17 * UIScale.font, weight: .bold))
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
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(size: 24 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            if let detail {
                Text(detail)
                    .font(.system(size: 8 * UIScale.font, weight: .black, design: .rounded))
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
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
            Text(stress.label)
                .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stress.englishLabel)
                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
            if let detail {
                Text(detail)
                    .font(.system(size: 8 * UIScale.font, weight: .black, design: .rounded))
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
            Text(icon).font(.system(size: 18 * UIScale.font))
            Text(text)
                .font(.system(size: 13 * UIScale.font, weight: .bold))
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
                    .font(.system(size: 32 * UIScale.font))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.75))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
                        .foregroundColor(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 18 * UIScale.font, weight: .bold))
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
        stressInfoFromHRV(hrv)
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
        // V25: キャッシュ済み値を参照（二重 reduce を排除）
        let totalMindfulness = cachedTotalMindfulness
        let totalMindfulnessGoal = cachedTotalMindfulnessGoal
        let totalStretch = cachedTotalStretch
        let totalStretchGoal = cachedTotalStretchGoal
        return HStack(spacing: 6) {
            Text("MIND")
                .font(.system(size: 8 * UIScale.font, weight: .black))
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
                    Text("🧘").font(.system(size: 13 * UIScale.font))
                    Text(totalMindfulnessGoal > 0 ? "\(totalMindfulness)/\(totalMindfulnessGoal)" : "\(totalMindfulness)")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(totalMindfulnessGoal > 0 && totalMindfulness >= totalMindfulnessGoal ? mindColor : Color.duoDark)
                }
                HStack(spacing: 2) {
                    Text("🤸").font(.system(size: 13 * UIScale.font))
                    Text(totalStretchGoal > 0 ? "\(totalStretch)/\(totalStretchGoal)分" : "—")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
                        .foregroundColor(totalStretchGoal > 0 && totalStretch >= totalStretchGoal ? mindColor : Color.duoDark)
                }
                HStack(spacing: 2) {
                    Text("☀️").font(.system(size: 13 * UIScale.font))
                    Text(healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—")
                        .font(.system(size: 9 * UIScale.font, weight: .bold))
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
                    .font(.system(size: 11 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                if let latest = data.last {
                    Text("\(Int(latest.value)) ms")
                        .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(Color.duoGreen)
                }
            }

            if data.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.55))
                    Text("今日のHRVサンプルがまだ少ないです")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
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
                                .font(.system(size: 8 * UIScale.font, weight: .black, design: .rounded))
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
            .font(.system(size: 8 * UIScale.font, weight: .bold))
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

    private var sortedDays: [DailyHRVAverage] {
        days.sorted { $0.date < $1.date }
    }

    private var validDays: [DailyHRVAverage] {
        sortedDays.filter { $0.value > 0 }
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
                        .font(.system(size: 11 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("赤ラインはストレス高めの目安 20ms")
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                if let latest = validDays.last {
                    Text("\(Int(latest.value)) ms")
                        .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(latest.value < lowerLimit ? Color(hex: "#FF4B4B") : Color.duoGreen)
                }
            }

            if validDays.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 22 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle.opacity(0.55))
                    Text("過去7日のHRV平均データがまだ少ないです")
                        .font(.system(size: 11 * UIScale.font, weight: .bold))
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
                            .font(.system(size: 8 * UIScale.font, weight: .black, design: .rounded))
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
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
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
                .font(.system(size: 13 * UIScale.font, weight: .semibold))
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
                .font(.system(size: 13 * UIScale.font, weight: .black))
                .foregroundColor(color)
            Spacer()
            Text(detail)
                .font(.system(size: 12 * UIScale.font, weight: .bold))
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

// MARK: - ムーミン名言一覧シート

struct MoominQuoteListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Int? = nil  // nil = すべて
    @ObservedObject private var ttsEngine = DuolingoTextExtractor.shared
    @State private var speakingQuoteText: String? = nil

    private struct QuoteSection: Identifiable {
        let id: Int          // stress score帯のID（-1, 0, 30, 55, 75）
        let title: String
        let emoji: String
        let color: Color
        let quotes: [MoominQuote]
    }

    private let sections: [QuoteSection] = [
        QuoteSection(id: 0, title: "元気なとき", emoji: "🟢", color: Color.duoGreen, quotes: [
            MoominQuote(text: "道や川ってふしぎだなあ。ずっと先までつづくのを見ていると、遠くへ行きたくてたまらなくなっちゃう。どこまで行くのかなって、ついていきたくなるんだ……", speaker: "スニフ"),
            MoominQuote(text: "食べることもわすれるほど、しあわせになれるんだね！", speaker: "スニフ"),
            MoominQuote(text: "長い旅行に必要なのは大きなカバンじゃなく、口ずさめる一つの歌さ", speaker: "スナフキン"),
            MoominQuote(text: "自分できれいだと思うものは、なんでも僕のものさ。その気になれば、世界中でもね", speaker: "スナフキン"),
            MoominQuote(text: "生きるなんて、だれにだってできるじゃないか", speaker: "ムーミンパパ"),
            MoominQuote(text: "月の光をごらんよ。なんてあったかいんだろ。ぼく、飛べそうな気がするよ！", speaker: "ムーミントロール"),
            MoominQuote(text: "これから、なにもかもがうまくいくんだ", speaker: "ムーミントロール"),
            MoominQuote(text: "今だったら、どんなことだってできるわ。ま、なにもしないけど。でも、なんだって自分のやりたいと思ったことをするっていうのは、すてきよね！", speaker: "ミムラねえさん"),
            MoominQuote(text: "劇場は、世界でいちばん大事なものなんだ。そこへ行けばだれでも、自分にどんな生き方ができるか、見ることができる", speaker: "エンマ"),
            MoominQuote(text: "友だちが、それぞれ自分にぴったりのことを見つけられるのって、うれしいものでしょ？", speaker: "ムーミンママ"),
            MoominQuote(text: "同じところに住みついていたんじゃ、冒険家になれるもんか！", speaker: "ムーミンパパ"),
            MoominQuote(text: "世の中には、すばらしいことがいっぱいあるが、そういうものはそれにふさわしい人物でなくては開かれんのだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "ぼくは自分の運命を、この手で切り開いてみせるぞ", speaker: "ムーミンパパ"),
            MoominQuote(text: "ぼく、腹ぺこだよ。食べることもわすれるほど、しあわせになれるんだね！", speaker: "スニフ"),
        ]),
        QuoteSection(id: 30, title: "おだやかなとき", emoji: "🟡", color: Color(hex: "#58CC02"), quotes: [
            MoominQuote(text: "大切なのは、自分のしたいことを自分で知ってるってことだよ", speaker: "スナフキン"),
            MoominQuote(text: "「そのうち」なんて当てにならないな。いまがその時さ", speaker: "スナフキン"),
            MoominQuote(text: "いつも希望を胸に生きるって、いいことよね", speaker: "リトルミイ"),
            MoominQuote(text: "さあ、明日もまた、長い一日になるでしょうよ。しかも、はじめからおわりまで自分のものよ。とてもすてきなことじゃない！", speaker: "ムーミンママ"),
            MoominQuote(text: "たまには変化も必要ですよ。わたしたちはおたがいに、あまりにも、あたりまえのことをあたりまえと思いすぎるのじゃない？", speaker: "ムーミンママ"),
            MoominQuote(text: "しないではいられないということと、しなければならないということは、ちがうわよね。", speaker: "フィリフヨンカ"),
            MoominQuote(text: "なんにでも、時期というものがあってね。今は、はたらくときなのさ", speaker: "ヘムレン"),
            MoominQuote(text: "人と違った考えを持つことは一向にかまわないさ。でも、その考えを無理やり他の人に押し付けてはいけないなあ", speaker: "スナフキン"),
            MoominQuote(text: "心の繋がった仲間こそ、ルビーにも勝る美しいルビーさ。", speaker: "スナフキン"),
            MoominQuote(text: "今夜は歌のことだけを考えよう。明日は明日の風が吹くさ", speaker: "スナフキン"),
            MoominQuote(text: "ぼくたちは、本能にしたがって歩くのがいいんだ。", speaker: "スナフキン"),
            MoominQuote(text: "ぜったいにたしかなもの―そういうものがあるんだよ。たとえば、海の潮流とか、季節のうつり変わりとか、朝になったら日がのぼるとかさ", speaker: "ムーミンパパ"),
            MoominQuote(text: "ときには思いついたことをやってみよ、ですわ", speaker: "フィリフヨンカ"),
            MoominQuote(text: "なにかためしてみようってときには、どうしたって危険がともなうんだ", speaker: "スナフキン"),
            MoominQuote(text: "春のいちばん初めの日には、ぼくはまたここへもどってきて、窓の下で口笛を吹くよ。一年なんか、あっという間さ", speaker: "スナフキン"),
            MoominQuote(text: "正義は正義であるべきです。そこは、わきまえなくてはいけない。", speaker: "スノーク"),
            MoominQuote(text: "生きるってことは、平和じゃないんですよ", speaker: "スナフキン"),
        ]),
        QuoteSection(id: 55, title: "疲れ気味のとき", emoji: "🟠", color: Color.duoOrange, quotes: [
            MoominQuote(text: "あんまりおおげさに考えすぎないようにしろよ。なんでも、大きくしすぎちゃ、だめだぜ", speaker: "スナフキン"),
            MoominQuote(text: "ちょっと眠るよ。ちょいちょい、寝ている間に、問題が自然にとけることがあるからな。頭はほったらかしておくと、よく働くものなんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "眠っているときは、休んでいるときだ。春、また元気を取り戻すために", speaker: "スナフキン"),
            MoominQuote(text: "ゆううつになんか、ならないで。ぼくたちが帰ったら、ママはごちそうを作って待ってるんだ", speaker: "ムーミントロール"),
            MoominQuote(text: "もう泣くのはやめて、サンドイッチを食べなよ。", speaker: "ムーミントロール"),
            MoominQuote(text: "ものごとって、みんなとてもあいまいなのよ。まさにそのことが、わたしを安心させるんだけれどもね", speaker: "トゥーティッキ"),
            MoominQuote(text: "あんまりだれかを崇拝すると、本物の自由はえられないんだぜ。そういうものなのさ", speaker: "スナフキン"),
            MoominQuote(text: "生きるって、すばらしいことだなあ。どんなものでも、なんの理由もなしにあべこべになったりするんだねえ", speaker: "ムーミントロール"),
            MoominQuote(text: "なんだっておもしろいのよ—多かれ、少なかれ", speaker: "リトルミイ"),
            MoominQuote(text: "だけど、こんなに泣いてもいい理由があるときには、泣けるだけ泣いておくの", speaker: "ミーサ"),
            MoominQuote(text: "明日という日があるじゃないの", speaker: "ムーミンママ"),
            MoominQuote(text: "なにもかもがちゃんとするまでには、ずいぶんと長くかかるかもしれないわ", speaker: "ムーミンママ"),
            MoominQuote(text: "あんたったら、ほんとに自分自身をだますのがじょうずね！", speaker: "リトルミイ"),
            MoominQuote(text: "あそこへ行けば、ほんとうに助けてくれるかね？ 人間て、そういうものかね？", speaker: "ムーミントロール"),
            MoominQuote(text: "人の目なんか気にしないで、思うとおりに暮らしていればいいのさ", speaker: "スナフキン"),
        ]),
        QuoteSection(id: 75, title: "力が必要なとき", emoji: "🔴", color: Color(hex: "#FF4B4B"), quotes: [
            MoominQuote(text: "どんなことでも、自分で見つけださなきゃいけないものよ。そうして自分ひとりで、それを乗りこえるんだわ", speaker: "トゥーティッキ"),
            MoominQuote(text: "ほら、元気をなくしてはだめだよ。もう一回！", speaker: "ヘムレン"),
            MoominQuote(text: "本当の勇気とは自分の弱い心に打ち勝つことだよ。包み隠さず本当のことを正々堂々と言える者こそ本当の勇気のある強い者なんだ", speaker: "スナフキン"),
            MoominQuote(text: "一度決めたら最後までやりぬく、それが俺の人生さ", speaker: "スナフキン"),
            MoominQuote(text: "あのさ、たたかうってことをおぼえないかぎり、あんたには自分の顔を持てるわけないわ", speaker: "リトルミイ"),
            MoominQuote(text: "飢えを知っていればこそ、ぼくは二度とそうなりたくないと努力するだけだよ", speaker: "スナフキン"),
            MoominQuote(text: "なにかちがうこと、なにかあたらしいことをしなくちゃな。なにかすごく大きなことをやるんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "いつでも日曜日だったら、すばらしいじゃないか。そういう気持ちこそ、われわれが見失っていたものなんだ", speaker: "ムーミンパパ"),
            MoominQuote(text: "おだやかな人生なんてあるわけがない", speaker: "スナフキン"),
            MoominQuote(text: "さあ、さっと思い立ったときに決心しなくては。決心がにぶらないうちに、すばやく実行しなくては", speaker: "フィリフヨンカ"),
            MoominQuote(text: "だれだって、ときにはおこるほうがいいのよ。どんな小さなクニットだって、おこる権利はあるのよ", speaker: "リトルミイ"),
            MoominQuote(text: "自然の力はすばらしいもんだよ", speaker: "スナフキン"),
            MoominQuote(text: "何でも自分のものにして持って帰ろうとすると難しいものなんだよ。ぼくは見るだけにしてるんだ。そして立ち去るときにはそれを頭の中へしまっておくのさ", speaker: "スナフキン"),
        ]),
        QuoteSection(id: -1, title: "いつでも", emoji: "🌿", color: Color.duoPurple, quotes: [
            MoominQuote(text: "ね、なにが起こったって、わたしにはちゃんとあなたがわかるのよ", speaker: "ムーミンママ"),
            MoominQuote(text: "もうだいじょうぶよ、ほら、いらっしゃい。", speaker: "ムーミンママ"),
            MoominQuote(text: "なんでも自分のものにして、持って帰ろうとすると、むずかしくなっちゃうんだよ。ぼくは見るだけにしてるんだ。そして立ち去るときには、頭の中へしまっておく", speaker: "スナフキン"),
            MoominQuote(text: "孤独になるには、旅に出るのがいちばんさ", speaker: "スナフキン"),
            MoominQuote(text: "でも、冒険物語じゃ、かならず助かることになっているんだよ", speaker: "スナフキン"),
            MoominQuote(text: "ね、なにが起こったって、わたしにはちゃんとあなたがわかるのよ", speaker: "ムーミンママ"),
            MoominQuote(text: "みんなそれぞれ、こうもちがうものなんだな", speaker: "ムーミントロール"),
            MoominQuote(text: "ときどき、どうしてもひとりになりたいっていうきみの気持ちを、ぼくはもちろんよくわかるんだ", speaker: "ムーミントロール"),
            MoominQuote(text: "ブラックコーヒーを一ぱい飲んだら、もう、ぼくのものだ。", speaker: "スナフキン"),
            MoominQuote(text: "あんまり誰かを崇拝したら、ホントの自由は、得られないんだぜ", speaker: "スナフキン"),
            MoominQuote(text: "故郷は別にないさ、強いて言えば地球かな", speaker: "スナフキン"),
            MoominQuote(text: "この世にはいくら考えてもわからない、でも、長く生きることで解かってくる事がたくさんあると思う", speaker: "スナフキン"),
            MoominQuote(text: "ムーミン「義務って何のこと？」スナフキン「したくないことを、することさ」", speaker: "スナフキン"),
            MoominQuote(text: "自由が幸せだとは限らない", speaker: "スナフキン"),
            MoominQuote(text: "だまされてはだめよ。わたしはちゃんとわかってるんだから。大きな災難が来るまえは、いつだって、こんなふうにおだやかなのよ", speaker: "フィリフヨンカ"),
            MoominQuote(text: "自分の入りたくないところへ無理やりに入れられたら、君はどうする？自分のやりたいことを押さえつけられたら、君はどうする", speaker: "スナフキン"),
            MoominQuote(text: "いきるってことは、平和なものじゃないんですよ", speaker: "スナフキン"),
        ]),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // カテゴリフィルター（コンパクト）
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            filterChip(id: nil, label: "全て", emoji: "✨", color: Color.duoPurple)
                            ForEach(sections) { sec in
                                filterChip(id: sec.id, label: sec.title, emoji: sec.emoji, color: sec.color)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider()

                    let visibleSections = selectedCategory == nil
                        ? sections
                        : sections.filter { $0.id == selectedCategory }

                    ForEach(visibleSections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            // セクションヘッダー
                            HStack(spacing: 8) {
                                Text(section.emoji)
                                    .font(.system(size: 16))
                                Text(section.title)
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(section.color)
                                Spacer()
                                Text("\(section.quotes.count)件")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(section.color.opacity(0.7))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(section.color.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 6)

                            VStack(spacing: 8) {
                                ForEach(section.quotes.indices, id: \.self) { idx in
                                    let q = section.quotes[idx]
                                    quoteRow(q, color: section.color)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            Divider().padding(.horizontal, 16).padding(.top, 8)
                        }
                    }
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("🌿 ムーミンの名言集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func filterChip(id: Int?, label: String, emoji: String, color: Color) -> some View {
        let isSelected = selectedCategory == id
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedCategory = id }
        } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 12))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .black : .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quoteRow(_ quote: MoominQuote, color: Color) -> some View {
        let isSpeaking = speakingQuoteText == quote.text && ttsEngine.isSpeaking
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("「\(quote.text)」")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(4)
                    .lineSpacing(2)
                Text("— \(quote.speaker)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color.opacity(0.8))
                    .italic()
            }
            Spacer(minLength: 4)
            Button {
                if isSpeaking {
                    ttsEngine.stopSpeaking()
                    speakingQuoteText = nil
                } else {
                    speakingQuoteText = quote.text
                    ttsEngine.speak(phrase: quote.text, languageCode: "ja")
                }
            } label: {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSpeaking ? .red : color)
                    .frame(width: 24, height: 24)
                    .background((isSpeaking ? Color.red : color).opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSpeaking ? color.opacity(0.12) : color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSpeaking ? color.opacity(0.4) : color.opacity(0.12), lineWidth: isSpeaking ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.2), value: isSpeaking)
    }
}
