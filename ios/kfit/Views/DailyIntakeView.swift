import SwiftUI

/// 今日の摂取記録画面（食事・水・コーヒー・アルコール）
struct DailyIntakeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var todaySummary = TodayIntakeSummary()
    /// todaySummary.meals / alcoholLogs をタイプ別（timestamp降順）に事前集計したキャッシュ。
    /// body 評価のたびに filter/sort をやり直すのを避ける（FoodView.foodHistoryCache と同じ方針）。
    private struct IntakeHistoryCache {
        var mealsByType: [MealType: [MealLog]] = [:]
        var alcoholByType: [AlcoholType: [AlcoholLog]] = [:]
    }
    @State private var intakeHistoryCache = IntakeHistoryCache()
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var isRefreshingHealth = false
    @State private var pfcAnalysis: PFCBalanceAnalysis?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("読み込み中...")
                            .padding()
                    } else {
                        // サマリーカード
                        summaryCard

                        // PFCバランス分析
                        if let analysis = pfcAnalysis, analysis.score > 0 {
                            pfcBalanceSection(analysis)
                        }

                        // 食事記録
                        mealsSection

                        // 水分記録
                        waterSection

                        // コーヒー記録
                        coffeeSection

                        // アルコール記録
                        alcoholSection
                    }
                }
                .padding()
            }
            .navigationTitle("摂取記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            isRefreshingHealth = true
                            await healthKit.fetchIntakeHealth(force: true)
                            isRefreshingHealth = false
                        }
                    } label: {
                        if isRefreshingHealth {
                            ProgressView()
                        } else {
                            Label("更新", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshingHealth)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                IntakeSettingsView()
                    .environmentObject(authManager)
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }

    // MARK: - サマリーカード

    private var summaryCard: some View {
        // Apple Health の値をベースに、ローカルのコーヒー・アルコール量を水分に加算
        let hkCalories = Int(healthKit.todayIntakeCalories)
        let hkWater    = Int(healthKit.todayIntakeWater)
        let coffeeMl   = todaySummary.coffeeLogs.reduce(0) { $0 + $1.amountMl }
        let alcoholMl  = todaySummary.alcoholLogs.reduce(0) { $0 + $1.amountMl }
        let totalWater = hkWater + coffeeMl + alcoholMl
        let hkCaffeine = Int(healthKit.todayIntakeCaffeine)
        let hkAlcohol  = healthKit.todayIntakeAlcohol

        return VStack(spacing: 12) {
            HStack(spacing: 20) {
                summaryItem(title: "カロリー", value: "\(hkCalories)", unit: "kcal", color: .duoOrange)
                Divider()
                summaryItem(title: "水分", value: "\(totalWater)", unit: "ml", color: .duoBlue)
            }
            .frame(height: 60)

            Divider()

            HStack(spacing: 20) {
                summaryItem(title: "カフェイン", value: "\(hkCaffeine)", unit: "mg", color: .duoBrown)
                Divider()
                summaryItem(title: "アルコール", value: String(format: "%.1f", hkAlcohol), unit: "g", color: .duoPurple)
            }
            .frame(height: 60)
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    private func summaryItem(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 食事記録

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("食事")
                .font(.headline)
                .foregroundColor(Color.duoText)

            VStack(spacing: 8) {
                ForEach(MealType.allCases, id: \.self) { mealType in
                    intakeButton(
                        emoji: mealType.emoji,
                        title: mealType.displayName,
                        logs: intakeHistoryCache.mealsByType[mealType] ?? [],
                        action: { await authManager.recordMeal(mealType: mealType) }
                    )
                }
            }
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    // MARK: - 水分記録

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("水分")
                .font(.headline)
                .foregroundColor(Color.duoText)

            intakeButton(
                emoji: "💧",
                title: "水1杯",
                logs: todaySummary.waterLogs,
                action: { await authManager.recordWater() }
            )
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    // MARK: - コーヒー記録

    private var coffeeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("コーヒー")
                .font(.headline)
                .foregroundColor(Color.duoText)

            intakeButton(
                emoji: "☕",
                title: "コーヒー1杯",
                logs: todaySummary.coffeeLogs,
                action: { await authManager.recordCoffee() }
            )
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    // MARK: - アルコール記録

    private var alcoholSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("アルコール")
                .font(.headline)
                .foregroundColor(Color.duoText)

            VStack(spacing: 8) {
                ForEach(AlcoholType.allCases, id: \.self) { alcoholType in
                    intakeButton(
                        emoji: alcoholType.emoji,
                        title: alcoholType.displayName,
                        logs: intakeHistoryCache.alcoholByType[alcoholType] ?? [],
                        action: { await authManager.recordAlcohol(alcoholType: alcoholType) }
                    )
                }
            }
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    // MARK: - 摂取ボタン

    private func intakeButton<T>(
        emoji: String,
        title: String,
        logs: [T],
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
                await loadData()
            }
        } label: {
            HStack {
                Text(emoji)
                    .font(.title2)
                Text(title)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoText)
                Spacer()
                Text("\(logs.count)")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color.duoGreen)
            }
            .padding()
            .background(Color.duoBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - PFCバランスセクション

    private func pfcBalanceSection(_ analysis: PFCBalanceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PFCバランス分析")
                    .font(.headline)
                    .foregroundColor(Color.duoText)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(analysis.score)")
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(scoreColor(analysis.score))
                    Text("点")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
            }

            Text(analysis.rating)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(scoreColor(analysis.score))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(scoreColor(analysis.score).opacity(0.1))
                .cornerRadius(8)

            VStack(spacing: 8) {
                pfcRow(
                    label: "たんぱく質",
                    emoji: "💪",
                    percent: analysis.proteinPercent,
                    grams: analysis.proteinGrams,
                    target: 15.0,
                    color: .duoOrange
                )
                pfcRow(
                    label: "脂質",
                    emoji: "🥑",
                    percent: analysis.fatPercent,
                    grams: analysis.fatGrams,
                    target: 25.0,
                    color: .duoPurple
                )
                pfcRow(
                    label: "炭水化物",
                    emoji: "🍚",
                    percent: analysis.carbsPercent,
                    grams: analysis.carbsGrams,
                    target: 60.0,
                    color: .duoBlue
                )
            }

            Text("目安: たんぱく質15% / 脂質25% / 炭水化物60%")
                .font(.caption2)
                .foregroundColor(Color.duoSubtitle)

            // ── 今日の食事履歴 ──────────────────────────────────────────
            Divider()

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.duoOrange)
                    Text("今日の食事")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(Color.duoText)
                }
                Spacer()
                let totalMealCal = todaySummary.meals.reduce(0) { $0 + $1.calories }
                if totalMealCal > 0 {
                    Text("\(totalMealCal) kcal")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoOrange)
                }
            }

            if todaySummary.meals.isEmpty {
                HStack {
                    Spacer()
                    Text("まだ記録がありません")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(MealType.allCases, id: \.self) { mealType in
                        let logs = intakeHistoryCache.mealsByType[mealType] ?? []
                        if !logs.isEmpty {
                            let cal = logs.reduce(0) { $0 + $1.calories }
                            HStack(spacing: 8) {
                                Text(mealType.emoji)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mealType.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color.duoText)
                                    if let last = logs.first {
                                        Text(timeString(last.timestamp))
                                            .font(.system(size: 10))
                                            .foregroundColor(Color.duoSubtitle)
                                    }
                                }
                                Spacer()
                                if logs.count > 1 {
                                    Text("×\(logs.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.duoSubtitle)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(5)
                                }
                                Text("\(cal) kcal")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color.duoOrange)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.duoBackground)
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
    }

    // DateFormatter は生成コストが高いため static で一度だけ生成
    private static let hhmmFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.hhmmFmt.string(from: date)
    }

    private func pfcRow(label: String, emoji: String, percent: Double, grams: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(emoji)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Color.duoText)
                Spacer()
                Text(String(format: "%.1f%%", percent))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(color)
                Text("(目標: \(Int(target))%)")
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
            }

            HStack {
                Spacer()
                Text(String(format: "%.1fg", grams))
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.duoBackground)
        .cornerRadius(8)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return .duoGreen
        case 80..<90:  return Color(red: 0.4, green: 0.8, blue: 0.2)
        case 70..<80:  return .duoOrange
        case 50..<70:  return Color(red: 1.0, green: 0.5, blue: 0.0)
        default:       return .duoRed
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        todaySummary = await authManager.getTodayIntakeSummary()
        rebuildIntakeHistoryCache()
        await healthKit.fetchIntakeHealth()
        pfcAnalysis = healthKit.analyzePFCBalance()
        isLoading = false
    }

    private func rebuildIntakeHistoryCache() {
        intakeHistoryCache.mealsByType = Dictionary(grouping: todaySummary.meals, by: \.mealType)
            .mapValues { $0.sorted { $0.timestamp > $1.timestamp } }
        intakeHistoryCache.alcoholByType = Dictionary(grouping: todaySummary.alcoholLogs, by: \.alcoholType)
    }
}

#Preview {
    DailyIntakeView()
        .environmentObject(AuthenticationManager.shared)
}
import SwiftUI
import PhotosUI

struct PhotoLogView: View {
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var healthKit = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedImage: UIImage?
    @State private var comment: String = ""
    @State private var analyzedNutrition: AnalyzedNutrition?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showErrorSheet = false
    @State private var llmSettings = LLMSettings.defaultSettings
    @State private var fromHistory = false          // 履歴から選択したか
    @State private var selectedHistoryId: String?   // 選択中の履歴ID
    @State private var showManageView = false
    @State private var markAsFavorite = true   // FOODページへの保存（常にtrue）
    @State private var isPublicPost = true    // TOMOフィードへの公開（デフォルトOn）
    @State private var showPlusUpsell = false  // 10日以降フリーユーザーへのPlus誘導シート

    var body: some View {
        NavigationStack {
            ZStack {
                Color.duoBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 状態A: 初期画面（履歴 + カメラ選択）
                        if selectedImage == nil && analyzedNutrition == nil {
                            if !photoLogManager.history.isEmpty {
                                historySection
                            }
                            photoSelectionSection

                        // 状態B: 履歴から選択済み
                        } else if fromHistory, let nutrition = analyzedNutrition {
                            historySelectedBanner
                            nutritionResultSection(nutrition)

                        // 状態C: 写真を撮影/選択して分析
                        } else if selectedImage != nil {
                            photoDisplaySection
                            commentSection
                            if !errorMessage.isEmpty && analyzedNutrition == nil {
                                analysisErrorCard
                            }
                            if let nutrition = analyzedNutrition {
                                nutritionResultSection(nutrition)
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    // 状態B/C でのみ下部固定ボタンを表示
                    if selectedImage != nil || (fromHistory && analyzedNutrition != nil) {
                        VStack(spacing: 10) {
                            if !fromHistory && analyzedNutrition == nil && !photoLogManager.isAnalyzing {
                                LLMAPIKeyNotice()
                                analyzeButton
                            }
                            if analyzedNutrition != nil {
                                saveButton
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                        .background(.regularMaterial)
                    }
                }

                // ローディング
                if photoLogManager.isAnalyzing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("AIが分析中...")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color.duoDark.opacity(0.9))
                        .cornerRadius(16)
                    }
                }
            }
            .navigationTitle("📸 フォトログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("完了") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .foregroundColor(Color.duoGreen)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoPicker) {
                PHPhotoPicker(selectedImage: $selectedImage)
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showErrorSheet) {
                analysisErrorSheet
            }
            .task {
                llmSettings = await authManager.getLLMSettings()
            }
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(Color.duoGreen)
                Text("最近の記録から追加")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Text("\(photoLogManager.history.count)件")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    // 「最近の記録から追加」用なので直近30件のみで十分。
                    // 全件（利用期間が長いほど数百件規模）を都度描画すると
                    // 開くたびのレイアウト計算コストが線形に増えるため上限を設ける。
                    ForEach(photoLogManager.history.prefix(30)) { item in
                        historyCard(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private func historyCard(_ item: PhotoLogHistoryItem) -> some View {
        let isSelected = selectedHistoryId == item.id

        return Button {
            applyHistoryItem(item)
        } label: {
            VStack(spacing: 6) {
                // サムネイルまたはプレースホルダー
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 72, height: 72)

                    if let thumb = item.smallThumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("🍽️")
                            .font(.system(size: 28 * UIScale.font))
                    }

                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.duoGreen, lineWidth: 2)
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.duoGreen)
                            .background(Color.white.clipShape(Circle()))
                            .offset(x: 26, y: -26)
                    }
                }

                Text(item.displayName)
                    .font(.system(size: 10 * UIScale.font, weight: .semibold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)

                Text("\(item.calories)kcal")
                    .font(.system(size: 10 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoGreen)

                // 日付
                Text(item.timestamp, style: .date)
                    .font(.system(size: 9 * UIScale.font))
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                photoLogManager.deleteHistoryItem(id: item.id)
            } label: {
                Label("履歴から削除", systemImage: "trash")
            }
        }
    }

    private var historySelectedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(Color.duoGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("履歴から選択")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
                if let id = selectedHistoryId,
                   let item = photoLogManager.history.first(where: { $0.id == id }) {
                    Text(item.displayName)
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                }
            }
            Spacer()
            Button {
                resetToInitial()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("戻る")
                }
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(12)
        .background(Color.duoGreen.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Photo Selection

    private var photoSelectionSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("カメラで撮影")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.duoGreen)
                    .cornerRadius(12)
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("アルバムから選択")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(Color.duoGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.duoGreen.opacity(0.1))
                    .cornerRadius(12)
                }

                if !photoLogManager.history.isEmpty {
                    Button {
                        showManageView = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("フォトログを管理")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(Color.duoSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            .sheet(isPresented: $showManageView) {
                PhotoLogManageView()
            }
            .sheet(isPresented: $showPlusUpsell) {
                AIRequiresPlusSheet()
            }

            Text("食べ物や飲み物の写真を撮影すると、AIが自動で栄養素を分析します")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: - Photo Display

    private var photoDisplaySection: some View {
        VStack(spacing: 8) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
            }

            Button {
                resetToInitial()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("別の写真を選択")
                }
                .font(.caption)
                .foregroundColor(Color.duoGreen)
            }
        }
    }

    // MARK: - Comment

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💬 コメント（オプション）")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(Color.duoDark)

            TextField("例: 朝食、コーヒー、ワイン（より正確な分析に）", text: $comment)
                .font(.subheadline)
                .padding(12)
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                .submitLabel(.done)
                .onSubmit {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
        }
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button {
            Task {
                await analyzePhoto()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("AIで栄養素を分析")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.duoGreen, Color(red: 0.18, green: 0.62, blue: 0.0)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Analysis Error

    private var analysisErrorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("分析エラー")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
                Spacer()
                Button {
                    showErrorSheet = true
                } label: {
                    Text("詳細")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
            }

            Text(errorMessage)
                .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
                .lineLimit(4)
                .truncationMode(.tail)
        }
        .padding(14)
        .background(Color.red.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }

    private var analysisErrorSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(Color(.label))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    Button {
                        UIPasteboard.general.string = errorMessage
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("エラー内容をコピー")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .navigationTitle("エラー詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { showErrorSheet = false }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
    }

    // MARK: - Nutrition Result

    private func nutritionResultSection(_ nutrition: AnalyzedNutrition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("✨ 分析結果")
                .font(.headline)
                .fontWeight(.black)
                .foregroundColor(Color.duoDark)

            if !nutrition.description.isEmpty {
                Text(nutrition.description)
                    .font(.subheadline)
                    .foregroundColor(Color.duoSubtitle)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.duoGreen.opacity(0.1))
                    .cornerRadius(10)
            }

            VStack(spacing: 8) {
                nutritionRow(label: "カロリー", value: "\(nutrition.calories) kcal", icon: "🔥")
                nutritionRow(label: "たんぱく質", value: "\(String(format: "%.1f", nutrition.protein)) g", icon: "💪")
                nutritionRow(label: "脂質", value: "\(String(format: "%.1f", nutrition.fat)) g", icon: "🥑")
                nutritionRow(label: "炭水化物", value: "\(String(format: "%.1f", nutrition.carbs)) g", icon: "🍚")

                if nutrition.water > 0 {
                    nutritionRow(label: "水分", value: "\(nutrition.water) ml", icon: "💧")
                }
                if nutrition.caffeine > 0 {
                    nutritionRow(label: "カフェイン", value: "\(nutrition.caffeine) mg", icon: "☕")
                }
                if nutrition.alcohol > 0 {
                    nutritionRow(label: "アルコール", value: "\(String(format: "%.1f", nutrition.alcohol)) g", icon: "🍷")
                }
            }

            Text("確度: \(Int(nutrition.confidence * 100))%")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func nutritionRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Text(icon)
            Text(label)
                .font(.subheadline)
                .foregroundColor(Color.duoDark)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(Color.duoGreen)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        VStack(spacing: 10) {
            // TOMOフィードへの公開トグル（FOODページへの保存は常にON）
            Toggle(isOn: $isPublicPost) {
                HStack(spacing: 6) {
                    Image(systemName: isPublicPost ? "person.2.fill" : "person.2")
                        .foregroundColor(isPublicPost ? Color.duoBlue : Color(.systemGray3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TOMOフィードに公開")
                            .font(.system(size: 14 * UIScale.font, weight: .semibold))
                            .foregroundColor(Color.duoDark)
                        Text(isPublicPost ? "TOMOの友達にも表示されます" : "自分のFOODページにのみ表示")
                            .font(.system(size: 10 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
            .tint(Color.duoBlue)

            Button {
                Task {
                    await savePhotoLog()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("ヘルスに保存")
                        .fontWeight(.black)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.duoGreen)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    /// 履歴アイテムを選択して栄養結果を即適用
    private func applyHistoryItem(_ item: PhotoLogHistoryItem) {
        selectedHistoryId = item.id
        analyzedNutrition = item.analyzedNutrition
        comment = item.comment
        selectedImage = nil
        fromHistory = true
    }

    /// 初期状態にリセット
    private func resetToInitial() {
        selectedImage = nil
        analyzedNutrition = nil
        comment = ""
        fromHistory = false
        selectedHistoryId = nil
        markAsFavorite = true
        isPublicPost = true    // TOMOフィード公開はデフォルトOn
    }

    private func analyzePhoto() async {
        guard let image = selectedImage else { return }

        errorMessage = ""

        // 10日以降のフリーユーザーはAI停止 → Plus誘導シートを直接表示
        let activeDayCount = UserDefaults.standard.integer(forKey: "retention.activeDayCount")
        let hasCustomKey = AIQuotaManager.shared.hasCustomKey
        let isPlus = PlusManager.shared.isPlus
        if activeDayCount >= AI_FREE_MAX_DAYS && !isPlus && !hasCustomKey {
            showPlusUpsell = true
            return
        }

        do {
            // APIキー未設定でもサーバー経由（1日1回無料）で解析
            analyzedNutrition = try await photoLogManager.analyzePhoto(image, comment: comment, settings: llmSettings)
        } catch {
            let raw = error.localizedDescription
            // 10日以降のPlus必須エラー
            if raw.contains("QUOTA_REQUIRE_PLUS") {
                showPlusUpsell = true
                return
            }
            // クォータ超過メッセージをフレンドリーに整形（"|" 区切りのプレフィックスを除去）
            if raw.contains("QUOTA_") || raw.contains("今日のAI枠") || raw.contains("無料枠") || raw.contains("上限") {
                let msg = raw.components(separatedBy: "|").last ?? raw
                errorMessage = "⏰ \(msg)\n\n設定画面でAPIキーを登録すると無制限に使えます。"
            } else {
                errorMessage = raw
                if comment.count > 80 {
                    errorMessage += "\n\n💡 コメントを少し短くして再分析してみてください。"
                }
            }
        }
    }

    private func savePhotoLog() async {
        guard let nutrition = analyzedNutrition else { return }

        // 履歴からの再利用時は savePhotoLogWithoutHistory() が HealthKit 保存を行わないため、
        // ここで直接保存する。新規アップロード時は photoLogManager.savePhotoLog() が
        // 保存を担当する（AuthenticationManager.swift）ため、ここでは呼ばない
        // ── 二重登録防止 ──。
        let mealNutrition = MealNutrition(
            calories: nutrition.calories,
            protein: nutrition.protein,
            fat: nutrition.fat,
            carbs: nutrition.carbs,
            sugar: nutrition.sugar,
            fiber: nutrition.fiber,
            sodium: nutrition.sodium
        )

        // フォトログを保存（履歴からの場合は履歴への再追加をスキップ）
        var entry = PhotoLogEntry()
        entry.imageData = selectedImage?.jpegData(compressionQuality: 0.82)
        entry.comment = comment
        entry.analyzedNutrition = nutrition
        entry.isFavorite = true          // FOODページへは常に保存
        entry.isPublic   = isPublicPost  // TOMOフィードへの公開はユーザー選択
        if fromHistory {
            // savePhotoLogWithoutHistory 側はHealthKit保存を行わないため、ここで1回だけ保存
            await healthKit.saveMealNutrition(mealNutrition)
            photoLogManager.savePhotoLogWithoutHistory(entry)
        } else {
            // savePhotoLog 側が HealthKit への保存（カロリー等）を内部で1回だけ行うため、
            // ここで重複して saveMealNutrition を呼ばないこと（二重記録の原因になっていた）
            photoLogManager.savePhotoLog(entry)
        }

        // 水分
        if nutrition.water > 0 {
            await healthKit.saveWaterIntake(amountMl: Double(nutrition.water), timestamp: Date())
        }

        // カフェイン
        if nutrition.caffeine > 0 {
            await healthKit.saveCaffeineIntake(caffeineMg: Double(nutrition.caffeine), timestamp: Date())
        }

        // TODO: アルコールの保存

        dismiss()
    }
}

// MARK: - Photo Log Manage View

struct PhotoLogManageView: View {
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteId: String?
    @State private var editingItem: PhotoLogHistoryItem?

    var body: some View {
        NavigationView {
            Group {
                if photoLogManager.history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 48 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                        Text("記録がありません")
                            .font(.subheadline)
                            .foregroundColor(Color.duoSubtitle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        let favorites = photoLogManager.history.filter { $0.isFavorite }
                        let others = photoLogManager.history.filter { !$0.isFavorite }

                        if !favorites.isEmpty {
                            Section(header: Text("お気に入り").font(.caption).foregroundColor(Color.duoSubtitle)) {
                                ForEach(favorites) { item in
                                    manageRow(item)
                                }
                            }
                        }
                        Section(header: Text(favorites.isEmpty ? "すべての記録（\(photoLogManager.history.count)件）" : "その他").font(.caption).foregroundColor(Color.duoSubtitle)) {
                            ForEach(others) { item in
                                manageRow(item)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("フォトログを管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
            .alert("削除しますか？", isPresented: $showDeleteConfirm) {
                Button("削除", role: .destructive) {
                    if let id = pendingDeleteId {
                        photoLogManager.deleteHistoryItem(id: id)
                    }
                    pendingDeleteId = nil
                }
                Button("キャンセル", role: .cancel) { pendingDeleteId = nil }
            } message: {
                Text("この食事記録を履歴から削除します。")
            }
            .sheet(item: $editingItem) { item in
                PhotoLogEditView(item: item)
            }
        }
    }

    private func manageRow(_ item: PhotoLogHistoryItem) -> some View {
        Button {
            editingItem = item
        } label: {
            HStack(spacing: 12) {
                if let thumb = item.smallThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 52, height: 52)
                        Text("🍽️").font(.system(size: 22 * UIScale.font))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 14 * UIScale.font, weight: .semibold))
                        .foregroundColor(Color.duoDark)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(item.calories) kcal")
                            .font(.system(size: 12 * UIScale.font, weight: .bold))
                            .foregroundColor(Color.duoGreen)
                        Text(item.timestamp, style: .date)
                            .font(.system(size: 11 * UIScale.font))
                            .foregroundColor(Color.duoSubtitle)
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        photoLogManager.toggleFavorite(id: item.id)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 20 * UIScale.font))
                            .foregroundColor(item.isFavorite ? Color(hex: "#FFD700") : Color.duoSubtitle)
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingDeleteId = item.id
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18 * UIScale.font))
                            .foregroundColor(Color(hex: "#FF4B4B"))
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * UIScale.font))
                        .foregroundColor(Color.duoSubtitle.opacity(0.5))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Photo Log Edit View

struct PhotoLogEditView: View {
    @StateObject private var photoLogManager = PhotoLogManager.shared
    @Environment(\.dismiss) private var dismiss

    let item: PhotoLogHistoryItem

    @State private var foodName: String
    @State private var calories: String
    @State private var protein: String
    @State private var fat: String
    @State private var carbs: String
    @State private var sugar: String
    @State private var fiber: String
    @State private var sodium: String
    @State private var water: String
    @State private var caffeine: String
    @State private var alcohol: String
    @State private var descriptionText: String
    @State private var showSavedBanner = false

    init(item: PhotoLogHistoryItem) {
        self.item = item
        let n = item.analyzedNutrition
        _foodName       = State(initialValue: item.foodName)
        _calories       = State(initialValue: "\(n.calories)")
        _protein        = State(initialValue: String(format: "%.1f", n.protein))
        _fat            = State(initialValue: String(format: "%.1f", n.fat))
        _carbs          = State(initialValue: String(format: "%.1f", n.carbs))
        _sugar          = State(initialValue: String(format: "%.1f", n.sugar))
        _fiber          = State(initialValue: String(format: "%.1f", n.fiber))
        _sodium         = State(initialValue: String(format: "%.0f", n.sodium))
        _water          = State(initialValue: "\(n.water)")
        _caffeine       = State(initialValue: "\(n.caffeine)")
        _alcohol        = State(initialValue: String(format: "%.1f", n.alcohol))
        _descriptionText = State(initialValue: n.description)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("食品情報")) {
                    HStack {
                        if let thumb = item.smallThumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 60, height: 60)
                                Text("🍽️").font(.system(size: 26 * UIScale.font))
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("料理名", text: $foodName)
                                .font(.system(size: 15 * UIScale.font, weight: .semibold))
                            Text(item.timestamp, style: .date)
                                .font(.caption)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("説明・メモ")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                        TextField("説明", text: $descriptionText, axis: .vertical)
                            .font(.system(size: 14 * UIScale.font))
                            .lineLimit(3, reservesSpace: true)
                    }
                }

                Section(header: Text("カロリー")) {
                    editRow(label: "カロリー", value: $calories, unit: "kcal", keyboard: .numberPad)
                }

                Section(header: Text("三大栄養素")) {
                    editRow(label: "たんぱく質", value: $protein, unit: "g", keyboard: .decimalPad)
                    editRow(label: "脂質",       value: $fat,     unit: "g", keyboard: .decimalPad)
                    editRow(label: "炭水化物",   value: $carbs,   unit: "g", keyboard: .decimalPad)
                    editRow(label: "糖質",       value: $sugar,   unit: "g", keyboard: .decimalPad)
                    editRow(label: "食物繊維",   value: $fiber,   unit: "g", keyboard: .decimalPad)
                }

                Section(header: Text("その他の成分")) {
                    editRow(label: "ナトリウム", value: $sodium,   unit: "mg", keyboard: .numberPad)
                    editRow(label: "水分",       value: $water,    unit: "ml", keyboard: .numberPad)
                    editRow(label: "カフェイン", value: $caffeine, unit: "mg", keyboard: .numberPad)
                    editRow(label: "アルコール", value: $alcohol,  unit: "g",  keyboard: .decimalPad)
                }
            }
            .navigationTitle("食事を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(Color.duoSubtitle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                }
            }
            .overlay(alignment: .top) {
                if showSavedBanner {
                    Text("保存しました")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.duoGreen)
                        .cornerRadius(20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSavedBanner)
        }
    }

    private func editRow(label: String, value: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .foregroundColor(Color.duoDark)
            Spacer()
            TextField("0", text: value)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .foregroundColor(Color.duoGreen)
            Text(unit)
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 30, alignment: .leading)
        }
    }

    private func save() {
        var updated = item
        updated.foodName = foodName.trimmingCharacters(in: .whitespaces)

        var n = item.analyzedNutrition
        n.description = descriptionText
        n.calories  = Int(calories) ?? n.calories
        n.protein   = Double(protein) ?? n.protein
        n.fat       = Double(fat) ?? n.fat
        n.carbs     = Double(carbs) ?? n.carbs
        n.sugar     = Double(sugar) ?? n.sugar
        n.fiber     = Double(fiber) ?? n.fiber
        n.sodium    = Double(sodium) ?? n.sodium
        n.water     = Int(water) ?? n.water
        n.caffeine  = Int(caffeine) ?? n.caffeine
        n.alcohol   = Double(alcohol) ?? n.alcohol
        updated.analyzedNutrition = n

        photoLogManager.updateHistoryItem(updated)
        showSavedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSavedBanner = false
            dismiss()
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        if sourceType == .camera {
            picker.modalPresentationStyle = .fullScreen
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
            picker.showsCameraControls = true
            picker.cameraFlashMode = .auto
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = resized(image)
            }
            parent.dismiss()
        }

        private func resized(_ image: UIImage, maxDimension: CGFloat = 1440) -> UIImage {
            let size = image.size
            let maxSide = max(size.width, size.height)
            guard maxSide > maxDimension else { return image }
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - PHPhotoPicker（フォトライブラリ選択）
// UIImagePickerController.photoLibrary は iOS 14+ で非推奨のため PHPickerViewController を使用

struct PHPhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPhotoPicker
        init(_ parent: PHPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    if let uiImage = image as? UIImage {
                        self.parent.selectedImage = self.resized(uiImage)
                    }
                }
            }
        }

        private func resized(_ image: UIImage, maxDimension: CGFloat = 1440) -> UIImage {
            let size = image.size
            let maxSide = max(size.width, size.height)
            guard maxSide > maxDimension else { return image }
            let scale = maxDimension / maxSide
            let newSize = CGSize(
                width: (size.width * scale).rounded(),
                height: (size.height * scale).rounded()
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
    }
}

#Preview {
    PhotoLogView()
}
