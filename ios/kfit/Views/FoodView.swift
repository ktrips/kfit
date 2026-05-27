import SwiftUI

struct FoodView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool

    @StateObject private var healthKit   = HealthKitManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var timeSlotManager = TimeSlotManager.shared

    @State private var pfcAnalysis:  PFCBalanceAnalysis?
    @State private var todayIntake = TodayIntakeSummary()
    @State private var intakeGoals = IntakeSettings.defaultSettings

    @State private var showPhotoLog      = false
    @State private var showDetailLog     = false
    @State private var showIntakeConfirm = false
    @State private var pendingIntakeAction: (() -> Void)?
    @State private var confirmMessage    = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                    // PFCバランス（最上段）
                    if let analysis = pfcAnalysis, analysis.score > 0 {
                        pfcBalanceCard(analysis)
                    } else {
                        noPFCDataCard
                    }

                    // 水分・カフェイン・アルコール（PFCカードの直下）
                    hydrationRow

                    // アドバイス
                    if let analysis = pfcAnalysis, analysis.score > 0 {
                        improvementCard(analysis)
                    }

                    // フォトログ（大）
                    photoLogButton

                    // クイックログ
                    quickLogSection

                    // 詳細ログ
                    detailLogButton

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
        }
        .background(Color.duoBg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            foodHeader
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await loadData() }
        }
        .fullScreenCover(isPresented: $showPhotoLog) {
            PhotoLogView()
        }
        .sheet(isPresented: $showDetailLog) {
            DailyIntakeView()
                .environmentObject(authManager)
        }
        .alert(confirmMessage, isPresented: $showIntakeConfirm) {
            Button("記録する", role: .none) {
                pendingIntakeAction?()
                pendingIntakeAction = nil
            }
            Button("キャンセル", role: .cancel) { pendingIntakeAction = nil }
        }
    }

    // MARK: - Header

    private var foodHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.0), Color(red: 0.85, green: 0.25, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                    HStack(spacing: 0) {
                        Text("Food").foregroundColor(Color(red: 1.0, green: 0.95, blue: 0.5))
                        Text("ingo").foregroundColor(.white)
                    }
                    .font(.system(size: 13, weight: .black, design: .rounded))
                }
                Spacer()
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 1.0, green: 0.95, blue: 0.5))
                        Text("\(Int(healthKit.todayIntakeCalories))")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("kcal")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(8)

                    if let a = pfcAnalysis, a.score > 0 {
                        HStack(spacing: 2) {
                            Text("\(a.score)")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("点")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .cornerRadius(8)
                    }

                    HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(height: 46)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - フォトログボタン

    private var photoLogButton: some View {
        Button { showPhotoLog = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.45, blue: 0.0).opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("📸 フォトログ")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color.duoDark)
                    Text("食事の写真を撮ってAIが栄養素を自動分析")
                        .font(.system(size: 11))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - クイックログ

    private var quickLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(Color.duoOrange)
                    .font(.system(size: 11))
                Text("クイックログ")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Color.duoDark)
            }

            // 行1: 朝食・昼食・夕食
            HStack(spacing: 8) {
                quickBtn(emoji: "🌅", label: "朝食", color: Color.duoOrange) {
                    confirm("朝食 \(intakeGoals.caloriesFor(mealType: .breakfast))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .breakfast)
                            await updateSlotForMeal(calories: intakeGoals.caloriesFor(mealType: .breakfast))
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "🍱", label: "昼食", color: Color.duoOrange) {
                    confirm("昼食 \(intakeGoals.caloriesFor(mealType: .lunch))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .lunch)
                            await updateSlotForMeal(calories: intakeGoals.caloriesFor(mealType: .lunch))
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "🍽️", label: "夕食", color: Color.duoOrange) {
                    confirm("夕食 \(intakeGoals.caloriesFor(mealType: .dinner))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .dinner)
                            await updateSlotForMeal(calories: intakeGoals.caloriesFor(mealType: .dinner))
                            await loadData()
                        }
                    }
                }
            }

            // 行2: スナック・水・コーヒー
            HStack(spacing: 8) {
                quickBtn(emoji: "🍫", label: "スナック", color: Color.duoOrange) {
                    confirm("スナック \(intakeGoals.caloriesFor(mealType: .snack))kcal を記録しますか？") {
                        Task {
                            await authManager.recordMeal(mealType: .snack)
                            await updateSlotForMeal(calories: intakeGoals.caloriesFor(mealType: .snack))
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "💧", label: "水", color: Color.duoBlue) {
                    confirm("水 \(intakeGoals.waterPerCup)ml を記録しますか？") {
                        Task {
                            await authManager.recordWater()
                            await updateSlotForDrink(ml: intakeGoals.waterPerCup)
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "☕", label: "コーヒー", color: Color(hex: "#8B5E3C")) {
                    confirm("コーヒー \(intakeGoals.coffeePerCup)ml (カフェイン \(intakeGoals.caffeinePerCup)mg) を記録しますか？") {
                        Task {
                            await authManager.recordCoffee()
                            await updateSlotForDrink(ml: intakeGoals.coffeePerCup)
                            await loadData()
                        }
                    }
                }
            }

            // 行3: ビール・ワイン・焼酎
            HStack(spacing: 8) {
                quickBtn(emoji: "🍺", label: "ビール", color: Color.duoPurple) {
                    confirm("ビール (アルコール \(String(format: "%.1f", AlcoholType.beer.alcoholG))g) を記録しますか？") {
                        Task {
                            await authManager.recordAlcohol(alcoholType: .beer)
                            await updateSlotForDrink(ml: AlcoholType.beer.amountMl)
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "🍷", label: "ワイン", color: Color.duoPurple) {
                    confirm("ワイン (アルコール \(String(format: "%.1f", AlcoholType.wine.alcoholG))g) を記録しますか？") {
                        Task {
                            await authManager.recordAlcohol(alcoholType: .wine)
                            await updateSlotForDrink(ml: AlcoholType.wine.amountMl)
                            await loadData()
                        }
                    }
                }
                quickBtn(emoji: "🍶", label: "焼酎", color: Color.duoPurple) {
                    confirm("焼酎・酎ハイ (アルコール \(String(format: "%.1f", AlcoholType.chuhai.alcoholG))g) を記録しますか？") {
                        Task {
                            await authManager.recordAlcohol(alcoholType: .chuhai)
                            await updateSlotForDrink(ml: AlcoholType.chuhai.amountMl)
                            await loadData()
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func quickBtn(emoji: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(emoji).font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.10))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 詳細ログボタン

    private var detailLogButton: some View {
        Button { showDetailLog = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 14))
                    .foregroundColor(Color.duoGreen)
                Text("詳細ログ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.duoGreen)
                Text("食事・ドリンクを詳しく登録")
                    .font(.system(size: 11))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(Color.duoSubtitle.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - PFC Balance Card

    private func pfcBalanceCard(_ analysis: PFCBalanceAnalysis) -> some View {
        let totalCalories = Int(healthKit.todayIntakeCalories)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                Text("PFCバランス")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Spacer()
                HStack(spacing: 2) {
                    Text("\(totalCalories)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                    Text("kcal")
                        .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(red: 1.0, green: 0.45, blue: 0.0).opacity(0.1))
                .cornerRadius(10)
                Text(analysis.rating)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(pfcScoreColor(analysis.score))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(pfcScoreColor(analysis.score).opacity(0.15))
                    .cornerRadius(10)
            }
            HStack(spacing: 12) {
                ZStack {
                    PFCPieChart(proteinPercent: analysis.proteinPercent,
                                fatPercent: analysis.fatPercent,
                                carbsPercent: analysis.carbsPercent)
                    .frame(width: 80, height: 80)
                    VStack(spacing: 0) {
                        Text("\(analysis.score)")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(pfcScoreColor(analysis.score))
                        Text("点").font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    pfcRow(color: Color.duoOrange,  label: "P", name: "たんぱく質", percent: analysis.proteinPercent, grams: analysis.proteinGrams)
                    pfcRow(color: Color.duoPurple,  label: "F", name: "脂質",       percent: analysis.fatPercent,     grams: analysis.fatGrams)
                    pfcRow(color: Color.duoBlue,    label: "C", name: "炭水化物",   percent: analysis.carbsPercent,   grams: analysis.carbsGrams)
                }
            }
            Text("目安: P 15% / F 25% / C 60%")
                .font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func pfcRow(color: Color, label: String, name: String, percent: Double, grams: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(Color.duoDark)
            Text(name).font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(String(format: "%.0f%%", percent)).font(.system(size: 11, weight: .bold)).foregroundColor(color)
            Text(String(format: "%.0fg", grams)).font(.system(size: 9)).foregroundColor(Color.duoSubtitle)
        }
    }

    private func pfcScoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .duoGreen
        case 80..<90:  return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 70..<80:  return Color(red: 1.0, green: 0.6, blue: 0.0)
        case 50..<70:  return Color(red: 1.0, green: 0.4, blue: 0.0)
        default:       return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
    }

    // MARK: - Improvement Card

    private func improvementCard(_ analysis: PFCBalanceAnalysis) -> some View {
        let tips = buildTips(analysis)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.0))
                Text("今日の食事アドバイス")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.message) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        ZStack {
                            Circle().fill(tip.color.opacity(0.15)).frame(width: 28, height: 28)
                            Text(tip.emoji).font(.system(size: 14))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.system(size: 12, weight: .bold)).foregroundColor(tip.color)
                            Text(tip.message).font(.system(size: 12))
                                .foregroundColor(Color.duoDark.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private struct FoodTip {
        let emoji: String; let title: String; let message: String; let color: Color
    }

    private func buildTips(_ a: PFCBalanceAnalysis) -> [FoodTip] {
        var tips: [FoodTip] = []
        if a.proteinPercent < 12 {
            tips.append(FoodTip(emoji: "🥩", title: "たんぱく質不足",
                message: "目標より少なめです。卵・鶏むね・豆腐・納豆などを積極的に取り入れましょう。",
                color: Color.duoOrange))
        } else if a.proteinPercent > 25 {
            tips.append(FoodTip(emoji: "🥩", title: "たんぱく質過多",
                message: "摂り過ぎると腎臓への負荷が増えます。バランスを意識してみましょう。",
                color: Color.duoOrange))
        }
        if a.fatPercent > 35 {
            tips.append(FoodTip(emoji: "🛢️", title: "脂質が多め",
                message: "揚げ物や脂身の多い肉を控え、青魚・アボカド・ナッツなど質の良い脂質を選びましょう。",
                color: Color.duoPurple))
        } else if a.fatPercent < 15 {
            tips.append(FoodTip(emoji: "🥑", title: "脂質が少なめ",
                message: "脂溶性ビタミン（A・D・E・K）の吸収に脂質が必要です。良質な油を少量加えましょう。",
                color: Color.duoPurple))
        }
        if a.carbsPercent > 70 {
            tips.append(FoodTip(emoji: "🍚", title: "炭水化物が多め",
                message: "白米や麺類の量を少し減らし、野菜・タンパク質の比率を増やすとバランスが改善します。",
                color: Color.duoBlue))
        } else if a.carbsPercent < 40 {
            tips.append(FoodTip(emoji: "🍚", title: "炭水化物が少なめ",
                message: "脳や筋肉のエネルギー源として重要です。玄米や全粒パンなど質の良い炭水化物を補いましょう。",
                color: Color.duoBlue))
        }
        let waterPct = intakeGoals.dailyWaterGoal > 0
            ? Double(todayIntake.totalWaterMl) / Double(intakeGoals.dailyWaterGoal) * 100 : 0
        if waterPct < 60 {
            tips.append(FoodTip(emoji: "💧", title: "水分補給を忘れずに",
                message: "今日の水分摂取が少なめです。こまめに水やお茶を飲む習慣をつけましょう。",
                color: Color(red: 0.2, green: 0.6, blue: 1.0)))
        }
        if tips.isEmpty {
            tips.append(a.score >= 80
                ? FoodTip(emoji: "✨", title: "バランス良好！",
                    message: "今日の食事はバランスが取れています。このペースを維持しましょう！",
                    color: Color.duoGreen)
                : FoodTip(emoji: "🍽️", title: "もう少しで理想的",
                    message: "P:15% / F:25% / C:60% の比率を意識すると、さらにバランスアップできます。",
                    color: Color(red: 1.0, green: 0.6, blue: 0.0))
            )
        }
        return tips
    }

    // MARK: - No Data

    private var noPFCDataCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 36))
                .foregroundColor(Color.duoSubtitle.opacity(0.4))
            Text("食事記録がありません")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.duoDark)
            Text("上のボタンから食事を記録すると\nPFCバランスとアドバイスが表示されます")
                .font(.system(size: 11))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    // MARK: - Water / Caffeine / Alcohol

    private var hydrationRow: some View {
        HStack(spacing: 8) {
            intakeItemCard(icon: "drop.fill",         iconColor: Color.duoBlue,
                label: "水分",      value: Double(todayIntake.totalWaterMl),
                goal: Double(intakeGoals.dailyWaterGoal), unit: "ml",
                formatValue: { "\(Int($0))" }, isReverse: false,
                healthKitURL: "x-apple-health://dietarywater")
            intakeItemCard(icon: "cup.and.saucer.fill", iconColor: Color(hex: "#8B5E3C"),
                label: "カフェイン", value: Double(todayIntake.totalCaffeineMg),
                goal: Double(intakeGoals.dailyCaffeineLimit), unit: "mg",
                formatValue: { "\(Int($0))" }, isReverse: true,
                healthKitURL: "x-apple-health://dietarycaffeine")
            intakeItemCard(icon: "wineglass.fill",     iconColor: Color.duoPurple,
                label: "アルコール", value: todayIntake.totalAlcoholG,
                goal: intakeGoals.dailyAlcoholLimit, unit: "g",
                formatValue: { String(format: "%.1f", $0) }, isReverse: true,
                healthKitURL: "x-apple-health://nutrition")
        }
    }

    private func adviceText(label: String, value: Double, goal: Double?, isReverse: Bool) -> String {
        guard let g = goal, g > 0 else { return "" }
        let percent = Int((value / g) * 100)
        if label == "水分" {
            if value <= 0 { return "まだ水分なし" }
            if percent >= 100 { return "目標達成！" }
            let remaining = Int(g - value)
            if percent >= 80 { return "あと\(remaining)ml！" }
            return "あと\(remaining)ml飲もう"
        } else if label == "カフェイン" {
            if value <= 0 { return "摂取なし" }
            if percent >= 100 { return "上限超過！" }
            if percent >= 70 { return "上限に近い" }
            if percent >= 40 { return "適度な範囲" }
            return "安全な範囲"
        } else {
            if value <= 0 { return "飲酒なし" }
            if percent >= 100 { return "上限超過！" }
            if percent >= 70 { return "飲み過ぎ注意" }
            return "適量範囲内"
        }
    }

    private func intakeItemCard(icon: String, iconColor: Color, label: String,
        value: Double, goal: Double?, unit: String,
        formatValue: (Double) -> String, isReverse: Bool,
        healthKitURL: String?) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver  = goal != nil && value > goal!
        let displayColor: Color
        if label == "水分" {
            displayColor = percent >= 100 ? .duoGreen : percent >= 70 ? .duoGreen.opacity(0.7) : percent >= 40 ? .duoOrange : .duoDark
        } else {
            displayColor = (isOver || percent >= 100) ? .red : percent >= 70 ? .duoOrange : .duoGreen
        }
        let advice = adviceText(label: label, value: value, goal: goal, isReverse: isReverse)
        let content = VStack(alignment: .center, spacing: 3) {
            Image(systemName: icon).font(.system(size: 17)).foregroundColor(iconColor)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(Color.duoDark)
            VStack(spacing: 1) {
                Text(value > 0 ? formatValue(value) : "—")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor((isOver && isReverse) ? .red : displayColor)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 8)).foregroundColor(Color.duoSubtitle)
            }
            if let _ = goal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 3)
                        Capsule().fill(displayColor)
                            .frame(width: max(3, geo.size.width * CGFloat(min(percent, 100)) / 100), height: 3)
                    }
                }.frame(height: 3)
                Text("\(percent)%").font(.system(size: 8, weight: .bold)).foregroundColor(displayColor)
            }
            if !advice.isEmpty {
                Text(advice)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(displayColor.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(iconColor.opacity(0.08))
        .cornerRadius(10)
        if let url = healthKitURL {
            return AnyView(Button { if let u = URL(string: url) { UIApplication.shared.open(u) } } label: { content }.buttonStyle(.plain))
        } else {
            return AnyView(content)
        }
    }

    // MARK: - Helpers

    private func confirm(_ message: String, action: @escaping () -> Void) {
        confirmMessage = message
        pendingIntakeAction = action
        showIntakeConfirm = true
    }

    private func updateSlotForMeal(calories: Int) async {
        let hour = Calendar.current.component(.hour, from: Date())
        let slot: TimeSlot = hour < 10 ? .morning : hour < 14 ? .noon : hour < 18 ? .afternoon : .evening
        await timeSlotManager.recordMealLog(at: slot, calories: calories)
    }

    private func updateSlotForDrink(ml: Int) async {
        let hour = Calendar.current.component(.hour, from: Date())
        let slot: TimeSlot = hour < 10 ? .morning : hour < 14 ? .noon : hour < 18 ? .afternoon : .evening
        await timeSlotManager.recordDrinkLog(at: slot, ml: ml)
    }

    private func loadData() async {
        async let summary = authManager.getTodayIntakeSummary()
        async let goals   = authManager.getIntakeSettings()
        await healthKit.fetchIntakeHealth()
        var (intake, settings) = await (summary, goals)

        // HealthKitの値をマージ（アプリ記録とHealthKit記録を合算して大きい方を採用）
        intake.totalWaterMl    = max(intake.totalWaterMl,    Int(healthKit.todayIntakeWater))
        intake.totalCaffeineMg = max(intake.totalCaffeineMg, Int(healthKit.todayIntakeCaffeine))
        intake.totalAlcoholG   = max(intake.totalAlcoholG,   healthKit.todayIntakeAlcohol)

        todayIntake = intake
        intakeGoals = settings
        pfcAnalysis = healthKit.analyzePFCBalance(settings: intakeGoals)
    }
}
