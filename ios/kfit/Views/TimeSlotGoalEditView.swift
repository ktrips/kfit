import SwiftUI

struct TimeSlotGoalEditView: View {
    let timeSlot: TimeSlot
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trainingGoal: Int = 1
    @State private var mindfulnessGoal: Int = 1
    @State private var mealRequired: Bool = true
    @State private var drinkRequired: Bool = true
    @State private var mindInputRequired: Bool = false
    @State private var reminderEnabled: Bool = false
    @State private var reminderTime: Date = Date()

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    trainingSection
                    mindfulnessSection
                    logSection
                    reminderSection

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
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Mindfulness Section

    private var mindfulnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "🧘", title: "マインドフルネス")

            HStack {
                Text("目標回数")
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
                        if mindfulnessGoal < 10 { mindfulnessGoal += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color.duoPurple)
                    }
                }
            }

            Text("この時間帯に実施するマインドフルネスの目標回数")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Log Section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "📝", title: "ログ記録")

            Toggle(isOn: $mealRequired) {
                HStack(spacing: 8) {
                    Text("🍽️")
                        .font(.title3)
                    Text("食事記録")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(Color.duoDark)
                }
            }
            .tint(Color.duoOrange)

            Toggle(isOn: $drinkRequired) {
                HStack(spacing: 8) {
                    Text("💧")
                        .font(.title3)
                    Text("飲み物記録")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(Color.duoDark)
                }
            }
            .tint(Color.duoBlue)

            Toggle(isOn: $mindInputRequired) {
                HStack(spacing: 8) {
                    Text("💭")
                        .font(.title3)
                    Text("マインド入力")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(Color.duoDark)
                }
            }
            .tint(Color.duoPurple)

            Text("この時間帯に記録する必要がある項目をオンにしてください")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Reminder Section

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "🔔", title: "リマインダー")

            Toggle(isOn: $reminderEnabled) {
                Text("リマインダーを有効化")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)
            }
            .tint(Color.duoGreen)

            if reminderEnabled {
                DatePicker("通知時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .foregroundColor(Color.duoDark)
            }

            Text("この時間帯に目標達成を促す通知を受け取ります")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
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
            mealRequired = goal.logGoal.mealRequired
            drinkRequired = goal.logGoal.drinkRequired
            mindInputRequired = goal.logGoal.mindInputRequired
            reminderEnabled = goal.reminderEnabled
            if let time = goal.reminderTime {
                reminderTime = time
            }
        }
    }

    private func saveGoal() {
        var goal = TimeSlotGoal(timeSlot: timeSlot)
        goal.trainingGoal = trainingGoal
        goal.mindfulnessGoal = mindfulnessGoal
        goal.logGoal.mealRequired = mealRequired
        goal.logGoal.drinkRequired = drinkRequired
        goal.logGoal.mindInputRequired = mindInputRequired
        goal.reminderEnabled = reminderEnabled
        goal.reminderTime = reminderEnabled ? reminderTime : nil

        timeSlotManager.settings.updateGoal(goal)

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
