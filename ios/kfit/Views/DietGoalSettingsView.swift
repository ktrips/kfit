import SwiftUI

struct DietGoalSettingsView: View {
    @StateObject private var manager  = DietGoalManager.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var targetWeight: Double = 65.0
    @State private var targetBodyFat: Double = 15.0
    @State private var hasBodyFatTarget: Bool = true
    @State private var targetDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var dailyIntakeGoal: Int = 2000
    @State private var dailyBurnGoal: Int = 2200
    @State private var showAIResult = false
    @State private var savedBanner = false

    private var dailyDeficit: Int { dailyIntakeGoal - dailyBurnGoal }
    private var daysRemaining: Int {
        max(1, Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 1)
    }

    // 時間帯別配分（固定比率）
    private var morningKcal:   Int { Int(Double(dailyIntakeGoal) * 0.20) }
    private var noonKcal:      Int { Int(Double(dailyIntakeGoal) * 0.30) }
    private var afternoonKcal: Int { Int(Double(dailyIntakeGoal) * 0.10) }
    private var eveningKcal:   Int { dailyIntakeGoal - morningKcal - noonKcal - afternoonKcal }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    currentStatsSection
                    targetSection
                    calorieGoalSection
                    mealDistributionSection
                    summarySection
                    saveButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("ダイエット目標")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSettings() }
        .overlay(alignment: .top) {
            if savedBanner {
                Text("保存しました ✓")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.duoGreen)
                    .cornerRadius(20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: savedBanner)
    }

    // MARK: - 現状（参考値）

    private var currentStatsSection: some View {
        card {
            sectionHeader(icon: "📊", title: "現在の状態（参考値）")
            HStack(spacing: 24) {
                statBadge(
                    label: "体重",
                    value: healthKit.latestBodyMass > 0
                        ? String(format: "%.1f kg", healthKit.latestBodyMass) : "—",
                    color: Color(hex: "#1CB0F6")
                )
                statBadge(
                    label: "体脂肪率",
                    value: healthKit.latestBodyFatPercentage > 0
                        ? String(format: "%.1f %%", healthKit.latestBodyFatPercentage) : "—",
                    color: Color(hex: "#CE82FF")
                )
                Spacer()
            }
            Text("Apple Healthの最新計測値")
                .font(.caption).foregroundColor(Color.duoSubtitle)
        }
    }

    // MARK: - 目標

    private var targetSection: some View {
        card {
            sectionHeader(icon: "🎯", title: "目標設定")

            HStack {
                Text("目標体重")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                Spacer()
                numericStepper(value: $targetWeight, step: 0.5, min: 30, max: 200, format: "%.1f kg")
            }

            Toggle(isOn: $hasBodyFatTarget) {
                Text("目標体脂肪率")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            }
            .tint(Color(hex: "#CE82FF"))

            if hasBodyFatTarget {
                HStack {
                    Spacer()
                    numericStepper(value: $targetBodyFat, step: 0.5, min: 5, max: 50, format: "%.1f %%")
                }
            }

            HStack {
                Text("目標日")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                Spacer()
                DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }

            HStack {
                Text("目標まで")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                Spacer()
                Text("\(daysRemaining) 日")
                    .font(.caption.weight(.bold)).foregroundColor(Color.duoDark)
            }

            if healthKit.latestBodyMass > 0 && targetWeight > 0 {
                let diff = healthKit.latestBodyMass - targetWeight
                if diff > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption).foregroundColor(Color.duoGreen)
                        Text(String(format: "減量目標: %.1f kg  (約 %.0f kcal)", diff, diff * 7700))
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                }
            }
        }
    }

    // MARK: - カロリー目標

    private var calorieGoalSection: some View {
        card {
            HStack {
                sectionHeader(icon: "🔥", title: "1日のカロリー目標")
                Spacer()
                Button {
                    applyAIGoal()
                    withAnimation { showAIResult = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showAIResult = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("AIで計算")
                            .font(.system(size: 11, weight: .black))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: "#CE82FF"))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            if showAIResult {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen).font(.caption)
                    Text("目標から逆算して設定しました")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .transition(.opacity)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("摂取カロリー目標")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                    Text("1日に摂取するカロリー")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                intStepper(value: $dailyIntakeGoal, step: 50, min: 800, max: 5000, unit: "kcal")
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("消費カロリー目標")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
                    Text("1日に消費するカロリー")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                intStepper(value: $dailyBurnGoal, step: 50, min: 1000, max: 6000, unit: "kcal")
            }
        }
    }

    // MARK: - 食事カロリー配分

    private var mealDistributionSection: some View {
        card {
            sectionHeader(icon: "🍽️", title: "食事カロリー配分")
            Text("摂取目標を時間帯別に自動配分（保存時に反映）")
                .font(.caption).foregroundColor(Color.duoSubtitle)

            VStack(spacing: 8) {
                mealRow(emoji: "🌅", label: "朝食", kcal: morningKcal,   percent: 20, color: Color(hex: "#FF9600"))
                mealRow(emoji: "☀️", label: "昼食", kcal: noonKcal,      percent: 30, color: Color(hex: "#1CB0F6"))
                mealRow(emoji: "🌤️", label: "午後", kcal: afternoonKcal, percent: 10, color: Color(hex: "#CE82FF"))
                mealRow(emoji: "🌆", label: "夕食", kcal: eveningKcal,   percent: 40, color: Color.duoGreen)
            }
        }
    }

    private func mealRow(emoji: String, label: String, kcal: Int, percent: Int, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.title3).frame(width: 28)
            Text(label)
                .font(.subheadline).fontWeight(.semibold).foregroundColor(Color.duoDark)
            Spacer()
            // ミニバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(color.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(width: 60, height: 6)
            Text("\(percent)%")
                .font(.caption).foregroundColor(Color.duoSubtitle)
                .frame(width: 28)
            Text("\(kcal) kcal")
                .font(.subheadline.weight(.black)).foregroundColor(color)
                .frame(width: 72, alignment: .trailing)
        }
    }

    // MARK: - サマリー

    private var summarySection: some View {
        let deficit      = dailyDeficit
        let defColor: Color = deficit < 0 ? Color.duoGreen : Color(hex: "#FF4B4B")
        let weeklyDef    = deficit * 7
        let weightImpact = Double(weeklyDef) / 7700.0

        // 目標日までの予測変化
        let currentWeight = healthKit.latestBodyMass > 0 ? healthKit.latestBodyMass : 0
        let currentFat    = healthKit.latestBodyFatPercentage > 0 ? healthKit.latestBodyFatPercentage : 0
        let projectedWeightChange = Double(deficit * daysRemaining) / 7700.0  // 負 = 減少
        let projectedEndWeight    = currentWeight + projectedWeightChange      // 予測終了時体重

        return card {
            sectionHeader(icon: "📈", title: "予測サマリー")

            // 週次サマリー行
            HStack(spacing: 0) {
                summaryItem(label: "1日収支",
                            value: (deficit >= 0 ? "+" : "") + "\(deficit)",
                            unit: "kcal", color: defColor)
                Divider().frame(height: 40)
                summaryItem(label: "週間収支",
                            value: (weeklyDef >= 0 ? "+" : "") + "\(weeklyDef)",
                            unit: "kcal", color: defColor)
                Divider().frame(height: 40)
                summaryItem(label: "週体重変化",
                            value: (weightImpact >= 0 ? "+" : "") + String(format: "%.2f", weightImpact),
                            unit: "kg/週", color: defColor)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // 目標日までの予測
            VStack(alignment: .leading, spacing: 8) {
                Text("目標日までの予測変化（\(daysRemaining)日後）")
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color.duoSubtitle)

                HStack(spacing: 0) {
                    // 体重予測
                    VStack(spacing: 4) {
                        Text("⚖️ 体重")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                        if currentWeight > 0 {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", currentWeight))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                                Text(String(format: "%.1f", projectedEndWeight))
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(defColor)
                            }
                            Text((projectedWeightChange >= 0 ? "+" : "") + String(format: "%.1f kg", projectedWeightChange))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(defColor)
                        } else {
                            Text("—").font(.caption).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 50)

                    // 体脂肪率予測（カロリーベース推算）
                    VStack(spacing: 4) {
                        Text("📉 体脂肪率")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                        if hasBodyFatTarget && currentFat > 0 {
                            let projectedFatChange: Double = {
                                guard currentWeight > 0, projectedEndWeight > 0 else { return 0 }
                                // 消費カロリーの75%が体脂肪から、残りは筋肉等からと仮定
                                let fatKgLost = (-projectedWeightChange) * 0.75
                                let newFatKg = (currentFat / 100) * currentWeight - fatKgLost
                                let newFatPct = (newFatKg / projectedEndWeight) * 100
                                return newFatPct - currentFat
                            }()
                            let projectedEndFat = currentFat + projectedFatChange
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", currentFat) + "%")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.duoSubtitle)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                                Text(String(format: "%.1f", projectedEndFat) + "%")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(defColor)
                            }
                            Text((projectedFatChange >= 0 ? "+" : "") + String(format: "%.1f%%", projectedFatChange))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(defColor)
                        } else {
                            Text("—").font(.caption).foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 保存ボタン

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("保存する").fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.duoGreen)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Text(icon).font(.title3)
            Text(title).font(.headline.weight(.black)).foregroundColor(Color.duoDark)
        }
    }

    private func statBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 16, weight: .black)).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(Color.duoSubtitle)
        }
    }

    private func numericStepper(value: Binding<Double>, step: Double, min: Double, max: Double, format: String) -> some View {
        HStack(spacing: 10) {
            Button {
                if value.wrappedValue - step >= min { value.wrappedValue -= step }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
                    .foregroundColor(value.wrappedValue > min ? Color.duoGreen : Color(.systemGray4))
            }
            .disabled(value.wrappedValue <= min)
            Text(String(format: format, value.wrappedValue))
                .font(.subheadline.weight(.black)).foregroundColor(Color.duoDark)
                .frame(minWidth: 72)
            Button {
                if value.wrappedValue + step <= max { value.wrappedValue += step }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
                    .foregroundColor(value.wrappedValue < max ? Color.duoGreen : Color(.systemGray4))
            }
            .disabled(value.wrappedValue >= max)
        }
    }

    private func intStepper(value: Binding<Int>, step: Int, min: Int, max: Int, unit: String) -> some View {
        HStack(spacing: 10) {
            Button {
                if value.wrappedValue - step >= min { value.wrappedValue -= step }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
                    .foregroundColor(value.wrappedValue > min ? Color.duoGreen : Color(.systemGray4))
            }
            .disabled(value.wrappedValue <= min)
            Text("\(value.wrappedValue) \(unit)")
                .font(.subheadline.weight(.black)).foregroundColor(Color.duoDark)
                .frame(minWidth: 84)
            Button {
                if value.wrappedValue + step <= max { value.wrappedValue += step }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
                    .foregroundColor(value.wrappedValue < max ? Color.duoGreen : Color(.systemGray4))
            }
            .disabled(value.wrappedValue >= max)
        }
    }

    private func summaryItem(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .black)).foregroundColor(color)
            Text(unit).font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
            Text(label).font(.caption).foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ロジック

    private func loadSettings() {
        let s = manager.settings
        targetWeight     = s.targetWeight
        targetBodyFat    = s.targetBodyFatPercent
        hasBodyFatTarget = s.hasBodyFatTarget
        targetDate       = s.targetDate
        dailyIntakeGoal  = s.dailyIntakeGoal
        dailyBurnGoal    = s.dailyBurnGoal
    }

    private func save() async {
        // DietGoalManager に保存
        var s = manager.settings
        s.targetWeight         = targetWeight
        s.targetBodyFatPercent = targetBodyFat
        s.hasBodyFatTarget     = hasBodyFatTarget
        s.targetDate           = targetDate
        s.dailyIntakeGoal      = dailyIntakeGoal
        s.dailyBurnGoal        = dailyBurnGoal
        manager.settings = s

        // IntakeSettings の食事カロリーを時間帯別に反映
        var intakeSettings = await AuthenticationManager.shared.getIntakeSettings()
        intakeSettings.breakfastCalories = morningKcal
        intakeSettings.lunchCalories     = noonKcal
        intakeSettings.snackCalories     = afternoonKcal
        intakeSettings.dinnerCalories    = eveningKcal
        intakeSettings.dailyCalorieGoal  = dailyIntakeGoal
        await AuthenticationManager.shared.saveIntakeSettings(intakeSettings)

        withAnimation { savedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedBanner = false }
        }
    }

    private func applyAIGoal() {
        let currentWeight = healthKit.latestBodyMass > 0 ? healthKit.latestBodyMass : targetWeight
        guard currentWeight > 0, targetWeight > 0, daysRemaining > 0 else { return }

        let totalDeficit = (currentWeight - targetWeight) * 7700
        let requiredDailyDeficit = totalDeficit / Double(daysRemaining)
        let tdee = max(1400.0, currentWeight * 30)

        let suggestedIntake = max(1200, Int((tdee - requiredDailyDeficit * 0.6) / 50) * 50)
        let suggestedBurn   = Int((tdee + requiredDailyDeficit * 0.4) / 50) * 50

        dailyIntakeGoal = suggestedIntake
        dailyBurnGoal   = suggestedBurn
    }
}

#Preview {
    NavigationView { DietGoalSettingsView() }
}
