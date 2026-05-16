import SwiftUI

/// 今日の摂取記録画面（食事・水・コーヒー・アルコール）
struct DailyIntakeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var todaySummary = TodayIntakeSummary()
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
                            await healthKit.fetchAll()
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
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                summaryItem(title: "カロリー", value: "\(todaySummary.totalCalories)", unit: "kcal", color: .duoOrange)
                Divider()
                summaryItem(title: "水分", value: "\(todaySummary.totalWaterMl)", unit: "ml", color: .duoBlue)
            }
            .frame(height: 60)

            Divider()

            HStack(spacing: 20) {
                summaryItem(title: "カフェイン", value: "\(todaySummary.totalCaffeineMg)", unit: "mg", color: .duoBrown)
                Divider()
                summaryItem(title: "アルコール", value: String(format: "%.1f", todaySummary.totalAlcoholG), unit: "g", color: .duoPurple)
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
                        logs: todaySummary.meals.filter { $0.mealType == mealType },
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
                        logs: todaySummary.alcoholLogs.filter { $0.alcoholType == alcoholType },
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
        }
        .padding()
        .background(Color.duoCard)
        .cornerRadius(16)
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
        await healthKit.fetchAll()
        pfcAnalysis = healthKit.analyzePFCBalance()
        isLoading = false
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
    @State private var llmSettings = LLMSettings.defaultSettings
    @State private var fromHistory = false          // 履歴から選択したか
    @State private var selectedHistoryId: String?   // 選択中の履歴ID

    var body: some View {
        NavigationView {
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
                            saveButton

                        // 状態C: 写真を撮影/選択して分析
                        } else if selectedImage != nil {
                            photoDisplaySection
                            commentSection
                            if analyzedNutrition == nil && !photoLogManager.isAnalyzing {
                                analyzeButton
                            }
                            if let nutrition = analyzedNutrition {
                                nutritionResultSection(nutrition)
                                saveButton
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(Color.duoGreen)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showPhotoPicker) {
                ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
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
                HStack(spacing: 10) {
                    ForEach(photoLogManager.history) { item in
                        historyCard(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.white)
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

                    if let thumb = item.thumbnail {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("🍽️")
                            .font(.system(size: 28))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.duoDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)

                Text("\(item.calories)kcal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoGreen)

                // 日付
                Text(item.timestamp, style: .date)
                    .font(.system(size: 9))
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
        VStack(spacing: 16) {
            Text("📸 写真を撮影または選択")
                .font(.title2)
                .fontWeight(.black)
                .foregroundColor(Color.duoDark)

            Text("食べ物や飲み物の写真を撮影すると、AIが自動で栄養素を分析します")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Photo Display

    private var photoDisplaySection: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("💬 コメント（オプション）")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(Color.duoDark)

            Text("「朝食」「コーヒー」「ワイン」などと入力すると、より正確に分析できます")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)

            TextField("例: 朝食、コーヒー、ワイン", text: $comment)
                .font(.subheadline)
                .padding(12)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
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
        .disabled(llmSettings.apiKey.isEmpty)
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
        .background(Color.white)
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
    }

    private func analyzePhoto() async {
        guard let image = selectedImage else { return }

        if llmSettings.apiKey.isEmpty {
            errorMessage = "APIキーが設定されていません。設定画面からLLM設定を行ってください。"
            showError = true
            return
        }

        do {
            analyzedNutrition = try await photoLogManager.analyzePhoto(image, comment: comment, settings: llmSettings)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func savePhotoLog() async {
        guard let nutrition = analyzedNutrition else { return }

        // MealNutritionに変換してHealthKitに保存
        let mealNutrition = MealNutrition(
            calories: nutrition.calories,
            protein: nutrition.protein,
            fat: nutrition.fat,
            carbs: nutrition.carbs,
            sugar: nutrition.sugar,
            fiber: nutrition.fiber,
            sodium: nutrition.sodium
        )

        await healthKit.saveMealNutrition(mealNutrition)

        // 水分
        if nutrition.water > 0 {
            await healthKit.saveWaterIntake(amountMl: Double(nutrition.water), timestamp: Date())
        }

        // カフェイン
        if nutrition.caffeine > 0 {
            await healthKit.saveCaffeineIntake(caffeineMg: Double(nutrition.caffeine), timestamp: Date())
        }

        // TODO: アルコールの保存

        // フォトログを保存（履歴からの場合は履歴への再追加をスキップ）
        var entry = PhotoLogEntry()
        entry.imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        entry.comment = comment
        entry.analyzedNutrition = nutrition
        if fromHistory {
            photoLogManager.savePhotoLogWithoutHistory(entry)
        } else {
            photoLogManager.savePhotoLog(entry)
        }

        dismiss()
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

        // カメラの場合、フルスクリーンでプレビューを表示
        if sourceType == .camera {
            picker.modalPresentationStyle = .fullScreen
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
            picker.showsCameraControls = true

            // 画面全体を使用するようにカメラのアスペクト比を調整
            picker.cameraFlashMode = .auto

            // カメラプレビューを画面全体に拡大（16:9や4:3から画面全体へ）
            let screenHeight = UIScreen.main.bounds.height
            let screenWidth = UIScreen.main.bounds.width
            let cameraAspectRatio: CGFloat = 4.0 / 3.0  // カメラの標準アスペクト比
            let screenAspectRatio = screenHeight / screenWidth

            var scale: CGFloat = 1.0
            if screenAspectRatio > cameraAspectRatio {
                // 画面の方が縦長の場合（ほとんどのiPhone）
                scale = screenHeight / (screenWidth * cameraAspectRatio)
            } else {
                // 画面の方が横長の場合
                scale = screenWidth / (screenHeight / cameraAspectRatio)
            }

            // スケール変換を適用してプレビューを拡大
            picker.cameraViewTransform = CGAffineTransform(scaleX: scale, y: scale)
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
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    PhotoLogView()
}
