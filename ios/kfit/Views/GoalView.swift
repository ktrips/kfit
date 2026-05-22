import SwiftUI

struct GoalView: View {
    @Binding var selectedTab: Int
    @StateObject private var healthKit   = HealthKitManager.shared
    @StateObject private var dietManager = DietGoalManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showDietGoalSettings = false
    @State private var showCharts = false
    @State private var weeklySetCounts: [String: Int] = [:]
    @State private var weeklyIntakeData: [String: [String: Int]] = [:]

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        goalHeader
                        goalHeroCard
                        if showCharts {
                            weightChartCard
                                .transition(.opacity)
                            bodyFatChartCard
                                .transition(.opacity)
                        }
                        progressCard
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.doc.horizontal.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.duoGreen)
                            Text("週間実績")
                                .font(.system(size: 13, weight: .black))
                                .foregroundColor(Color.duoDark)
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, -4)
                        weeklyBurnCard
                        intakeTrendCard
                        weeklyCalorieCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showDietGoalSettings) {
                NavigationView { DietGoalSettingsView() }
            }
            .task {
                await healthKit.fetchBodyMassHistory(days: 30)
                await healthKit.fetchBodyFatHistory(days: 30)
                if healthKit.weeklyCalorieData.isEmpty {
                    await healthKit.fetchAll()
                }
                await healthKit.fetchWeeklyBurnData()
                await healthKit.fetchWeeklyDietarySamples()
                weeklySetCounts = await authManager.fetchWeeklySetCounts()
                weeklyIntakeData = await authManager.fetchWeeklyIntakeData()
            }
        }
    }

    // MARK: - Fitingoヘッダー（ホームページと同じデザイン）

    private var goalHeader: some View {
        let goal    = dietManager.settings
        let current = healthKit.latestBodyMass

        let weightChange = (goal.startWeight > 0 && current > 0) ? current - goal.startWeight : nil
        let remaining    = (goal.targetWeight > 0 && current > 0) ? current - goal.targetWeight : nil
        let daysLeft     = goal.hasStartStats
            ? max(0, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
            : nil

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ja_JP")
        dateFmt.dateFormat = "M/d(E)"
        let dateStr = dateFmt.string(from: Date())

        return ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack(spacing: 4) {
                // 左側: ロゴ
                HStack(spacing: 2) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.4))
                    HStack(spacing: 0) {
                        Text("Fit")
                            .foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                        Text("ingo")
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    Text(dateStr)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.leading, 8)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // 右側: 体重変化 / 残り削減分
                if goal.targetWeight > 0 && current > 0 {
                    HStack(spacing: 2) {
                        if let change = weightChange {
                            Text(String(format: "%+.1f", change))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Text("/")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.6))
                        if let rem = remaining {
                            Text(String(format: "%.1fkg残", rem))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }

                // 一番右: 残り日数
                if let days = daysLeft {
                    let daysColor: Color = days <= 7 ? Color(hex: "#FF4B4B") : days <= 30 ? Color(hex: "#FFCC00") : .white
                    Text("\(days)日")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundColor(daysColor)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(7)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .cornerRadius(12)
    }

    // MARK: - ヒーローカード（現状 vs 目標）

    private var goalHeroCard: some View {
        let goal       = dietManager.settings
        let current    = healthKit.latestBodyMass
        let currentFat = healthKit.latestBodyFatPercentage
        let weightDiff = (current > 0 && goal.targetWeight > 0) ? current - goal.targetWeight : nil
        let cal        = Calendar.current

        // 体重達成度（スタート体重設定時はそこからの進捗、未設定時は現在と目標の差から推定）
        let weightProgress: Double = {
            if goal.hasStartStats && goal.startWeight > 0 && goal.targetWeight > 0 && current > 0 {
                let total = goal.startWeight - goal.targetWeight
                guard total != 0 else { return 1 }
                return min(1, max(0, (goal.startWeight - current) / total))
            }
            guard let diff = weightDiff, current > 0, goal.targetWeight > 0 else { return 0 }
            let sw = max(current, goal.targetWeight + diff)
            let tc = sw - goal.targetWeight
            guard tc > 0 else { return 1 }
            return min(1, max(0, (sw - current) / tc))
        }()

        // 期間進捗（スタート日〜目標日）
        let totalDays: Int = goal.hasStartStats
            ? max(0, cal.dateComponents([.day],
                from: cal.startOfDay(for: goal.startDate),
                to:   cal.startOfDay(for: goal.targetDate)).day ?? 0) : 0
        let elapsedDays: Int = goal.hasStartStats
            ? max(0, cal.dateComponents([.day],
                from: cal.startOfDay(for: goal.startDate),
                to:   cal.startOfDay(for: Date())).day ?? 0) : 0
        let timeProgress: Double = totalDays > 0 ? min(1, Double(elapsedDays) / Double(totalDays)) : 0
        let daysRemaining = max(0, cal.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)

        // バナー用データ
        let dateFmtB = DateFormatter(); dateFmtB.dateFormat = "yyyy-MM-dd"
        let todayKeyB = dateFmtB.string(from: Date())
        let weeklySetTotal = weeklySetCounts.values.reduce(0, +)
        let todayHKDay = healthKit.weeklyCalorieData.first { dateFmtB.string(from: $0.date) == todayKeyB }
        let todayBalance = todayHKDay.map { Int($0.consumed) - Int($0.burned) } ?? 0
        let hasIntakeThisWeek = weeklyIntakeData.values.contains { $0.values.contains { $0 > 0 } }
        let todayBurnDay = healthKit.weeklyBurnData.first { dateFmtB.string(from: $0.date) == todayKeyB }
        let todaySteps = todayBurnDay?.steps ?? 0
        let todayActiveCalories = todayBurnDay?.activeCalories ?? 0.0
        let todaySetCount = weeklySetCounts[todayKeyB] ?? 0

        return VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            if goal.hasStartStats {
                GoalTimelineStrip(
                    startWeight: goal.startWeight > 0 ? formatCompactKg(goal.startWeight) : "—",
                    startBodyFat: goal.startBodyFatPercent > 0 ? formatCompactPercent(goal.startBodyFatPercent) : nil,
                    currentWeight: current > 0 ? formatCompactKg(current) : "—",
                    currentBodyFat: currentFat > 0 ? formatCompactPercent(currentFat) : nil,
                    goalWeight: goal.targetWeight > 0 ? formatCompactKg(goal.targetWeight) : "—",
                    goalBodyFat: goal.hasBodyFatTarget && goal.targetBodyFatPercent > 0
                        ? formatCompactPercent(goal.targetBodyFatPercent) : nil,
                    startToCurrentDelta: goal.startWeight > 0 && current > 0
                        ? formatSignedDelta(current - goal.startWeight) : nil,
                    currentToGoalDelta: current > 0 && goal.targetWeight > 0
                        ? formatSignedDelta(goal.targetWeight - current) : nil,
                    timeProgress: timeProgress,
                    daysRemaining: daysRemaining,
                    startDate: goal.startDate,
                    targetDate: goal.targetDate
                )
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            if goal.targetWeight > 0 && current > 0 {
                GoalMotivatingBanner(
                    weightProgress: weightProgress,
                    timeProgress: timeProgress,
                    daysRemaining: daysRemaining,
                    weeklySetTotal: weeklySetTotal,
                    todayBalance: todayBalance,
                    hasIntakeThisWeek: hasIntakeThisWeek,
                    todaySteps: todaySteps,
                    todayActiveCalories: todayActiveCalories,
                    todaySetCount: todaySetCount,
                    onAction: { action in
                        switch action {
                        case "training":
                            selectedTab = 0
                            iOSWatchBridge.shared.sendStartWorkoutSignal()
                        case "intake":
                            selectedTab = 3
                        default: break
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // グラフ展開ボタン + 設定アイコン（右下）
            Divider()
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { showCharts.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.duoGreen)
                        Text(showCharts ? "グラフを閉じる" : "体重・体脂肪グラフを表示")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                        Spacer()
                        Image(systemName: showCharts ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.duoGreen.opacity(0.7))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showDietGoalSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.duoGreen)
                        .padding(8)
                        .background(Color.duoGreen.opacity(0.1))
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 8, y: 3)
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy/M/d"
        return fmt.string(from: date)
    }

    private func formatCompactKg(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))kg" : String(format: "%.1fkg", value)
    }

    private func formatCompactPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func formatSignedDelta(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }

    private func metricColumn(label: String, weightVal: String, fatVal: String?, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundColor(Color.duoSubtitle)
            Text(weightVal)
                .font(.system(size: 36, weight: .black))
                .foregroundColor(color)
            Text("kg")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .offset(y: -6)
            if let fat = fatVal {
                Text(fat + "%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func daysRemainingBadge(goal: DietGoalSettings) -> some View {
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 0)
        let color: Color = days > 30 ? Color(hex: "#1CB0F6") : days > 7 ? Color(hex: "#FF9600") : Color(hex: "#FF4B4B")
        return VStack(spacing: 1) {
            Text("\(days)")
                .font(.system(size: 17, weight: .black))
                .foregroundColor(color)
            Text("日後")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.1))
        .cornerRadius(9)
    }

    // MARK: - 進捗カード

    private var progressCard: some View {
        let goal    = dietManager.settings
        let deficit = goal.dailyDeficitGoal
        let days    = max(1, Calendar.current.dateComponents([.day], from: Date(), to: goal.targetDate).day ?? 1)
        let deficitColor: Color = deficit < 0 ? Color.duoGreen : Color(hex: "#FF4B4B")
        let weeklyChange     = Double(deficit * 7)  / 7700.0
        let monthlyChange    = Double(deficit * 30) / 7700.0
        let threeMonthChange = Double(deficit * 90) / 7700.0
        let goalDateChange   = Double(deficit * days) / 7700.0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("📋").font(.title3)
                Text("目標プラン").font(.headline.weight(.black)).foregroundColor(Color.duoDark)
            }

            // Row 1: 基本指標
            HStack(spacing: 0) {
                planItem(icon: "🔥", label: "1日収支目標",
                         value: (deficit >= 0 ? "+" : "") + "\(deficit)",
                         unit: "kcal",
                         color: deficitColor)
                Divider().frame(height: 44)
                planItem(icon: "📅", label: "残り日数",
                         value: "\(days)",
                         unit: "日",
                         color: Color(hex: "#1CB0F6"))
                Divider().frame(height: 44)
                planItem(icon: "⚖️", label: "週体重変化",
                         value: String(format: "%.2f", weeklyChange),
                         unit: "kg/週",
                         color: deficitColor)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Row 2: 期間別体重変化予測
            HStack(spacing: 0) {
                planItem(icon: "📆", label: "月体重変化",
                         value: String(format: "%.1f", monthlyChange),
                         unit: "kg/月",
                         color: deficitColor)
                Divider().frame(height: 44)
                planItem(icon: "🗓️", label: "3ヶ月後変化",
                         value: String(format: "%.1f", threeMonthChange),
                         unit: "kg",
                         color: deficitColor)
                Divider().frame(height: 44)
                planItem(icon: "🎯", label: "目標日変化",
                         value: String(format: "%.1f", goalDateChange),
                         unit: "kg",
                         color: deficitColor)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func planItem(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(icon).font(.title3)
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
            Text(label)
                .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 週間消費カロリーカード

    private var weeklyBurnCard: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var data = healthKit.weeklyBurnData
        for i in data.indices {
            let key = formatter.string(from: data[i].date)
            data[i].setCount = weeklySetCounts[key] ?? 0
        }
        return GoalWeeklyBurnCard(data: data)
    }

    // MARK: - 摂取カロリートレンドカード

    private var intakeTrendCard: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = Date()
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) ?? today

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "ja_JP")
        dayFmt.dateFormat = "E"

        // HealthKit サンプルを日付キーでグルーピング
        var samplesByKey: [String: [DietarySample]] = [:]
        for sample in healthKit.weeklyDietarySamples {
            let key = dateFmt.string(from: sample.startDate)
            samplesByKey[key, default: []].append(sample)
        }

        // 水分は Firestore から
        let days: [GoalIntakeDayData] = (0..<7).compactMap { i in
            guard let dayStart = cal.date(byAdding: .day, value: i, to: weekStart) else { return nil }
            let key = dateFmt.string(from: dayStart)
            let intake = weeklyIntakeData[key] ?? [:]
            return GoalIntakeDayData(
                date: dayStart,
                dayLabel: dayFmt.string(from: dayStart),
                samples: samplesByKey[key] ?? [],
                waterMl: intake["waterMl"] ?? 0
            )
        }
        return GoalIntakeTrendCard(days: days)
    }

    // MARK: - 週間カロリー収支カード

    private var weeklyCalorieCard: some View {
        let settings = dietManager.settings
        // Apple Health トグル OFF の場合は目標値で差し替え
        let adjustedData: [DailyCalorieBalance] = healthKit.weeklyCalorieData.map { day in
            let intake = settings.useHealthKitForIntake ? day.consumed : Double(settings.dailyIntakeGoal)
            let burn   = settings.useHealthKitForBurn   ? day.burned   : Double(settings.dailyBurnGoal)
            var d = DailyCalorieBalance(date: day.date, burned: burn, consumed: intake)
            d.bodyMass = day.bodyMass
            d.bodyFatPercentage = day.bodyFatPercentage
            d.steps = day.steps
            return d
        }
        return GoalWeeklyCalorieCard(
            data: adjustedData,
            dailyGoal: settings.dailyDeficitGoal
        )
    }

    // MARK: - 体重グラフ

    private var weightChartCard: some View {
        let records = healthKit.bodyMassHistory
            .sorted { $0.measuredAt < $1.measuredAt }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("⚖️").font(.title3)
                Text("体重 推移（直近30日）")
                    .font(.headline.weight(.black)).foregroundColor(Color.duoDark)
                Spacer()
                if let latest = records.last {
                    Text(String(format: "%.1f kg", latest.kg))
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                }
            }

            if records.count >= 2 {
                LineChartView(
                    points: records.map { CGFloat($0.kg) },
                    lineColor: Color(hex: "#1CB0F6"),
                    goalLine: dietManager.settings.targetWeight > 0
                        ? CGFloat(dietManager.settings.targetWeight) : nil,
                    goalColor: Color.duoGreen,
                    labels: chartDateLabels(records.map { $0.measuredAt }),
                    unit: "kg"
                )
                .frame(height: 140)
            } else {
                emptyChartPlaceholder(message: "体重データが2件以上記録されると表示されます")
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - 体脂肪グラフ

    private var bodyFatChartCard: some View {
        let records = healthKit.bodyFatHistory

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("📉").font(.title3)
                Text("体脂肪率 推移（直近30日）")
                    .font(.headline.weight(.black)).foregroundColor(Color.duoDark)
                Spacer()
                if let latest = records.last {
                    Text(String(format: "%.1f%%", latest.percent))
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(Color(hex: "#CE82FF"))
                }
            }

            if records.count >= 2 {
                let goal = dietManager.settings
                LineChartView(
                    points: records.map { CGFloat($0.percent) },
                    lineColor: Color(hex: "#CE82FF"),
                    goalLine: goal.hasBodyFatTarget && goal.targetBodyFatPercent > 0
                        ? CGFloat(goal.targetBodyFatPercent) : nil,
                    goalColor: Color.duoGreen,
                    labels: chartDateLabels(records.map { $0.measuredAt }),
                    unit: "%"
                )
                .frame(height: 140)
            } else {
                emptyChartPlaceholder(message: "体脂肪率データが2件以上記録されると表示されます")
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundColor(Color(.systemGray4))
                Text(message)
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(height: 100)
    }

    private func chartDateLabels(_ dates: [Date]) -> [String] {
        guard !dates.isEmpty else { return [] }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "M/d"
        let step = max(1, dates.count / 4)
        return dates.enumerated().map { i, d in
            (i % step == 0 || i == dates.count - 1) ? fmt.string(from: d) : ""
        }
    }
}

// MARK: - 週間カロリー収支バー（日別）

private struct GoalWeeklyDayBarView: View {
    let day: DailyCalorieBalance
    let maxAbs: Int
    let halfBarH: CGFloat

    var body: some View {
        let bal = day.balance
        let barH = maxAbs > 0 ? max(CGFloat(bal != 0 ? 2 : 0), halfBarH * CGFloat(abs(bal)) / CGFloat(maxAbs)) : 0

        VStack(spacing: 2) {
            Text(bal != 0 ? (bal >= 0 ? "+" : "") + "\(bal)" : "")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(bal <= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 10)

            // 上半分：消費オーバー（赤字）→ 緑
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: halfBarH)
                if bal < 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.duoGreen.opacity(0.85))
                        .frame(height: min(barH, halfBarH))
                }
            }

            // 中心線
            Rectangle()
                .fill(Color(.systemGray3))
                .frame(height: 0.5)

            // 下半分：摂取オーバー → 赤
            ZStack(alignment: .top) {
                Color.clear.frame(height: halfBarH)
                if bal > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#FF4B4B").opacity(0.75))
                        .frame(height: min(barH, halfBarH))
                }
            }

            Text(day.dayLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)

            if let mass = day.bodyMass {
                Text(String(format: "%.1f", mass))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 7))
                    .foregroundColor(Color(.systemGray4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 週間カロリー収支カード

private struct GoalWeeklyCalorieCard: View {
    let data: [DailyCalorieBalance]
    var dailyGoal: Int = -150

    private let halfBarH: CGFloat = 32
    private var weeklyGoal: Int { dailyGoal * 7 }

    private func statusBadge(weekTotal: Int) -> (label: String, color: Color) {
        let today = Calendar.current.startOfDay(for: Date())
        let daysElapsed = max(1, data.filter { Calendar.current.startOfDay(for: $0.date) <= today }.count)
        let expected = daysElapsed * dailyGoal
        if weekTotal <= weeklyGoal       { return ("🎉 達成！", Color.duoGreen) }
        if weekTotal <= expected         { return ("👍 順調", Color(hex: "#1CB0F6")) }
        if weekTotal < expected / 2      { return ("⚠️ 注意", Color(hex: "#FF9600")) }
        return ("🚨 要注意", Color(hex: "#FF4B4B"))
    }

    var body: some View {
        let weekTotal = data.reduce(0) { $0 + $1.balance }
        let weightImpactKg = Double(weekTotal) / 7700.0
        let maxAbs = max(data.map { abs($0.balance) }.max() ?? 0, 300)
        let badge = statusBadge(weekTotal: weekTotal)

        let todayStart = Calendar.current.startOfDay(for: Date())
        let daysElapsed = max(1, data.filter { Calendar.current.startOfDay(for: $0.date) <= todayStart }.count)
        let dailyAvg = weekTotal / daysElapsed

        let mondayMass = data.first?.bodyMass
        let latestMass = data.last(where: { $0.bodyMass != nil })?.bodyMass
        let massDiff: Double? = (mondayMass != nil && latestMass != nil) ? latestMass! - mondayMass! : nil
        let diffColor: Color = (massDiff ?? 0) < 0 ? Color.duoGreen
            : (massDiff ?? 0) > 0 ? Color(hex: "#FF4B4B")
            : Color.duoSubtitle
        let balanceColor: Color = weekTotal > 0 ? Color(hex: "#FF4B4B") : Color.duoGreen

        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#FF9600"), Color(hex: "#FFCC00")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                // タイトル行
                HStack(spacing: 6) {
                    Text("⚖️")
                        .font(.system(size: 15))
                    HStack(spacing: 5) {
                        Text("カロリー収支")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Text(badge.label)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color)
                            .cornerRadius(6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text("平均 " + (dailyAvg >= 0 ? "+" : "") + "\(dailyAvg)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.duoSubtitle)
                            Text("/")
                                .font(.system(size: 9))
                                .foregroundColor(Color.duoSubtitle)
                            Text("計 " + (weekTotal >= 0 ? "+" : "") + "\(weekTotal)")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(balanceColor)
                        }
                        Text("kcal")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }

                if data.isEmpty {
                    Text("今週のカロリーデータを読み込み中...")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(data) { day in
                            GoalWeeklyDayBarView(day: day, maxAbs: maxAbs, halfBarH: halfBarH)
                        }
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.duoGreen.opacity(0.85)).frame(width: 10, height: 4)
                            Text("消費超過").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1).fill(Color(hex: "#FF4B4B").opacity(0.75)).frame(width: 10, height: 4)
                            Text("摂取超過").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        // 右下: 推定変化 / 実変化kg
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("推定変化(" + (weightImpactKg >= 0 ? "+" : "") + String(format: "%.1f", weightImpactKg) + "kg)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(balanceColor)
                            if let diff = massDiff {
                                Text("/")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("実" + (diff >= 0 ? "+" : "") + String(format: "%.1f", diff) + "kg")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(diffColor)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Line Chart View

private struct LineChartView: View {
    let points: [CGFloat]
    let lineColor: Color
    var goalLine: CGFloat? = nil
    var goalColor: Color = Color.duoGreen
    var labels: [String] = []
    var unit: String = ""

    var body: some View {
        let minVal = (points.min() ?? 0)
        let maxVal = (points.max() ?? 1)
        let dataRange = max(maxVal - minVal, 0.5)

        let effectiveMin: CGFloat = {
            if let g = goalLine { return min(minVal, g) - dataRange * 0.1 }
            return minVal - dataRange * 0.15
        }()
        let effectiveMax: CGFloat = {
            if let g = goalLine { return max(maxVal, g) + dataRange * 0.1 }
            return maxVal + dataRange * 0.15
        }()
        let totalRange = max(effectiveMax - effectiveMin, 0.1)

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Grid lines
                    ForEach(0..<4) { i in
                        let y = h * CGFloat(i) / 3
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                    }

                    // Goal line (dashed green)
                    if let goal = goalLine {
                        let gy = h * (1 - (goal - effectiveMin) / totalRange)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: gy))
                            p.addLine(to: CGPoint(x: w, y: gy))
                        }
                        .stroke(goalColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))

                        Text(unit == "%" ? String(format: "%.1f%%", Float(goal)) : String(format: "%.1f", Float(goal)))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(goalColor)
                            .position(x: w - 22, y: max(10, min(h - 10, gy - 8)))
                    }

                    // Fill area
                    Path { p in
                        guard points.count > 1 else { return }
                        let step = w / CGFloat(points.count - 1)
                        let startY = h * (1 - (points[0] - effectiveMin) / totalRange)
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: CGPoint(x: 0, y: startY))
                        for i in 1..<points.count {
                            let x = step * CGFloat(i)
                            let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(lineColor.opacity(0.12))

                    // Line
                    Path { p in
                        guard points.count > 1 else { return }
                        let step = w / CGFloat(points.count - 1)
                        p.move(to: CGPoint(
                            x: 0,
                            y: h * (1 - (points[0] - effectiveMin) / totalRange)
                        ))
                        for i in 1..<points.count {
                            let x = step * CGFloat(i)
                            let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Dots
                    ForEach(0..<points.count, id: \.self) { i in
                        let step = w / CGFloat(max(points.count - 1, 1))
                        let x = step * CGFloat(i)
                        let y = h * (1 - (points[i] - effectiveMin) / totalRange)
                        Circle()
                            .fill(lineColor)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }

                    // Min/Max labels
                    VStack {
                        Text(String(format: "%.1f", Float(effectiveMax)))
                            .font(.system(size: 8)).foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text(String(format: "%.1f", Float(effectiveMin)))
                            .font(.system(size: 8)).foregroundColor(Color.duoSubtitle)
                    }
                    .frame(width: w, height: h, alignment: .trailing)
                    .padding(.trailing, 2)
                }
            }

            // X-axis labels
            if !labels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(0..<labels.count, id: \.self) { i in
                        Text(labels[i])
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - 週間消費カロリーカード（安静時・活動積み上げ棒グラフ）

private struct GoalWeeklyBurnCard: View {
    let data: [DailyBurnSummary]

    private let restingColor = Color(hex: "#16A34A")
    private let activeColor  = Color(hex: "#4ADE80")

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pastData = data.filter { Calendar.current.startOfDay(for: $0.date) < todayStart }
        let maxTotal = max(data.map { $0.totalCalories }.max() ?? 1, 1)
        let weekTotal = Int(data.reduce(0) { $0 + $1.totalCalories })
        let avgBurn: Int? = pastData.isEmpty ? nil : Int(pastData.reduce(0) { $0 + $1.totalCalories } / Double(pastData.count))

        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#16A34A"), Color(hex: "#4ADE80")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("🔥")
                        .font(.system(size: 15))
                    Text("燃やしたカロリー")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if let avg = avgBurn, weekTotal > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text("平均 \(avg)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("/")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("計 \(weekTotal)")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(Color(hex: "#16A34A"))
                            }
                            Text("kcal")
                                .font(.system(size: 8))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                }

                // 凡例
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(restingColor).frame(width: 10, height: 8)
                        Text("安静時").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(activeColor).frame(width: 10, height: 8)
                        Text("活動").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                }

                if data.isEmpty {
                    Text("データを読み込み中...")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(data) { day in
                            GoalBurnDayColumn(
                                day: day,
                                maxTotal: maxTotal,
                                restingColor: restingColor,
                                activeColor: activeColor
                            )
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct GoalBurnDayColumn: View {
    let day: DailyBurnSummary
    let maxTotal: Double
    let restingColor: Color
    let activeColor: Color

    private let maxBarH: CGFloat = 56

    var body: some View {
        let totalH = maxTotal > 0 ? maxBarH * CGFloat(day.totalCalories) / CGFloat(maxTotal) : 0
        let restH  = day.totalCalories > 0 ? totalH * CGFloat(day.restingCalories) / CGFloat(day.totalCalories) : 0
        let actH   = totalH - restH

        VStack(spacing: 3) {
            // カロリーラベル
            Text(day.totalCalories > 0 ? "\(Int(day.totalCalories))" : "")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 10)

            // 積み上げ棒（下：安静時、上：活動）
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activeColor)
                        .frame(height: max(actH, day.activeCalories > 0 ? 2 : 0))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(restingColor)
                        .frame(height: max(restH, day.restingCalories > 0 ? 2 : 0))
                }
            }
            .frame(height: maxBarH)

            // 曜日
            Text(day.dayLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)

            // セット数
            HStack(spacing: 2) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 7))
                    .foregroundColor(day.setCount > 0 ? Color.duoGreen : Color(.systemGray4))
                Text(day.setCount > 0 ? "\(day.setCount)" : "-")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(day.setCount > 0 ? Color.duoGreen : Color(.systemGray4))
            }

            // 有酸素時間
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 7))
                    .foregroundColor(day.exerciseMinutes > 0 ? Color(hex: "#1CB0F6") : Color(.systemGray4))
                Text(day.exerciseMinutes > 0 ? "\(Int(day.exerciseMinutes))m" : "-")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(day.exerciseMinutes > 0 ? Color(hex: "#1CB0F6") : Color(.systemGray4))
            }

            // 歩数
            HStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 7))
                    .foregroundColor(day.steps > 0 ? Color(hex: "#FF9600") : Color(.systemGray4))
                Text(day.steps > 0
                    ? (day.steps >= 1000 ? String(format: "%.1fk", Double(day.steps) / 1000.0) : "\(day.steps)")
                    : "-")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(day.steps > 0 ? Color(hex: "#FF9600") : Color(.systemGray4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 摂取カロリートレンド データ

private struct GoalIntakeDayData: Identifiable {
    let id = UUID()
    let date: Date
    let dayLabel: String
    var samples: [DietarySample] = []   // HealthKit 摂取サンプル（時刻順）
    var waterMl: Int = 0
    var totalCal: Int { samples.reduce(0) { $0 + Int($1.value) } }
}

// MARK: - 摂取カロリートレンドカード

private struct GoalIntakeTrendCard: View {
    let days: [GoalIntakeDayData]

    // 時間帯別カラー（ポップカラー）
    static func timeColor(hour: Int) -> Color {
        switch hour {
        case 0..<6:   return Color(hex: "#A78BFA")  // ラベンダー（深夜）
        case 6..<10:  return Color(hex: "#FF9600")  // オレンジ（朝）
        case 10..<13: return Color(hex: "#FFCC00")  // イエロー（昼前）
        case 13..<17: return Color(hex: "#58CC02")  // グリーン（昼後）
        case 17..<21: return Color(hex: "#1CB0F6")  // ブルー（夕）
        default:      return Color(hex: "#CE82FF")  // パープル（夜）
        }
    }

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let pastDays = days.filter { Calendar.current.startOfDay(for: $0.date) < todayStart }
        let maxCal = max(days.map { Double($0.totalCal) }.max() ?? 1, 1)
        let hasData = days.contains { $0.totalCal > 0 || $0.waterMl > 0 }
        let weekTotal = days.reduce(0) { $0 + $1.totalCal }
        let pastWithData = pastDays.filter { $0.totalCal > 0 }
        let avgIntake: Int? = pastWithData.isEmpty ? nil : Int(pastWithData.reduce(0) { $0 + $1.totalCal } / pastWithData.count)

        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#FF4B4B"), Color(hex: "#FF9600")],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("🍽️")
                        .font(.system(size: 15))
                    Text("食事カロリー")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if let avg = avgIntake, weekTotal > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text("平均 \(avg)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("/")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.duoSubtitle)
                                Text("計 \(weekTotal)")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(Color(hex: "#FF4B4B"))
                            }
                            Text("kcal")
                                .font(.system(size: 8))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                }

                // 時間帯カラー凡例
                HStack(spacing: 8) {
                    ForEach([
                        (6, "朝"), (10, "昼前"), (13, "昼後"), (17, "夕"), (21, "夜")
                    ], id: \.0) { hour, label in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GoalIntakeTrendCard.timeColor(hour: hour))
                                .frame(width: 10, height: 8)
                            Text(label)
                                .font(.system(size: 8))
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                    Spacer()
                }

                if days.isEmpty {
                    Text("データを読み込み中...")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(days) { day in
                            GoalIntakeDayColumn(day: day, maxCal: maxCal)
                        }
                    }
                    if !hasData {
                        Text("今週の食事記録がありません（Apple Health に記録すると表示されます）")
                            .font(.system(size: 9))
                            .foregroundColor(Color.duoSubtitle)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct GoalIntakeDayColumn: View {
    let day: GoalIntakeDayData
    let maxCal: Double

    private let maxBarH: CGFloat = 60
    private let cal = Calendar.current

    var body: some View {
        let totalCal = day.totalCal
        let totalH = maxCal > 0 ? maxBarH * CGFloat(totalCal) / CGFloat(maxCal) : 0

        VStack(spacing: 3) {
            Text(totalCal > 0 ? "\(totalCal)" : "")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color.duoDark)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 10)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if day.samples.isEmpty {
                    Color.clear
                } else {
                    // 各サンプルを時間帯色で積み上げ（下＝早朝、上＝深夜）
                    let sorted = day.samples.sorted { $0.startDate < $1.startDate }
                    let totalKcal = Double(max(totalCal, 1))
                    VStack(spacing: 1) {
                        ForEach(sorted.reversed()) { sample in
                            let h = totalH * CGFloat(sample.value) / CGFloat(totalKcal)
                            let hour = cal.component(.hour, from: sample.startDate)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GoalIntakeTrendCard.timeColor(hour: hour))
                                .frame(height: max(h, h > 0 ? 2 : 0))
                        }
                    }
                }
            }
            .frame(height: maxBarH)

            Text(day.dayLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)

            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 7))
                    .foregroundColor(day.waterMl > 0 ? Color(hex: "#1CB0F6") : Color(.systemGray4))
                Text(day.waterMl > 0
                    ? (day.waterMl >= 1000
                        ? String(format: "%.1fL", Double(day.waterMl) / 1000.0)
                        : "\(day.waterMl)ml")
                    : "-")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(day.waterMl > 0 ? Color(hex: "#1CB0F6") : Color(.systemGray4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - タイムラインストリップ

private struct GoalTimelineStrip: View {
    let startWeight: String
    let startBodyFat: String?
    let currentWeight: String
    let currentBodyFat: String?
    let goalWeight: String
    let goalBodyFat: String?
    let startToCurrentDelta: String?
    let currentToGoalDelta: String?
    let timeProgress: Double
    let daysRemaining: Int
    var startDate: Date? = nil
    var targetDate: Date? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private var daysColor: Color {
        if daysRemaining <= 7 { return Color(hex: "#FF4B4B") }
        if daysRemaining <= 30 { return Color(hex: "#FF9600") }
        return Color(hex: "#1CB0F6")
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let rawX = w * CGFloat(max(0, min(1, timeProgress)))
                let dotX = max(6, min(w - 6, rawX))

                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(width: w, height: 5)
                        .position(x: w / 2, y: h / 2)

                    if rawX > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#1A7A3F"), Color(hex: "#58CC02")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: dotX, height: 5)
                            .position(x: dotX / 2, y: h / 2)
                    }

                    Circle()
                        .fill(Color(hex: "#1CB0F6"))
                        .frame(width: 13, height: 13)
                        .shadow(color: Color(hex: "#1CB0F6").opacity(0.35), radius: 4)
                        .position(x: dotX, y: h / 2)
                }
            }
            .frame(height: 13)

            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoSubtitle)
                        Text("スタート")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    if let d = startDate {
                        Text("(\(GoalTimelineStrip.dateFormatter.string(from: d)))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    outlinedWeightText(startWeight)
                        .padding(.top, 2)
                    if let startBodyFat {
                        Text(startBodyFat)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                deltaArrowColumn(delta: startToCurrentDelta, color: Color.duoGreen)
                    .padding(.trailing, 6)

                VStack(spacing: 2) {
                    Text("今日")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#1CB0F6"))
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("あと")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(daysColor)
                        Text("\(daysRemaining)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(daysColor)
                        Text("日")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .foregroundColor(daysColor)
                    }
                    weightText(currentWeight, size: 38, color: Color(hex: "#1CB0F6"), kgSize: 9)
                    if let currentBodyFat {
                        Text(currentBodyFat)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "#1CB0F6").opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                deltaArrowColumn(delta: currentToGoalDelta, color: Color.duoGreen)
                    .padding(.leading, 6)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("ゴール")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.duoGreen)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color.duoGreen)
                    }
                    if let d = targetDate {
                        Text("(\(GoalTimelineStrip.dateFormatter.string(from: d)))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoGreen)
                    }
                    weightText(goalWeight, size: 27, color: Color.duoGreen, kgSize: 8)
                        .padding(.top, 2)
                    if let goalBodyFat {
                        Text(goalBodyFat)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color.duoGreen.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func deltaArrowColumn(delta: String?, color: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .black))
                .foregroundColor(color)
            if let delta {
                Text(delta)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text("kg")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(color.opacity(0.75))
            }
        }
        .frame(minWidth: 28)
        .padding(.top, 18)
    }

    private func outlinedWeightText(_ value: String) -> some View {
        VStack(spacing: -2) {
            ZStack {
                ForEach([-1, 0, 1], id: \.self) { x in
                    ForEach([-1, 0, 1], id: \.self) { y in
                        if x != 0 || y != 0 {
                            weightNumberText(value, size: 27, decimalSize: 15, color: Color.duoDark)
                                .offset(x: CGFloat(x) * 0.5, y: CGFloat(y) * 0.5)
                        }
                    }
                }
                weightNumberText(value, size: 27, decimalSize: 15, color: .white)
            }
            Text("kg")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundColor(Color.duoSubtitle)
        }
    }

    private func weightText(_ value: String, size: CGFloat, color: Color, kgSize: CGFloat) -> some View {
        VStack(spacing: -2) {
            weightNumberText(value, size: size, decimalSize: size * 0.58, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: true, vertical: false)
            Text("kg")
                .font(.system(size: kgSize, weight: .bold, design: .rounded))
                .foregroundColor(color.opacity(0.75))
        }
    }

    private func weightNumber(_ value: String) -> String {
        value.replacingOccurrences(of: "kg", with: "")
    }

    private func weightNumberText(_ value: String, size: CGFloat, decimalSize: CGFloat, color: Color) -> Text {
        let number = weightNumber(value)
        let parts = number.split(separator: ".", maxSplits: 1).map(String.init)
        let integer = parts.first ?? number
        let decimal = parts.count > 1 ? "." + parts[1] : ""
        return Text(integer)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundColor(color)
        + Text(decimal)
            .font(.system(size: decimalSize, weight: .black, design: .rounded))
            .foregroundColor(color)
    }
}

// MARK: - モチベーションバナー

private struct GoalMotivatingBanner: View {
    let weightProgress: Double
    let timeProgress: Double
    let daysRemaining: Int
    var weeklySetTotal: Int = 0
    var todayBalance: Int = 0
    var hasIntakeThisWeek: Bool = false
    var todaySteps: Int = 0
    var todayActiveCalories: Double = 0
    var todaySetCount: Int = 0
    var onAction: ((String) -> Void)? = nil

    private var contents: [(message: String, color: Color, action: String?)] {
        // 目標達成・期間終了 → 1件だけ
        if daysRemaining <= 0 {
            return [weightProgress >= 1
                ? ("🏆 目標達成！おめでとうございます！", Color.duoGreen, nil)
                : ("📅 挑戦期間終了。次の目標を設定しよう！", Color.duoSubtitle, nil)]
        }
        if weightProgress >= 1 {
            return [("🏆 目標体重クリア！この調子で維持を続けよう！", Color.duoGreen, nil)]
        }

        var items: [(message: String, color: Color, action: String?)] = []

        // ラストスパート
        if daysRemaining <= 3 {
            items.append(("🔥 あと\(daysRemaining)日！できることを全力でやろう！ →", Color(hex: "#FF4B4B"), "training"))
        } else if daysRemaining <= 7 {
            items.append(("🔥 ラストスパート！今週の運動と食事が勝負！ →", Color(hex: "#FF4B4B"), "training"))
        }

        // 今日のカロリーオーバー
        if todayBalance > 300 {
            items.append(("🍽️ 今日\(todayBalance)kcalオーバー。夕食を軽めにしてみよう →", Color(hex: "#FF9600"), "intake"))
        }

        // 今日の運動なし
        if todaySetCount == 0 {
            items.append(("💪 今日まだ筋トレなし！1セットやってみよう →", Color(hex: "#FF9600"), "training"))
        } else if weeklySetTotal == 0 {
            items.append(("💪 今週まだ運動なし！今日1セット始めよう →", Color(hex: "#FF9600"), "training"))
        }

        // 歩数少ない
        if items.count < 3 && todaySteps > 0 && todaySteps < 5000 {
            let stepsStr = todaySteps >= 1000
                ? String(format: "%.1fk", Double(todaySteps) / 1000.0)
                : "\(todaySteps)"
            items.append(("🚶 今日の歩数が\(stepsStr)歩。少し散歩してみよう！", Color(hex: "#1CB0F6"), nil))
        }

        // 活動カロリー少ない
        if items.count < 3 && todayActiveCalories > 0 && todayActiveCalories < 200 {
            items.append(("🏃 今日の活動カロリーが少なめ。散歩や軽い運動はどうですか？ →", Color(hex: "#FF9600"), "training"))
        }

        // 食事記録なし
        if items.count < 3 && !hasIntakeThisWeek {
            items.append(("📝 食事記録を続けよう！記録がダイエットの近道です →", Color(hex: "#1CB0F6"), "intake"))
        }

        // 進捗 vs 時間
        if items.count < 3 {
            let lead = weightProgress - timeProgress
            if lead > 0.1 {
                items.append(("🚀 目標ペース超え！週\(weeklySetTotal)セット達成中。絶好調！", Color.duoGreen, nil))
            } else if lead > 0 {
                items.append(("💪 順調！週\(weeklySetTotal)セット継続中。この調子で！", Color.duoGreen, nil))
            } else if lead > -0.15 {
                items.append(("⚡ もう少しペースアップを。週に1回は有酸素運動を加えよう →", Color(hex: "#FF9600"), "training"))
            } else {
                items.append(("🏃 ペースが遅れ気味。毎日の食事記録と運動習慣を見直そう →", Color(hex: "#FF4B4B"), "intake"))
            }
        }

        return Array(items.prefix(3))
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, item in
                bannerRow(item)
            }
        }
    }

    private func bannerRow(_ item: (message: String, color: Color, action: String?)) -> some View {
        let (message, color, action) = item
        let label = Text(message)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(color.opacity(action != nil ? 0.13 : 0.09))
            .cornerRadius(10)
        if let action {
            return AnyView(Button { onAction?(action) } label: { label }.buttonStyle(.plain))
        } else {
            return AnyView(label)
        }
    }
}

#Preview {
    GoalView(selectedTab: .constant(1))
        .environmentObject(AuthenticationManager.shared)
}
