import SwiftUI

// MARK: - データ定義

struct PlannedExercise: Identifiable {
    let id = UUID()
    let name: String
    let reps: String
    let emoji: String
    let exerciseId: String
    let repCount: Int
}

struct CardioSession: Identifiable {
    let id = UUID()
    let type: String
    let detail: String
    let emoji: String
}

private let phase1Circuit: [PlannedExercise] = [
    PlannedExercise(name: "スクワット",               reps: "20回",      emoji: "🏋️", exerciseId: "squat",  repCount: 20),
    PlannedExercise(name: "腕立て伏せ",               reps: "15回",      emoji: "💪", exerciseId: "pushup", repCount: 15),
    PlannedExercise(name: "レッグレイズ",             reps: "15回",      emoji: "🔥", exerciseId: "situp",  repCount: 15),
    PlannedExercise(name: "プランク",                 reps: "45秒",      emoji: "🧘", exerciseId: "plank",  repCount: 45),
    PlannedExercise(name: "ブルガリアンスクワット",   reps: "10回×片足", emoji: "🦵", exerciseId: "lunge",  repCount: 20),
]

private let phase2Upper: [PlannedExercise] = [
    PlannedExercise(name: "腕立て・ダンベルプレス",   reps: "3セット限界", emoji: "💪", exerciseId: "pushup", repCount: 12),
    PlannedExercise(name: "懸垂・ローイング",         reps: "3セット限界", emoji: "🏋️", exerciseId: "pushup", repCount: 10),
    PlannedExercise(name: "ショルダープレス",         reps: "3セット限界", emoji: "🙌", exerciseId: "pushup", repCount: 12),
]

private let phase2Lower: [PlannedExercise] = [
    PlannedExercise(name: "スクワット・ゴブレット",   reps: "3セット限界", emoji: "🏋️", exerciseId: "squat",  repCount: 15),
    PlannedExercise(name: "ランジ",                   reps: "3セット限界", emoji: "🦵", exerciseId: "lunge",  repCount: 12),
    PlannedExercise(name: "レッグレイズ",             reps: "3セット限界", emoji: "🔥", exerciseId: "situp",  repCount: 15),
    PlannedExercise(name: "プランク",                 reps: "3セット限界", emoji: "🧘", exerciseId: "plank",  repCount: 45),
]

private let weeklyCardio: [Int: CardioSession] = [
    2: CardioSession(type: "バイク",   detail: "軽め 30km", emoji: "🚴"),
    3: CardioSession(type: "ラン",     detail: "5km",       emoji: "🏃"),
    4: CardioSession(type: "スイム",   detail: "1km",       emoji: "🏊"),
    6: CardioSession(type: "ラン",     detail: "5km",       emoji: "🏃"),
    7: CardioSession(type: "バイク",   detail: "長め 70km", emoji: "🚴"),
    1: CardioSession(type: "スイム",   detail: "1km",       emoji: "🏊"),
]

// MARK: - View

struct WorkoutPlanView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var doneIds: Set<UUID> = []
    @State private var showRecordSheet = false
    @State private var recordingExercise: PlannedExercise?

    private var dayOfWeek: Int {
        Calendar.current.component(.weekday, from: Date())
    }

    private var phase: Int {
        guard let join = authManager.userProfile?.joinDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: join, to: Date()).day ?? 0
        return days >= 90 ? 2 : 1
    }

    private var phaseProgress: Double {
        guard let join = authManager.userProfile?.joinDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: join, to: Date()).day ?? 0
        return phase == 1 ? min(Double(days) / 90.0, 1.0)
                          : min(Double(days - 90) / 90.0, 1.0)
    }

    private var isUpperDay: Bool { dayOfWeek % 2 == 0 }

    private var todayExercises: [PlannedExercise] {
        if phase == 1 { return phase1Circuit }
        return isUpperDay ? phase2Upper : phase2Lower
    }

    private var todayCardio: CardioSession? { weeklyCardio[dayOfWeek] }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen.opacity(0.15), Color.duoBg],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        phaseCard
                        if let cardio = todayCardio { cardioCard(cardio) }
                        strengthCard
                        nutritionCard
                        Spacer(minLength: 40)
                    }
                    .padding(16)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showRecordSheet) {
            if let ex = recordingExercise {
                QuickRecordView(exercise: ex)
                    .environmentObject(authManager)
            }
        }
    }

    // MARK: ヘッダー
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Circle())
            }
            Spacer()
            Text("今日のプラン")
                .font(.headline).fontWeight(.black)
            Spacer()
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }

    // MARK: フェーズカード
    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("フェーズ \(phase)")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.duoGreen.opacity(0.12))
                        .cornerRadius(8)
                    Text(phase == 1 ? "0〜3ヶ月：体脂肪 20%→17%" : "3〜6ヶ月：体脂肪 17%→15%")
                        .font(.subheadline).fontWeight(.black)
                }
                Spacer()
                Text(phase == 1 ? "15分サーキット" : (isUpperDay ? "上半身の日" : "下半身＋腹筋"))
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.duoOrange)
                    .cornerRadius(10)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * CGFloat(phaseProgress)), height: 10)
                }
            }
            .frame(height: 10)

            Text("🎯 6ヶ月で体脂肪 -5%、1年で6パックへ")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: 有酸素カード
    private func cardioCard(_ cardio: CardioSession) -> some View {
        HStack(spacing: 14) {
            Text(cardio.emoji)
                .font(.system(size: 36))
                .frame(width: 60, height: 60)
                .background(Color.duoBlue.opacity(0.1))
                .cornerRadius(14)

            VStack(alignment: .leading, spacing: 4) {
                Text("今日の有酸素")
                    .font(.caption).foregroundColor(.secondary)
                Text("\(cardio.type) \(cardio.detail)")
                    .font(.headline).fontWeight(.black)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(Color.duoBlue.opacity(0.3))
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: 筋トレカード
    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(phase == 1 ? "💥 15分サーキット × 3周" : "💪 分割トレーニング")
                    .font(.headline).fontWeight(.black)
                Spacer()
                Text("\(doneIds.count)/\(todayExercises.count)")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoGreen)
            }

            if phase == 1 {
                Text("インターバルなし・最後は限界まで！")
                    .font(.caption).foregroundColor(Color.duoOrange)
            }

            VStack(spacing: 8) {
                ForEach(todayExercises) { ex in
                    exerciseRow(ex)
                }
            }

            if doneIds.count == todayExercises.count && !todayExercises.isEmpty {
                HStack {
                    Spacer()
                    Text("🎉 今日のメニュー完了！")
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(Color.duoGreen)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.duoGreen.opacity(0.08))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    private func exerciseRow(_ ex: PlannedExercise) -> some View {
        let done = doneIds.contains(ex.id)
        return HStack(spacing: 12) {
            Text(ex.emoji)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(done ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .font(.subheadline).fontWeight(.bold)
                    .strikethrough(done)
                    .foregroundColor(done ? .secondary : .primary)
                Text(ex.reps)
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if done {
                    doneIds.remove(ex.id)
                } else {
                    recordingExercise = ex
                    showRecordSheet = true
                    doneIds.insert(ex.id)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(done ? Color.duoGreen : Color(.systemGray3))
            }
        }
        .padding(12)
        .background(done ? Color.duoGreen.opacity(0.05) : Color.duoBg)
        .cornerRadius(14)
    }

    // MARK: 栄養カード
    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🍽 今日の栄養目標")
                .font(.headline).fontWeight(.black)

            HStack(spacing: 10) {
                NutritionChip(label: "カロリー", value: "1900〜2100", unit: "kcal", color: Color.duoOrange)
                NutritionChip(label: "タンパク質", value: "130〜150", unit: "g", color: Color.duoGreen)
            }
            HStack(spacing: 10) {
                NutritionChip(label: "脂質", value: "40〜55", unit: "g", color: Color.duoYellow)
                NutritionChip(label: "炭水化物", value: "200〜250", unit: "g", color: Color.duoBlue)
            }

            VStack(alignment: .leading, spacing: 6) {
                tipRow(icon: "🥣", text: "朝：プロテイン＋バナナ＋ゆで卵")
                tipRow(icon: "🍱", text: "昼：鶏胸肉200g＋ご飯150g＋野菜")
                tipRow(icon: "🍽", text: "夜：鶏 or 魚＋野菜（炭水化物少なめ）")
                tipRow(icon: "⚡", text: "トレ後30分以内にプロテイン")
            }
            .padding(12)
            .background(Color.duoBg)
            .cornerRadius(12)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Text(icon).font(.subheadline)
            Text(text).font(.caption).foregroundColor(.primary)
        }
    }
}

// MARK: - 栄養チップ
private struct NutritionChip: View {
    let label: String; let value: String; let unit: String; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.black).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - クイック記録シート
struct QuickRecordView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    let exercise: PlannedExercise
    @State private var reps: Int
    @State private var isSubmitting = false
    @State private var done = false

    init(exercise: PlannedExercise) {
        self.exercise = exercise
        _reps = State(initialValue: exercise.repCount)
    }

    var body: some View {
        VStack(spacing: 28) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 40, height: 4)
                .padding(.top, 12)

            Text(exercise.emoji).font(.system(size: 56))

            Text(exercise.name)
                .font(.title2).fontWeight(.black)

            HStack(spacing: 24) {
                Button { if reps > 0 { reps -= 1 } } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 48)).foregroundColor(Color.duoRed)
                }
                Text("\(reps)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(Color.duoGreen)
                    .frame(minWidth: 100)
                Button { reps += 1 } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 48)).foregroundColor(Color.duoGreen)
                }
            }

            if done {
                Text("✅ 記録完了！").font(.headline).foregroundColor(Color.duoGreen)
            } else {
                Button {
                    guard !isSubmitting, reps > 0 else { return }
                    isSubmitting = true
                    let matched = authManager.exercises.first { $0.id == exercise.exerciseId }
                        ?? authManager.exercises.first { $0.name.lowercased().contains(exercise.exerciseId) }
                    guard let ex = matched else { isSubmitting = false; dismiss(); return }
                    Task {
                        await authManager.recordExercise(ex, reps: reps)
                        done = true
                        try? await Task.sleep(nanoseconds: 900_000_000)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(.white) }
                        else { Text("記録する！").fontWeight(.black) }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(reps == 0 ? Color(.systemGray3) : Color.duoGreen)
                    .cornerRadius(16)
                    .shadow(color: Color.duoGreen.opacity(0.4), radius: 4, y: 3)
                }
                .disabled(reps == 0 || isSubmitting)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    WorkoutPlanView().environmentObject(AuthenticationManager.shared)
}
