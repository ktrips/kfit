import SwiftUI

struct RecordMenuView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showWorkoutTracker = false
    @State private var todayIntake = TodayIntakeSummary()

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

                        // 食事記録
                        VStack(spacing: 12) {
                            Text("食事記録")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                quickRecordButton(emoji: "🌅", label: "朝食", color: Color.duoOrange) {
                                    Task {
                                        await authManager.recordMeal(mealType: .breakfast)
                                        todayIntake = await authManager.getTodayIntakeSummary()
                                    }
                                }
                                quickRecordButton(emoji: "🍱", label: "昼食", color: Color.duoOrange) {
                                    Task {
                                        await authManager.recordMeal(mealType: .lunch)
                                        todayIntake = await authManager.getTodayIntakeSummary()
                                    }
                                }
                                quickRecordButton(emoji: "🍽️", label: "夕食", color: Color.duoOrange) {
                                    Task {
                                        await authManager.recordMeal(mealType: .dinner)
                                        todayIntake = await authManager.getTodayIntakeSummary()
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)

                        // 水分・その他
                        VStack(spacing: 12) {
                            Text("水分・その他")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(Color.duoDark)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 10) {
                                quickRecordRow(emoji: "💧", label: "水", color: Color.duoBlue) {
                                    Task {
                                        await authManager.recordWater()
                                        todayIntake = await authManager.getTodayIntakeSummary()
                                    }
                                }
                                quickRecordRow(emoji: "☕", label: "コーヒー", color: Color.duoBrown) {
                                    Task {
                                        await authManager.recordCoffee()
                                        todayIntake = await authManager.getTodayIntakeSummary()
                                    }
                                }
                                Menu {
                                    Button("🍺 ビール") {
                                        Task {
                                            await authManager.recordAlcohol(alcoholType: .beer)
                                            todayIntake = await authManager.getTodayIntakeSummary()
                                        }
                                    }
                                    Button("🍷 ワイン") {
                                        Task {
                                            await authManager.recordAlcohol(alcoholType: .wine)
                                            todayIntake = await authManager.getTodayIntakeSummary()
                                        }
                                    }
                                    Button("🥃 酎ハイ") {
                                        Task {
                                            await authManager.recordAlcohol(alcoholType: .chuhai)
                                            todayIntake = await authManager.getTodayIntakeSummary()
                                        }
                                    }
                                    Button("🚫 ノンアル") {
                                        Task {
                                            await authManager.recordAlcohol(alcoholType: .nonAlcoholic)
                                            todayIntake = await authManager.getTodayIntakeSummary()
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("🍺")
                                            .font(.title2)
                                        Text("アルコール")
                                            .font(.body).fontWeight(.semibold)
                                            .foregroundColor(Color.duoDark)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(Color.duoSubtitle)
                                    }
                                    .padding(16)
                                    .background(Color.duoPurple.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
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
        .onAppear {
            Task {
                todayIntake = await authManager.getTodayIntakeSummary()
            }
        }
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
                    .font(.system(size: 48))

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
            .background(Color.white)
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
                    .font(.system(size: 32))
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
