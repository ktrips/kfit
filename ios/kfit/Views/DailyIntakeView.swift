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
