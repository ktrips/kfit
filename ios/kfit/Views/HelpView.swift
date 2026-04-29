import SwiftUI

struct HelpItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let content: String
}

private let helpItems: [HelpItem] = [
    HelpItem(
        icon: "💪",
        title: "トレーニングの記録方法",
        content: """
        1. ダッシュボードの「記録する」ボタンをタップ
        2. 種目（プッシュアップ・スクワットなど）を選択
        3. ＋ ボタンでレップ数を入力、または「モーション自動検出」をONにする
        4. 「✓ トレーニングを記録」で保存
        5. XP が獲得されてダッシュボードに戻ります
        """
    ),
    HelpItem(
        icon: "⭐",
        title: "XP（ポイント）の仕組み",
        content: """
        1 rep ごとに以下の XP が加算されます：
        • プッシュアップ・スクワット・ランジ：2 XP / rep
        • シットアップ・プランク：1 XP / rep（秒）
        • バーピー：5 XP / rep
        獲得 XP はダッシュボードの「今日の XP」に表示されます。
        """
    ),
    HelpItem(
        icon: "🔥",
        title: "ストリーク（連続記録）",
        content: """
        毎日トレーニングを記録すると連続日数が伸びます。
        • 週2日まで休息日を設けても streak は継続します
        • 3日以上空くとリセットされます
        • 90日連続達成が最初の大きな目標です
        """
    ),
    HelpItem(
        icon: "🎯",
        title: "週間目標の設定",
        content: """
        ダッシュボードの「週間目標」カードをタップして設定できます。
        • 各種目の 1日のrep数 を入力
        • 週間目標は自動で × 5日（週2日休息）計算
        • ダッシュボードの進捗バーでリアルタイム確認
        • 週が変わると目標はリセットされます
        """
    ),
    HelpItem(
        icon: "📅",
        title: "履歴の確認",
        content: """
        メニュー → 「履歴」から過去14日間のトレーニング記録を確認できます。
        各日のXP合計・種目別rep数が表示されます。
        """
    ),
    HelpItem(
        icon: "📱",
        title: "モーション自動検出（iPhone）",
        content: """
        トレーニング記録画面で「モーション自動検出」をONにすると、
        iPhoneの加速度センサーでrepを自動カウントします。
        • フォームスコアも同時に計算されます
        • Apple Watch からもモーション検出が使えます
        • Watch でのトレーニングはiPhoneに自動同期されます
        """
    ),
    HelpItem(
        icon: "🔐",
        title: "アカウント・データについて",
        content: """
        • Google アカウントでログインします
        • データは Firebase に安全に保存されます
        • Web・iOS・Watch のデータはリアルタイム同期されます
        • ログアウトはダッシュボード右下のボタンから行えます
        """
    ),
]

struct HelpView: View {
    @State private var openId: UUID? = helpItems.first?.id

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView {
                    VStack(spacing: 16) {
                        // ヘッダー
                        HStack(spacing: 12) {
                            Image("mascot")
                                .resizable().scaledToFit().frame(width: 52, height: 52)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ヘルプ・使い方")
                                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                                Text("DuoFit の使い方ガイド")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // アコーディオン
                        ForEach(helpItems) { item in
                            accordionItem(item)
                        }

                        // バージョン情報
                        HStack(spacing: 12) {
                            Text("ℹ️").font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DuoFit")
                                    .font(.subheadline).fontWeight(.black)
                                Text("Web・iOS・Apple Watch 対応")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("ヘルプ")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func accordionItem(_ item: HelpItem) -> some View {
        let isOpen = openId == item.id

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    openId = isOpen ? nil : item.id
                }
            }) {
                HStack(spacing: 12) {
                    Text(item.icon).font(.title3)
                    Text(item.title)
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(Color.duoDark)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(Color.duoSubtitle)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }

            if isOpen {
                Divider().padding(.horizontal, 16)
                Text(item.content)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(Color.duoDark)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 20)
    }
}

#Preview {
    HelpView()
}
