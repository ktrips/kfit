import SwiftUI

/// 今日の摂取記録画面（食事・水・コーヒー・アルコール）
struct DailyIntakeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var todaySummary = TodayIntakeSummary()
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var isRefreshingHealth = false

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

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        todaySummary = await authManager.getTodayIntakeSummary()
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

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if selectedImage == nil {
                            // 写真選択
                            photoSelectionSection
                        } else {
                            // 写真表示
                            photoDisplaySection

                            // コメント入力
                            commentSection

                            // 分析ボタン
                            if analyzedNutrition == nil && !photoLogManager.isAnalyzing {
                                analyzeButton
                            }

                            // 分析結果
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
            .sheet(isPresented: $showCamera) {
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
        .padding(.vertical, 40)
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
                selectedImage = nil
                analyzedNutrition = nil
                comment = ""
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

        // フォトログを保存
        var entry = PhotoLogEntry()
        entry.imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        entry.comment = comment
        entry.analyzedNutrition = nutrition
        photoLogManager.savePhotoLog(entry)

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
