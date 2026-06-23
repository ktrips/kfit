import SwiftUI

struct RecordMenuView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthenticationManager
    // V1: EnvironmentObject で受け取る
    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var showWorkoutTracker = false
    @State private var showPhotoLog = false
    @State private var showMindfulnessSession = false
    @State private var showStretchSession = false
    @State private var todayIntake = TodayIntakeSummary()
    @State private var showConfirmAlert = false
    @State private var pendingRecordAction: (() async -> Void)?
    @State private var confirmMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // ヘッダー
                        VStack(spacing: 8) {
                            Image("mascot")
                                .resizable().scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 3))

                            Text("何を記録しますか？")
                                .font(.title2).fontWeight(.black)
                                .foregroundColor(Color.duoDark)
                        }
                        .padding(.top, 20)

                        // トレーニング記録
                        recordCategoryCard(
                            icon: "💪",
                            title: "トレーニング",
                            subtitle: "運動の記録",
                            color: Color.duoGreen
                        ) {
                            showWorkoutTracker = true
                        }

                        // マインドフルネス記録
                        VStack(spacing: 12) {
                            Text("マインドフル記録")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                quickRecordButton(emoji: "🧘", label: "1分瞑想", color: Color.duoPurple) {
                                    showMindfulnessSession = true
                                }
                                quickRecordButton(emoji: "🤸", label: "3分ストレッチ", color: Color.duoBlue) {
                                    showStretchSession = true
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)

                        // 食事記録
                        VStack(spacing: 12) {
                            Text("食事記録")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // 行1: 朝食・昼食・夕食
                            HStack(spacing: 12) {
                                quickRecordButton(emoji: "🌅", label: "朝食", color: Color.duoOrange) {
                                    confirmMessage = "朝食 400kcal を記録しますか？"
                                    pendingRecordAction = { await recordMealAndTimeSlot(.breakfast) }
                                    showConfirmAlert = true
                                }
                                quickRecordButton(emoji: "🍱", label: "昼食", color: Color.duoOrange) {
                                    confirmMessage = "昼食 600kcal を記録しますか？"
                                    pendingRecordAction = { await recordMealAndTimeSlot(.lunch) }
                                    showConfirmAlert = true
                                }
                                quickRecordButton(emoji: "🍽️", label: "夕食", color: Color.duoOrange) {
                                    confirmMessage = "夕食 800kcal を記録しますか？"
                                    pendingRecordAction = { await recordMealAndTimeSlot(.dinner) }
                                    showConfirmAlert = true
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)

                        photoLogButton

                        // 水分・その他（行2: スナック・ドリンク・アルコール）
                        VStack(spacing: 12) {
                            Text("水分・その他")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                // スナック
                                quickRecordButton(emoji: "🍫", label: "スナック", color: Color.duoOrange) {
                                    confirmMessage = "スナック 100kcal を記録しますか？"
                                    pendingRecordAction = { await recordMealAndTimeSlot(.snack) }
                                    showConfirmAlert = true
                                }

                                // ドリンク（水 / コーヒーを選択）
                                Menu {
                                    Button("💧 水（200ml）") {
                                        confirmMessage = "水 200ml を記録しますか？"
                                        pendingRecordAction = { await recordWaterAndTimeSlot() }
                                        showConfirmAlert = true
                                    }
                                    Button("☕ コーヒー（150ml）") {
                                        confirmMessage = "コーヒー 150ml (カフェイン90mg) を記録しますか？"
                                        pendingRecordAction = { await recordCoffeeAndTimeSlot() }
                                        showConfirmAlert = true
                                    }
                                    Button("🍊 フルーツジュース（200ml）") {
                                        confirmMessage = "フルーツジュース 200ml (76kcal / 糖質18g) を記録しますか？"
                                        pendingRecordAction = { await recordFruitJuiceAndTimeSlot() }
                                        showConfirmAlert = true
                                    }
                                } label: {
                                    quickRecordMenuButton(emoji: "🥤", label: "ドリンク", color: Color.duoBlue)
                                }

                                // アルコール（種類を選択）
                                Menu {
                                    Button("🍺 ビール") {
                                        confirmMessage = "ビール 350ml (アルコール14g) を記録しますか？"
                                        pendingRecordAction = { await recordAlcoholAndTimeSlot(.beer) }
                                        showConfirmAlert = true
                                    }
                                    Button("🍷 ワイン") {
                                        confirmMessage = "ワイン 120ml (アルコール11.5g) を記録しますか？"
                                        pendingRecordAction = { await recordAlcoholAndTimeSlot(.wine) }
                                        showConfirmAlert = true
                                    }
                                    Button("🥃 酎ハイ") {
                                        confirmMessage = "酎ハイ 350ml (アルコール19.6g) を記録しますか？"
                                        pendingRecordAction = { await recordAlcoholAndTimeSlot(.chuhai) }
                                        showConfirmAlert = true
                                    }
                                    Button("🚫 ノンアル") {
                                        confirmMessage = "ノンアルコール 0g を記録しますか？"
                                        pendingRecordAction = { await recordAlcoholAndTimeSlot(.nonAlcoholic) }
                                        showConfirmAlert = true
                                    }
                                } label: {
                                    quickRecordMenuButton(emoji: "🍺", label: "アルコール", color: Color.duoPurple)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(Color.duoSubtitle)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showWorkoutTracker) {
            ExerciseTrackerView(isPresented: $showWorkoutTracker)
                .environmentObject(authManager)
        }
        .fullScreenCover(isPresented: $showPhotoLog, onDismiss: {
            Task {
                todayIntake = await authManager.getTodayIntakeSummary()
            }
        }) {
            PhotoLogView()
        }
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
                    }
                }
            }
        }
        .onAppear {
            Task {
                todayIntake = await authManager.getTodayIntakeSummary()
            }
        }
        .alert(confirmMessage, isPresented: $showConfirmAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("記録する") {
                Task {
                    await pendingRecordAction?()
                    todayIntake = await authManager.getTodayIntakeSummary()
                    pendingRecordAction = nil
                }
            }
        }
    }

    private func currentTimeSlot() -> TimeSlot {
        TimeSlot.current()
    }

    private func recordMealAndTimeSlot(_ mealType: MealType) async {
        let settings = await authManager.getIntakeSettings()
        let calories = settings.caloriesFor(mealType: mealType)
        await TimeSlotManager.shared.recordMealLog(at: currentTimeSlot(), calories: calories)
        await authManager.recordMeal(mealType: mealType)
    }

    private func recordWaterAndTimeSlot() async {
        let settings = await authManager.getIntakeSettings()
        await TimeSlotManager.shared.recordDrinkLog(at: currentTimeSlot(), ml: settings.waterPerCup)
        await authManager.recordWater()
    }

    private func recordCoffeeAndTimeSlot() async {
        let settings = await authManager.getIntakeSettings()
        await TimeSlotManager.shared.recordDrinkLog(at: currentTimeSlot(), ml: settings.coffeePerCup)
        await authManager.recordCoffee()
    }

    private func recordFruitJuiceAndTimeSlot() async {
        await TimeSlotManager.shared.recordDrinkLog(at: currentTimeSlot(), ml: 200)
        await authManager.recordFruitJuice()
    }

    private func recordAlcoholAndTimeSlot(_ alcoholType: AlcoholType) async {
        if let setting = (await authManager.getIntakeSettings()).settingFor(alcoholType: alcoholType) {
            await TimeSlotManager.shared.recordDrinkLog(at: currentTimeSlot(), ml: setting.amountMl)
        }
        await authManager.recordAlcohol(alcoholType: alcoholType)
    }

    private var photoLogButton: some View {
        Button {
            showPhotoLog = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.24))
                        .frame(width: 54, height: 54)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24 * UIScale.font, weight: .black))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("フォトログ")
                        .font(.system(size: 20 * UIScale.font, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("写真からカロリーとPFCをAI分析")
                        .font(.system(size: 12 * UIScale.font, weight: .bold))
                        .foregroundColor(.white.opacity(0.88))
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 24 * UIScale.font, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#FF9600"), Color(hex: "#FF4B4B")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(18)
            .shadow(color: Color(hex: "#FF9600").opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - カテゴリーカード
    private func recordCategoryCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(icon)
                    .font(.system(size: 48 * UIScale.font))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Color.duoSubtitle)
                }

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(color)
            }
            .padding(20)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: color.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - クイック記録ボタン（小）
    private func quickRecordButton(emoji: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 32 * UIScale.font))
                Text(label)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - クイック記録ボタン（Menu用・chevron付き）
    private func quickRecordMenuButton(emoji: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 32 * UIScale.font))
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(Color.duoDark)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8 * UIScale.font, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }

    // MARK: - クイック記録行
    private func quickRecordRow(emoji: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(emoji)
                    .font(.title2)
                Text(label)
                    .font(.body).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(color)
            }
            .padding(16)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
