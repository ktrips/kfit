import SwiftUI

// MARK: - MindView（kfit と同等レイアウト）
// 変更点: 「昨晩の睡眠」カードの内容を「今日のまとめ」カード内に統合

struct MindView: View {

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
    private static let hm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "H:mm"; return f
    }()

    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool

    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var plus: PlusManager

    @AppStorage(AppStorageKey.sleepHoursGoal) private var sleepHoursGoal = 7

    @State private var showMindfulnessSession = false
    @State private var showStretchSession = false
    @State private var showMindfulHistory = false
    @State private var showHRVHelp = false
    @State private var showPlusView = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                if plus.isPlus {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            currentStressCard
                            todaySummaryCard       // 今日のまとめ + 睡眠スコア統合
                            suggestionsCard
                            mindBookSection
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await healthKit.fetchMindHealth(force: true)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            fitActivityCard
                            pfcBalanceCard
                            plusLockView
                            smartfulnessBanner
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                    .refreshable {
                        await healthKit.fetchMindHealth(force: true)
                    }
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) { mindHeader }
            .sheet(isPresented: $showPlusView) {
                PlusView().environmentObject(plus)
            }
            .sheet(isPresented: $showHRVHelp) {
                HRVStressHelpView()
            }
            .sheet(isPresented: $showMindfulnessSession) {
                TimedMeditationView(
                    durationSeconds: 60,
                    title: "1分瞑想",
                    sessionType: "Breathe"
                ) { start, end in
                    Task {
                        let ok = await healthKit.saveMindfulnessSession(
                            startDate: start, endDate: end, durationSeconds: 60, sessionType: "Breathe"
                        )
                        if ok { await healthKit.refreshMindfulness() }
                    }
                }
            }
            .sheet(isPresented: $showStretchSession) {
                TimedMeditationView(
                    durationSeconds: 180,
                    title: "3分ストレッチ",
                    sessionType: "Reflect"
                ) { start, end in
                    Task {
                        let ok = await healthKit.saveMindfulnessSession(
                            startDate: start, endDate: end, durationSeconds: 180, sessionType: "Reflect"
                        )
                        if ok { await healthKit.refreshMindfulness() }
                    }
                }
            }
        }
        .task {
            if healthKit.isAvailable && !healthKit.isAuthorized {
                await healthKit.requestAuthorization()
            } else {
                await healthKit.fetchMindHealth()
            }
        }
    }

    // MARK: - グラデーションヘッダー

    private var mindHeader: some View {
        ZStack {
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
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    Text("🧘").font(.system(size: 15 * UIScale.font))
                    Text("\(healthKit.todayMindfulnessSessions)")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("☀️").font(.system(size: 15 * UIScale.font))
                    Text(healthKit.todayDaylightMinutes > 0 ? "\(Int(healthKit.todayDaylightMinutes))分" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(healthKit.todayDaylightMinutes >= 30
                                         ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await healthKit.fetchMindHealth(force: true) }
                } label: {
                    Image(systemName: healthKit.isLoading ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        .foregroundColor(.white)
                        .font(.system(size: 16 * UIScale.font, weight: .bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(height: 50)
    }

    // MARK: - 現在のストレスレベルカード

    private var currentStressCard: some View {
        let stress = stressInfo(healthKit.latestHRV)
        return card {
            cardTitleWithHelp("現在のストレスレベル", icon: "heart.fill", color: stress.color)
            HStack(spacing: 10) {
                metricTile(label: "心拍数",
                           value: healthKit.latestHeartRate > 0 ? "\(Int(healthKit.latestHeartRate))" : "—",
                           unit: "bpm", color: Color(hex: "#FF4B4B"))
                metricTile(label: "HRV",
                           value: healthKit.latestHRV > 0 ? "\(Int(healthKit.latestHRV))" : "—",
                           unit: "ms", color: Color.duoGreen)
                stressTile(stress)
            }
            if stress.score >= 55 {
                suggestionBanner(icon: "🫁",
                    text: "ストレスが高めです。マインドフルネスで深呼吸を1分だけ試してみましょう。",
                    color: stress.color)
            } else {
                suggestionBanner(icon: "🌿",
                    text: "今の状態は落ち着いています。こまめな水分補給と短い休憩で維持しましょう。",
                    color: Color.duoGreen)
            }
            largeActionButton(icon: "🧘", title: "1分瞑想タイマー",
                              subtitle: "自分の呼吸に集中して1分瞑想でリラックスする",
                              color: Color(hex: "#1CB0F6")) {
                showMindfulnessSession = true
            }
            HRVTrendChart(samples: healthKit.hrvSamples).frame(height: 126)
                .padding(10).background(Color(.systemBackground)).cornerRadius(14)
            mindfulHistorySection
        }
    }

    // MARK: - 今日のまとめ + 睡眠（統合カード）

    private var todaySummaryCard: some View {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        let sleepAnalysis = healthKit.analyzeSleepScore(targetHours: Double(sleepHoursGoal))
        return card {
            // ─ 今日のまとめ ─
            cardTitleWithHelp("今日のまとめ", icon: "waveform.path.ecg", color: stress.color)
            HStack(spacing: 10) {
                metricTile(label: "平均心拍",
                           value: healthKit.todayAvgHeartRate > 0 ? "\(Int(healthKit.todayAvgHeartRate))" : "—",
                           unit: "bpm", color: Color(hex: "#FF4B4B"))
                metricTile(label: "平均HRV",
                           value: avgHRV > 0 ? "\(Int(avgHRV))" : "—",
                           unit: "ms", color: Color.duoGreen)
                stressTile(stress)
            }
            HStack(spacing: 10) {
                mindSummaryMetricCard(icon: "bed.double.fill",    label: "睡眠時間",
                                      value: formatSleepHours(healthKit.lastNightTotalHours),
                                      color: Color(red: 0.451, green: 0.369, blue: 0.937))
                mindSummaryMetricCard(icon: "sun.max.fill",       label: "日光下時間",
                                      value: formatMinutes(Int(healthKit.todayDaylightMinutes)),
                                      color: Color(hex: "#FFCC00"))
                mindSummaryMetricCard(icon: "figure.run",         label: "運動時間",
                                      value: formatMinutes(healthKit.todayWorkoutMinutes),
                                      color: Color(hex: "#1CB0F6"))
            }
            suggestionBanner(icon: "🌿",
                             text: holisticMessage(stress),
                             color: stress.color)

            // ─ 昨晩の睡眠（統合）─
            Divider().padding(.vertical, 4)

            sleepSectionTitle("昨晩の睡眠", icon: "bed.double.fill",
                              color: Color(red: 0.451, green: 0.369, blue: 0.937))

            if sleepAnalysis.score > 0 {
                HStack(alignment: .center, spacing: 8) {
                    SleepScoreRingView(sleep: sleepAnalysis)
                    VStack(alignment: .leading, spacing: 4) {
                        sleepBulletRow(color: Color(red: 0.44, green: 0.52, blue: 0.90),
                                       label: "睡眠時間",
                                       value: "\(sleepAnalysis.durationScore)/50",
                                       note: String(format: "%.1fh/%.0fh", sleepAnalysis.totalHours, sleepAnalysis.targetHours))
                        sleepBulletRow(color: Color(red: 0.22, green: 0.80, blue: 0.72),
                                       label: "就寝時刻",
                                       value: "\(sleepAnalysis.bedtimeScore)/30",
                                       note: sleepAnalysis.firstSleepTime.map { MindView.hm.string(from: $0) } ?? "—")
                        sleepBulletRow(color: Color(red: 0.95, green: 0.48, blue: 0.40),
                                       label: "睡眠中断",
                                       value: "\(sleepAnalysis.interruptionScore)/20",
                                       note: sleepAnalysis.awakeHours < 0.1 ? "なし" : String(format: "%.0f分", sleepAnalysis.awakeHours * 60))
                    }
                    Spacer(minLength: 0)
                }
            } else if healthKit.lastNightTotalHours > 0 {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", healthKit.lastNightTotalHours))
                        .font(.system(size: 19 * UIScale.font, weight: .black))
                        .foregroundColor(healthKit.lastNightTotalHours >= 7 ? Color.duoGreen : Color.duoOrange)
                    Text("h").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    Spacer()
                }
            } else {
                Text("昨夜の睡眠データなし")
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
            }

            // 睡眠ステージバー
            if !healthKit.sleepSegments.isEmpty {
                sleepStageBar
            }

            sleepInsightMessage(sleepScoreInsight(sleepAnalysis),
                                color: sleepScoreColor(sleepAnalysis.score))

            // バイタル
            sleepVitalsSection(healthKit.sleepVitals)

            Divider().padding(.vertical, 4)

            largeActionButton(icon: "🤸", title: "3分ストレッチ",
                              subtitle: "肩・首・背中をゆるめる3分セッションをHealthKitへ保存",
                              color: Color.duoGreen) {
                showStretchSession = true
            }

            WeeklyHRVAverageChart(days: healthKit.weeklyHRVAverages).frame(height: 132)
                .padding(10).background(Color(.systemBackground)).cornerRadius(14)
        }
    }

    // MARK: - 具体的にできることカード

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

    // MARK: - Smartfulness ブック

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
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: "#CE82FF").opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#CE82FF").opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - FIT アクティビティカード（フリーユーザー表示）

    private var fitActivityCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack(spacing: 6) {
                    Text("🏃")
                    Text("今日のアクティビティ")
                        .font(.system(size: UIScale.font == 1 ? 14 : 13 * UIScale.font, weight: .black))
                        .foregroundStyle(Color.duoDark)
                    Spacer()
                    Text("FIT")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(hex: "#FF6B35"))
                        .clipShape(Capsule())
                }

                // メトリクスグリッド
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    fitMetricTile(
                        icon: "figure.walk",
                        color: Color(hex: "#FF6B35"),
                        value: healthKit.todaySteps >= 1000
                            ? String(format: "%.1fk", Double(healthKit.todaySteps) / 1000)
                            : "\(healthKit.todaySteps)",
                        unit: "歩",
                        label: "歩数",
                        progress: min(Double(healthKit.todaySteps) / 10000, 1.0)
                    )
                    fitMetricTile(
                        icon: "flame.fill",
                        color: Color(hex: "#FF3B30"),
                        value: String(format: "%.0f", healthKit.todayActiveCalories),
                        unit: "kcal",
                        label: "消費",
                        progress: min(healthKit.todayActiveCalories / 500, 1.0)
                    )
                    fitMetricTile(
                        icon: "figure.run",
                        color: Color(hex: "#34C759"),
                        value: "\(healthKit.todayWorkoutMinutes)",
                        unit: "分",
                        label: "運動",
                        progress: min(Double(healthKit.todayWorkoutMinutes) / 30, 1.0)
                    )
                    fitMetricTile(
                        icon: "person.fill",
                        color: Color(hex: "#007AFF"),
                        value: "\(healthKit.todayStandHours)",
                        unit: "時間",
                        label: "スタンド",
                        progress: min(Double(healthKit.todayStandHours) / 12, 1.0)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fitMetricTile(icon: String, color: Color, value: String, unit: String, label: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.duoSubtitle)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color.duoDark)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.duoSubtitle)
            }
            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(geo.size.width * progress, 4), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - PFC バランスカード（フリーユーザー表示）

    private var pfcBalanceCard: some View {
        let total = healthKit.todayProteinG + healthKit.todayFatG + healthKit.todayCarbsG
        let hasData = total > 0
        return card {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack(spacing: 6) {
                    Text("🥗")
                    Text("PFCバランス")
                        .font(.system(size: UIScale.font == 1 ? 14 : 13 * UIScale.font, weight: .black))
                        .foregroundStyle(Color.duoDark)
                    Spacer()
                    Text("FOOD")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(hex: "#4CD964"))
                        .clipShape(Capsule())
                }

                if hasData {
                    HStack(spacing: 16) {
                        // PFC リング
                        ZStack {
                            pfcRingArc(start: 0,    end: total > 0 ? healthKit.todayCarbsG   / total : 0,   color: Color(hex: "#5AC8FA"))
                            pfcRingArc(start: total > 0 ? healthKit.todayCarbsG / total : 0,
                                       end: total > 0 ? (healthKit.todayCarbsG + healthKit.todayFatG) / total : 0,
                                       color: Color(hex: "#FF9500"))
                            pfcRingArc(start: total > 0 ? (healthKit.todayCarbsG + healthKit.todayFatG) / total : 0,
                                       end: 1.0,   color: Color(hex: "#FF2D55"))
                            VStack(spacing: 0) {
                                Text(String(format: "%.0f", total))
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.duoDark)
                                Text("g")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.duoSubtitle)
                            }
                        }
                        .frame(width: 76, height: 76)

                        // 凡例
                        VStack(alignment: .leading, spacing: 8) {
                            pfcLegendRow(label: "P タンパク質", gram: healthKit.todayProteinG, color: Color(hex: "#FF2D55"),
                                         ratio: total > 0 ? healthKit.todayProteinG / total : 0)
                            pfcLegendRow(label: "F 脂質",       gram: healthKit.todayFatG,     color: Color(hex: "#FF9500"),
                                         ratio: total > 0 ? healthKit.todayFatG / total : 0)
                            pfcLegendRow(label: "C 炭水化物",   gram: healthKit.todayCarbsG,   color: Color(hex: "#5AC8FA"),
                                         ratio: total > 0 ? healthKit.todayCarbsG / total : 0)
                        }
                        Spacer()
                    }
                } else {
                    HStack {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "#4CD964").opacity(0.5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("今日の食事データがありません")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.duoSubtitle)
                            Text("食事管理アプリで HealthKit に記録すると表示されます")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.duoSubtitle.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func pfcRingArc(start: Double, end: Double, color: Color) -> some View {
        let span = max(end - start, 0)
        return Circle()
            .trim(from: start, to: start + span)
            .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    @ViewBuilder
    private func pfcLegendRow(label: String, gram: Double, color: Color, ratio: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.duoSubtitle)
            Spacer()
            Text(String(format: "%.0fg", gram))
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.duoDark)
            Text(String(format: "%.0f%%", ratio * 100))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.duoSubtitle)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Plus ロック画面（フリーユーザー）

    private var plusLockView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: "#6D5DF6"))
            Text("MIND は Plus 機能です")
                .font(.title2.bold())
            Text("HRV・睡眠・マインドフルネスの詳細分析は\nkmind Plus で利用できます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { showPlusView = true } label: {
                Text("Plus にアップグレード")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LinearGradient(colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var smartfulnessBanner: some View {
        let bookURL = URL(string: "https://amzn.to/4xODH4z")!
        return Link(destination: bookURL) {
            HStack(spacing: 12) {
                Text("🧘")
                    .font(.system(size: 26 * UIScale.font))
                    .frame(width: 50, height: 50)
                    .background(Color(hex: "#FF9900").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smartfulness")
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("AppleWatchで簡単、手軽にマインドフルなライフ&ワーク")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
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
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(hex: "#FF9900").opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#FF9900").opacity(0.2), lineWidth: 1))
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: - マインドフル履歴

    private var mindfulHistorySection: some View {
        let sessions = healthKit.todayMindfulnessSamples
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.durationMinutes }

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showMindfulHistory.toggle() }
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
                .padding(.horizontal, 12).padding(.vertical, 8)
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
                .padding(.horizontal, 10).padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.duoGreen.opacity(0.12), lineWidth: 1))
    }

    private func mindfulHistoryRow(_ session: MindfulSession) -> some View {
        let isReflect = session.sessionTypeLabel == "Reflect"
        let isStand   = session.sessionTypeLabel == "Stand"
        let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)
        let typeColor: Color = isStand ? standColor : (isReflect ? Color.duoPurple : Color(hex: "#1CB0F6"))
        let label = isStand ? "20分スタンド" : (isReflect ? "3分ストレッチ" : "1分瞑想")
        return HStack(spacing: 6) {
            Text(MindView.hhmm.string(from: session.startDate))
                .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                .frame(width: 38, alignment: .leading)
            Text(label)
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
            Text(formatMindfulMinutes(session.durationMinutes))
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(typeColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(typeColor.opacity(0.07))
        .cornerRadius(8)
    }

    // MARK: - 睡眠ステージバー

    private var sleepStageBar: some View {
        let segments = healthKit.sleepSegments.filter { $0.stage != .inBed }
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
                        (.rem,  "REM"),
                        (.core, "コア"),
                        (.awake,"覚醒"),
                    ], id: \.0.rawValue) { stage, label in
                        HStack(spacing: 3) {
                            Circle().fill(Color(hex: stage.color)).frame(width: 6, height: 6)
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

    // MARK: - 睡眠バイタル

    private func sleepVitalsSection(_ vitals: SleepVitalsAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sleepSectionTitle("睡眠中のバイタル情報", icon: "waveform.path.ecg", color: Color(hex: "#1CB0F6"))
            HStack(spacing: 6) {
                sleepVitalTile(label: "心拍",
                               value: vitals.averageHeartRate > 0 ? "\(Int(vitals.averageHeartRate))" : "—",
                               unit: "bpm",
                               color: sleepHeartRateColor(vitals.averageHeartRate))
                sleepVitalTile(label: "呼吸",
                               value: vitals.averageRespiratoryRate > 0 ? String(format: "%.1f", vitals.averageRespiratoryRate) : "—",
                               unit: "回/分",
                               color: sleepRespiratoryColor(vitals.averageRespiratoryRate))
                sleepVitalTile(label: "酸素",
                               value: vitals.averageOxygenSaturation > 0 ? "\(Int(vitals.averageOxygenSaturation))" : "—",
                               unit: "%",
                               color: sleepOxygenColor(vitals.minimumOxygenSaturation > 0
                                                        ? vitals.minimumOxygenSaturation
                                                        : vitals.averageOxygenSaturation))
            }
            if vitals.hasData {
                ForEach(sleepVitalsInsights(vitals), id: \.self) { msg in
                    let isAlert = vitals.alertMessages.contains(msg)
                    sleepInsightMessage(msg, color: isAlert ? Color.duoRed : Color.duoGreen, isAlert: isAlert)
                }
            } else {
                sleepInsightMessage(
                    "睡眠中のバイタルデータがまだありません。Apple Watchを装着して睡眠すると、心拍・呼吸・酸素レベルを確認できます。",
                    color: Color.duoSubtitle)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - レコメンデーション

    private var recommendations: [MindRecommendation] {
        let avgHRV = healthKit.todayAvgHRV > 0 ? healthKit.todayAvgHRV : healthKit.latestHRV
        let stress = stressInfo(avgHRV)
        var items: [MindRecommendation] = []
        if healthKit.todayMindfulnessMinutes < 1 {
            items.append(MindRecommendation(prefix: "🫁",
                text: "まだ深呼吸やマインドフルネスをしていません。1分だけ呼吸を整えてみましょう。",
                color: Color(hex: "#1CB0F6"), actionType: "mindfulness"))
        }
        if healthKit.todayMindfulnessSamples.filter({ $0.sessionTypeLabel == "Reflect" }).isEmpty {
            items.append(MindRecommendation(prefix: "🤸",
                text: "Reflectや軽いストレッチで、肩・首・背中をゆるめてみましょう。",
                color: Color.duoGreen, actionType: "stretch"))
        }
        if healthKit.todayStandHours < 6 || healthKit.todaySteps < 5000 {
            items.append(MindRecommendation(prefix: "🚶",
                text: "スタンド時間や歩数が少なめです。5分だけ外を歩く、階段を使うなどがおすすめです。",
                color: Color(hex: "#FF9600")))
        }
        if stress.score >= 55 {
            items.append(MindRecommendation(prefix: "💆",
                text: "こめかみ・首・肩を軽くマッサージして、体の緊張を落としてみましょう。",
                color: Color(hex: "#CE82FF"), actionType: "mindfulness"))
        }
        items.append(MindRecommendation(prefix: "☕",
            text: "コーヒーを淹れる、水を飲む、歯磨きをするなど、小さな切り替えを入れましょう。",
            color: Color(hex: "#1CB0F6")))
        items.append(MindRecommendation(prefix: "🌤️",
            text: "遠くを見る、ぼおっとする、軽く息継ぎをするなど、いつもと違う休み方を試しましょう。",
            color: Color.duoGreen))
        return Array(items.prefix(6))
    }

    private func recommendationRow(_ item: MindRecommendation) -> some View {
        let content = HStack(alignment: .top, spacing: 8) {
            Text(item.prefix).font(.system(size: 17 * UIScale.font))
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
                    switch action {
                    case "mindfulness": showMindfulnessSession = true
                    case "stretch":     showStretchSession = true
                    default: break
                    }
                } label: { content }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    // MARK: - Helper Views

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(title).font(.headline.weight(.black)).foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func cardTitleWithHelp(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(title).font(.headline.weight(.black)).foregroundColor(Color.duoDark)
            Spacer()
            Button { showHRVHelp = true } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 17 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
    }

    private func metricTile(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
            Text(value)
                .font(.system(size: 24 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(color)
            Text(unit).font(.system(size: 9 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(color.opacity(0.10)).cornerRadius(12)
    }

    private func stressTile(_ stress: MindStressInfo) -> some View {
        VStack(spacing: 3) {
            Text("ストレス").font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
            Text(stress.label)
                .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(stress.color).lineLimit(1).minimumScaleFactor(0.7)
            Text(stress.englishLabel)
                .font(.system(size: 9 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(stress.color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(stress.color.opacity(0.12)).cornerRadius(12)
    }

    private func mindSummaryMetricCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13 * UIScale.font, weight: .black)).foregroundColor(color)
            Text(value)
                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark).lineLimit(1).minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 9)
        .background(color.opacity(0.10)).cornerRadius(12)
    }

    private func suggestionBanner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon).font(.system(size: 18 * UIScale.font))
            Text(text)
                .font(.system(size: 13 * UIScale.font, weight: .bold)).foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12).background(color.opacity(0.10)).cornerRadius(12)
    }

    private func largeActionButton(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon).font(.system(size: 32 * UIScale.font))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.75)).clipShape(Circle())
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
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [color, color.opacity(0.72)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(16)
            .shadow(color: color.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func sleepSectionTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(title)
                .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(Color.duoDark)
            Spacer()
        }
    }

    private func sleepInsightMessage(_ message: String, color: Color, isAlert: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                .font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(message)
                .font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8).background(color.opacity(0.10)).cornerRadius(8)
    }

    private func sleepVitalTile(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit).font(.system(size: 7 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(color.opacity(0.10)).cornerRadius(9)
    }

    private func sleepBulletRow(color: Color, label: String, value: String, note: String = "") -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            if note.isEmpty {
                Text("\(label): \(value)")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark)
            } else {
                Text("\(label): \(value) ").font(.system(size: 11 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoDark)
                + Text("(\(note))").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
            }
        }
    }

    // MARK: - Helper Functions

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
        case ..<30: return MindStressInfo(score: score, label: "低い",   englishLabel: "Low",      color: Color.duoGreen)
        case ..<55: return MindStressInfo(score: score, label: "普通",   englishLabel: "Normal",   color: Color(red: 0.4, green: 0.75, blue: 0.1))
        case ..<75: return MindStressInfo(score: score, label: "やや高", englishLabel: "Elevated", color: Color.duoOrange)
        default:    return MindStressInfo(score: score, label: "高い",   englishLabel: "High",     color: Color(hex: "#FF4B4B"))
        }
    }

    private func holisticMessage(_ stress: MindStressInfo) -> String {
        if healthKit.lastNightTotalHours > 0 && healthKit.lastNightTotalHours < 6 {
            return "昨晩の睡眠が短めです。今日はカフェインを控えめにして、寝る前の画面時間を減らすと回復しやすくなります。"
        }
        if healthKit.todayDaylightMinutes < 20 {
            return "日光下時間が少なめです。午前中か昼に5〜10分だけ外へ出ると、体内時計とストレス回復を整えやすくなります。"
        }
        if healthKit.todayWorkoutMinutes < 20 {
            return "運動時間が少なめです。軽い散歩やストレッチを10分足すと、HRVと気分の回復につながりやすいです。"
        }
        if stress.score >= 55 {
            return "睡眠・日光・運動はある程度取れています。今日は1分瞑想や3分ストレッチで、首肩の緊張を落としてみましょう。"
        }
        return "睡眠・日光・運動のバランスは良好です。今のリズムを保ちつつ、短い休憩をこまめに入れましょう。"
    }

    private func sleepScoreInsight(_ a: SleepScoreAnalysis) -> String {
        guard a.score > 0 else {
            return "睡眠データがまだ十分にありません。Apple Watchを装着して寝ると、睡眠時間・就寝時刻・中断を分析できます。"
        }
        if a.durationScore < 35 {
            return "睡眠時間が目標より短めです。就寝を30分早める、夕方以降のカフェインを控えるなどで回復時間を増やしましょう。"
        }
        if a.bedtimeScore < 20 {
            return "就寝時刻が遅めです。寝る前の画面時間を減らし、同じ時間にベッドへ入る習慣を作るとスコアが安定します。"
        }
        if a.interruptionScore < 14 {
            return "睡眠中の覚醒が多めです。寝室の温度・光・音を整え、アルコールや遅い食事を控えると改善しやすいです。"
        }
        if a.score >= 80 {
            return "昨晩の睡眠は良好です。今日も同じ就寝リズムを保つと、ストレス回復が安定しやすくなります。"
        }
        return "大きな異常はありませんが、睡眠時間・就寝時刻・中断のうち弱い項目を1つだけ整えると改善しやすいです。"
    }

    private func sleepVitalsInsights(_ vitals: SleepVitalsAnalysis) -> [String] {
        var messages = vitals.alertMessages
        if messages.isEmpty && vitals.hasData {
            messages.append("睡眠中のバイタルに大きな注意点はありません。今の睡眠環境を維持しつつ、起床後の体調も合わせて確認しましょう。")
        }
        if vitals.averageHeartRate > 0 && vitals.averageHeartRate > 80 {
            messages.append("睡眠中の心拍が高めです。寝る前の強い運動・飲酒・カフェインを少し下げると落ち着きやすいです。")
        }
        if vitals.averageRespiratoryRate > 0 && vitals.averageRespiratoryRate > 20 {
            messages.append("呼吸数がやや高めです。鼻詰まり、寝室の乾燥、疲労感がないか確認し、就寝前にゆっくり呼吸を整えましょう。")
        }
        return Array(messages.prefix(3))
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
    private func sleepHeartRateColor(_ v: Double) -> Color { v <= 0 ? .duoSubtitle : (v < 40 || v > 100 ? .duoRed : .duoGreen) }
    private func sleepRespiratoryColor(_ v: Double) -> Color { v <= 0 ? .duoSubtitle : (v < 10 || v > 24 ? .duoRed : .duoGreen) }
    private func sleepOxygenColor(_ v: Double) -> Color {
        guard v > 0 else { return .duoSubtitle }
        if v < 90 { return .duoRed }
        if v < 94 { return .duoOrange }
        return .duoGreen
    }

    private func formatMindfulMinutes(_ minutes: Double) -> String {
        if minutes < 1 { return "\(Int(minutes * 60))秒" }
        if abs(minutes.rounded() - minutes) < 0.05 { return "\(Int(minutes.rounded()))分" }
        return String(format: "%.1f分", minutes)
    }
    private func formatMinutes(_ minutes: Int) -> String {
        if minutes <= 0 { return "—" }
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }
    private func formatSleepHours(_ hours: Double) -> String {
        guard hours > 0 else { return "—" }
        return formatMinutes(Int((hours * 60).rounded()))
    }
}

// MARK: - 睡眠スコアリング

private struct SleepScoreRingView: View {
    let sleep: SleepScoreAnalysis
    var size: CGFloat = 52
    private var lineWidth: CGFloat { size * 0.11 }
    private let gap: Double = 0.018
    private let durationColor  = Color(red: 0.44, green: 0.52, blue: 0.90)
    private let bedtimeColor   = Color(red: 0.22, green: 0.80, blue: 0.72)
    private let interruptColor = Color(red: 0.95, green: 0.48, blue: 0.40)

    var body: some View {
        ZStack {
            ZStack {
                Circle().trim(from: 0.0, to: 0.50 - gap)
                    .stroke(durationColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                if sleep.durationScore > 0 {
                    Circle().trim(from: 0.0, to: (0.50 - gap) * min(Double(sleep.durationScore) / 50.0, 1))
                        .stroke(durationColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                Circle().trim(from: 0.50, to: 0.80 - gap)
                    .stroke(bedtimeColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                if sleep.bedtimeScore > 0 {
                    Circle().trim(from: 0.50, to: 0.50 + (0.30 - gap) * min(Double(sleep.bedtimeScore) / 30.0, 1))
                        .stroke(bedtimeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                Circle().trim(from: 0.80, to: 1.00 - gap)
                    .stroke(interruptColor.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                if sleep.interruptionScore > 0 {
                    Circle().trim(from: 0.80, to: 0.80 + (0.20 - gap) * min(Double(sleep.interruptionScore) / 20.0, 1))
                        .stroke(interruptColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            .rotationEffect(.degrees(-30))
            Text("\(sleep.score)")
                .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                .foregroundColor(scoreColor)
        }
        .frame(width: size, height: size)
    }

    private var scoreColor: Color {
        switch sleep.score {
        case 90...: return Color(red: 0.27, green: 0.76, blue: 0.20)
        case 80...: return Color(red: 0.27, green: 0.76, blue: 0.20)
        case 70...: return Color(red: 0.45, green: 0.37, blue: 0.94)
        case 50...: return Color(red: 1.00, green: 0.60, blue: 0.00)
        default:    return Color(red: 0.95, green: 0.25, blue: 0.25)
        }
    }
}

// MARK: - HRV 推移グラフ（今日）

private struct HRVTrendChart: View {
    let samples: [HRVSample]

    private var sorted: [HRVSample] { samples.sorted { $0.date < $1.date } }

    var body: some View {
        let data = sorted
        let values = data.map(\.value)
        let minVal = max(0, (values.min() ?? 0) - 5)
        let maxVal = max((values.max() ?? 80) + 5, minVal + 20, 30)

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
                    let w = geo.size.width, h = geo.size.height
                    let range = max(maxVal - minVal, 1)
                    let startOfDay = Calendar.current.startOfDay(for: Date())
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            let y = h * CGFloat(i) / 3
                            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                                .stroke(Color(.systemGray5), lineWidth: 0.7)
                        }
                        Path { path in
                            for (idx, s) in data.enumerated() {
                                let prog = min(max(s.date.timeIntervalSince(startOfDay) / 86_400, 0), 1)
                                let x = w * CGFloat(prog)
                                let y = h * (1 - CGFloat((s.value - minVal) / range))
                                idx == 0 ? path.move(to: CGPoint(x: x, y: y))
                                         : path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(data) { s in
                            let prog = min(max(s.date.timeIntervalSince(startOfDay) / 86_400, 0), 1)
                            let x = w * CGFloat(prog)
                            let y = h * (1 - CGFloat((s.value - minVal) / range))
                            Circle().fill(Color.white).frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                                .position(x: x, y: y)
                        }
                    }
                }
            }

            HStack {
                Text("0:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00")
            }
            .font(.system(size: 8 * UIScale.font, weight: .bold))
            .foregroundColor(Color.duoSubtitle)
        }
    }
}

// MARK: - 週間 HRV 平均グラフ

private struct WeeklyHRVAverageChart: View {
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "E"; return f
    }()

    let days: [DailyHRVAverage]
    private let lowerLimit = 20.0

    private var sorted: [DailyHRVAverage] { days.sorted { $0.date < $1.date } }
    private var valid: [DailyHRVAverage]  { sorted.filter { $0.value > 0 } }

    var body: some View {
        let data = sorted
        let values = valid.map(\.value)
        let minVal = max(0, min(values.min() ?? lowerLimit, lowerLimit) - 5)
        let maxVal = max(values.max() ?? 60, lowerLimit + 10, minVal + 20)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("過去7日のHRV平均")
                        .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(Color.duoDark)
                    Text("赤ラインはストレス高めの目安 20ms")
                        .font(.system(size: 8 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                if let latest = valid.last {
                    Text("\(Int(latest.value)) ms")
                        .font(.system(size: 12 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(latest.value < lowerLimit ? Color(hex: "#FF4B4B") : Color.duoGreen)
                }
            }

            if valid.count < 2 {
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
                    let w = geo.size.width, h = geo.size.height
                    let range = max(maxVal - minVal, 1)
                    let xStep = data.count > 1 ? w / CGFloat(data.count - 1) : 0
                    let limitY = h * (1 - CGFloat((lowerLimit - minVal) / range))

                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            let y = h * CGFloat(i) / 3
                            Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                                .stroke(Color(.systemGray5), lineWidth: 0.7)
                        }
                        Path { p in p.move(to: CGPoint(x: 0, y: limitY)); p.addLine(to: CGPoint(x: w, y: limitY)) }
                            .stroke(Color(hex: "#FF4B4B"), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                        Text("20ms")
                            .font(.system(size: 8 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#FF4B4B"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.white.opacity(0.9)).clipShape(Capsule())
                            .position(x: w - 22, y: max(10, limitY - 10))
                        Path { path in
                            var started = false
                            for (idx, day) in data.enumerated() where day.value > 0 {
                                let x = CGFloat(idx) * xStep
                                let y = h * (1 - CGFloat((day.value - minVal) / range))
                                if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.duoGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.element.id) { idx, day in
                            if day.value > 0 {
                                let x = CGFloat(idx) * xStep
                                let y = h * (1 - CGFloat((day.value - minVal) / range))
                                Circle().fill(Color.white).frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(
                                        day.value < lowerLimit ? Color(hex: "#FF4B4B") : Color.duoGreen,
                                        lineWidth: 2))
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
            }

            HStack {
                ForEach(data) { day in
                    Text(WeeklyHRVAverageChart.dayFmt.string(from: day.date))
                        .font(.system(size: 8 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - HRV ヘルプ

private struct HRVStressHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    helpSection(title: "HRVとは",
                        text: "HRV（心拍変動）は、心拍と心拍の間隔のゆらぎです。HRVが高いほど回復力やリラックス状態が高く、低いほど疲労・緊張・ストレスが出やすい状態と考えます。")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("判定基準").font(.headline.weight(.black)).foregroundColor(Color.duoDark)
                        thresholdRow("低い / Low",      detail: "HRV 60ms以上",  color: Color.duoGreen)
                        thresholdRow("普通 / Normal",   detail: "HRV 40〜59ms",  color: Color(red: 0.4, green: 0.75, blue: 0.1))
                        thresholdRow("やや高 / Elevated",detail: "HRV 20〜39ms", color: Color.duoOrange)
                        thresholdRow("高い / High",     detail: "HRV 20ms未満",  color: Color(hex: "#FF4B4B"))
                    }
                    .padding(14).background(Color(.systemBackground)).cornerRadius(16)
                    helpSection(title: "見方のポイント",
                        text: "HRVは個人差が大きいため、1回の数値だけで判断せず、自分の普段の平均からの変化を見るのが大切です。")
                }
                .padding(16)
            }
            .background(Color.duoBg.ignoresSafeArea())
            .navigationTitle("HRVとストレス").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }.foregroundColor(Color.duoGreen)
                }
            }
        }
    }
    private func helpSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline.weight(.black)).foregroundColor(Color.duoDark)
            Text(text).font(.system(size: 13 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).background(Color(.systemBackground)).cornerRadius(16)
    }
    private func thresholdRow(_ label: String, detail: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 13 * UIScale.font, weight: .black)).foregroundColor(color)
            Spacer()
            Text(detail).font(.system(size: 12 * UIScale.font, weight: .bold)).foregroundColor(Color.duoSubtitle)
        }
    }
}

// MARK: - 瞑想タイマー（フルスクリーン）

private struct TimedMeditationView: View {
    let durationSeconds: Int
    let title: String
    let sessionType: String
    let onComplete: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var timeLeft: Int
    @State private var startDate: Date? = nil
    @State private var timer: Timer? = nil
    @State private var isRunning = false
    @State private var isFinished = false

    init(durationSeconds: Int, title: String, sessionType: String, onComplete: @escaping (Date, Date) -> Void) {
        self.durationSeconds = durationSeconds
        self.title = title
        self.sessionType = sessionType
        self.onComplete = onComplete
        _timeLeft = State(initialValue: durationSeconds)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#6D5DF6"), Color(hex: "#1CB0F6")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                Text(title).font(.largeTitle.bold()).foregroundStyle(.white)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 12)
                        .frame(width: 200, height: 200)
                    Circle()
                        .trim(from: 0, to: isFinished ? 1 : CGFloat(durationSeconds - timeLeft) / CGFloat(durationSeconds))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timeLeft)
                    Text(timeString)
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                if isFinished {
                    Label("完了！HealthKitに保存しました", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.headline)
                } else {
                    Button {
                        if isRunning { stopTimer() } else { startTimer() }
                    } label: {
                        Text(isRunning ? "一時停止" : (startDate == nil ? "開始" : "再開"))
                            .font(.headline)
                            .foregroundStyle(Color(hex: "#6D5DF6"))
                            .padding(.horizontal, 40).padding(.vertical, 14)
                            .background(Color.white, in: Capsule())
                    }
                }

                Button { dismiss() } label: {
                    Text("閉じる").foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private var timeString: String {
        let m = timeLeft / 60, s = timeLeft % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startTimer() {
        if startDate == nil { startDate = Date() }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            } else {
                stopTimer()
                isFinished = true
                if let start = startDate {
                    onComplete(start, Date())
                }
            }
        }
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Private Models

private struct MindStressInfo {
    let score: Int
    let label: String
    let englishLabel: String
    let color: Color
}

private struct MindRecommendation: Identifiable {
    let id = UUID()
    let prefix: String
    let text: String
    let color: Color
    var actionType: String? = nil
}

#Preview {
    MindView(selectedTab: .constant(0), showRecordMenu: .constant(false))
        .environmentObject(HealthKitManager.shared)
        .environmentObject(PlusManager.shared)
}
