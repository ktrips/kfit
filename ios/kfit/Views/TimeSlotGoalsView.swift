import SwiftUI

struct TimeSlotGoalsView: View {
    @StateObject private var timeSlotManager = TimeSlotManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    if timeSlotManager.isLoading {
                        ProgressView()
                            .tint(Color.duoGreen)
                            .scaleEffect(1.4)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(TimeSlot.allCases, id: \.self) { timeSlot in
                            if let goal = timeSlotManager.settings.goalFor(timeSlot),
                               let progress = timeSlotManager.progress.progressFor(timeSlot) {
                                timeSlotCard(timeSlot: timeSlot, goal: goal, progress: progress)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("時間帯別の目標")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完了") {
                    dismiss()
                }
                .foregroundColor(Color.duoGreen)
                .fontWeight(.bold)
            }
        }
        .task {
            await timeSlotManager.loadTodaySettings()
            await timeSlotManager.loadTodayProgress()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.duoGreen, Color(hex: "#58CC02").opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    Image(systemName: "clock.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("時間帯別の目標設定")
                        .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("1日を4つの時間帯に分けて管理")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }

            Text("朝・昼・午後・夜の時間帯ごとに、トレーニング、マインドフルネス、ログ記録の目標を設定できます。")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Time Slot Card

    private func timeSlotCard(timeSlot: TimeSlot, goal: TimeSlotGoal, progress: TimeSlotProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text(timeSlot.emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeSlot.displayName)
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                    Text(timeSlot.timeRange)
                        .font(.caption)
                        .foregroundColor(Color.duoSubtitle)
                }
                Spacer()

                // 達成率
                let rate = progress.completionRate(goal: goal)
                CircularProgressView(progress: rate, isCompleted: progress.isFullyCompleted(goal: goal))
            }

            Divider()

            // トレーニング目標
            goalRow(
                icon: "💪",
                label: "トレーニング",
                current: progress.trainingCompleted,
                goal: goal.trainingGoal,
                color: Color.duoGreen
            )

            // マインドフルネス目標
            goalRow(
                icon: "🧘",
                label: "マインドフルネス",
                current: progress.mindfulnessCompleted,
                goal: goal.mindfulnessGoal,
                color: Color.duoPurple
            )

            // ログ目標
            logGoalRow(logGoal: goal.logGoal, logProgress: progress.logProgress)

            // 編集ボタン
            NavigationLink {
                TimeSlotGoalEditView(timeSlot: timeSlot)
            } label: {
                HStack {
                    Image(systemName: "pencil")
                    Text("目標を編集")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.duoGreen.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Goal Row

    private func goalRow(icon: String, label: String, current: Int, goal: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)

                HStack(spacing: 8) {
                    Text("\(current) / \(goal)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(current >= goal ? Color.duoGreen : Color.duoSubtitle)

                    // プログレスバー
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 4)
                            Capsule()
                                .fill(color)
                                .frame(width: goal > 0 ? min(geo.size.width, geo.size.width * CGFloat(current) / CGFloat(goal)) : 0, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()

            if current >= goal {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.duoGreen)
                    .font(.title3)
            }
        }
    }

    // MARK: - Log Goal Row

    private func logGoalRow(logGoal: LogGoal, logProgress: LogProgress) -> some View {
        HStack(spacing: 12) {
            Text("📝")
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text("ログ記録")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Color.duoDark)

                HStack(spacing: 8) {
                    if logGoal.mealRequired {
                        logBadge(label: "食事", completed: logProgress.mealLogged)
                    }
                    if logGoal.drinkRequired {
                        logBadge(label: "飲み物", completed: logProgress.drinkLogged)
                    }
                    if logGoal.mindInputRequired {
                        logBadge(label: "マインド", completed: logProgress.mindInputLogged)
                    }
                }
            }

            Spacer()

            if logProgress.completedCount >= logGoal.totalRequired {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color.duoGreen)
                    .font(.title3)
            }
        }
    }

    private func logBadge(label: String, completed: Bool) -> some View {
        HStack(spacing: 4) {
            if completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Color.duoGreen)
            }
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(completed ? Color.duoGreen : Color.duoSubtitle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(completed ? Color.duoGreen.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(6)
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(isCompleted ? Color.duoGreen : Color.duoOrange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isCompleted ? Color.duoGreen : Color.duoDark)
        }
    }
}

#Preview {
    NavigationView {
        TimeSlotGoalsView()
    }
}
