import SwiftUI

struct TimeSlotGoalEditView: View {
    let timeSlot: TimeSlot
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trainingGoal: Int = 1
    @State private var mindfulnessGoal: Int = 1
    @State private var standEnabled: Bool = false

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    trainingSection
                    mindfulnessSection
                    if timeSlot != .midnight { standSection }

                    resetButton
                    saveButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("\(timeSlot.emoji) \(timeSlot.displayName)の目標")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentGoal()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeSlot.emoji)
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(timeSlot.displayName)の目標設定")
                        .font(.title3).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text(timeSlot.timeRange)
                        .font(.subheadline)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Training Section

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "💪", title: "トレーニング")

            HStack {
                Text("目標セット数")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)
                Spacer()

                HStack(spacing: 12) {
                    Button {
                        if trainingGoal > 0 { trainingGoal -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(trainingGoal > 0 ? Color.duoGreen : Color(.systemGray4))
                    }
                    .disabled(trainingGoal <= 0)

                    Text("\(trainingGoal)")
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                        .frame(width: 40)

                    Button {
                        if trainingGoal < 10 { trainingGoal += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color.duoGreen)
                    }
                }
            }

            Text("この時間帯に完了するトレーニングセット数の目標")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Mindfulness Section

    private var mindfulnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "🧘", title: "マインドフルネス")

            HStack {
                Text("目標時間（分）")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)
                Spacer()

                HStack(spacing: 12) {
                    Button {
                        if mindfulnessGoal > 0 { mindfulnessGoal -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(mindfulnessGoal > 0 ? Color.duoPurple : Color(.systemGray4))
                    }
                    .disabled(mindfulnessGoal <= 0)

                    Text("\(mindfulnessGoal)")
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                        .frame(width: 40)

                    Button {
                        if mindfulnessGoal < 60 { mindfulnessGoal += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color.duoPurple)
                    }
                    .disabled(mindfulnessGoal >= 60)
                }
            }

            Text("1分瞑想・3分ストレッチの合計分数で達成")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Stand Section（20分スタンド）

    private let standColor = Color(red: 0.0, green: 0.6, blue: 0.85)

    private var standSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionTitle(icon: "🧍", title: "20分スタンド")
                Spacer()
                Toggle("", isOn: $standEnabled)
                    .tint(standColor)
                    .labelsHidden()
            }

            if standEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(standColor)
                    Text("20分タイマー完了、またはWatchで20分連続スタンド検知で達成")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            trainingGoal    = 1
            mindfulnessGoal = 1
            standEnabled    = false
        } label: {
            Text("デフォルトに戻す")
                .font(.subheadline).fontWeight(.bold)
                .foregroundColor(Color.duoOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveGoal()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("保存する")
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

    // MARK: - Helpers

    private func sectionTitle(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.title3)
            Text(title)
                .font(.headline).fontWeight(.black)
                .foregroundColor(Color.duoDark)
        }
    }

    private func loadCurrentGoal() {
        if let goal = timeSlotManager.settings.goalFor(timeSlot) {
            trainingGoal = goal.trainingGoal
            mindfulnessGoal = goal.mindfulnessGoal
            standEnabled = goal.standGoal.enabled
        }
    }

    private func saveGoal() {
        var goal = timeSlotManager.settings.goalFor(timeSlot) ?? TimeSlotGoal(timeSlot: timeSlot)
        goal.trainingGoal = trainingGoal
        goal.mindfulnessGoal = mindfulnessGoal
        goal.standGoal.enabled = standEnabled

        timeSlotManager.settings.updateGoal(goal)
        timeSlotManager.saveGoalTemplate()

        Task {
            await timeSlotManager.saveTodaySettings()
            dismiss()
        }
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalEditView(timeSlot: .morning)
    }
}
