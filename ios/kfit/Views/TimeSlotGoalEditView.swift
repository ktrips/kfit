import SwiftUI

struct TimeSlotGoalEditView: View {
    let timeSlot: TimeSlot
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var trainingGoal: Int = 1
    @State private var mindfulnessGoal: Int = 1
    @State private var mindInputRequired: Bool = false
    // ストレッチ・ヨガ
    @State private var stretchEnabled: Bool = false
    @State private var stretchMinutes: Int = 3

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    trainingSection
                    mindfulnessSection
                    if timeSlot != .midnight { stretchSection }
                    logSection

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

    // MARK: - Stretch Section

    private let stretchColor = Color(red: 0.22, green: 0.75, blue: 0.56)

    private var stretchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionTitle(icon: "🤸", title: "ストレッチ・ヨガ")
                Spacer()
                Toggle("", isOn: $stretchEnabled)
                    .tint(stretchColor)
                    .labelsHidden()
            }

            if stretchEnabled {
                stretchStepperRow(icon: "🤸", label: "目標時間（分）", value: $stretchMinutes, max: 30)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(stretchColor)
                    Text("マインドフルネス（種類不問）合計\(stretchMinutes)分で達成")
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    private func stretchStepperRow(icon: String, label: String, value: Binding<Int>, max: Int) -> some View {
        HStack {
            Text(icon).font(.title3)
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(Color.duoDark)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if value.wrappedValue > 1 { value.wrappedValue -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(value.wrappedValue > 1 ? stretchColor : Color(.systemGray4))
                }
                .disabled(value.wrappedValue <= 1)

                Text("\(value.wrappedValue)")
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(Color.duoDark)
                    .frame(width: 40)

                Button {
                    if value.wrappedValue < max { value.wrappedValue += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(value.wrappedValue < max ? stretchColor : Color(.systemGray4))
                }
                .disabled(value.wrappedValue >= max)
            }
        }
    }

    // MARK: - Log Section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "📝", title: "ログ記録")

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
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Reminder Section


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
            mindInputRequired = goal.logGoal.mindInputRequired
            stretchEnabled = goal.stretchGoal.enabled
            stretchMinutes = goal.stretchGoal.stretchMinutes
        }
    }

    private func saveGoal() {
        // 既存値（customActivities、reminderEnabled 等）を保持して更新
        var goal = timeSlotManager.settings.goalFor(timeSlot) ?? TimeSlotGoal(timeSlot: timeSlot)
        goal.trainingGoal = trainingGoal
        goal.mindfulnessGoal = mindfulnessGoal
        goal.logGoal.mindInputRequired = mindInputRequired
        goal.stretchGoal.enabled = stretchEnabled
        goal.stretchGoal.stretchMinutes = stretchMinutes

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
