import SwiftUI

// MARK: - データ

struct PlannedExercise: Identifiable {
    let id = UUID()
    let name: String; let reps: String; let emoji: String
    let exerciseId: String; let repCount: Int
    let description: String; let tips: [String]; let muscles: [String]
    let difficulty: String
}

struct CardioSession: Identifiable {
    let id = UUID()
    let type: String; let detail: String; let emoji: String
}

private let phase1Circuit: [PlannedExercise] = [
    PlannedExercise(name: "スクワット", reps: "20回", emoji: "🏋️", exerciseId: "squat", repCount: 20,
        description: "下半身の王様。太もも・お尻を鍛える基本種目。毎日やっても疲れにくく、脂肪燃焼にも効果的。",
        tips: ["足を肩幅に開く", "つま先はやや外向き", "膝がつま先より前に出ないように", "お尻を後ろに引くイメージで下げる", "太ももが床と平行になるまで下げる"],
        muscles: ["大腿四頭筋", "大殿筋", "ハムストリングス"], difficulty: "初級"),
    PlannedExercise(name: "腕立て伏せ", reps: "15回", emoji: "💪", exerciseId: "pushup", repCount: 15,
        description: "胸・肩・三頭筋を一度に鍛えられる全身種目。フォームを正確に保つことが最大の効果につながる。",
        tips: ["手は肩幅より少し広め", "体を一直線に保つ", "胸が床に触れるまで下げる", "ひじを90度まで曲げる", "腰が落ちないように注意"],
        muscles: ["大胸筋", "三角筋前部", "上腕三頭筋"], difficulty: "初級"),
    PlannedExercise(name: "レッグレイズ", reps: "15回", emoji: "🔥", exerciseId: "situp", repCount: 15,
        description: "下腹部を集中的に鍛える種目。反動を使わず、腹筋の力だけで足を上げるのがポイント。",
        tips: ["仰向けで腰を床につける", "足をゆっくり上げ下げする", "足が床につく直前で止める", "呼吸は足を上げるときに吐く", "首を前に出さない"],
        muscles: ["腸腰筋", "下腹部", "腹直筋"], difficulty: "初級"),
    PlannedExercise(name: "プランク", reps: "45秒", emoji: "🧘", exerciseId: "plank", repCount: 45,
        description: "体幹全体を等尺性収縮で鍛える種目。姿勢改善・腰痛予防にも効果的。",
        tips: ["ひじは肩の真下に置く", "体を一直線に保つ", "お尻が上がらないように", "視線は床に向ける", "呼吸を止めない"],
        muscles: ["腹横筋", "脊柱起立筋", "大殿筋"], difficulty: "初級"),
    PlannedExercise(name: "ブルガリアンスクワット", reps: "10回×片足", emoji: "🦵", exerciseId: "lunge", repCount: 20,
        description: "片足スクワット。通常のスクワットより高強度で、左右の筋力バランスを整える効果がある。",
        tips: ["後ろ足をベンチ・椅子に乗せる", "前足は股関節の真下あたり", "膝が内側に入らないように", "上体はやや前傾", "前足のかかとで踏みしめる"],
        muscles: ["大腿四頭筋", "大殿筋", "ハムストリングス", "腸腰筋"], difficulty: "中級"),
]

private let phase2Upper: [PlannedExercise] = [
    PlannedExercise(name: "腕立て・ダンベルプレス", reps: "3セット 限界", emoji: "💪", exerciseId: "pushup", repCount: 12,
        description: "大胸筋の主力種目。限界まで追い込むことで筋肥大を狙う。ダンベルがあればより可動域を広げられる。",
        tips: ["ダンベルなら乳頭ライン付近でおろす", "肩甲骨を寄せて胸を張る", "下げるときゆっくり2秒", "上げるとき1秒で爆発的に", "インターバル90〜120秒"],
        muscles: ["大胸筋", "三角筋前部", "上腕三頭筋"], difficulty: "中級"),
    PlannedExercise(name: "懸垂・ローイング", reps: "3セット 限界", emoji: "🏋️", exerciseId: "pushup", repCount: 10,
        description: "背中の厚みをつくる引く系種目。懸垂ができない場合はテーブルロウで代替可能。",
        tips: ["懸垂：肩幅より広めに握る", "あごがバーを超えるまで引く", "テーブルロウ：斜め懸垂でも効果的", "肩甲骨を使って背中で引く意識", "ネガティブ（下げる）を2秒かけて"],
        muscles: ["広背筋", "大円筋", "上腕二頭筋", "菱形筋"], difficulty: "上級"),
    PlannedExercise(name: "ショルダープレス", reps: "3セット 限界", emoji: "🙌", exerciseId: "pushup", repCount: 12,
        description: "肩の丸みを作る種目。ペットボトルでも代替できる。三角筋中部・前部を鍛える。",
        tips: ["ひじは90度で耳の横あたり", "真上に向かって押し上げる", "腰を反りすぎない", "下げるとき肩より低くしない", "首をすくめないよう注意"],
        muscles: ["三角筋", "上腕三頭筋", "僧帽筋上部"], difficulty: "中級"),
]

private let phase2Lower: [PlannedExercise] = [
    PlannedExercise(name: "スクワット・ゴブレット", reps: "3セット 限界", emoji: "🏋️", exerciseId: "squat", repCount: 15,
        description: "重りを胸の前で抱えるスクワット。深くしゃがめて股関節の可動域が広がり、姿勢が安定する。",
        tips: ["ダンベルやペットボトルを両手で胸前に", "深くしゃがむほど効果的", "ひじが内側の太ももに当たるイメージ", "背中をまっすぐ保つ", "息を吸いながら下げる"],
        muscles: ["大腿四頭筋", "大殿筋", "内転筋"], difficulty: "中級"),
    PlannedExercise(name: "ランジ", reps: "3セット 限界", emoji: "🦵", exerciseId: "lunge", repCount: 12,
        description: "前後にステップして片足ずつ鍛えるバランス系種目。ヒップアップ効果が高い。",
        tips: ["大股で一歩踏み出す", "前膝が90度になるまで下げる", "後ろ膝は床スレスレまで", "上体は真っすぐ保つ", "左右交互にリズムよく"],
        muscles: ["大腿四頭筋", "大殿筋", "ハムストリングス"], difficulty: "中級"),
    PlannedExercise(name: "レッグレイズ", reps: "3セット 限界", emoji: "🔥", exerciseId: "situp", repCount: 15,
        description: "下腹部を集中的に鍛える種目。反動を使わず、腹筋の力だけで足を上げる。",
        tips: ["仰向けで腰を床につける", "足をゆっくり上げ下げ", "足が床につく直前で止める", "呼吸は足を上げるときに吐く", "首を前に出さない"],
        muscles: ["腸腰筋", "下腹部", "腹直筋"], difficulty: "初級"),
    PlannedExercise(name: "プランク", reps: "3セット 限界", emoji: "🧘", exerciseId: "plank", repCount: 45,
        description: "体幹全体を等尺性収縮で鍛える。姿勢改善・腰痛予防にも効果的。",
        tips: ["ひじは肩の真下", "体を一直線に", "お尻が上がらないように", "視線は床", "呼吸を止めない"],
        muscles: ["腹横筋", "脊柱起立筋", "大殿筋"], difficulty: "初級"),
]

private let weeklyCardio: [Int: CardioSession] = [
    2: CardioSession(type: "バイク",  detail: "軽め 30km", emoji: "🚴"),
    3: CardioSession(type: "ラン",    detail: "5km",       emoji: "🏃"),
    4: CardioSession(type: "スイム",  detail: "1km",       emoji: "🏊"),
    6: CardioSession(type: "ラン",    detail: "5km",       emoji: "🏃"),
    7: CardioSession(type: "バイク",  detail: "長め 70km", emoji: "🚴"),
    1: CardioSession(type: "スイム",  detail: "1km",       emoji: "🏊"),
]

private func difficultyColor(_ d: String) -> Color {
    switch d {
    case "初級": return Color.duoGreen
    case "中級": return Color.duoOrange
    default: return Color.duoRed
    }
}

// MARK: - 詳細シート

private struct DetailSheet: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    let exercise: PlannedExercise
    let onRecorded: (UUID) -> Void

    @State private var tab: Int = 0
    @State private var reps: Int
    @State private var saving = false
    @State private var done = false

    init(exercise: PlannedExercise, onRecorded: @escaping (UUID) -> Void) {
        self.exercise = exercise
        self.onRecorded = onRecorded
        _reps = State(initialValue: exercise.repCount)
    }

    private var pts: Int { reps * 2 }
    private let color = Color.duoGreen

    var body: some View {
        VStack(spacing: 0) {
            // ハンドル
            Capsule().fill(Color(.systemGray4))
                .frame(width: 40, height: 5).padding(.top, 10)

            // ヘッダー
            HStack(spacing: 12) {
                Text(exercise.emoji).font(.system(size: 44))
                    .frame(width: 64, height: 64)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                            .font(.headline).fontWeight(.black)
                        Text(exercise.difficulty)
                            .font(.caption2).fontWeight(.black)
                            .foregroundColor(difficultyColor(exercise.difficulty))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(difficultyColor(exercise.difficulty).opacity(0.12))
                            .cornerRadius(8)
                    }
                    Text(exercise.reps).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(Color(.systemGray3))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            // タブ切り替え
            HStack(spacing: 0) {
                ForEach([("📖 詳細", 0), ("✏️ 記録", 1)], id: \.1) { label, idx in
                    Button {
                        withAnimation { tab = idx }
                    } label: {
                        Text(label).font(.subheadline).fontWeight(.black)
                            .foregroundColor(tab == idx ? .white : .secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(tab == idx ? Color.duoGreen : Color.clear)
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 20).padding(.bottom, 8)

            Divider()

            ScrollView {
                if tab == 0 {
                    detailContent
                } else {
                    recordContent
                }
            }
        }
        .background(Color.white)
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 説明
            Text(exercise.description)
                .font(.subheadline).foregroundColor(.primary)
                .padding(14)
                .background(Color(.systemGray6))
                .cornerRadius(12)

            // 鍛える部位
            VStack(alignment: .leading, spacing: 8) {
                Text("鍛える部位")
                    .font(.caption).fontWeight(.black).foregroundColor(.secondary)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(exercise.muscles, id: \.self) { m in
                            Text(m)
                                .font(.caption).fontWeight(.black)
                                .foregroundColor(Color.duoGreen)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.duoGreen.opacity(0.12))
                                .cornerRadius(20)
                        }
                    }
                }
            }

            // フォームのコツ
            VStack(alignment: .leading, spacing: 8) {
                Text("フォームのコツ")
                    .font(.caption).fontWeight(.black).foregroundColor(.secondary)
                    .textCase(.uppercase)
                VStack(spacing: 8) {
                    ForEach(Array(exercise.tips.enumerated()), id: \.offset) { i, tip in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.caption2).fontWeight(.black)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.duoGreen)
                                .clipShape(Circle())
                            Text(tip).font(.subheadline).foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
            }

            Button {
                withAnimation { tab = 1 }
            } label: {
                Text("✏️ このトレーニングを記録する").fontWeight(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundColor(.white).background(Color.duoGreen).cornerRadius(14)
            }
        }
        .padding(20)
    }

    private var recordContent: some View {
        VStack(spacing: 24) {
            if done {
                VStack(spacing: 12) {
                    Text("✅").font(.system(size: 64))
                    Text("記録完了！").font(.title2).fontWeight(.black).foregroundColor(Color.duoGreen)
                    Text("+\(pts) XP 獲得！")
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(Color.duoYellow)
                }
                .padding(.top, 40)
            } else {
                Text("rep数を調整")
                    .font(.caption).fontWeight(.black).foregroundColor(.secondary)
                    .padding(.top, 16)

                HStack(spacing: 24) {
                    Button { reps = max(1, reps - 1) } label: {
                        Text("−").font(.title).fontWeight(.black)
                            .frame(width: 56, height: 56)
                            .foregroundColor(.secondary)
                            .background(Color(.systemGray5))
                            .cornerRadius(16)
                    }
                    VStack(spacing: 4) {
                        Text("\(reps)")
                            .font(.system(size: 72, weight: .black))
                            .foregroundColor(Color.duoGreen)
                        Text("rep").font(.caption).foregroundColor(.secondary)
                    }
                    Button { reps += 1 } label: {
                        Text("＋").font(.title).fontWeight(.black)
                            .frame(width: 56, height: 56)
                            .foregroundColor(Color.duoGreen)
                            .background(Color.duoGreen.opacity(0.15))
                            .cornerRadius(16)
                    }
                }

                Text("+\(pts) XP")
                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoYellow)

                Button {
                    Task {
                        saving = true
                        await authManager.recordExerciseDirect(
                            exerciseId: exercise.exerciseId,
                            exerciseName: exercise.name,
                            reps: reps, points: pts)
                        saving = false
                        done = true
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        onRecorded(exercise.id)
                        dismiss()
                    }
                } label: {
                    Text(saving ? "記録中…" : "✅ 記録する").fontWeight(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .foregroundColor(.white)
                        .background(saving ? Color(.systemGray3) : Color.duoGreen)
                        .cornerRadius(16)
                }
                .disabled(saving)
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

// MARK: - WorkoutPlanView

struct WorkoutPlanView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var doneIds: Set<UUID> = []
    @State private var selected: PlannedExercise?

    private var dayOfWeek: Int { Calendar.current.component(.weekday, from: Date()) }

    private var phase: Int {
        guard let join = authManager.userProfile?.joinDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: join, to: Date()).day ?? 0
        return days >= 90 ? 2 : 1
    }

    private var phaseProgress: Double {
        guard let join = authManager.userProfile?.joinDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: join, to: Date()).day ?? 0
        return phase == 1 ? min(Double(days) / 90.0, 1.0) : min(Double(days - 90) / 90.0, 1.0)
    }

    private var isUpperDay: Bool { dayOfWeek % 2 == 0 }

    private var todayExercises: [PlannedExercise] {
        if phase == 1 { return phase1Circuit }
        return isUpperDay ? phase2Upper : phase2Lower
    }

    private var todayCardio: CardioSession? { weeklyCardio[dayOfWeek] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.duoGreen.opacity(0.13), Color.duoBg],
                           startPoint: .top, endPoint: .center).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    phaseCard
                    if let cardio = todayCardio { cardioCard(cardio) }
                    strengthCard
                    nutritionCard
                    Spacer(minLength: 40)
                }
                .padding(16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("今日のプラン")
        .sheet(item: $selected) { ex in
            DetailSheet(exercise: ex) { id in
                doneIds.insert(id)
                selected = nil
            }
            .environmentObject(authManager)
        }
    }

    // MARK: フェーズカード
    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("フェーズ \(phase)")
                        .font(.caption).fontWeight(.bold).foregroundColor(Color.duoGreen)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.duoGreen.opacity(0.12)).cornerRadius(8)
                    Text(phase == 1 ? "0〜3ヶ月：体脂肪 20%→17%" : "3〜6ヶ月：体脂肪 17%→15%")
                        .font(.subheadline).fontWeight(.black)
                }
                Spacer()
                Text(phase == 1 ? "15分サーキット" : (isUpperDay ? "上半身の日" : "下半身＋腹筋"))
                    .font(.caption).fontWeight(.bold).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.duoOrange).cornerRadius(10)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.duoGreen, Color.duoBlue],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * CGFloat(phaseProgress)), height: 10)
                }
            }.frame(height: 10)
            Text("🎯 6ヶ月で体脂肪 -5%、1年で6パックへ")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: 有酸素カード
    private func cardioCard(_ cardio: CardioSession) -> some View {
        HStack(spacing: 14) {
            Text(cardio.emoji).font(.system(size: 36))
                .frame(width: 60, height: 60)
                .background(Color.duoBlue.opacity(0.1)).cornerRadius(14)
            VStack(alignment: .leading, spacing: 4) {
                Text("今日の有酸素").font(.caption).foregroundColor(.secondary)
                Text("\(cardio.type) \(cardio.detail)").font(.headline).fontWeight(.black)
            }
            Spacer()
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: 筋トレカード
    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(phase == 1 ? "💥 15分サーキット × 3周" : "💪 分割トレーニング")
                    .font(.headline).fontWeight(.black)
                Spacer()
                Text("\(doneIds.filter { id in todayExercises.contains(where: { $0.id == id }) }.count)/\(todayExercises.count)")
                    .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoGreen)
            }
            if phase == 1 {
                Text("タップで詳細・記録 ／ インターバルなし・限界まで！")
                    .font(.caption).foregroundColor(Color.duoOrange)
            }
            VStack(spacing: 8) {
                ForEach(todayExercises) { ex in exerciseRow(ex) }
            }
            let doneCount = doneIds.filter { id in todayExercises.contains(where: { $0.id == id }) }.count
            if doneCount == todayExercises.count && !todayExercises.isEmpty {
                HStack { Spacer()
                    Text("🎉 今日のメニュー完了！すごい！")
                        .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoGreen)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color.duoGreen.opacity(0.08)).cornerRadius(12)
            }
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }

    private func exerciseRow(_ ex: PlannedExercise) -> some View {
        let done = doneIds.contains(ex.id)
        return Button { selected = ex } label: {
            HStack(spacing: 12) {
                Text(ex.emoji).font(.title3)
                    .frame(width: 42, height: 42)
                    .background(done ? Color.duoGreen.opacity(0.15) : Color(.systemGray6))
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ex.name).font(.subheadline).fontWeight(.bold)
                            .strikethrough(done)
                            .foregroundColor(done ? .secondary : .primary)
                        Text(ex.difficulty)
                            .font(.caption2).fontWeight(.black)
                            .foregroundColor(difficultyColor(ex.difficulty))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(difficultyColor(ex.difficulty).opacity(0.12))
                            .cornerRadius(6)
                    }
                    Text(ex.reps).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(done ? Color.duoGreen : Color(.systemGray3))
            }
            .padding(12)
            .background(done ? Color.duoGreen.opacity(0.05) : Color.duoBg)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: 栄養カード
    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🍽 今日の栄養目標").font(.headline).fontWeight(.black)
            HStack(spacing: 10) {
                NutritionChip(label: "カロリー",   value: "1900〜2100", unit: "kcal", color: Color.duoOrange)
                NutritionChip(label: "タンパク質", value: "130〜150",   unit: "g",    color: Color.duoGreen)
            }
            HStack(spacing: 10) {
                NutritionChip(label: "脂質",       value: "40〜55",     unit: "g",    color: Color.duoYellow)
                NutritionChip(label: "炭水化物",   value: "200〜250",   unit: "g",    color: Color.duoBlue)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach([("🌅", "朝：プロテイン＋バナナ＋ゆで卵"),
                         ("🍱", "昼：鶏胸肉200g＋ご飯150g＋野菜"),
                         ("🌙", "夜：鶏 or 魚＋野菜（炭水化物少なめ）"),
                         ("⚡", "トレ後30分以内にプロテイン")], id: \.1) { icon, text in
                    HStack(spacing: 8) {
                        Text(icon).font(.subheadline)
                        Text(text).font(.caption).foregroundColor(.primary)
                    }
                }
            }
            .padding(12).background(Color.duoBg).cornerRadius(12)
        }
        .padding(16).background(Color.white).cornerRadius(18)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
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
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(color.opacity(0.08)).cornerRadius(12)
    }
}
