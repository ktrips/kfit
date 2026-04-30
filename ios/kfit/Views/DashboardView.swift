import SwiftUI
import UIKit

// デバイスのステータスバー高さを動的取得
private var statusBarHeight: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.windows.first?.safeAreaInsets.top ?? 44
}

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var todayExercises: [CompletedExercise] = []
    @State private var totalReps  = 0
    @State private var totalXP    = 0
    @State private var dailySets  = DailySets(amSets: 0, pmSets: 0)
    @State private var isLoading  = true
    @State private var mascotBounce = false
    @State private var showTracker  = false

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
                        VStack(spacing: 14) {
                            dailySetsCard
                            challengeCard
                            todayCard
                            quickMenu
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
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

    // MARK: - ヒーロー（コンパクト版）
    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                // タイトルバー
                HStack {
                    HStack(spacing: 7) {
                        Image("mascot")
                            .resizable().scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                        Text("DuoFit")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    // あいさつテキスト（コンパクト）
                    Text("やあ、\(authManager.userProfile?.username ?? "ユーザー")！")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.white.opacity(0.92))
                    Spacer()
                    Button { authManager.signOut() } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.white.opacity(0.9))
                            .padding(7)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, statusBarHeight + 6)
                .padding(.bottom, 10)

                // 統計バー（コンパクト）
                HStack(spacing: 0) {
                    heroStat(icon: "🔥",
                             value: "\(authManager.userProfile?.streak ?? 0)",
                             label: "連続")
                    divider
                    heroStat(icon: "⚡",
                             value: "\(totalReps)",
                             label: "今日 rep")
                    divider
                    heroStat(icon: "🏆",
                             value: "\(totalXP)",
                             label: "今日 XP")
                    divider
                    heroStat(icon: "⭐",
                             value: "\(authManager.userProfile?.totalPoints ?? 0)",
                             label: "総 XP")
                }
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 26)
    }

    private func heroStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.subheadline)
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.black)
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 今日のセット状況カード
    private var dailySetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // タイトル行
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("今日のセット状況").fontWeight(.black)
                }
                .font(.headline)
                .foregroundColor(Color.duoDark)

                Spacer()

                if dailySets.isGoalMet {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("達成！")
                            .font(.caption).fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.duoGreen)
                    .cornerRadius(20)
                } else {
                    Text("あと \(dailySets.pmSetsNeeded) セット")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoOrange)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.duoOrange.opacity(0.12))
                        .cornerRadius(20)
                }
            }

            Divider()

            // AM / PM 行
            VStack(spacing: 8) {
                setRow(
                    icon: "🌅",
                    label: "午前（〜12時）",
                    count: dailySets.amSets,
                    needed: 1,
                    isFlexible: true
                )
                setRow(
                    icon: "🌆",
                    label: dailySets.amSets == 0 ? "午後（12時〜）※2セット必要" : "午後（12時〜）",
                    count: dailySets.pmSets,
                    needed: dailySets.amSets == 0 ? 2 : 1,
                    isFlexible: false
                )
            }

            // 達成メッセージ
            if dailySets.isGoalMet {
                HStack(spacing: 6) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 22, height: 22).clipShape(Circle())
                    Text(dailySets.amSets == 0
                         ? "午後2セットで目標クリア！すごい💪"
                         : "午前・午後バッチリ！最高の一日🎉")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                }
                .padding(.top, 2)
            } else if dailySets.amSets + dailySets.pmSets == 0 {
                Text("今日はまだトレーニングしていません。始めましょう！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .padding(.top, 2)
            } else if dailySets.amSets == 0 && dailySets.pmSets == 1 {
                Text("午後あと1セット、または午前1セットで達成！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.07), radius: 6, y: 3)
    }

    private func setRow(icon: String, label: String, count: Int, needed: Int, isFlexible: Bool) -> some View {
        HStack(spacing: 10) {
            Text(icon).font(.subheadline)
                .frame(width: 24)

            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundColor(Color.duoDark)

            Spacer()

            // セットアイコン
            HStack(spacing: 4) {
                ForEach(0..<needed, id: \.self) { idx in
                    Image(systemName: idx < count ? "circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(idx < count ? Color.duoGreen : Color(.systemGray3))
                }
            }

            // 状態テキスト
            if count >= needed {
                Text("完了")
                    .font(.caption2).fontWeight(.black).foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoGreen.opacity(0.12)).cornerRadius(6)
            } else if count > 0 {
                Text("\(count)/\(needed)")
                    .font(.caption2).fontWeight(.bold).foregroundColor(Color.duoOrange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.duoOrange.opacity(0.12)).cornerRadius(6)
            } else {
                Text("未実施")
                    .font(.caption2).fontWeight(.medium).foregroundColor(Color.duoSubtitle)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(.systemGray5)).cornerRadius(6)
            }
        }
    }

    // MARK: - 90日チャレンジ
    private var challengeCard: some View {
        let streak   = authManager.userProfile?.streak ?? 0
        let progress = min(Double(streak) / 90.0, 1.0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                    Text("90日チャレンジ").fontWeight(.black)
                }
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
                Spacer()
                Text("\(streak) / 90日")
                    .font(.caption).fontWeight(.black)
                    .foregroundColor(Color.duoGreen)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.duoGreen.opacity(0.12))
                    .cornerRadius(8)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 12)
                    Capsule().fill(
                        LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(12, geo.size.width * CGFloat(progress)), height: 12)
                }
            }
            .frame(height: 12)
            Text("毎日続けてフィットネス習慣を身につけよう！")
                .font(.caption).foregroundColor(Color.duoSubtitle)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    // MARK: - 今日のトレーニング
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "calendar.badge.checkmark")
                Text("今日のトレーニング").fontWeight(.black)
            }
            .font(.subheadline)
            .foregroundColor(Color.duoDark)

            if todayExercises.isEmpty {
                Button { showTracker = true } label: {
                    VStack(spacing: 8) {
                        Text("🏋️").font(.system(size: 36))
                        Text("今日のトレーニングを始めよう！")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(.white)
                        Text("タップして記録開始 →")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(
                        LinearGradient(
                            colors: [Color.duoGreen, Color(red: 0.18, green: 0.58, blue: 0.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ForEach(todayExercises) { ex in
                        HStack(spacing: 10) {
                            Text(emojiFor(ex.exerciseName))
                                .font(.title3)
                                .frame(width: 38, height: 38)
                                .background(Color.duoGreen.opacity(0.1))
                                .cornerRadius(10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.exerciseName)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoDark)
                                Text("\(ex.reps) rep")
                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                            Text("+\(ex.points) XP")
                                .font(.caption).fontWeight(.black)
                                .foregroundColor(Color.duoGold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.duoYellow.opacity(0.22))
                                .cornerRadius(8)
                        }
                        .padding(10)
                        .background(Color.duoBg)
                        .cornerRadius(12)
                    }
                    Button { showTracker = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("さらに記録する").fontWeight(.black)
                        }
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.duoGreen)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    // MARK: - クイックメニュー
    private var quickMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("メニュー")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(Color.duoDark)

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
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
    }

    private func quickMenuItem(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(icon).font(.title3)
            Text(label)
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(Color.duoDark)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12))
        .cornerRadius(12)
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
        async let exercises = authManager.getTodayExercises()
        async let sets      = authManager.getDailySets()
        todayExercises = await exercises
        dailySets      = await sets
        totalReps = todayExercises.reduce(0) { $0 + $1.reps }
        totalXP   = todayExercises.reduce(0) { $0 + $1.points }
        isLoading = false
    }
}

#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager.shared)
}
