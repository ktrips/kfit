import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps = 0
    @State private var totalXP = 0
    @State private var isLoading = true
    @State private var mascotBounce = false
    @State private var showTracker = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.duoGreen.opacity(0.12), Color.duoBg, Color.duoBg],
                    startPoint: .top, endPoint: .center
                ).ignoresSafeArea()

                if isLoading {
                    loadingView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            welcomeBanner
                            statsRow
                            challengeCard
                            todayCard
                            Spacer(minLength: 100)
                        }
                        .padding(.top, 8)
                    }
                }

                // 記録ボタン（フローティング）
                if !isLoading {
                    bottomBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("mascot")
                            .resizable().scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                        Text("DuoFit")
                            .font(.headline).fontWeight(.black)
                            .foregroundColor(Color.duoGreen)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { authManager.signOut() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showTracker) {
                ExerciseTrackerView()
                    .environmentObject(authManager)
                    .onDisappear { Task { await loadData() } }
            }
        }
        .task { await loadData() }
    }

    // MARK: - ローディング
    private var loadingView: some View {
        VStack(spacing: 16) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 90, height: 90)
                .clipShape(Circle())
                .scaleEffect(mascotBounce ? 1.08 : 0.95)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: mascotBounce)
                .onAppear { mascotBounce = true }
            Text("読み込み中…")
                .font(.subheadline).foregroundColor(.secondary)
        }
    }

    // MARK: - ウェルカムバナー
    private var welcomeBanner: some View {
        HStack(spacing: 14) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 3))
                .shadow(color: Color.duoGreen.opacity(0.3), radius: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text("やあ、\(authManager.userProfile?.username ?? "ユーザー")！")
                    .font(.title3).fontWeight(.black)
                Text(todayExercises.isEmpty ? "今日も一緒に頑張ろう💪" : "今日も最高！続けよう🎉")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - スタッツ
    private var statsRow: some View {
        HStack(spacing: 10) {
            StatCard(icon: "🔥", value: "\(authManager.userProfile?.streak ?? 0)",
                     label: "日連続", color: Color.duoOrange)
            StatCard(icon: "⚡", value: "\(totalReps)",
                     label: "今日のrep", color: Color.duoGreen)
            StatCard(icon: "🏆", value: "\(totalXP)",
                     label: "今日のXP", color: Color.duoYellow)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("90日チャレンジ", systemImage: "flag.fill")
                    .font(.system(.headline, weight: .black))
                    .foregroundColor(Color.duoGreen)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(10)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 14)
                    Capsule().fill(
                        LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(14, geo.size.width * CGFloat(progress)), height: 14)
                }
            }
            .frame(height: 14)

            Text("毎日続けてフィットネス習慣を身につけよう！")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - 今日のトレーニング
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("今日のトレーニング", systemImage: "calendar.badge.checkmark")
                .font(.system(.headline, weight: .black))

            if todayExercises.isEmpty {
                VStack(spacing: 16) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                        .opacity(0.6)

                    Text("まだ記録がありません")
                        .font(.subheadline).foregroundColor(.secondary)

                    Button { showTracker = true } label: {
                        Label("最初の記録をつける", systemImage: "plus.circle.fill")
                            .font(.system(.headline, weight: .black))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.duoGreen)
                            .cornerRadius(16)
                            .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(todayExercises) { ex in
                        HStack(spacing: 12) {
                            Text(emojiFor(ex.exerciseName))
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color.duoGreen.opacity(0.1))
                                .cornerRadius(12)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.exerciseName)
                                    .font(.subheadline).fontWeight(.bold)
                                Text("\(ex.reps) rep")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("+\(ex.points) XP")
                                .font(.subheadline).fontWeight(.black)
                                .foregroundColor(Color.duoYellow)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.duoYellow.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .padding(12)
                        .background(Color.duoBg)
                        .cornerRadius(14)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - 下部バー
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button { showTracker = true } label: {
                Label(todayExercises.isEmpty ? "記録する" : "＋ 追加記録",
                      systemImage: "plus.circle.fill")
                    .font(.system(.headline, weight: .black))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [Color.duoGreen, Color(red: 0.2, green: 0.7, blue: 0.0)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.duoGreen.opacity(0.4), radius: 6, y: 4)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Color.white)
        }
    }

    private func emojiFor(_ name: String) -> String {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        let map = ["pushup": "💪", "push-up": "💪", "squat": "🏋️",
                   "situp": "🔥", "sit-up": "🔥", "lunge": "🦵",
                   "burpee": "⚡", "plank": "🧘"]
        for (k, v) in map { if key.contains(k) { return v } }
        return "🏃"
    }

    private func loadData() async {
        isLoading = true
        todayExercises = await authManager.getTodayExercises()
        totalReps = todayExercises.reduce(0) { $0 + $1.reps }
        totalXP   = todayExercises.reduce(0) { $0 + $1.points }
        isLoading = false
    }
}

// MARK: - スタッツカード
struct DuoStatCard: View {
    let icon: String; let value: String; let label: String; let color: Color
    var body: some View {
        StatCard(icon: icon, value: value, label: label, color: color)
    }
}

struct StatCard: View {
    let icon: String; let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Text(icon).font(.title2)
            Text(value)
                .font(.system(.title3, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: color.opacity(0.15), radius: 4, y: 2)
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
