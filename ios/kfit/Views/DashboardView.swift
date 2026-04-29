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
        ZStack {
            Color.duoBg.ignoresSafeArea()
            VStack(spacing: 0) {
                heroSection
                if isLoading {
                    Spacer()
                    ProgressView().tint(Color.duoGreen).scaleEffect(1.4)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            challengeCard
                            todayCard
                            quickMenu
                            Spacer(minLength: 40)
                        }
                        .padding(16)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showTracker) {
            ExerciseTrackerView()
                .environmentObject(authManager)
                .onDisappear { Task { await loadData() } }
        }
        .task { await loadData() }
    }

    // MARK: - ヒーロー
    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image("mascot")
                            .resizable().scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                        Text("DuoFit")
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button { authManager.signOut() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.85))
                            .padding(8)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 16)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("やあ、\(authManager.userProfile?.username ?? "ユーザー")！")
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                        Text(todayExercises.isEmpty ? "今日も一緒に頑張ろう💪" : "今日も最高！続けよう🎉")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.88))
                    }
                    Spacer()
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 68, height: 68)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .shadow(color: Color.black.opacity(0.2), radius: 6)
                        .scaleEffect(mascotBounce ? 1.06 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: mascotBounce
                        )
                        .onAppear { mascotBounce = true }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                HStack(spacing: 0) {
                    heroStat(icon: "🔥", value: "\(authManager.userProfile?.streak ?? 0)", label: "連続")
                    Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 32)
                    heroStat(icon: "⚡", value: "\(totalReps)", label: "今日rep")
                    Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 32)
                    heroStat(icon: "🏆", value: "\(totalXP)", label: "今日XP")
                }
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.15))
                .cornerRadius(16)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(icon).font(.title3)
            Text(value)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                    Text("90日チャレンジ").fontWeight(.black)
                }
                .font(.headline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.subheadline).fontWeight(.black)
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
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - 今日のトレーニング
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                Text("今日のトレーニング").fontWeight(.black)
            }
            .font(.headline)

            if todayExercises.isEmpty {
                Button { showTracker = true } label: {
                    VStack(spacing: 10) {
                        Text("🏋️").font(.system(size: 44))
                        Text("今日のトレーニングを始めよう！")
                            .font(.headline).fontWeight(.black)
                            .foregroundColor(.white)
                        Text("タップして記録開始 →")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(
                        LinearGradient(
                            colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
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
                    Button { showTracker = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("さらに記録する").fontWeight(.black)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.duoGreen)
                        .cornerRadius(14)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }

    // MARK: - クイックメニュー
    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("メニュー")
                .font(.headline).fontWeight(.black)

            HStack(spacing: 10) {
                NavigationLink(destination: WeeklyGoalView().environmentObject(authManager)) {
                    quickMenuItem(icon: "🎯", label: "週間目標", color: Color.duoGreen)
                }
                NavigationLink(destination: HistoryView().environmentObject(authManager)) {
                    quickMenuItem(icon: "📅", label: "履歴", color: Color.duoBlue)
                }
                NavigationLink(destination: HelpView()) {
                    quickMenuItem(icon: "❓", label: "ヘルプ", color: Color.duoOrange)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
    }

    private func quickMenuItem(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(icon).font(.title2)
            Text(label)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .cornerRadius(14)
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
                .font(Font.title3.weight(.black))
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
