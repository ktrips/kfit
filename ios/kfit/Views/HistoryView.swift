import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var history: [DayExercises] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            if isLoading {
                VStack(spacing: 16) {
                    Image("mascot").resizable().scaledToFill()
                        .frame(width: 80, height: 80).clipShape(Circle())
                    Text("読み込み中…").font(.subheadline).foregroundColor(.secondary)
                }
            } else if history.isEmpty {
                VStack(spacing: 16) {
                    Image("mascot").resizable().scaledToFill()
                        .frame(width: 90, height: 90).clipShape(Circle()).opacity(0.7)
                    Text("まだ履歴がありません")
                        .font(.headline).fontWeight(.black)
                    Text("トレーニングを記録すると\nここに表示されます！")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(history) { day in
                            dayCard(day)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("トレーニング履歴")
        .task { await loadData() }
    }

    private func dayCard(_ day: DayExercises) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.label).font(.headline).fontWeight(.black)
                Spacer()
                HStack(spacing: 10) {
                    Text("⚡ \(day.totalReps) rep")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    Text("+\(day.totalPoints) XP")
                        .font(.caption).fontWeight(.black)
                        .foregroundColor(Color.duoYellow)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.duoYellow.opacity(0.15)).cornerRadius(8)
                }
            }
            VStack(spacing: 6) {
                ForEach(day.exercises) { ex in
                    HStack(spacing: 10) {
                        Text(emojiFor(ex.exerciseName)).font(.title3)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6)).cornerRadius(10)
                        Text(ex.exerciseName).font(.subheadline).fontWeight(.bold)
                        Spacer()
                        Text("\(ex.reps) rep")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("+\(ex.points) XP")
                            .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoYellow)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color(.systemGray6)).cornerRadius(12)
                }
            }
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    private func loadData() async {
        history = await authManager.getRecentExercises(days: 14)
        isLoading = false
    }

    private func emojiFor(_ name: String) -> String {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        let map = ["pushup": "💪", "push-up": "💪", "squat": "🏋️",
                   "situp": "🔥", "sit-up": "🔥", "lunge": "🦵",
                   "burpee": "⚡", "plank": "🧘"]
        for (k, v) in map { if key.contains(k) { return v } }
        return "🏃"
    }
}
