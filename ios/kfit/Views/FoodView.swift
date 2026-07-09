import SwiftUI

// MARK: - User Avatar View
/// Google アイコン（URL）があれば表示、なければイニシャルをグラデーション円で表示
struct UserAvatarView: View {
    let name: String
    let photoURL: String
    let gradient: LinearGradient
    let size: CGFloat

    init(name: String, photoURL: String = "",
         gradient: LinearGradient = LinearGradient(
            colors: [Color.duoBlue, Color.duoPurple],
            startPoint: .topLeading, endPoint: .bottomTrailing),
         size: CGFloat = 36) {
        self.name     = name
        self.photoURL = photoURL
        self.gradient = gradient
        self.size     = size
    }

    private var initial: String {
        String((name.first ?? "?").uppercased())
    }

    var body: some View {
        Group {
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(gradient)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Body modifier（コンパイラのタイプチェックタイムアウト回避）
// body に sheet/alert を直接チェーンすると推論が重いため ViewModifier に分離
private struct FoodViewSheets: ViewModifier {
    @Binding var showPhotoLog: Bool
    @Binding var showDetailLog: Bool
    var authManager: AuthenticationManager
    @Binding var showIntakeSettings: Bool
    @Binding var swipeFoodItems: [PhotoLogHistoryItem]
    @Binding var swipeFoodStart: Int
    @Binding var showPlusView: Bool
    var confirmMessage: String
    @Binding var showIntakeConfirm: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showPhotoLog) { PhotoLogView() }
            .sheet(isPresented: $showDetailLog) {
                DailyIntakeView().environmentObject(authManager)
            }
            .sheet(isPresented: $showIntakeSettings) { IntakeSettingsView() }
            .sheet(isPresented: Binding(
                get: { !swipeFoodItems.isEmpty },
                set: { if !$0 { swipeFoodItems = [] } }
            )) {
                SwipeableFoodFeedSheet(items: swipeFoodItems, startIndex: swipeFoodStart)
            }
            .sheet(isPresented: $showPlusView) { PlusView() }
            .alert(confirmMessage, isPresented: $showIntakeConfirm) {
                Button("記録する", role: .none, action: onConfirm)
                Button("キャンセル", role: .cancel, action: onCancel)
            }
    }
}

/// ライフサイクル系モディファイア（onChange / onReceive / task）をまとめて型チェック負荷を分散
private struct FoodViewLifecycle: ViewModifier {
    var historyVersion: Int
    var mealsCount: Int
    var waterLogsCount: Int
    var coffeeLogsCount: Int
    var alcoholLogsCount: Int
    var mealSamplesCount: Int
    var waterSamplesCount: Int
    /// 時間帯別カロリー集計値（変化を検知して再描画トリガー）
    var mealSlotHash: Int
    var onHistoryVersionChange: () -> Void
    var onFoodHistoryChange: () -> Void
    var onForeground: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: historyVersion) { _, _ in onHistoryVersionChange() }
            .onChange(of: mealsCount)     { _, _ in onFoodHistoryChange() }
            .onChange(of: waterLogsCount) { _, _ in onFoodHistoryChange() }
            .onChange(of: coffeeLogsCount){ _, _ in onFoodHistoryChange() }
            .onChange(of: alcoholLogsCount){ _, _ in onFoodHistoryChange() }
            .onChange(of: mealSamplesCount){ _, _ in onFoodHistoryChange() }
            .onChange(of: waterSamplesCount){ _, _ in onFoodHistoryChange() }
            .onChange(of: mealSlotHash){ _, _ in onFoodHistoryChange() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                onForeground()
            }
    }
}

struct FoodView: View {
    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool

    // V1: 共有シングルトンは kfitApp から EnvironmentObject で受け取る
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var timeSlotManager: TimeSlotManager
    @EnvironmentObject private var photoLogManager: PhotoLogManager
    @EnvironmentObject private var plus: PlusManager

    @State private var showPlusViewFromFood = false
    @State private var pfcAnalysis:  PFCBalanceAnalysis?
    @State private var todayIntake = TodayIntakeSummary()
    @State private var intakeGoals = IntakeSettings.defaultSettings

    @State private var showPhotoLog        = false
    @State private var showDetailLog       = false
    @State private var showPhotoCarousel   = false  // 今日の食事タップ→食事スライド
    @State private var mealSlideFilter: String? = nil  // nil=全件, "朝食"/"ランチ"/"スナック"/"夕食"
    @State private var showDrinkRows       = false  // 飲料クイックボタン行の展開
    @State private var showIntakeConfirm = false
    @State private var pendingIntakeAction: (() -> Void)?
    @State private var confirmMessage    = ""
    // フォトログ集計キャッシュ（photoLogManager.history 変化時のみ再計算）
    @State private var cachedPhotoLogTotals: (protein: Double, fat: Double, carbs: Double, calories: Int) = (0, 0, 0, 0)
    @State private var swipeFoodItems: [PhotoLogHistoryItem] = []
    @State private var swipeFoodStart: Int = 0
    @State private var showFoodHistory = false
    @State private var showIntakeSettings = false
    @State private var showOlderFoodFeed = false
    @State private var dailyFixedGoals: DailyFixedGoals = DailyFixedGoals()
    // 水分・カフェイン・アルコールカードのクイックログパネル開閉
    @State private var hydrationQuickType: String? = nil
    // V4: foodHistorySection キャッシュ — 入力変化時のみ再構築
    private struct FoodHistoryCache {
        var meals: [HistoryEntry] = []
        var water: [HistoryEntry] = []
        var coffee: [HistoryEntry] = []
        var alcohol: [HistoryEntry] = []
        var totalCount: Int { meals.count + water.count + coffee.count + alcohol.count }
    }
    @State private var foodHistoryCache = FoodHistoryCache()

    // クイックログ固定メニューの栄養素（カロリーに見合った値）
    static let katsuCurryNutrition = MealNutrition(
        calories: 1000, protein: 30, fat: 40, carbs: 125, sugar: 118, fiber: 7, sodium: 4.0
    )
    static let nutritionBarNutrition = MealNutrition(
        calories: 100, protein: 2, fat: 5, carbs: 12, sugar: 10, fiber: 1, sodium: 0.1
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                    // 栄養サマリーカード（PFC・水分・クイックログ・アドバイス・食事履歴）
                    nutritionSummaryCard

                    // 食事記録カード（フォトログ＋クイックログ＋詳細ログ）
                    mealRecordCard

                    // FOODフィード（お気に入りのみ）
                    if !photoLogManager.history.filter({ $0.isFavorite }).isEmpty {
                        photoFeedSection
                    }

                    // FOODフィードプロモーション（Freeユーザー向け）
                    foodFeedPromoSection

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
        }
        .refreshable { await loadData() }
        .background(Color.duoBg.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { foodHeader }
        .task { await loadData(); recomputePhotoLogTotals(); rebuildFoodHistory() }
        .modifier(FoodViewLifecycle(
            historyVersion:    photoLogManager.historyVersion,
            mealsCount:        todayIntake.meals.count,
            waterLogsCount:    todayIntake.waterLogs.count,
            coffeeLogsCount:   todayIntake.coffeeLogs.count,
            alcoholLogsCount:  todayIntake.alcoholLogs.count,
            mealSamplesCount:  healthKit.todayMealSamples.count,
            waterSamplesCount: healthKit.todayWaterSamples.count,
            mealSlotHash: {
                let s = healthKit.todayMealCalBySlot
                return Int(s.breakfast) ^ (Int(s.lunch) << 8) ^ (Int(s.snack) << 16) ^ (Int(s.dinner) << 24)
            }(),
            onHistoryVersionChange: {
                // フォトログのHK保存完了後: HKデータを先に再取得してから合計を再計算
                Task { await loadData(); recomputePhotoLogTotals(); rebuildFoodHistory() }
            },
            onFoodHistoryChange: { rebuildFoodHistory() },
            onForeground: {
                Task { await loadData() }
                recomputePhotoLogTotals()
                rebuildFoodHistory()
            }
        ))
        .modifier(FoodViewSheets(
            showPhotoLog: $showPhotoLog,
            showDetailLog: $showDetailLog,
            authManager: authManager,
            showIntakeSettings: $showIntakeSettings,
            swipeFoodItems: $swipeFoodItems,
            swipeFoodStart: $swipeFoodStart,
            showPlusView: $showPlusViewFromFood,
            confirmMessage: confirmMessage,
            showIntakeConfirm: $showIntakeConfirm,
            onConfirm: { pendingIntakeAction?(); pendingIntakeAction = nil },
            onCancel: { pendingIntakeAction = nil }
        ))
    }

    // MARK: - Header

    private var foodHeader: some View {
        // キャッシュ済み集計を参照（onChange で photoLogManager.history 変化時のみ再計算）
        let prot = healthKit.todayIntakeProtein + cachedPhotoLogTotals.protein
        let fat_ = healthKit.todayIntakeFat + cachedPhotoLogTotals.fat
        let carb = healthKit.todayIntakeCarbs + cachedPhotoLogTotals.carbs
        let totalIntakeCal = Int(healthKit.todayIntakeCalories) + cachedPhotoLogTotals.calories
        let calDiff = totalIntakeCal - Int(healthKit.todayActiveCalories + healthKit.todayRestingCalories)
        let waterMl = Int(healthKit.todayIntakeWater)
        let foodGoalDone = dailyFixedGoals.foodEnabled && totalIntakeCal >= 2000
        let sign = calDiff >= 0 ? "+" : ""
        return ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.0), Color(red: 0.85, green: 0.25, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
            HStack(spacing: 0) {
                Text("FOOD")
                    .font(.system(size: 8 * UIScale.font, weight: .black))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .fixedSize()
                Spacer(minLength: 8)
                PFCMiniRingView(
                    proteinKcal: prot * 4,
                    fatKcal: fat_ * 9,
                    carbsKcal: carb * 4,
                    diameter: 26,
                    lineWidth: 4.5,
                    centerText: pfcAnalysis.map { "\($0.score)" },
                    centerTextColor: Color.white
                )
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("💧").font(.system(size: 15 * UIScale.font))
                    Text(waterMl > 0 ? "\(waterMl)" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("🍽️").font(.system(size: 15 * UIScale.font))
                    Text(totalIntakeCal > 0 ? "\(totalIntakeCal)" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(foodGoalDone ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                }
                .fixedSize()
                Spacer(minLength: 6)
                HStack(spacing: 2) {
                    Text("⚡").font(.system(size: 15 * UIScale.font))
                    Text(totalIntakeCal > 0 ? "\(sign)\(calDiff)" : "—")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(calDiff > 200 ? Color(red: 1.0, green: 0.95, blue: 0.5) : .white)
                        .lineLimit(1)
                    if totalIntakeCal > 0 {
                        Text("cal").font(.system(size: 10 * UIScale.font)).foregroundColor(.white.opacity(0.7))
                    }
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

    // MARK: - 栄養サマリーカード（PFC・水分・アドバイス・食事履歴）

    /// 今日の食事カロリーを朝食/ランチ/スナック/夕食に分類して返す。
    /// foodHistoryCache.meals（食事履歴）のタイムスタンプを使って時間帯ごとに積算する。
    /// 時間帯: 朝食 0〜9時, ランチ 10〜13時, スナック 14〜17時, 夕食 18〜23時（深夜0〜4時は朝食へ）
    private var todayMealBreakdown: [(emoji: String, label: String, kcal: Int, color: Color)] {
        let cal = Calendar.current
        var breakfast = 0, lunch = 0, snack = 0, dinner = 0
        for entry in foodHistoryCache.meals {
            let h = cal.component(.hour, from: entry.time)
            switch h {
            case 0..<5:   breakfast += entry.kcal   // 深夜は朝食バケツへ
            case 5..<10:  breakfast += entry.kcal
            case 10..<14: lunch     += entry.kcal
            case 14..<18: snack     += entry.kcal
            default:      dinner    += entry.kcal
            }
        }
        return [
            ("🌅", "朝食",     breakfast, Color.duoOrange),
            ("☀️", "ランチ",   lunch,     Color(hex: "#58CC02")),
            ("🍎", "スナック", snack,     Color(hex: "#A78BFA")),
            ("🌙", "夕食",     dinner,    Color(hex: "#1CB0F6")),
        ]
    }

    // MARK: - 食事スライドエントリ（クイック・フォト・HK 統合）

    struct MealSlideEntry: Identifiable {
        let id: String
        let emoji: String
        let name: String
        let time: Date
        let image: UIImage?
        let calories: Int
        let protein: Double
        let fat: Double
        let carbs: Double
        let sugar: Double
        let sodium: Double
        let source: String  // "クイック" | "フォト" | "HealthKit"
        var photoLogItem: PhotoLogHistoryItem? = nil  // フォトログ由来の場合に原本を保持

        var slotLabel: String {
            let h = Calendar.current.component(.hour, from: time)
            switch h {
            case 0..<10: return "朝食"
            case 10..<14: return "ランチ"
            case 14..<18: return "スナック"
            default:      return "夕食"
            }
        }
        var slotEmoji: String {
            switch slotLabel {
            case "朝食":   return "🌅"
            case "ランチ": return "☀️"
            case "スナック": return "🍎"
            default:       return "🌙"
            }
        }
    }

    private var todayMealSlideEntries: [MealSlideEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var entries: [MealSlideEntry] = []

        // 1. Firestoreクイックミール
        let fsTimes = todayIntake.meals.map { $0.timestamp }
        for meal in todayIntake.meals {
            let nutr = intakeGoals.nutritionFor(mealType: meal.mealType)
            entries.append(MealSlideEntry(
                id: meal.id.uuidString,
                emoji: meal.mealType.emoji,
                name: meal.mealType.displayName,
                time: meal.timestamp,
                image: nil,
                calories: meal.calories,
                protein: nutr.protein,
                fat: nutr.fat,
                carbs: nutr.carbs,
                sugar: nutr.sugar,
                sodium: nutr.sodium,
                source: "クイック"
            ))
        }

        // 2. フォトログ
        let photoToday = photoLogManager.history.filter { cal.startOfDay(for: $0.timestamp) == today }
        let photoTimes = photoToday.map { $0.timestamp }
        for item in photoToday {
            let isDup = fsTimes.contains { abs($0.timeIntervalSince(item.timestamp)) < 300 }
            if isDup { continue }
            let n = item.analyzedNutrition
            entries.append(MealSlideEntry(
                id: item.id,
                emoji: "📸",
                name: item.displayName,
                time: item.timestamp,
                image: item.thumbnail,
                calories: n.calories,
                protein: n.protein,
                fat: n.fat,
                carbs: n.carbs,
                sugar: n.sugar,
                sodium: n.sodium,
                source: "フォト",
                photoLogItem: item  // 詳細シートで PhotoFeedDetailSheet と統一するために保持
            ))
        }

        // 3. HKサンプル（重複なし）
        let usedTimes = fsTimes + photoTimes
        for sample in healthKit.todayMealSamples {
            let isDup = usedTimes.contains { abs($0.timeIntervalSince(sample.startDate)) < 300 }
            if isDup { continue }
            entries.append(MealSlideEntry(
                id: UUID().uuidString,
                emoji: "🍽️",
                name: "食事",
                time: sample.startDate,
                image: nil,
                calories: Int(sample.value),
                protein: 0,
                fat: 0,
                carbs: 0,
                sugar: 0,
                sodium: 0,
                source: "HealthKit"
            ))
        }

        return entries.sorted { $0.time < $1.time }
    }

    private var nutritionSummaryCard: some View {
        VStack(spacing: 0) {
            // ── 食事時間帯別カロリー（今日の食事：最上部）─────────────────
            mealTimeCalorieSection
            Divider().padding(.horizontal, 12)

            // ── PFCバランス（Plus のみ・食事の下）──────────────────────────
            if plus.isPlus {
                if let analysis = pfcAnalysis, analysis.score > 0 {
                    pfcBalanceCard(analysis)
                } else {
                    noPFCDataCard
                }
                Divider().padding(.horizontal, 12)
            }

            // ── 水分・カフェイン・アルコール ────────────────────────────
            hydrationRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // ── クイックログパネル（タップで展開） ─────────────────────
            hydrationQuickLogPanel

            // ── 改善ポイント（Plus のみ） ────────────────────────────────
            if plus.isPlus {
                adviceInlineSection
            }

            Divider().padding(.horizontal, 12)

            // ── 食事履歴 ────────────────────────────────────────────────
            foodHistorySection
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    // MARK: - 食事スライドシート（クイック・フォト・HK 統合）
    struct PhotoMealCarouselSheet: View {
        let allEntries: [MealSlideEntry]
        let filterSlot: String?         // nil=全件, "朝食"/"ランチ"/"スナック"/"夕食"
        @Environment(\.dismiss) private var dismiss

        private static let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
        }()

        private var displayEntries: [MealSlideEntry] {
            guard let slot = filterSlot else { return allEntries }
            return allEntries.filter { $0.slotLabel == slot }
        }

        private var sheetTitle: String {
            if let slot = filterSlot { return "\(slot)の食事 \(displayEntries.count)件" }
            return "今日の食事 \(displayEntries.count)件"
        }

        var body: some View {
            NavigationView {
                Group {
                    if displayEntries.isEmpty {
                        VStack(spacing: 16) {
                            Text("🍽️").font(.system(size: 48))
                            Text("この時間帯の記録はありません")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TabView {
                            ForEach(displayEntries) { entry in
                                Group {
                                    if let photoItem = entry.photoLogItem {
                                        // フォトログ由来 → TOMO と共通の PhotoFeedDetailSheet を埋め込み
                                        PhotoFeedDetailSheet(item: photoItem, embedded: true)
                                    } else {
                                        // クイックログ / HealthKit 由来 → シンプル表示
                                        ScrollView {
                                            VStack(spacing: 0) {
                                                // ── 画像 or 絵文字アイコン ────────────────
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [Color.duoOrange.opacity(0.12), Color.duoOrange.opacity(0.04)],
                                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                                            )
                                                        )
                                                    VStack(spacing: 6) {
                                                        Text(entry.emoji).font(.system(size: 80))
                                                        Text(entry.name)
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundColor(Color.duoDark)
                                                            .multilineTextAlignment(.center)
                                                            .padding(.horizontal, 16)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 200)
                                                .padding(.horizontal, 16)
                                                .padding(.top, 10)

                                                // ── 時間帯ヘッダー ────────────────────
                                                HStack(spacing: 10) {
                                                    Text(entry.slotEmoji).font(.system(size: 28))
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(entry.slotLabel)
                                                            .font(.system(size: 22, weight: .black))
                                                            .foregroundColor(Color.duoOrange)
                                                        Text(Self.timeFmt.string(from: entry.time))
                                                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                                                            .foregroundColor(Color.duoOrange.opacity(0.75))
                                                    }
                                                    Spacer()
                                                    Text(entry.source)
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.secondary)
                                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                                        .background(Color(.systemGray5))
                                                        .clipShape(Capsule())
                                                }
                                                .padding(.horizontal, 20)
                                                .padding(.top, 14)
                                                .padding(.bottom, 4)

                                                // ── カロリー大表示 ────────────────────
                                                if entry.calories > 0 {
                                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                                        Text("🔥").font(.system(size: 26))
                                                        Text("\(entry.calories)")
                                                            .font(.system(size: 44, weight: .black, design: .rounded))
                                                            .foregroundColor(Color.duoOrange)
                                                        Text("kcal")
                                                            .font(.system(size: 18, weight: .bold))
                                                            .foregroundColor(Color.duoOrange.opacity(0.75))
                                                            .padding(.bottom, 4)
                                                    }
                                                    .padding(.vertical, 10)
                                                    .frame(maxWidth: .infinity)
                                                    .background(Color.duoOrange.opacity(0.06))
                                                    .cornerRadius(16)
                                                    .padding(.horizontal, 16)
                                                }

                                                // ── P/F/C チップ ──────────────────────
                                                if entry.protein > 0 || entry.fat > 0 || entry.carbs > 0 {
                                                    HStack(spacing: 10) {
                                                        MacroChip(label: "P タンパク質", value: String(format: "%.1fg", entry.protein), color: Color.duoRed)
                                                        MacroChip(label: "F 脂質",       value: String(format: "%.1fg", entry.fat),     color: Color(hex: "#F5A623"))
                                                        MacroChip(label: "C 炭水化物",   value: String(format: "%.1fg", entry.carbs),   color: Color(hex: "#58CC02"))
                                                    }
                                                    .padding(.horizontal, 16)
                                                    .padding(.top, 10)
                                                }

                                                if entry.sugar > 0 || entry.sodium > 0 {
                                                    HStack(spacing: 10) {
                                                        if entry.sugar > 0 {
                                                            MacroChip(label: "🍬 糖質", value: String(format: "%.1fg", entry.sugar), color: Color(hex: "#A78BFA"))
                                                        }
                                                        if entry.sodium > 0 {
                                                            MacroChip(label: "🧂 塩分", value: String(format: "%.2fg", entry.sodium), color: Color(hex: "#1CB0F6"))
                                                        }
                                                    }
                                                    .padding(.horizontal, 16)
                                                    .padding(.top, 6)
                                                }

                                                Spacer(minLength: 32)
                                            }
                                        }
                                    }
                                }
                                .tag(entry.id)
                            }
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                    }
                }
                .navigationTitle(sheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
            }
        }

    }

    // MARK: - 食事記録カード（フォトログ＋クイックログ＋詳細ログ）

    private var mealRecordCard: some View {
        VStack(spacing: 0) {
            // ── 食事フォトログ ────────────────────────────────────────────
            Button { plus.isPlus ? (showPhotoLog = true) : (showPlusViewFromFood = true) } label: {
                let recentPhotos = photoLogManager.history.prefix(3).compactMap { $0.smallThumbnail }
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                            )
                            .frame(width: 76, height: 76)
                        if recentPhotos.isEmpty {
                            VStack(spacing: 3) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30 * UIScale.font, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("AI")
                                    .font(.system(size: 10 * UIScale.font, weight: .black))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                        } else {
                            Image(uiImage: recentPhotos[0])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("📸 AI食事フォトログ")
                            .font(.system(size: 18 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if recentPhotos.isEmpty {
                            Text("写真を撮ってAIカロリー計算")
                                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(Array(recentPhotos.dropFirst().enumerated()), id: \.offset) { _, img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                Text("最近の記録 \(photoLogManager.history.count)件")
                                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 20 * UIScale.font, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .background(
                    Color.instagramGradient
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.84, green: 0.16, blue: 0.46).opacity(0.35), radius: 10, x: 0, y: 5)
                .overlay(alignment: .topTrailing) {
                    if !plus.isPlus {
                        HStack(spacing: 3) {
                            Text("+")
                                .font(.system(size: 9 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(Color.duoGold)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text("Plus限定")
                                .font(.system(size: 10 * UIScale.font, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                        .padding(.top, 8).padding(.trailing, 20)
                    }
                }
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)

            // ── クイックログ ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Spacer().frame(height: 4)

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

                // 行2: カツカレー・スナック・栄養バー
                HStack(spacing: 8) {
                    quickBtn(emoji: "🍛", label: "カツカレー", color: Color.duoOrange) {
                        confirm("カツカレー 1000kcal を記録しますか？") {
                            Task {
                                await authManager.recordCustomMeal(
                                    name: "カツカレー",
                                    mealType: .lunch,
                                    nutrition: FoodView.katsuCurryNutrition
                                )
                                await updateSlotForMeal(calories: FoodView.katsuCurryNutrition.calories)
                                await loadData()
                            }
                        }
                    }
                    quickBtn(emoji: "🍫", label: "スナック", color: Color.duoOrange) {
                        confirm("スナック \(intakeGoals.caloriesFor(mealType: .snack))kcal を記録しますか？") {
                            Task {
                                await authManager.recordMeal(mealType: .snack)
                                await updateSlotForMeal(calories: intakeGoals.caloriesFor(mealType: .snack))
                                await loadData()
                            }
                        }
                    }
                    quickBtn(emoji: "🍪", label: "栄養バー", color: Color.duoOrange) {
                        confirm("栄養バー 100kcal を記録しますか？") {
                            Task {
                                await authManager.recordCustomMeal(
                                    name: "栄養バー",
                                    mealType: .snack,
                                    nutrition: FoodView.nutritionBarNutrition
                                )
                                await updateSlotForMeal(calories: FoodView.nutritionBarNutrition.calories)
                                await loadData()
                            }
                        }
                    }
                }

                // ── 飲料ログ展開ボタン ──────────────────────────────────────
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDrinkRows.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showDrinkRows ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoBlue)
                        Text(showDrinkRows ? "飲料ログを隠す" : "飲料ログを追加")
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoBlue)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("💧☕🥤🍺")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.duoBlue.opacity(0.07))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                if showDrinkRows {
                    // 行2b: 水・コーヒー・フルーツジュース
                    HStack(spacing: 8) {
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
                                    await healthKit.saveWaterIntake(amountMl: Double(intakeGoals.coffeePerCup), timestamp: Date())
                                    await updateSlotForDrink(ml: intakeGoals.coffeePerCup)
                                    await loadData()
                                }
                            }
                        }
                        quickBtn(emoji: "🍊", label: "フルーツジュース", color: Color(hex: "#FF9600")) {
                            confirm("フルーツジュース 200ml (76kcal / 糖質18g) を記録しますか？") {
                                Task {
                                    await authManager.recordFruitJuice()
                                    await updateSlotForDrink(ml: 200)
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
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.beer.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.beer.amountMl)
                                    await loadData()
                                }
                            }
                        }
                        quickBtn(emoji: "🍷", label: "ワイン", color: Color.duoPurple) {
                            confirm("ワイン (アルコール \(String(format: "%.1f", AlcoholType.wine.alcoholG))g) を記録しますか？") {
                                Task {
                                    await authManager.recordAlcohol(alcoholType: .wine)
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.wine.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.wine.amountMl)
                                    await loadData()
                                }
                            }
                        }
                        quickBtn(emoji: "🍶", label: "焼酎", color: Color.duoPurple) {
                            confirm("焼酎・酎ハイ (アルコール \(String(format: "%.1f", AlcoholType.chuhai.alcoholG))g) を記録しますか？") {
                                Task {
                                    await authManager.recordAlcohol(alcoholType: .chuhai)
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.chuhai.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.chuhai.amountMl)
                                    await loadData()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            // ── 詳細ログ ────────────────────────────────────────────────
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 10)

            Button { showDetailLog = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoGreen)
                    Text("詳細ログ")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoGreen)
                    Text("食事・ドリンクを詳しく登録")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    private func quickBtn(emoji: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(emoji).font(.system(size: 22 * UIScale.font))
                Text(label)
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
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

    // MARK: - 食事時間帯別カロリーバー

    private var mealTimeCalorieSection: some View {
        let breakdown = todayMealBreakdown
        let maxKcal = max(breakdown.map(\.kcal).max() ?? 1, 1)
        let totalKcal = breakdown.reduce(0) { $0 + $1.kcal }
        let slideEntries = todayMealSlideEntries
        let hasEntries = !slideEntries.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            // ── ヘッダー（全件スライドを開く）───────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoOrange)
                Button {
                    if hasEntries {
                        mealSlideFilter = nil
                        showPhotoCarousel = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("今日の食事")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoDark)
                        if hasEntries {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 10 * UIScale.font))
                                .foregroundColor(Color.duoOrange.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                if totalKcal > 0 {
                    HStack(spacing: 2) {
                        Text("🔥").font(.system(size: 9 * UIScale.font))
                        Text("\(totalKcal)")
                            .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("kcal")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(.white.opacity(0.88))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.duoOrange).clipShape(Capsule())
                }
                Button { showIntakeSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoOrange)
                        .padding(6)
                        .background(Color.duoOrange.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // ── 時間帯内訳行（タップで該当スロットのスライド表示）──────
            ForEach(breakdown, id: \.label) { meal in
                let slotKey = meal.label  // "朝食" | "ランチ" | "スナック" | "夕食"
                let slotCount = slideEntries.filter { $0.slotLabel == slotKey }.count
                Button {
                    if slotCount > 0 {
                        mealSlideFilter = slotKey
                        showPhotoCarousel = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(meal.emoji)
                            .font(.system(size: 13))
                            .frame(width: 20)
                        Text(meal.label)
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoDark)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(meal.color.opacity(0.12)).frame(height: 10)
                                let ratio = meal.kcal > 0 ? CGFloat(meal.kcal) / CGFloat(maxKcal) : 0
                                Capsule().fill(meal.color)
                                    .frame(width: max(0, geo.size.width * ratio), height: 10)
                            }
                        }
                        .frame(height: 10)
                        Text(meal.kcal > 0 ? "\(meal.kcal)" : "—")
                            .font(.system(size: 11 * UIScale.font, weight: .bold, design: .rounded))
                            .foregroundColor(meal.kcal > 0 ? meal.color : Color.duoSubtitle)
                            .frame(width: 42, alignment: .trailing)
                        Text("kcal")
                            .font(.system(size: 8 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        if slotCount > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8 * UIScale.font, weight: .semibold))
                                .foregroundColor(meal.color.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(slotCount == 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .sheet(isPresented: $showPhotoCarousel) {
            PhotoMealCarouselSheet(allEntries: todayMealSlideEntries, filterSlot: mealSlideFilter)
        }
    }

    // MARK: - PFC Balance Card

    private func pfcBalanceCard(_ analysis: PFCBalanceAnalysis) -> some View {
        Button {
            mealSlideFilter = nil
            showPhotoCarousel = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    PFCPieChart(proteinPercent: analysis.proteinPercent,
                                fatPercent: analysis.fatPercent,
                                carbsPercent: analysis.carbsPercent)
                    .frame(width: 80, height: 80)
                    VStack(spacing: 0) {
                        Text("\(analysis.score)")
                            .font(.system(size: 22 * UIScale.font, weight: .black))
                            .foregroundColor(pfcScoreColor(analysis.score))
                        Text("点").font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    pfcRow(color: Color.duoOrange, label: "P", name: "たんぱく質", percent: analysis.proteinPercent, grams: analysis.proteinGrams, target: 15)
                    pfcRow(color: Color.duoPurple, label: "F", name: "脂質",       percent: analysis.fatPercent,     grams: analysis.fatGrams,     target: 25)
                    pfcRow(color: Color.duoBlue,   label: "C", name: "炭水化物",   percent: analysis.carbsPercent,   grams: analysis.carbsGrams,   target: 60)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle.opacity(0.5))
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .disabled(todayMealSlideEntries.isEmpty)
    }

    private func pfcRow(color: Color, label: String, name: String, percent: Double, grams: Double, target: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11 * UIScale.font, weight: .bold)).foregroundColor(Color.duoDark)
            Text("\(name)(目標\(target)%)")
                .font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
            Spacer()
            Text(String(format: "%.0f%%", percent)).font(.system(size: 11 * UIScale.font, weight: .bold)).foregroundColor(color)
            Text(String(format: "%.0fg", grams)).font(.system(size: 9 * UIScale.font)).foregroundColor(Color.duoSubtitle)
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

    private var adviceCard: some View {
        // 記録促進メッセージを除外し、実際に改善が必要な項目のみ表示
        let tips = buildTips(pfcAnalysis).filter { $0.emoji != "📝" && $0.emoji != "🍽️" }
        return Group {
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tips, id: \.message) { tip in
                            HStack(spacing: 6) {
                                Text(tip.emoji).font(.system(size: 13 * UIScale.font))
                                Text(tip.title)
                                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                                    .foregroundColor(tip.color)
                                Text("— \(tip.message)")
                                    .font(.system(size: 10 * UIScale.font))
                                    .foregroundColor(Color.duoDark.opacity(0.6))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
            }
        }
    }

    private struct FoodTip {
        let emoji: String; let title: String; let message: String; let color: Color
    }

    private func buildTips(_ a: PFCBalanceAnalysis?) -> [FoodTip] {
        let waterGoal     = intakeGoals.dailyWaterGoal
        let waterMl       = todayIntake.totalWaterMl
        let caffeineMg    = todayIntake.totalCaffeineMg
        let caffeineLimit = intakeGoals.dailyCaffeineLimit
        let alcoholG      = todayIntake.totalAlcoholG
        let alcoholLimit  = intakeGoals.dailyAlcoholLimit

        let hasFoodData  = (a?.score ?? 0) > 0
        let hasDrinkData = waterMl > 0 || caffeineMg > 0 || alcoholG > 0

        // 何も記録されていない → 促進メッセージのみ
        if !hasFoodData && !hasDrinkData {
            return [FoodTip(emoji: "📝", title: "食事・ドリンクを記録しよう",
                message: "フォトログやクイックログから記録すると、栄養バランスのアドバイスが届きます。",
                color: Color.duoGreen)]
        }

        var tips: [FoodTip] = []

        // ── PFC不均衡のある場合のみ表示 ───────────────────────────
        if let a = a {
            if a.proteinPercent < 12 {
                tips.append(FoodTip(emoji: "🥩", title: "たんぱく質が少なめ",
                    message: "卵・鶏むね・納豆などを追加しよう",
                    color: Color.duoOrange))
            } else if a.proteinPercent > 25 {
                tips.append(FoodTip(emoji: "🥩", title: "たんぱく質が多め",
                    message: "他の栄養素とのバランスを意識して",
                    color: Color.duoOrange))
            }
            if a.fatPercent > 35 {
                tips.append(FoodTip(emoji: "🛢️", title: "脂質が多め",
                    message: "揚げ物を控え、青魚・ナッツを選ぼう",
                    color: Color.duoPurple))
            } else if a.fatPercent < 15 {
                tips.append(FoodTip(emoji: "🥑", title: "脂質が少なめ",
                    message: "オリーブオイルやアボカドを少量加えて",
                    color: Color.duoPurple))
            }
            if a.carbsPercent > 70 {
                tips.append(FoodTip(emoji: "🍚", title: "炭水化物が多め",
                    message: "主食を少し減らし、野菜・タンパク質を増やして",
                    color: Color.duoBlue))
            } else if a.carbsPercent < 40 {
                tips.append(FoodTip(emoji: "🍚", title: "炭水化物が少なめ",
                    message: "玄米や全粒パンなどで補給しよう",
                    color: Color.duoBlue))
            }
            // バランス良好なら何も表示しない
        }

        // ── 水分が50%未満のときのみ警告 ──────────────────────────
        if waterGoal > 0 {
            let pct = Int(min(Double(waterMl) / Double(waterGoal) * 100, 100))
            if pct < 50 {
                let remaining = waterGoal - waterMl
                tips.append(FoodTip(emoji: "💧", title: "水分が足りていません",
                    message: "あと \(remaining)ml 補給しよう（現在 \(pct)%）",
                    color: Color(red: 0.2, green: 0.6, blue: 1.0)))
            }
        }

        // ── カフェイン過多（70%以上）のみ警告 ────────────────────
        if caffeineMg > 0 && caffeineLimit > 0 {
            let pct = Int(Double(caffeineMg) / Double(caffeineLimit) * 100)
            if pct >= 100 {
                tips.append(FoodTip(emoji: "☕", title: "カフェイン上限超過",
                    message: "\(caffeineMg)mg 摂取。これ以上は控えて",
                    color: .red))
            } else if pct >= 70 {
                tips.append(FoodTip(emoji: "☕", title: "カフェインが多め",
                    message: "上限の \(pct)%。午後のコーヒーは控えめに",
                    color: Color.duoOrange))
            }
        }

        // ── アルコール過多（70%以上）のみ警告 ────────────────────
        if alcoholG > 0 && alcoholLimit > 0 {
            let pct = Int(alcoholG / alcoholLimit * 100)
            if pct >= 100 {
                tips.append(FoodTip(emoji: "🍷", title: "アルコール上限超過",
                    message: String(format: "%.0fg 摂取。水分補給を忘れずに", alcoholG),
                    color: .red))
            } else if pct >= 70 {
                tips.append(FoodTip(emoji: "🍷", title: "飲みすぎ注意",
                    message: String(format: "%.0fg（上限の %d%%）。お水も飲もう", alcoholG, pct),
                    color: Color.duoPurple))
            }
        }

        // ドリンクのみ記録・食事未記録 → 食事記録を促す
        if !hasFoodData && hasDrinkData {
            tips.append(FoodTip(emoji: "🍽️", title: "食事も記録しよう",
                message: "PFCバランスのアドバイスが表示されます",
                color: Color.duoSubtitle))
        }

        return tips
    }

    // MARK: - 食事履歴

    private struct HistoryEntry: Identifiable {
        let id = UUID()
        let emoji: String
        let primary: String
        let detail: String
        let sub: String    // source tag (クイック / フォト / Watch / etc.)
        let time: Date
        var kcal: Int = 0  // 時間帯別集計用
    }

    // V4: body 外で食事履歴を再構築する（filter/map/sorted を毎描画で実行しない）
    private func rebuildFoodHistory() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let quickMeals: [HistoryEntry] = todayIntake.meals.map {
            HistoryEntry(emoji: $0.mealType.emoji, primary: $0.mealType.displayName,
                detail: "\($0.calories)kcal", sub: "クイック", time: $0.timestamp,
                kcal: $0.calories)
        }
        let firestoreTimestamps = todayIntake.meals.map { $0.timestamp }

        let rawPhotoItems = photoLogManager.history
            .filter { calendar.startOfDay(for: $0.timestamp) == today }
        let photoMeals: [HistoryEntry] = rawPhotoItems
            .filter { item in
                !firestoreTimestamps.contains { abs($0.timeIntervalSince(item.timestamp)) < 300 }
            }
            .map { HistoryEntry(emoji: "📸", primary: $0.displayName,
                detail: "\($0.calories)kcal", sub: "フォト", time: $0.timestamp,
                kcal: $0.calories) }
        let photoTimestamps = rawPhotoItems.map { $0.timestamp }

        let usedTimestamps = firestoreTimestamps + photoTimestamps
        let hkExtraMeals: [HistoryEntry] = healthKit.todayMealSamples
            .filter { sample in
                !usedTimestamps.contains { abs($0.timeIntervalSince(sample.startDate)) < 300 }
            }
            .map { HistoryEntry(emoji: "🍽️", primary: "食事",
                detail: "\(Int($0.value)) kcal", sub: "クイック", time: $0.startDate,
                kcal: Int($0.value)) }

        let allMeals = (quickMeals + photoMeals + hkExtraMeals).sorted { $0.time < $1.time }

        let waterFsTimestamps = todayIntake.waterLogs.map { $0.timestamp }
        let waterFirestore: [HistoryEntry] = todayIntake.waterLogs.map {
            HistoryEntry(emoji: "💧", primary: "水", detail: "\($0.amountMl)ml", sub: "クイック", time: $0.timestamp)
        }
        let waterHKExtra: [HistoryEntry] = healthKit.todayWaterSamples
            .filter { sample in
                !waterFsTimestamps.contains { abs($0.timeIntervalSince(sample.startDate)) < 300 }
            }
            .map { HistoryEntry(emoji: "💧", primary: "水",
                detail: "\(Int($0.value))ml", sub: "HK", time: $0.startDate) }

        let coffeeEntries: [HistoryEntry] = todayIntake.coffeeLogs
            .sorted { $0.timestamp < $1.timestamp }
            .map { HistoryEntry(emoji: "☕", primary: "コーヒー",
                detail: "\($0.amountMl)ml · カフェイン\($0.caffeineMg)mg", sub: "クイック", time: $0.timestamp) }

        let alcoholEntries: [HistoryEntry] = todayIntake.alcoholLogs
            .sorted { $0.timestamp < $1.timestamp }
            .map { HistoryEntry(emoji: $0.alcoholType.emoji, primary: $0.alcoholType.displayName,
                detail: "\($0.amountMl)ml · 純アルコール\(String(format: "%.1f", $0.alcoholG))g",
                sub: "クイック", time: $0.timestamp) }

        foodHistoryCache = FoodHistoryCache(
            meals: allMeals,
            water: (waterFirestore + waterHKExtra).sorted { $0.time < $1.time },
            coffee: coffeeEntries,
            alcohol: alcoholEntries
        )
    }

    private var foodHistorySection: some View {
        // V4: キャッシュ済みデータを参照（body 評価ごとに filter/map/sorted を実行しない）
        let allMeals     = foodHistoryCache.meals
        let waterEntries = foodHistoryCache.water
        let coffeeEntries = foodHistoryCache.coffee
        let alcoholEntries = foodHistoryCache.alcohol
        let totalCount   = foodHistoryCache.totalCount

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFoodHistory.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                    Text("今日の食事履歴")
                        .font(.system(size: 13 * UIScale.font, weight: .bold))
                        .foregroundColor(Color.duoDark)
                    Spacer()
                    if totalCount > 0 {
                        Text("\(totalCount)件")
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                    Image(systemName: showFoodHistory ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showFoodHistory {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    if totalCount == 0 {
                        Text("今日の記録はまだありません")
                            .font(.system(size: 12 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        if !allMeals.isEmpty {
                            foodHistoryCategoryHeader(title: "食事", icon: "fork.knife.circle.fill",
                                color: Color(red: 1.0, green: 0.45, blue: 0.0))
                            ForEach(allMeals) { e in historyEntryRow(e) }
                        }
                        let allDrinks = (waterEntries + coffeeEntries + alcoholEntries)
                            .sorted { $0.time < $1.time }
                        if !allDrinks.isEmpty {
                            foodHistoryCategoryHeader(title: "飲料", icon: "drop.fill", color: Color.duoBlue)
                            ForEach(allDrinks) { e in historyEntryRow(e) }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func historyEntryRow(_ e: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            Text(e.emoji).font(.system(size: 14 * UIScale.font))
            VStack(alignment: .leading, spacing: 1) {
                Text(e.primary)
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark)
                Text(e.detail)
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatTime(e.time))
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle.opacity(0.7))
                Text(e.sub)
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func foodHistoryCategoryHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10 * UIScale.font)).foregroundColor(color)
            Text(title).font(.system(size: 10 * UIScale.font, weight: .bold)).foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func formatTime(_ date: Date) -> String {
        FoodView.hhmm.string(from: date)
    }

    // MARK: - No Data

    private var noPFCDataCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 36 * UIScale.font))
                .foregroundColor(Color.duoSubtitle.opacity(0.4))
            Text("食事記録がありません")
                .font(.system(size: 14 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
            Text("下のボタンから食事を記録すると\nPFCバランスとアドバイスが表示されます")
                .font(.system(size: 11 * UIScale.font))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Water / Caffeine / Alcohol

    private var hydrationRow: some View {
        HStack(spacing: 6) {
            intakeItemCard(icon: "drop.fill", iconColor: Color.duoBlue,
                label: "水分", value: Double(todayIntake.totalWaterMl),
                goal: Double(intakeGoals.dailyWaterGoal), unit: "ml",
                formatValue: { "\(Int($0))" }, isReverse: false,
                isSelected: hydrationQuickType == "水分") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hydrationQuickType = hydrationQuickType == "水分" ? nil : "水分"
                    }
                }
            intakeItemCard(icon: "cup.and.saucer.fill", iconColor: Color(hex: "#8B5E3C"),
                label: "カフェイン", value: Double(todayIntake.totalCaffeineMg),
                goal: Double(intakeGoals.dailyCaffeineLimit), unit: "mg",
                formatValue: { "\(Int($0))" }, isReverse: true,
                isSelected: hydrationQuickType == "カフェイン") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hydrationQuickType = hydrationQuickType == "カフェイン" ? nil : "カフェイン"
                    }
                }
            intakeItemCard(icon: "wineglass.fill", iconColor: Color.duoPurple,
                label: "アルコール", value: todayIntake.totalAlcoholG,
                goal: intakeGoals.dailyAlcoholLimit, unit: "g",
                formatValue: { String(format: "%.1f", $0) }, isReverse: true,
                isSelected: hydrationQuickType == "アルコール") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hydrationQuickType = hydrationQuickType == "アルコール" ? nil : "アルコール"
                    }
                }
        }
    }

    // ── クイックログパネル ──────────────────────────────────────────────
    @ViewBuilder
    private var hydrationQuickLogPanel: some View {
        if let type = hydrationQuickType {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if type == "水分" {
                        hydrationQuickBtn(emoji: "💧", label: "水", sub: "\(intakeGoals.waterPerCup)ml") {
                            confirm("水 \(intakeGoals.waterPerCup)ml を記録しますか？") {
                                Task {
                                    await authManager.recordWater()
                                    await updateSlotForDrink(ml: intakeGoals.waterPerCup)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "🍊", label: "フルーツジュース", sub: "200ml・76kcal") {
                            confirm("フルーツジュース 200ml (76kcal / 糖質18g) を記録しますか？") {
                                Task {
                                    await authManager.recordFruitJuice()
                                    await updateSlotForDrink(ml: 200)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "🥤", label: "スポーツ飲料300ml", sub: "72kcal・糖21g・塩0.3g") {
                            confirm("スポーツ飲料 300ml (72kcal / 糖質21g / ナトリウム360mg) を記録しますか？") {
                                Task {
                                    await authManager.recordSportsDrink()
                                    await updateSlotForDrink(ml: 300)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                    } else if type == "カフェイン" {
                        hydrationQuickBtn(emoji: "☕", label: "コーヒー", sub: "\(intakeGoals.caffeinePerCup)mg") {
                            confirm("コーヒー \(intakeGoals.coffeePerCup)ml (カフェイン \(intakeGoals.caffeinePerCup)mg) を記録しますか？") {
                                Task {
                                    await authManager.recordCoffee()
                                    await healthKit.saveWaterIntake(amountMl: Double(intakeGoals.coffeePerCup), timestamp: Date())
                                    await updateSlotForDrink(ml: intakeGoals.coffeePerCup)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "☕", label: "エスプレッソダブル", sub: "120mg") {
                            confirm("エスプレッソダブル 30ml (カフェイン 120mg) を記録しますか？") {
                                Task {
                                    await authManager.recordEspresso()
                                    await updateSlotForDrink(ml: 30)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "🍵", label: "緑茶150ml", sub: "30mg") {
                            confirm("緑茶 150ml (カフェイン 30mg) を記録しますか？") {
                                Task {
                                    await authManager.recordGreenTea()
                                    await updateSlotForDrink(ml: 150)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                    } else if type == "アルコール" {
                        hydrationQuickBtn(emoji: "🍺", label: "ビール",
                            sub: String(format: "%.1fg", AlcoholType.beer.alcoholG)) {
                            confirm("ビール (アルコール \(String(format: "%.1f", AlcoholType.beer.alcoholG))g) を記録しますか？") {
                                Task {
                                    await authManager.recordAlcohol(alcoholType: .beer)
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.beer.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.beer.amountMl)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "🍷", label: "ワイン",
                            sub: String(format: "%.1fg", AlcoholType.wine.alcoholG)) {
                            confirm("ワイン (アルコール \(String(format: "%.1f", AlcoholType.wine.alcoholG))g) を記録しますか？") {
                                Task {
                                    await authManager.recordAlcohol(alcoholType: .wine)
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.wine.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.wine.amountMl)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                        hydrationQuickBtn(emoji: "🍶", label: "焼酎",
                            sub: String(format: "%.1fg", AlcoholType.chuhai.alcoholG)) {
                            confirm("焼酎・酎ハイ (アルコール \(String(format: "%.1f", AlcoholType.chuhai.alcoholG))g) を記録しますか？") {
                                Task {
                                    await authManager.recordAlcohol(alcoholType: .chuhai)
                                    await healthKit.saveWaterIntake(amountMl: Double(AlcoholType.chuhai.amountMl), timestamp: Date())
                                    await updateSlotForDrink(ml: AlcoholType.chuhai.amountMl)
                                    await loadData()
                                    hydrationQuickType = nil
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGray6))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func hydrationQuickBtn(emoji: String, label: String, sub: String,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(emoji).font(.system(size: 20 * UIScale.font))
                Text(label)
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text(sub)
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // ── 改善ポイント（インライン版） ────────────────────────────────────
    @ViewBuilder
    private var adviceInlineSection: some View {
        let tips = buildTips(pfcAnalysis).filter { $0.emoji != "📝" && $0.emoji != "🍽️" }
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tips, id: \.message) { tip in
                    HStack(spacing: 6) {
                        Text(tip.emoji).font(.system(size: 12 * UIScale.font))
                        Text(tip.title)
                            .font(.system(size: 10 * UIScale.font, weight: .bold))
                            .foregroundColor(tip.color)
                        Text("— \(tip.message)")
                            .font(.system(size: 9 * UIScale.font))
                            .foregroundColor(Color.duoDark.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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
        isSelected: Bool = false, onTap: @escaping () -> Void) -> some View {
        let percent = goal != nil && goal! > 0 ? Int((value / goal!) * 100) : 0
        let isOver  = goal != nil && value > goal!
        let displayColor: Color
        if label == "水分" {
            displayColor = percent >= 100 ? .duoGreen : percent >= 70 ? .duoGreen.opacity(0.7) : percent >= 40 ? .duoOrange : .duoDark
        } else {
            displayColor = (isOver || percent >= 100) ? .red : percent >= 70 ? .duoOrange : .duoGreen
        }
        let content = VStack(alignment: .center, spacing: 2) {
            Image(systemName: icon).font(.system(size: 12 * UIScale.font)).foregroundColor(iconColor)
            Text(label).font(.system(size: 7 * UIScale.font, weight: .bold)).foregroundColor(Color.duoDark)
            Text(value > 0 ? "\(formatValue(value))\(unit)" : "—")
                .font(.system(size: 10 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor((isOver && isReverse) ? .red : displayColor)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let _ = goal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 2)
                        Capsule().fill(displayColor)
                            .frame(width: max(2, geo.size.width * CGFloat(min(percent, 100)) / 100), height: 2)
                    }
                }.frame(height: 2)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(isSelected ? iconColor.opacity(0.18) : iconColor.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? iconColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        return AnyView(Button(action: onTap) { content }.buttonStyle(.plain))
    }

    // MARK: - FOODフィード

    private var photoFeedSection: some View {
        let twoWeeksAgo  = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let allFavorites = photoLogManager.history.filter { $0.isFavorite }
        let recent       = allFavorites.filter { $0.timestamp >= twoWeeksAgo }
        let older        = allFavorites.filter { $0.timestamp < twoWeeksAgo }
        let displayed    = showOlderFoodFeed ? allFavorites : recent

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color(hex: "#FFD700"))
                Text("FOODフィード")
                    .font(.system(size: 13 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("\(displayed.count)件")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }

            if displayed.isEmpty {
                Text("直近2週間のお気に入りはありません")
                    .font(.system(size: 12 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, item in
                        PhotoFeedCard(item: item, gradientIndex: index)
                            .onTapGesture {
                                swipeFoodStart = index
                                swipeFoodItems = displayed
                            }
                    }
                }
            }

            // 過去フィード展開ボタン
            if !showOlderFoodFeed && !older.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFoodFeed = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13 * UIScale.font, weight: .semibold))
                        Text("過去のフィードを表示（\(older.count)件）")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#FFD700"))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(hex: "#FFD700").opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else if showOlderFoodFeed && !older.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOlderFoodFeed = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10 * UIScale.font, weight: .semibold))
                        Text("2週間以内のみ表示")
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(Color.duoSubtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - FOODフィードプロモーション（Freeユーザー向け）

    private var foodFeedPromoSection: some View {
        guard !plus.isPlus else { return AnyView(EmptyView()) }
        return AnyView(
            Button { showPlusViewFromFood = true } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                        Text("FOODフィード")
                            .font(.system(size: 15 * UIScale.font, weight: .black))
                            .foregroundColor(Color.duoDark)
                        Spacer()
                        HStack(spacing: 3) {
                            Text("+")
                                .font(.system(size: 9 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .frame(width: 15, height: 15)
                                .background(Color.duoGold)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text("Plus限定")
                                .font(.system(size: 10 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGold)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.duoGold.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22 * UIScale.font))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.duoGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FOOD に関する写真とカロリーを記録できます")
                                .font(.system(size: 13 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoDark)
                            Text("AIが写真から栄養素を解析 · 食事推移を可視化")
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                .padding(14)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
        )
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
        loadDailyFixedGoals()
        async let summary = authManager.getTodayIntakeSummary()
        async let goals   = authManager.getIntakeSettings()
        // force: true でTTLをバイパスし、常に最新のHKデータを取得する
        await healthKit.fetchIntakeHealth(force: true)
        var (intake, settings) = await (summary, goals)

        // HealthKitの値をマージ（アプリ記録とHealthKit記録を合算して大きい方を採用）
        intake.totalWaterMl    = max(intake.totalWaterMl,    Int(healthKit.todayIntakeWater))
        intake.totalCaffeineMg = max(intake.totalCaffeineMg, Int(healthKit.todayIntakeCaffeine))
        intake.totalAlcoholG   = max(intake.totalAlcoholG,   healthKit.todayIntakeAlcohol)

        todayIntake = intake
        intakeGoals = settings
        pfcAnalysis = healthKit.analyzePFCBalance(settings: intakeGoals)
    }

    private func recomputePhotoLogTotals() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // savedToHealthKit == true のエントリはHealthKitに保存済みのため除外（二重計算防止）
        cachedPhotoLogTotals = photoLogManager.history
            .filter { cal.startOfDay(for: $0.timestamp) == today && !$0.savedToHealthKit }
            .reduce(into: (protein: 0.0, fat: 0.0, carbs: 0.0, calories: 0)) { acc, item in
                acc.protein  += item.analyzedNutrition.protein
                acc.fat      += item.analyzedNutrition.fat
                acc.carbs    += item.analyzedNutrition.carbs
                acc.calories += item.analyzedNutrition.calories
            }
    }

    private func loadDailyFixedGoals() {
        if let data = UserDefaults.standard.data(forKey: "dailyFixedGoals_v1"),
           let saved = try? JSONDecoder().decode(DailyFixedGoals.self, from: data) {
            dailyFixedGoals = saved
        }
    }

    // MARK: - FOODサマリー行

    private var foodSummaryRow: some View {
        let foodColor = Color.duoGreen
        // cachedPhotoLogTotals を再利用（body評価ごとの重複filter/reduce防止）
        let photoTotals = cachedPhotoLogTotals
        let prot = healthKit.todayIntakeProtein + photoTotals.protein
        let fat_ = healthKit.todayIntakeFat + photoTotals.fat
        let carb = healthKit.todayIntakeCarbs + photoTotals.carbs
        let totalIntakeCal = Int(healthKit.todayIntakeCalories) + photoTotals.calories
        let calDiff = totalIntakeCal - Int(healthKit.todayActiveCalories + healthKit.todayRestingCalories)
        let waterMl = Int(healthKit.todayIntakeWater)
        let foodGoalDone = dailyFixedGoals.foodEnabled && totalIntakeCal >= 2000
        let sign = calDiff >= 0 ? "+" : ""
        return HStack(spacing: 6) {
            Text("FOOD")
                .font(.system(size: 8 * UIScale.font, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(foodColor)
                .cornerRadius(4)
            PFCMiniRingView(
                proteinKcal: prot * 4,
                fatKcal: fat_ * 9,
                carbsKcal: carb * 4,
                diameter: 22,
                lineWidth: 4,
                centerText: pfcAnalysis.map { "\($0.score)" },
                centerTextColor: (pfcAnalysis?.score ?? 0) >= 70 ? foodColor : Color.duoDark
            )
            HStack(spacing: 2) {
                Text("💧").font(.system(size: 11 * UIScale.font))
                Text(waterMl > 0 ? "\(waterMl)" : "—")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoDark)
            }
            HStack(spacing: 2) {
                Text("🍽️").font(.system(size: 11 * UIScale.font))
                Text(totalIntakeCal > 0 ? "\(totalIntakeCal)" : "—")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(foodGoalDone ? foodColor : Color.duoDark)
            }
            HStack(spacing: 2) {
                Text("⚡").font(.system(size: 11 * UIScale.font))
                Text(totalIntakeCal > 0 ? "\(sign)\(calDiff)" : "—")
                    .font(.system(size: 9 * UIScale.font, weight: .bold))
                    .foregroundColor(calDiff > 200 ? Color(hex: "#FF4B4B") : calDiff < -200 ? foodColor : Color.duoDark)
                if totalIntakeCal > 0 {
                    Text("cal").font(.system(size: 7 * UIScale.font)).foregroundColor(Color.duoSubtitle)
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

// MARK: - Photo Feed Card

private struct PhotoFeedCard: View {
    let item: PhotoLogHistoryItem
    let gradientIndex: Int

    private let gradients: [[Color]] = [
        [Color(hex: "#FF6B6B"), Color(hex: "#FF8E53")],
        [Color(hex: "#4ECDC4"), Color(hex: "#45B7D1")],
        [Color(hex: "#96CEB4"), Color(hex: "#00B894")],
        [Color(hex: "#FFEAA7"), Color(hex: "#FDCB6E")],
        [Color(hex: "#A29BFE"), Color(hex: "#6C5CE7")],
        [Color(hex: "#FD79A8"), Color(hex: "#E84393")],
        [Color(hex: "#74B9FF"), Color(hex: "#0984E3")],
        [Color(hex: "#55EFC4"), Color(hex: "#00CEC9")],
    ]

    private var gradient: [Color] { gradients[gradientIndex % gradients.count] }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 背景: サムネイル or グラジェント
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(
                            Text(foodEmoji(for: item.displayName))
                                .font(.system(size: 44 * UIScale.font))
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
            .clipped()

            // 下部グラデーションオーバーレイ（星なし）
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 11 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                HStack(spacing: 3) {
                    Text("🔥")
                        .font(.system(size: 9 * UIScale.font))
                    Text("\(item.calories)kcal")
                        .font(.system(size: 10 * UIScale.font, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    Spacer()
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        // 左上: 食事タイムバッジ
        .overlay(alignment: .topLeading) {
            let info = mealTimeInfo(for: item.timestamp)
            Text(info.label)
                .font(.system(size: 10 * UIScale.font, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(info.color)
                .clipShape(Capsule())
                .padding(7)
        }
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)
    }

    private func foodEmoji(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("米") || n.contains("ご飯") || n.contains("rice") { return "🍚" }
        if n.contains("麺") || n.contains("ラーメン") || n.contains("パスタ") { return "🍜" }
        if n.contains("肉") || n.contains("チキン") || n.contains("beef") { return "🥩" }
        if n.contains("魚") || n.contains("サーモン") || n.contains("サバ") { return "🐟" }
        if n.contains("サラダ") || n.contains("野菜") { return "🥗" }
        if n.contains("パン") || n.contains("toast") { return "🍞" }
        if n.contains("スープ") || n.contains("soup") { return "🍲" }
        if n.contains("卵") || n.contains("たまご") { return "🥚" }
        if n.contains("フルーツ") || n.contains("果物") { return "🍎" }
        if n.contains("コーヒー") || n.contains("ティー") { return "☕" }
        return "🍽️"
    }
}

// MARK: - 食事時間ラベルヘルパー（FoodView / TomoView 共通）

private func mealTimeInfo(for date: Date) -> (label: String, color: Color) {
    let hour = Calendar.current.component(.hour, from: date)
    switch hour {
    case 5..<11:  return ("Breakfast", Color(hex: "#FF9500"))
    case 11..<14: return ("Lunch",     Color(hex: "#34C759"))
    case 14..<18: return ("Snack",     Color(hex: "#AF52DE"))
    case 18..<24: return ("Dinner",    Color(hex: "#0A84FF"))
    default:      return ("Late Night",Color(hex: "#5E5CE6"))
    }
}

// MARK: - Photo Feed Detail Sheet

struct PhotoFeedDetailSheet: View {
    private static let mdHhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    let item: PhotoLogHistoryItem
    var embedded: Bool = false
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var savedOK = false
    @State private var showSaveConfirm = false
    @State private var isPublicInTomo: Bool = false

    private let cardGradients: [[Color]] = [
        [Color(hex: "#FF6B6B"), Color(hex: "#FF8E53")],
        [Color(hex: "#4ECDC4"), Color(hex: "#45B7D1")],
        [Color(hex: "#96CEB4"), Color(hex: "#00B894")],
        [Color(hex: "#A29BFE"), Color(hex: "#6C5CE7")],
    ]

    var body: some View {
        if embedded {
            mainContent
        } else {
            NavigationView {
                mainContent
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(item.displayName)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("閉じる") { dismiss() }
                                .foregroundColor(Color.duoGreen)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerImage
                VStack(alignment: .leading, spacing: 16) {
                    calorieBanner
                    if !item.comment.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGreen.opacity(0.7))
                            Text(item.comment)
                                .font(.system(size: 14 * UIScale.font))
                                .foregroundColor(Color.duoDark.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    if !item.analyzedNutrition.description.isEmpty {
                        descriptionCard
                    }
                    nutritionGrid
                    recordButton
                    photoTomoPublicToggle
                }
                .padding(16)
            }
        }
        .background(Color.duoBg.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isPublicInTomo = item.isPublic }
        .alert("食事を記録しますか？", isPresented: $showSaveConfirm) {
            Button("記録する") {
                Task {
                    isSaving = true
                    await saveToHealth()
                    isSaving = false
                    savedOK = true
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(item.displayName)（\(item.calories)kcal）を今日の食事としてHealthKitに保存します")
        }
    }

    private var headerImage: some View {
        let mealInfo = mealTimeInfo(for: item.timestamp)
        return ZStack(alignment: .bottom) {
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: cardGradients[abs(item.id.hashValue) % cardGradients.count],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(Text("🍽️").font(.system(size: 72 * UIScale.font)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.width * 0.85)
            .clipped()

            // 下部: 写真名称 + 日時
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 15 * UIScale.font, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeLabel(item.timestamp))
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            )
        }
        // 左上: 食事タイムバッジ（Breakfast / Lunch / Snack / Dinner）
        .overlay(alignment: .topLeading) {
            Text(mealInfo.label)
                .font(.system(size: 12 * UIScale.font, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(mealInfo.color)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4)
                .padding(12)
        }
    }

    private var calorieBanner: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("\(item.calories)")
                    .font(.system(size: 34 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.0))
                Text("kcal")
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            Divider().frame(height: 44)
            VStack(alignment: .leading, spacing: 4) {
                pfcBar(label: "P", percent: proteinPercent, color: Color.duoOrange)
                pfcBar(label: "F", percent: fatPercent, color: Color.duoPurple)
                pfcBar(label: "C", percent: carbsPercent, color: Color.duoBlue)
            }
            Spacer()
            Text(String(format: "確度\n%.0f%%", item.analyzedNutrition.confidence * 100))
                .font(.system(size: 10 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func pfcBar(label: String, percent: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10 * UIScale.font, weight: .black))
                .foregroundColor(color)
                .frame(width: 12)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15)).frame(height: 8)
                    Capsule().fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(percent / 100, 1))), height: 8)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", percent))
                .font(.system(size: 9 * UIScale.font, weight: .bold))
                .foregroundColor(color)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var descriptionCard: some View {
        Text(item.analyzedNutrition.description)
            .font(.system(size: 13 * UIScale.font, weight: .semibold))
            .foregroundColor(Color.duoDark.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
    }

    private var nutritionGrid: some View {
        let n = item.analyzedNutrition
        return VStack(alignment: .leading, spacing: 10) {
            Text("栄養素")
                .font(.system(size: 12 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoDark)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                nutritionTile(icon: "💪", label: "たんぱく質", value: String(format: "%.1fg", n.protein), color: Color.duoOrange)
                nutritionTile(icon: "🛢️", label: "脂質",     value: String(format: "%.1fg", n.fat),     color: Color.duoPurple)
                nutritionTile(icon: "🍚", label: "炭水化物", value: String(format: "%.1fg", n.carbs),   color: Color.duoBlue)
                if n.sugar > 0 {
                    nutritionTile(icon: "🍬", label: "糖質",   value: String(format: "%.1fg", n.sugar),  color: Color(hex: "#FDCB6E"))
                }
                if n.fiber > 0 {
                    nutritionTile(icon: "🌾", label: "食物繊維", value: String(format: "%.1fg", n.fiber), color: Color(hex: "#00B894"))
                }
                if n.sodium > 0 {
                    nutritionTile(icon: "🧂", label: "塩分",   value: String(format: "%.1fg", n.sodium), color: Color(hex: "#B2BEC3"))
                }
                if n.water > 0 {
                    nutritionTile(icon: "💧", label: "水分",   value: "\(n.water)ml",                    color: Color(hex: "#1CB0F6"))
                }
                if n.caffeine > 0 {
                    nutritionTile(icon: "☕", label: "カフェイン", value: "\(n.caffeine)mg",               color: Color(hex: "#8B5E3C"))
                }
                if n.alcohol > 0 {
                    nutritionTile(icon: "🍷", label: "アルコール", value: String(format: "%.1fg", n.alcohol), color: Color.duoPurple)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func nutritionTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(icon).font(.system(size: 20 * UIScale.font))
            Text(value)
                .font(.system(size: 13 * UIScale.font, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 8 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoSubtitle)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10))
        .cornerRadius(12)
    }

    private var recordButton: some View {
        Button {
            if !savedOK { showSaveConfirm = true }
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(.white).scaleEffect(0.9)
                } else {
                    Image(systemName: savedOK ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18 * UIScale.font, weight: .bold))
                }
                Text(savedOK ? "記録しました！" : "今日の食事として記録する")
                    .font(.system(size: 15 * UIScale.font, weight: .black))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if savedOK {
                        AnyView(Color.duoGreen)
                    } else {
                        AnyView(LinearGradient(
                            colors: [Color(red: 1.0, green: 0.55, blue: 0.0), Color(red: 0.9, green: 0.3, blue: 0.0)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    }
                }
            )
            .cornerRadius(16)
            .shadow(color: (savedOK ? Color.duoGreen : Color(red: 1.0, green: 0.45, blue: 0.0)).opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || savedOK)
    }

    private func saveToHealth() async {
        let n = item.analyzedNutrition
        let mealNutrition = MealNutrition(
            calories: n.calories,
            protein: n.protein,
            fat: n.fat,
            carbs: n.carbs,
            sugar: n.sugar,
            fiber: n.fiber,
            sodium: n.sodium
        )
        await healthKit.saveMealNutrition(mealNutrition)
        if n.water > 0 {
            await healthKit.saveWaterIntake(amountMl: Double(n.water), timestamp: Date())
        }
        if n.caffeine > 0 {
            await healthKit.saveCaffeineIntake(caffeineMg: Double(n.caffeine), timestamp: Date())
        }
    }

    private var totalCalories: Double { Double(item.analyzedNutrition.calories) }
    private var proteinCalories: Double { item.analyzedNutrition.protein * 4 }
    private var fatCalories: Double { item.analyzedNutrition.fat * 9 }
    private var carbsCalories: Double { item.analyzedNutrition.carbs * 4 }
    private var macroTotal: Double { max(1, proteinCalories + fatCalories + carbsCalories) }
    private var proteinPercent: Double { proteinCalories / macroTotal * 100 }
    private var fatPercent: Double { fatCalories / macroTotal * 100 }
    private var carbsPercent: Double { carbsCalories / macroTotal * 100 }

    private func timeLabel(_ date: Date) -> String {
        PhotoFeedDetailSheet.mdHhmm.string(from: date)
    }

    private var photoTomoPublicToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: isPublicInTomo ? "person.2.fill" : "person.2")
                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                .foregroundColor(isPublicInTomo ? Color.duoBlue : Color(.systemGray3))
            Text("TOMOフィードに公開")
                .font(.system(size: 12 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoDark)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isPublicInTomo },
                set: { v in
                    isPublicInTomo = v
                    photoLogManager.setPublic(id: item.id, isPublic: v)
                }
            ))
            .labelsHidden()
            .tint(Color.duoBlue)
            .scaleEffect(0.85)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Swipeable FOOD feed sheet

struct SwipeableFoodFeedSheet: View {
    let items: [PhotoLogHistoryItem]
    let startIndex: Int
    @State private var page: Int
    @Environment(\.dismiss) private var dismiss

    init(items: [PhotoLogHistoryItem], startIndex: Int) {
        self.items = items
        self.startIndex = startIndex
        _page = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $page) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    PhotoFeedDetailSheet(item: item, embedded: true)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
            .navigationTitle(items.count > 1 ? "\(page + 1) / \(items.count)" : (items.first?.displayName ?? "FOOD"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
            .onAppear {
                let target = startIndex
                DispatchQueue.main.async { page = target }
            }
        }
    }
}

// MARK: - Daily Feed Card (Instagram style)

struct EduFeedCard: View {
    let item: EduLogHistoryItem
    var onLike: (() -> Void)? = nil
    var onComment: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.unitsStyle = .abbreviated
        return f
    }()

    private var timeAgo: String {
        let diff = Date().timeIntervalSince(item.timestamp)
        if diff < 3600 { return EduFeedCard.relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()) }
        return EduFeedCard.timeFormatter.string(from: item.timestamp)
    }

    private var accentGradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
            [Color(hex: "#1CB5E0"), Color(hex: "#000851")],
            [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
            [Color(hex: "#f7971e"), Color(hex: "#ffd200")],
            [Color(hex: "#f953c6"), Color(hex: "#b91d73")],
            [Color(hex: "#4776E6"), Color(hex: "#8E54E9")],
        ]
        let idx = abs(item.id.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── ヘッダー：アバター + 名前 + 時刻 ──────────────────────────
            HStack(spacing: 10) {
                UserAvatarView(
                    name: item.authorFirstName,
                    photoURL: item.authorPhotoURL.isEmpty
                        ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                        : item.authorPhotoURL,
                    gradient: accentGradient,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.authorFirstName)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.activityEmoji.isEmpty ? "📚" : item.activityEmoji)
                            .font(.system(size: 10 * UIScale.font))
                        Text(item.activityName)
                            .font(.system(size: 11 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoPurple)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(timeAgo)
                    .font(.system(size: 10 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // ── メイン画像 or 絵文字バナー ───────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 240)
                            .clipped()
                    } else {
                        ZStack {
                            accentGradient
                                .frame(width: geo.size.width, height: 180)
                            VStack(spacing: 8) {
                                Text(item.activityEmoji.isEmpty ? "📚" : item.activityEmoji)
                                    .font(.system(size: 64 * UIScale.font))
                                    .shadow(color: .black.opacity(0.2), radius: 8)
                                Text(item.activityName)
                                    .font(.system(size: 16 * UIScale.font, weight: .black))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 4)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    if item.thumbnail != nil {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.55)],
                            startPoint: .center, endPoint: .bottom
                        )
                        .frame(width: geo.size.width, height: 240)

                        HStack(spacing: 6) {
                            Text(item.activityEmoji.isEmpty ? "📚" : item.activityEmoji)
                                .font(.system(size: 14 * UIScale.font))
                            Text(item.activityName)
                                .font(.system(size: 13 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }
            }
            .frame(height: item.thumbnail != nil ? 240 : 180)
            .clipped()

            // ── コメント ───────────────────────────────────────────────────
            if !item.comment.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text(item.authorFirstName)
                        .font(.system(size: 12 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                        .fixedSize()
                    Text(item.comment)
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoDark.opacity(0.85))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            // ── ボトムバー：ハート + コメント ──────────────────────────────
            HStack(spacing: 0) {
                // いいねボタン
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { onLike?() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 20 * UIScale.font, weight: .semibold))
                            .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.6))
                            .scaleEffect(item.isLiked ? 1.15 : 1.0)
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.trailing, 6)
                }
                .buttonStyle(.plain)

                // コメントボタン
                Button {
                    onComment?()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 19 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoDark.opacity(0.6))
                        if !item.feedComments.isEmpty {
                            Text("\(item.feedComments.count)")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoDark.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 6)
                }
                .buttonStyle(.plain)

                Spacer()

                // シェアボタン
                Button {
                    onShare?()
                } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 18 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark.opacity(0.6))
                        .padding(.vertical, 10)
                        .padding(.leading, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .clipped()
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Daily Feed Detail Sheet

struct EduFeedDetailSheet: View {
    private static let ymdHhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    let item: EduLogHistoryItem
    @StateObject private var eduLogManager = EduLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var isSpeaking = false
    @State private var isPublicInTomo: Bool = false
    @State private var showCommentSheet = false
    @State private var showShareSheet = false
    @State private var speakingExKey: String? = nil   // 例文 TTS

    // いいね・コメント数はライブ値を優先
    private var liveItem: EduLogHistoryItem {
        eduLogManager.history.first(where: { $0.id == item.id }) ?? item
    }

    /// 友達の投稿は ID が "friend_" プレフィックス
    private var isOwnPost: Bool { !item.id.hasPrefix("friend_") }

    private var dateLabel: String {
        EduFeedDetailSheet.ymdHhmm.string(from: item.timestamp)
    }

    private var accentGradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
            [Color(hex: "#1CB5E0"), Color(hex: "#000851")],
            [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
            [Color(hex: "#f7971e"), Color(hex: "#ffd200")],
            [Color(hex: "#f953c6"), Color(hex: "#b91d73")],
            [Color(hex: "#4776E6"), Color(hex: "#8E54E9")],
        ]
        let idx = abs(item.id.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // ヘッダー
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(accentGradient).frame(width: 42, height: 42)
                            Text(String((item.authorFirstName.first ?? "?").uppercased()))
                                .font(.system(size: 18 * UIScale.font, weight: .black))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.authorFirstName)
                                .font(.system(size: 15 * UIScale.font, weight: .black))
                                .foregroundColor(Color.duoDark)
                            Text(dateLabel)
                                .font(.system(size: 11 * UIScale.font))
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        Button { showDeleteConfirm = true } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18 * UIScale.font))
                                .foregroundColor(Color.duoDark.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // メイン画像
                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    } else {
                        ZStack {
                            accentGradient
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                            VStack(spacing: 10) {
                                Text(item.activityEmoji.isEmpty ? "📚" : item.activityEmoji)
                                    .font(.system(size: 80 * UIScale.font))
                                Text(item.activityName)
                                    .font(.system(size: 20 * UIScale.font, weight: .black))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 4)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }

                    // キャプション（コメント）— 画像直下に目立つ形で表示
                    if !item.comment.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 12 * UIScale.font, weight: .bold))
                                .foregroundColor(Color.duoGreen.opacity(0.7))
                                .padding(.top, 2)
                            Text(item.comment)
                                .font(.system(size: 14 * UIScale.font))
                                .foregroundColor(Color.duoDark.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }

                    // アクション行
                    HStack(spacing: 4) {
                        // いいね
                        Button {
                            if isOwnPost {
                                eduLogManager.toggleLike(id: item.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: liveItem.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 20 * UIScale.font, weight: .semibold))
                                    .foregroundColor(liveItem.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.75))
                                if liveItem.likeCount > 0 {
                                    Text("\(liveItem.likeCount)")
                                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                                        .foregroundColor(Color.duoDark.opacity(0.75))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        // コメント
                        Button {
                            showCommentSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 19 * UIScale.font, weight: .semibold))
                                    .foregroundColor(Color.duoDark.opacity(0.75))
                                if !liveItem.feedComments.isEmpty {
                                    Text("\(liveItem.feedComments.count)")
                                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                                        .foregroundColor(Color.duoDark.opacity(0.75))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // シェア
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "paperplane")
                                .font(.system(size: 19 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color.duoDark.opacity(0.75))
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                    // Duolingo: 発音情報＋再生
                    if let phrase = item.extractedPhrase, !phrase.isEmpty {
                        duolingoDetailPanel(phrase: phrase)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // 体重ログ: 体重・体脂肪
                    if item.activityName == "体重ログ" || item.weightKg != nil || item.bodyFatPercent != nil {
                        weightDetailPanel
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // 食事ログ（友達の共有投稿など）: カロリー
                    if let cal = item.calories, cal > 0 {
                        HStack(spacing: 6) {
                            Text("🔥").font(.system(size: 18 * UIScale.font))
                            Text("\(cal) kcal")
                                .font(.system(size: 18 * UIScale.font, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "#FF9600"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#FF9600").opacity(0.10))
                        .cornerRadius(14)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }

                    // アクティビティバッジ
                    HStack(spacing: 6) {
                        Text(item.activityEmoji.isEmpty ? "📚" : item.activityEmoji)
                            .font(.system(size: 13 * UIScale.font))
                        Text(item.activityName)
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoPurple)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.duoPurple.opacity(0.10))
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    // TOMOフィード公開トグル（自分の投稿のみ）
                    if isOwnPost {
                        tomoPublicToggle
                    }

                    Spacer(minLength: 24)
                }
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .confirmationDialog("この投稿を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                eduLogManager.deleteItem(id: item.id)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showCommentSheet) {
            FeedCommentsSheet(item: liveItem, eduLogManager: eduLogManager,
                              photoLogManager: PhotoLogManager.shared)
        }
        .sheet(isPresented: $showShareSheet) {
            SocialShareSheet(item: liveItem)
        }
        .onAppear { isPublicInTomo = item.isPublic }
        .onDisappear {
            DuolingoTextExtractor.shared.stopSpeaking()
        }
    }

    private var tomoPublicToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: isPublicInTomo ? "person.2.fill" : "person.2")
                .font(.system(size: 13 * UIScale.font, weight: .semibold))
                .foregroundColor(isPublicInTomo ? Color.duoBlue : Color(.systemGray3))
            Text("TOMOフィードに公開")
                .font(.system(size: 12 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoDark)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isPublicInTomo },
                set: { v in
                    isPublicInTomo = v
                    eduLogManager.setPublic(id: item.id, isPublic: v)
                }
            ))
            .labelsHidden()
            .tint(Color.duoBlue)
            .scaleEffect(0.85)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 体重ログ パネル（体重・体脂肪）

    private var weightDetailPanel: some View {
        HStack(spacing: 12) {
            weightMetric(emoji: "⚖️", label: "体重",
                         value: item.weightKg != nil ? String(format: "%.1f", item.weightKg!) : "—",
                         unit: "kg", color: Color(hex: "#1CB0F6"))
            weightMetric(emoji: "📉", label: "体脂肪率",
                         value: item.bodyFatPercent != nil ? String(format: "%.1f", item.bodyFatPercent!) : "—",
                         unit: "%", color: Color(hex: "#CE82FF"))
        }
    }

    private func weightMetric(emoji: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 22 * UIScale.font))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24 * UIScale.font, weight: .black, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            Text(label)
                .font(.system(size: 11 * UIScale.font, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .cornerRadius(14)
    }

    // MARK: - Duolingo 発音パネル（詳細）

    @ViewBuilder
    private func duolingoDetailPanel(phrase: String) -> some View {
        let langCode = item.extractedLanguageCode ?? "en"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(languageFlag(langCode)).font(.system(size: 18))
                Text(languageLabel(langCode))
                    .font(.system(size: 12 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                Button {
                    if isSpeaking {
                        DuolingoTextExtractor.shared.stopSpeaking()
                        isSpeaking = false
                    } else {
                        isSpeaking = true
                        DuolingoTextExtractor.shared.speak(phrase: phrase, languageCode: langCode)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                            isSpeaking = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15))
                        Text(isSpeaking ? "停止" : "再生")
                            .font(.system(size: 13 * UIScale.font, weight: .bold))
                    }
                    .foregroundColor(isSpeaking ? Color.red : Color(hex: "#1CB0F6"))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background((isSpeaking ? Color.red : Color(hex: "#1CB0F6")).opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Text(phrase)
                .font(.system(size: 20 * UIScale.font, weight: .bold))
                .foregroundColor(Color.duoDark)
                .fixedSize(horizontal: false, vertical: true)

            if let pron = item.pronunciation, !pron.isEmpty {
                Text(pron)
                    .font(.system(size: 14 * UIScale.font))
                    .foregroundColor(Color(hex: "#1CB0F6"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tja = item.translationJA, !tja.isEmpty {
                Text(tja)
                    .font(.system(size: 14 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── 間違えた理由解説 ─────────────────────────────────────────
            if let note = item.mistakeNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("ダメな理由", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF3B30"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF3B30").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 4)
            }

            // ── 文法解説 ─────────────────────────────────────────────────
            if let note = item.grammarNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("文法メモ", systemImage: "text.book.closed")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9500"))
                    Text(note)
                        .font(.system(size: 13 * UIScale.font))
                        .foregroundColor(Color.duoDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "#FF9500").opacity(0.08))
                .cornerRadius(8)
                .padding(.top, 4)
            }

            // ── 例文 2 件 ─────────────────────────────────────────────────
            if let examples = item.exampleSentences, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("例文", systemImage: "quote.bubble")
                        .font(.system(size: 11 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color(hex: "#58CC02"))
                    ForEach(Array(examples.enumerated()), id: \.offset) { idx, ex in
                        let exKey       = "detail-ex\(idx)"
                        let isExSpeaking = speakingExKey == exKey
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(idx + 1).")
                                .font(.system(size: 13 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(hex: "#58CC02"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.text)
                                    .font(.system(size: 14 * UIScale.font, weight: .semibold))
                                    .foregroundColor(Color.duoDark)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let tr = ex.translationJA, !tr.isEmpty {
                                    Text(tr)
                                        .font(.system(size: 12 * UIScale.font))
                                        .foregroundColor(Color.duoSubtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            Button {
                                if isExSpeaking {
                                    DuolingoTextExtractor.shared.stopSpeaking()
                                    speakingExKey = nil
                                } else {
                                    speakingExKey = exKey
                                    isSpeaking = false
                                    DuolingoTextExtractor.shared.speak(
                                        phrase: ex.text, languageCode: langCode)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                                        if speakingExKey == exKey { speakingExKey = nil }
                                    }
                                }
                            } label: {
                                Image(systemName: isExSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(isExSpeaking ? .red : Color(hex: "#58CC02"))
                                    .frame(width: 28, height: 28)
                                    .background((isExSpeaking ? Color.red : Color(hex: "#58CC02")).opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(Color(hex: "#58CC02").opacity(0.07))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.6))
        .cornerRadius(14)
    }

}

// MARK: - Feed Comments Sheet

struct FeedCommentsSheet: View {
    let item: EduLogHistoryItem
    @ObservedObject var eduLogManager: EduLogManager
    var photoLogManager: PhotoLogManager? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var newCommentText = ""
    @FocusState private var inputFocused: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private var isFoodItem: Bool { item.id.hasPrefix("food_") }
    private var foodOriginalId: String { String(item.id.dropFirst("food_".count)) }

    private var currentItem: EduLogHistoryItem {
        if isFoodItem, let pm = photoLogManager,
           let food = pm.history.first(where: { $0.id == foodOriginalId }) {
            var copy = item
            copy.isLiked = food.isLiked
            copy.likeCount = food.likeCount
            copy.feedComments = food.feedComments
            return copy
        }
        return eduLogManager.history.first { $0.id == item.id } ?? item
    }

    var body: some View {
        VStack(spacing: 0) {
            // ハンドル
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            // ナビ行
            HStack {
                Text("コメント")
                    .font(.system(size: 16 * UIScale.font, weight: .black))
                    .foregroundColor(Color.duoDark)
                Spacer()
                Button("閉じる") { dismiss() }
                    .font(.system(size: 14 * UIScale.font))
                    .foregroundColor(Color.duoBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // コメント一覧
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 投稿のキャプション（コメント風に表示）
                    if !item.comment.isEmpty {
                        commentRow(
                            name: item.authorFirstName,
                            photoURL: item.authorPhotoURL,
                            text: item.comment,
                            date: item.timestamp,
                            isCaption: true,
                            commentId: nil
                        )
                        Divider().padding(.leading, 52)
                    }

                    if currentItem.feedComments.isEmpty && item.comment.isEmpty {
                        Text("まだコメントがありません\n最初のコメントを残しましょう！")
                            .font(.system(size: 13 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }

                    ForEach(currentItem.feedComments) { c in
                        commentRow(
                            name: c.authorFirstName,
                            photoURL: c.authorPhotoURL,
                            text: c.text,
                            date: c.timestamp,
                            isCaption: false,
                            commentId: c.id
                        )
                        if c.id != currentItem.feedComments.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }

            Divider()

            // コメント入力バー
            HStack(spacing: 10) {
                // 自分のアバター
                UserAvatarView(
                    name: AuthenticationManager.shared.userProfile?.username ?? "?",
                    photoURL: UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "",
                    size: 32
                )

                TextField("コメントを追加...", text: $newCommentText, axis: .vertical)
                    .font(.system(size: 14 * UIScale.font))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendComment() }

                Button {
                    sendComment()
                } label: {
                    Text("投稿")
                        .font(.system(size: 14 * UIScale.font, weight: .bold))
                        .foregroundColor(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.duoBlue.opacity(0.3) : Color.duoBlue)
                }
                .buttonStyle(.plain)
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear { inputFocused = true }
    }

    private func commentRow(name: String, photoURL: String = "", text: String, date: Date,
                            isCaption: Bool, commentId: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            UserAvatarView(
                name: name,
                photoURL: photoURL,
                gradient: LinearGradient(
                    colors: isCaption
                        ? [Color.duoPurple, Color(hex: "#b91d73")]
                        : [Color.duoGreen, Color(hex: "#38ef7d")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                    if isCaption {
                        Text("投稿者")
                            .font(.system(size: 9 * UIScale.font, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.duoPurple)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(FeedCommentsSheet.timeFormatter.string(from: date))
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
                Text(text)
                    .font(.system(size: 13 * UIScale.font))
                    .foregroundColor(Color.duoDark.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            if let cid = commentId {
                Button(role: .destructive) {
                    if isFoodItem, let pm = photoLogManager {
                        pm.deleteFeedComment(itemId: foodOriginalId, commentId: cid)
                    } else {
                        eduLogManager.deleteFeedComment(itemId: item.id, commentId: cid)
                    }
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
        }
    }

    private func sendComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if isFoodItem, let pm = photoLogManager {
            pm.addFeedComment(id: foodOriginalId, text: text)
        } else {
            eduLogManager.addFeedComment(id: item.id, text: text)
        }
        newCommentText = ""
    }
}

// MARK: - Social Share Sheet

struct SocialShareSheet: View {
    let item: EduLogHistoryItem
    /// 追加で共有したいURL（リンクシェア用）
    var shareURL: URL? = nil
    /// 追加で共有したい画像（item.thumbnail より優先）
    var overrideImage: UIImage? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showSystemShare = false

    // 設定済みSNSアカウント
    @AppStorage("sns.x.handle")         private var xHandle  = ""
    @AppStorage("sns.instagram.handle") private var igHandle = ""
    @AppStorage("sns.facebook.url")     private var fbUrl    = ""
    @AppStorage("sns.line.id")          private var lineId   = ""

    private var effectiveImage: UIImage? { overrideImage ?? item.thumbnail }

    private var systemShareItems: [Any] {
        var items: [Any] = [shareText]
        if let img = effectiveImage { items.insert(img, at: 0) }
        if let url = shareURL { items.append(url) }
        return items
    }

    private var shareText: String {
        let emoji = item.activityEmoji.isEmpty ? "💪" : item.activityEmoji
        let name  = item.activityName.isEmpty ? "アクティビティ" : item.activityName
        var text  = "\(emoji) \(name) を達成！"
        if !item.comment.isEmpty { text += "\n\(item.comment)" }
        if let url = shareURL { text += "\n\(url.absoluteString)" }
        text += "\n\n#kfit #フィットネス #健康習慣"
        return text
    }

    // LINE shared text (URL encoded)
    private var lineText: String {
        var t = shareText
        if let url = shareURL { t += "\n\(url.absoluteString)" }
        return t
    }

    // シートの高さ：LINEボタンありの場合は高め
    private var sheetHeight: CGFloat {
        let hasLine = !lineId.isEmpty
        return hasLine ? 230 : 195
    }

    var body: some View {
        VStack(spacing: 0) {
            // ドラッグハンドル
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("シェア")
                .font(.system(size: 16 * UIScale.font, weight: .black))
                .foregroundColor(Color.duoDark)
                .padding(.bottom, 16)

            // ── メインSNSボタン行 ────────────────────────────────
            HStack(spacing: 0) {
                Spacer()
                socialButton(
                    label: xHandle.isEmpty ? "X (Twitter)" : xHandle,
                    color: .black,
                    systemIcon: "x.square.fill"
                ) { shareToX() }
                Spacer()
                socialButton(
                    label: fbUrl.isEmpty ? "Facebook" : "Facebook",
                    color: Color(hex: "#1877F2"),
                    systemIcon: "f.square.fill"
                ) { shareToFacebook() }
                Spacer()
                socialButton(
                    label: igHandle.isEmpty ? "Instagram" : igHandle,
                    color: Color(hex: "#E1306C"),
                    systemIcon: "camera.fill"
                ) { shareToInstagram() }
                Spacer()
                socialButton(
                    label: "その他",
                    color: Color.duoSubtitle,
                    systemIcon: "square.and.arrow.up"
                ) { showSystemShare = true }
                Spacer()
            }
            .padding(.bottom, lineId.isEmpty ? 28 : 16)

            // ── LINEボタン（登録済みの場合のみ表示）────────────────
            if !lineId.isEmpty {
                Button { shareToLine() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text("LINEで送る")
                            .font(.system(size: 14 * UIScale.font, weight: .bold))
                            .foregroundColor(.white)
                        Text("(\(lineId))")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#06C755"))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showSystemShare) {
            SystemShareSheet(items: systemShareItems)
        }
    }

    // MARK: - ボタンビュー

    private func socialButton(label: String, color: Color, systemIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color)
                        .frame(width: 54, height: 54)
                    Image(systemName: systemIcon)
                        .font(.system(size: 24 * UIScale.font))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 9 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoSubtitle)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Share Actions

    private func shareToX() {
        var text = shareText
        // アカウントハンドルが設定されていれば末尾に追加
        if !xHandle.isEmpty, !text.contains(xHandle) {
            text += "\n\(xHandle)"
        }
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // URL を別パラメータで渡す（x.com Web Intent対応）
        var urlStr = "https://x.com/intent/post?text=\(encodedText)"
        if let url = shareURL, let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlStr += "&url=\(encodedURL)"
        }
        let appURLStr = "twitter://post?message=\(encodedText)"
        if let appURL = URL(string: appURLStr), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: urlStr) {
            UIApplication.shared.open(webURL)
        }
        dismiss()
    }

    private func shareToFacebook() {
        // Facebook はURLシェアが主流（テキスト直接投稿はAPIなしでは困難）
        if let url = shareURL,
           let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let webURL = URL(string: "https://www.facebook.com/sharer/sharer.php?u=\(encoded)") {
            UIApplication.shared.open(webURL)
        } else if let appURL = URL(string: "fb://"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(URL(string: "https://www.facebook.com/")!)
        }
        dismiss()
    }

    private func shareToInstagram() {
        let image = effectiveImage
        if let image {
            guard let imageData = image.pngData() else { openInstagramApp(); dismiss(); return }
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("kfit_share_\(UUID().uuidString).igo")
            do {
                try imageData.write(to: tmpURL)
                let controller = UIDocumentInteractionController(url: tmpURL)
                controller.uti = "com.instagram.exclusivegram"
                var caption = shareText
                if !igHandle.isEmpty, !caption.contains(igHandle) { caption += "\n\(igHandle)" }
                controller.annotation = ["InstagramCaption": caption]
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.windows.first?.rootViewController })
                    .first {
                    controller.presentOpenInMenu(from: .zero, in: root.view, animated: true)
                }
            } catch { openInstagramApp() }
        } else {
            openInstagramApp()
        }
        dismiss()
    }

    private func openInstagramApp() {
        let url = URL(string: "instagram://app")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIApplication.shared.open(URL(string: "https://www.instagram.com")!)
        }
    }

    private func shareToLine() {
        let text = lineText
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let appURL = URL(string: "line://msg/text/\(encoded)")
        let webURL = URL(string: "https://line.me/R/msg/text/?\(encoded)")
        if let app = appURL, UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = webURL {
            UIApplication.shared.open(web)
        }
        dismiss()
    }
}

// MARK: - System Share Sheet Wrapper
// → Components/SharedEduViews.swift に移動（kedu ターゲットと共有するため）

// MARK: - Category Mini Card
// 横スクロール行の中に並ぶ、カテゴリ単位のコンパクトカード

struct CategoryMiniCard: View {
    let group: TomoView.FeedCategoryGroup
    var onTap: (EduLogHistoryItem) -> Void

    private let cardW: CGFloat = 130
    private let cardH: CGFloat = 182

    private var accentGradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
            [Color(hex: "#1CB5E0"), Color(hex: "#000851")],
            [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
            [Color(hex: "#f7971e"), Color(hex: "#ffd200")],
            [Color(hex: "#f953c6"), Color(hex: "#b91d73")],
            [Color(hex: "#4776E6"), Color(hex: "#8E54E9")],
        ]
        let idx = abs(group.categoryKey.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// カードに表示するラベルテキスト
    /// 食事ログ → comment（食事名）、その他 → commentの1行目（なければactivityName）
    private var cardLabel: String {
        guard let item = group.items.first else { return "" }
        if item.id.hasPrefix("food_") {
            return item.comment.isEmpty ? "食事" : item.comment
        }
        let firstLine = item.comment
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? item.activityName : firstLine
    }

    var body: some View {
        Button {
            onTap(group.items.first!)
        } label: {
            ZStack(alignment: .bottom) {
                // 背景：先頭投稿の写真 or グラデーション＋絵文字
                backgroundView

                // 下部グラデーション
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.72)],
                    startPoint: .center, endPoint: .bottom
                )

                // 複数件：右上にサブサムネイルをスタック
                if !group.isSingle {
                    multiThumbBadge
                }

                // カテゴリ情報（下部）
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(group.categoryEmoji.isEmpty ? "📝" : group.categoryEmoji)
                            .font(.system(size: 13 * UIScale.font))
                        Text(cardLabel)
                            .font(.system(size: 11 * UIScale.font, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        if !group.isSingle {
                            Label("\(group.items.count)件", systemImage: "square.stack.fill")
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        let likes = group.items.reduce(0) { $0 + $1.likeCount }
                        if likes > 0 {
                            Label("\(likes)", systemImage: "heart.fill")
                                .font(.system(size: 9 * UIScale.font, weight: .bold))
                                .foregroundColor(Color(hex: "#ED4956"))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(width: cardW, height: cardH)
            .cornerRadius(14)
            .clipped()
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let thumb = group.items.first?.thumbnail {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: cardW, height: cardH)
                .clipped()
        } else {
            ZStack {
                accentGradient
                Text(group.categoryEmoji.isEmpty ? "📝" : group.categoryEmoji)
                    .font(.system(size: 52 * UIScale.font))
                    .shadow(color: .black.opacity(0.25), radius: 8)
            }
            .frame(width: cardW, height: cardH)
        }
    }

    // 右上に2枚目以降のサムネをスタック表示
    @ViewBuilder
    private var multiThumbBadge: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    ForEach(Array(group.items.dropFirst().prefix(2).enumerated()), id: \.element.id) { idx, item in
                        Group {
                            if let thumb = item.smallThumbnail {
                                Image(uiImage: thumb)
                                    .resizable().scaledToFill()
                            } else {
                                accentGradient
                            }
                        }
                        .frame(width: 28, height: 28)
                        .cornerRadius(6)
                        .clipped()
                        .offset(x: CGFloat(idx) * 6, y: CGFloat(idx) * 6)
                    }
                }
                .padding(8)
            }
            Spacer()
        }
    }
}

// MARK: - Category Group List Sheet
// カテゴリ内の複数投稿を一覧表示するシート

struct CategoryGroupListSheet: View {
    let group: TomoView.FeedCategoryGroup
    var onTapItem: (EduLogHistoryItem) -> Void
    var onLike: ((EduLogHistoryItem) -> Void)? = nil
    var onComment: ((EduLogHistoryItem) -> Void)? = nil
    var onShare: ((EduLogHistoryItem) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // ハンドル
            Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 4).padding(.top, 10)

            // ヘッダー
            HStack(spacing: 10) {
                Text(group.categoryEmoji.isEmpty ? "📝" : group.categoryEmoji)
                    .font(.system(size: 24 * UIScale.font))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.categoryKey)
                        .font(.system(size: 16 * UIScale.font, weight: .black)).foregroundColor(Color.duoDark)
                    Text("\(group.items.count)件の記録")
                        .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Button("閉じる") { dismiss() }
                    .font(.system(size: 14 * UIScale.font)).foregroundColor(Color.duoBlue)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        listRow(item: item)
                        if item.id != group.items.last?.id { Divider().padding(.leading, 64) }
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func listRow(item: EduLogHistoryItem) -> some View {
        HStack(spacing: 12) {
            // アバター（左）
            UserAvatarView(
                name: item.authorFirstName,
                photoURL: item.authorPhotoURL.isEmpty
                    ? (UserDefaults.standard.string(forKey: "cachedCurrentUserPhotoURL") ?? "")
                    : item.authorPhotoURL,
                size: 36
            )

            // サムネイル（FOOD は食事タイムバッジをオーバーレイ）
            let isFood = item.id.hasPrefix("food_")
            let mealInfo = mealTimeInfo(for: item.timestamp)
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let thumb = item.smallThumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [Color.duoBlue.opacity(0.6), Color.duoPurple.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .overlay(Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji).font(.system(size: 20 * UIScale.font)))
                    }
                }
                .frame(width: 48, height: 48)
                .clipped()

                if isFood {
                    Text(mealInfo.label)
                        .font(.system(size: 7 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(mealInfo.color)
                        .clipShape(Capsule())
                        .padding(3)
                }
            }
            .cornerRadius(10)

            // テキスト（FOOD は食事名を色付きで強調）
            VStack(alignment: .leading, spacing: 4) {
                if isFood {
                    Text(mealInfo.label)
                        .font(.system(size: 10 * UIScale.font, weight: .black))
                        .foregroundColor(mealInfo.color)
                } else {
                    Text(item.authorFirstName)
                        .font(.system(size: 11 * UIScale.font, weight: .black)).foregroundColor(Color.duoSubtitle)
                }
                Text(item.comment.isEmpty ? item.activityName : item.comment)
                    .font(.system(size: 13 * UIScale.font, weight: .semibold)).foregroundColor(Color.duoDark).lineLimit(2)
                HStack(spacing: 10) {
                    Text(CategoryGroupListSheet.hhmm.string(from: item.timestamp))
                        .font(.system(size: 11 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    if item.likeCount > 0 {
                        Label("\(item.likeCount)", systemImage: "heart.fill")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color(hex: "#ED4956"))
                    }
                    if !item.feedComments.isEmpty {
                        Label("\(item.feedComments.count)", systemImage: "bubble.right")
                            .font(.system(size: 10 * UIScale.font)).foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            Spacer()

            // アクション
            HStack(spacing: 14) {
                Button { onLike?(item) } label: {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18 * UIScale.font))
                        .foregroundColor(item.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.4))
                }
                Button { onTapItem(item) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTapItem(item) }
    }
}

// MARK: - Compact Category Card (legacy, kept for reference)
// 同日・同カテゴリに複数投稿がある場合、1行にまとめて表示するカード

struct CompactCategoryCard: View {
    let group: TomoView.FeedCategoryGroup
    var onTapItem: (EduLogHistoryItem) -> Void
    var onLike: ((EduLogHistoryItem) -> Void)? = nil
    var onComment: ((EduLogHistoryItem) -> Void)? = nil
    var onShare: ((EduLogHistoryItem) -> Void)? = nil

    @State private var selectedItem: EduLogHistoryItem? = nil

    private var accentGradient: LinearGradient {
        let palettes: [[Color]] = [
            [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
            [Color(hex: "#1CB5E0"), Color(hex: "#000851")],
            [Color(hex: "#11998e"), Color(hex: "#38ef7d")],
            [Color(hex: "#f7971e"), Color(hex: "#ffd200")],
            [Color(hex: "#f953c6"), Color(hex: "#b91d73")],
            [Color(hex: "#4776E6"), Color(hex: "#8E54E9")],
        ]
        let idx = abs(group.categoryKey.hashValue) % palettes.count
        return LinearGradient(colors: palettes[idx], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── カテゴリヘッダー ──────────────────────────────────────────
            HStack(spacing: 8) {
                // アイコン
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentGradient)
                        .frame(width: 32, height: 32)
                    Text(group.categoryEmoji.isEmpty ? "📝" : group.categoryEmoji)
                        .font(.system(size: 17 * UIScale.font))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text({
                        guard let item = group.items.first else { return group.categoryKey }
                        if item.id.hasPrefix("food_") { return item.comment.isEmpty ? "食事" : item.comment }
                        let first = item.comment.split(separator: "\n").first.map(String.init) ?? ""
                        return first.isEmpty ? item.activityName : first
                    }())
                        .font(.system(size: 13 * UIScale.font, weight: .black))
                        .foregroundColor(Color.duoDark)
                        .lineLimit(1)
                    Text("\(group.items.count)件の記録")
                        .font(.system(size: 10 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()

                // いいね合計
                let totalLikes = group.items.reduce(0) { $0 + $1.likeCount }
                if totalLikes > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(Color(hex: "#ED4956"))
                        Text("\(totalLikes)")
                            .font(.system(size: 11 * UIScale.font, weight: .bold))
                            .foregroundColor(Color(hex: "#ED4956"))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 12)

            // ── 投稿サムネイル横スクロール ────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.items) { item in
                        compactThumb(item: item)
                            .onTapGesture { onTapItem(item) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 12)

            // ── ボトムバー（先頭投稿に対してアクション） ─────────────────
            if let first = group.items.first {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            onLike?(first)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: first.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 17 * UIScale.font, weight: .semibold))
                                .foregroundColor(first.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.5))
                            if first.likeCount > 0 {
                                Text("\(first.likeCount)")
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(first.isLiked ? Color(hex: "#ED4956") : Color.duoDark.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 8).padding(.trailing, 6)
                    }
                    .buttonStyle(.plain)

                    Button { onComment?(first) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 16 * UIScale.font, weight: .semibold))
                                .foregroundColor(Color.duoDark.opacity(0.5))
                            if !first.feedComments.isEmpty {
                                Text("\(first.feedComments.count)")
                                    .font(.system(size: 12 * UIScale.font, weight: .bold))
                                    .foregroundColor(Color.duoDark.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 8).padding(.leading, 6)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button { onShare?(first) } label: {
                        Image(systemName: "paperplane")
                            .font(.system(size: 16 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoDark.opacity(0.5))
                            .padding(.vertical, 8).padding(.leading, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .clipped()
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
    }

    // 各投稿の小さいサムネイルセル
    @ViewBuilder
    private func compactThumb(item: EduLogHistoryItem) -> some View {
        let size: CGFloat = 74
        ZStack(alignment: .bottomLeading) {
            if let thumb = item.smallThumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                ZStack {
                    accentGradient
                    Text(item.activityEmoji.isEmpty ? "📝" : item.activityEmoji)
                        .font(.system(size: 28 * UIScale.font))
                }
                .frame(width: size, height: size)
            }

            // いいねバッジ
            if item.likeCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8 * UIScale.font))
                        .foregroundColor(.white)
                    Text("\(item.likeCount)")
                        .font(.system(size: 8 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.45))
                .cornerRadius(4)
                .padding(4)
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(10)
        .clipped()
    }
}
