import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var history: [DayExercises] = []
    @State private var isLoading = true

    private let exerciseEmoji: [String: String] = [
        "push": "💪", "squat": "🏋️", "sit": "🔥",
        "lunge": "🚶", "burpee": "🔥", "plank": "🧱",
    ]

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        Image("mascot")
                            .resizable().scaledToFit().frame(width: 72, height: 72)
                            .clipShape(Circle())
                        Text("読み込み中...")
                            .foregroundColor(Color.duoDark).font(.subheadline).fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if history.isEmpty {
                    VStack(spacing: 12) {
                        Image("mascot")
                            .resizable().scaledToFit().frame(width: 80, height: 80)
                            .clipShape(Circle()).opacity(0.7)
                        Text("まだトレーニング記録がありません")
                            .foregroundColor(Color.duoDark).font(.subheadline).fontWeight(.semibold)
                        Text("トレーニングを記録するとここに表示されます")
                            .foregroundColor(Color.duoSubtitle).font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(history) { day in
                                dayCard(day)
                            }
                            Spacer(minLength: 40)
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("📅 履歴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadHistory() }
    }

    // MARK: - 日別カード
    private func dayCard(_ day: DayExercises) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 日別ヘッダー
            HStack {
                Text(day.label)
                    .font(.headline).fontWeight(.black).foregroundColor(Color.duoDark)
                Spacer()
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("⚡")
                        Text("\(day.totalReps) rep")
                            .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                    }
                    HStack(spacing: 4) {
                        Text("⭐")
                        Text("+\(day.totalPoints) XP")
                            .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGold)
                    }
                }
            }

            Divider()

            // セット一覧
            VStack(spacing: 10) {
                ForEach(day.sets) { set in
                    setCard(set)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - セットカード
    private func setCard(_ set: ExerciseSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // セットヘッダー
            HStack {
                Text("\(set.period) セット\(set.setNumber)")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoDark.opacity(0.8))
                Text(timeString(set.startTime))
                    .font(.caption2)
                    .foregroundColor(Color.duoSubtitle)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(set.totalReps) rep")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Color.duoGreen)
                    Text("+\(set.totalPoints) XP")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Color.duoGold)
                }
            }

            // 種目一覧
            VStack(spacing: 5) {
                ForEach(set.exercises) { ex in
                    HStack {
                        Text(emoji(for: ex.exerciseName))
                            .font(.body)
                            .frame(width: 28, height: 28)
                            .background(Color.duoGreen.opacity(0.08))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.exerciseName)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(Color.duoDark)
                            Text("\(ex.reps) rep")
                                .font(.caption2).foregroundColor(Color.duoSubtitle)
                        }

                        Spacer()

                        Text("+\(ex.points)")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(Color.duoGold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.duoYellow.opacity(0.18))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.duoGreen.opacity(0.04))
        .cornerRadius(10)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - ヘルパー
    private func emoji(for name: String) -> String {
        let lower = name.lowercased()
        for (key, val) in exerciseEmoji {
            if lower.contains(key) { return val }
        }
        return "⚡"
    }

    private func loadHistory() async {
        isLoading = true
        history = await authManager.getRecentExercises(days: 14)
        isLoading = false
    }
}

#Preview {
    HistoryView()
        .environmentObject(AuthenticationManager.shared)
}
