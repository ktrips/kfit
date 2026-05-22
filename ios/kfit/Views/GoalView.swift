import SwiftUI

struct GoalView: View {
    @StateObject private var healthKit   = HealthKitManager.shared
    @StateObject private var dietManager = DietGoalManager.shared
    @State private var showDietGoalSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        goalHeroCard
                        progressCard
                        weeklyCalorieCard
                        weightChartCard
                        bodyFatChartCard
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
            }
        }
    }

    // MARK: - ヒーローカード（現状 vs 目標）

    private var goalHeroCard: some View {
        let goal       = dietManager.settings
        let current    = healthKit.latestBodyMass
        let currentFat = healthKit.latestBodyFatPercentage

        let weightDiff = (current > 0 && goal.targetWeight > 0) ? current - goal.targetWeight : nil

        let weightProgress: Double = {
            guard let diff = weightDiff, current > 0, goal.targetWeight > 0 else { return 0 }
            let startWeight = max(current, goal.targetWeight + diff)
            let totalChange = startWeight - goal.targetWeight
            guard totalChange > 0 else { return 1 }
            return min(1, max(0, (startWeight - current) / totalChange))
        }()

        return VStack(spacing: 0) {
            // タイトル行
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diet Goal")
                        .font(.headline.weight(.black))
                        .foregroundColor(Color.duoDark)
                    Text("目標日: \(formattedDate(goal.targetDate))")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Button {
                    showDietGoalSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.duoGreen)
                        .padding(8)
                        .background(Color.duoGreen.opacity(0.1))
                        .cornerRadius(10)
                }
                daysRemainingBadge(goal: goal)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

            Divider()

            // 現状 vs 目標
            HStack(spacing: 0) {
                metricColumn(
                    label: "現在",
                    weightVal: current > 0 ? String(format: "%.1f", current) : "—",
                    fatVal: currentFat > 0 ? String(format: "%.1f", currentFat) : nil,
                    color: Color(hex: "#1CB0F6")
                )

                VStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    if let d = weightDiff {
                        Text((d >= 0 ? "-" : "+") + String(format: "%.1f kg", abs(d)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(d >= 0 ? Color.duoGreen : Color(hex: "#FF4B4B"))
                    }
                }
                .frame(maxWidth: 60)

                metricColumn(
                    label: "目標",
                    weightVal: goal.targetWeight > 0 ? String(format: "%.1f", goal.targetWeight) : "未設定",
                    fatVal: goal.hasBodyFatTarget && goal.targetBodyFatPercent > 0
                        ? String(format: "%.1f", goal.targetBodyFatPercent) : nil,
                    color: Color.duoGreen
                )
            }
            .padding(.horizontal, 16).padding(.vertical, 16)

            // 達成度バー
            if goal.targetWeight > 0 && current > 0 {
                VStack(spacing: 6) {
                    HStack {
                        Text("達成度")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color.duoSubtitle)
                        Spacer()
                        Text(String(format: "%.0f%%", weightProgress * 100))
                            .font(.caption.weight(.black))
                            .foregroundColor(Color.duoGreen)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#58CC02"), Color(hex: "#1CB0F6")],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(weightProgress))
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
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
        return VStack(spacing: 2) {
            Text("\(days)")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(color)
            Text("日後")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color.opacity(0.8))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(12)
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

    // MARK: - 週間カロリー収支カード

    private var weeklyCalorieCard: some View {
        GoalWeeklyCalorieCard(
            data: healthKit.weeklyCalorieData,
            dailyGoal: dietManager.settings.dailyDeficitGoal
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
        if weekTotal <= weeklyGoal       { return ("達成！", Color.duoGreen) }
        if weekTotal <= expected         { return ("順調", Color(hex: "#1CB0F6")) }
        if weekTotal < expected / 2      { return ("注意", Color(hex: "#FF9600")) }
        return ("危険", Color(hex: "#FF4B4B"))
    }

    var body: some View {
        let weekTotal = data.reduce(0) { $0 + $1.balance }
        let weightImpactKg = Double(weekTotal) / 7700.0
        let maxAbs = max(data.map { abs($0.balance) }.max() ?? 0, 300)
        let badge = statusBadge(weekTotal: weekTotal)

        let mondayMass = data.first?.bodyMass
        let latestMass = data.last(where: { $0.bodyMass != nil })?.bodyMass
        let massDiff: Double? = (mondayMass != nil && latestMass != nil) ? latestMass! - mondayMass! : nil
        let diffColor: Color = (massDiff ?? 0) < 0 ? Color.duoGreen
            : (massDiff ?? 0) > 0 ? Color(hex: "#FF4B4B")
            : Color.duoSubtitle

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#FF9600"))
                Text("週間カロリー")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        Text((weekTotal >= 0 ? "+" : "") + "\(weekTotal) kcal")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(weekTotal > 0 ? Color(hex: "#FF4B4B") : Color.duoGreen)
                        Text(badge.label)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(badge.color)
                            .cornerRadius(6)
                    }
                    HStack(spacing: 5) {
                        Text((weightImpactKg >= 0 ? "+" : "") + String(format: "%.2f", weightImpactKg) + " kg")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(weightImpactKg > 0 ? Color(hex: "#FF4B4B").opacity(0.8) : Color.duoGreen.opacity(0.8))
                        if let diff = massDiff {
                            Text((diff >= 0 ? "+" : "") + String(format: "%.1f", diff) + "kg")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(diffColor)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(diffColor.opacity(0.1))
                                .cornerRadius(5)
                        }
                    }
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

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.duoGreen.opacity(0.85)).frame(width: 10, height: 4)
                        Text("消費オーバー").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1).fill(Color(hex: "#FF4B4B").opacity(0.75)).frame(width: 10, height: 4)
                        Text("摂取オーバー").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Text("目標: 1日-\(abs(dailyGoal))kcal")
                        .font(.system(size: 9))
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(12)
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

#Preview {
    GoalView()
        .environmentObject(AuthenticationManager.shared)
}
