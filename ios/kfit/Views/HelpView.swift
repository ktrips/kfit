import SwiftUI

private struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String; let title: String; let items: [String]
}

private let sections: [HelpSection] = [
    HelpSection(icon: "💪", title: "トレーニングの記録方法", items: [
        "下のタブ「記録」をタップ",
        "種目（プッシュアップ・スクワットなど）を選択",
        "＋ボタンでレップ数を入力",
        "「記録する」で保存",
        "XPが獲得されてホームに戻ります",
    ]),
    HelpSection(icon: "⭐", title: "XP（ポイント）の仕組み", items: [
        "🤜 プッシュアップ：2 XP / rep",
        "🦵 スクワット：2 XP / rep",
        "🧘 シットアップ：1 XP / rep",
        "🚶 ランジ：2 XP / rep",
        "🔥 バーピー：5 XP / rep",
        "🧱 プランク：1 XP / 秒",
    ]),
    HelpSection(icon: "🔥", title: "ストリーク（連続記録）", items: [
        "毎日トレーニングを記録すると連続日数が伸びます",
        "24時間以上記録がないとリセットされます",
        "90日連続達成が最初の大きな目標です",
        "ホーム画面の🔥アイコンで現在の日数を確認できます",
    ]),
    HelpSection(icon: "🎯", title: "週間目標の設定", items: [
        "「週間」タブから設定できます",
        "各種目の1日のrep数を入力",
        "週間目標は自動で × 5日（週2日休息）計算",
        "ホーム画面の進捗バーでリアルタイム確認できます",
        "週が変わると目標はリセットされます",
    ]),
    HelpSection(icon: "📋", title: "今日のプラン", items: [
        "「プラン」タブから個人プランを確認できます",
        "フェーズ1（0〜3ヶ月）: 15分サーキット × 3周",
        "フェーズ2（3〜6ヶ月）: 分割トレーニング",
        "各種目をタップすると詳細とフォームのコツを確認できます",
        "チェックすると記録に自動保存されます",
    ]),
    HelpSection(icon: "📅", title: "履歴の確認", items: [
        "「履歴」タブから過去14日間のトレーニング記録を確認できます",
        "各日のXP合計・種目別rep数が表示されます",
    ]),
    HelpSection(icon: "⌚", title: "Apple Watch", items: [
        "iPhoneアプリと同期してWatchからも記録できます",
        "手首の動きで自動rep計測（開発中）",
        "トレーニング完了後にiPhoneへ自動同期されます",
    ]),
]

struct HelpView: View {
    @State private var openIdx: Int? = 0

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { i, sec in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    openIdx = openIdx == i ? nil : i
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(sec.icon).font(.title3)
                                    Text(sec.title).font(.subheadline).fontWeight(.black)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: openIdx == i ? "chevron.up" : "chevron.down")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(16)
                            }
                            if openIdx == i {
                                Divider().padding(.horizontal, 16)
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(sec.items.enumerated()), id: \.offset) { j, item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("•").foregroundColor(Color.duoGreen)
                                                .fontWeight(.black)
                                            Text(item).font(.subheadline).foregroundColor(.secondary)
                                            Spacer()
                                        }
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .background(Color.white).cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
                    }

                    // バージョン情報
                    HStack(spacing: 12) {
                        Text("ℹ️").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DuoFit").font(.subheadline).fontWeight(.black)
                            Text("Web・iOS・Apple Watch 対応 / Firebase バックエンド")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16).background(Color.white).cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)

                    Spacer(minLength: 40)
                }
                .padding(16)
            }
        }
        .navigationTitle("ヘルプ・使い方")
    }
}
