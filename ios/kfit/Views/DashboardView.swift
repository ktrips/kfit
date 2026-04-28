import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps = 0
    @State private var totalXP = 0
    @State private var isLoading = true
    @State private var mascotWiggle = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        Image("mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .rotationEffect(.degrees(mascotWiggle ? 10 : -10))
                            .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: mascotWiggle)
                            .onAppear { mascotWiggle = true }

                        Text("読み込み中...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // ウェルカムバナー
                            welcomeBanner

                            // XPステータスカード
                            xpStatsRow

                            // 90日チャレンジ
                            challengeCard

                            // 今日のトレーニング
                            todayWorkoutsCard

                            Spacer(minLength: 100)
                        }
                        .padding(.top, 8)
                    }

                    // フローティングボタン
                    VStack {
                        Spacer()
                        navigationButtons
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("mascot")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        Text("DuoFit")
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(Color.duoGreen)
                    }
                }
            }
        }
        .task { await loadData() }
    }

    // MARK: - ウェルカムバナー
    private var welcomeBanner: some View {
        HStack(spacing: 12) {
            Image("mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text("やあ、\(authManager.userProfile?.username ?? "ユーザー")！")
                    .font(.title3)
                    .fontWeight(.bold)

                Text(todayExercises.isEmpty ? "今日も一緒に頑張ろう！" : "今日も最高！続けよう！🎉")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - XPステータス
    private var xpStatsRow: some View {
        HStack(spacing: 12) {
            DuoStatCard(icon: "🔥", value: "\(authManager.userProfile?.streak ?? 0)", label: "日連続", color: Color.duoOrange)
            DuoStatCard(icon: "⚡", value: "\(totalReps)", label: "今日のrep", color: Color.duoGreen)
            DuoStatCard(icon: "🏆", value: "\(totalXP)", label: "今日のXP", color: Color.duoYellow)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎯 90日チャレンジ")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .foregroundColor(Color(.systemGray5))
                        .frame(height: 12)
                    Capsule()
                        .foregroundColor(Color.duoGreen)
                        .frame(width: geo.size.width * CGFloat(progress), height: 12)
                }
            }
            .frame(height: 12)

            Text("フィットネス習慣を身につけて3ヶ月チャレンジを達成しよう！")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }

    // MARK: - 今日のトレーニング
    private var todayWorkoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日のトレーニング")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            if todayExercises.isEmpty {
                VStack(spacing: 16) {
                    Image("mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .opacity(0.7)

                    Text("まだトレーニングしていません")
                        .foregroundColor(.secondary)
                        .font(.subheadline)

                    NavigationLink(destination: ExerciseTrackerView()) {
                        Text("最初のトレーニングを記録")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.duoGreen)
                            .cornerRadius(14)
                            .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(todayExercises) { exercise in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.exerciseName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("\(exercise.reps) rep")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("+\(exercise.points) XP")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(Color.duoYellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.duoYellow.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .padding(12)
                        .background(Color.duoBg)
                        .cornerRadius(10)
                    }

                    NavigationLink(destination: ExerciseTrackerView()) {
                        Text("＋ もう一種目記録する")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.duoGreen)
                            .cornerRadius(14)
                            .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
                    }
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - ナビゲーションボタン
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: ExerciseTrackerView()) {
                Label("記録する", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.duoGreen)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
            }

            Button(action: { authManager.signOut() }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(Color.duoRed.opacity(0.15))
                    .foregroundColor(Color.duoRed)
                    .cornerRadius(14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .background(
            Color.duoBg
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - データ読み込み
    private func loadData() async {
        isLoading = true
        todayExercises = await authManager.getTodayExercises()
        totalReps = todayExercises.reduce(0) { $0 + $1.reps }
        totalXP = todayExercises.reduce(0) { $0 + $1.points }
        isLoading = false
    }
}

// MARK: - DuoFit スタッツカード
struct DuoStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(icon)
                .font(.title2)
            Text(value)
                .font(.title3)
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
