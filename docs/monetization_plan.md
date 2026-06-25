# Fitingo 有料化プラン（フリーミアム戦略）

作成日: 2026-06-24  
最終更新: 2026-06-25

---

## 1. プラン概要

| プラン | 月額 | 年額 | 備考 |
|-------|------|------|------|
| **Free** | 無料 | 無料 | ダウンロード即利用可 |
| **Fitingo Plus** | ¥480/月 | ¥3,800/年（約34%オフ） | 年額を訴求してLTV最大化 |

> Apple Small Business Program（年収100万ドル以下）適用時、手数料は **15%**。超過後は30%。

---

## 2. Free / Plus 機能比較

### ✅ Free でできること（広めに設定してユーザー獲得を優先）

| カテゴリ | 機能 |
|---------|------|
| FIT | スパイラル・基本ゴール設定、HealthKit連携、今日のアクティビティ表示 |
| FOOD | 食事ログ記録（手入力）、PFCバランス表示 |
| TOMO | 友達3人まで追加、自分の投稿閲覧・投稿 |
| ウィジェット | 基本ウィジェット（ロック画面・ホーム画面 各1種） |
| 通知 | 時間帯別リマインダー 1スロットのみ |

### 🔑 Plus で解放される機能

| カテゴリ | 機能 |
|---------|------|
| **全般** | 広告なし、全機能フルアクセス |
| **AI機能** | フォトログのAI栄養解析、AIコーチングコメント生成（※別途APIキー要） |
| **FIT** | 詳細アクティビティ分析、目標自動調整提案、FITフィード写真記録 |
| **FOOD** | 食事ログ写真AI解析（カロリー・栄養素の自動認識）、週次・月次レポート、FOODフィード写真記録 |
| **MIND** | MINDタブ全機能（睡眠・マインドフル記録、睡眠スコア分析、AIコーチング） |
| **ROUTIN** | FIT・FOOD・MIND統合レポート、カロリー収支レポート |
| **TOMO** | 友達無制限追加、フレンドフィード全閲覧 |
| **BOOKS** | Kindle本をWebで全文読む、書籍のオフライン保存 |
| **Apple Watch** | Watchアプリ、Watchモーション運動検出、Watchウィジェット |
| **カスタマイズ** | スパイラルテーマ変更（10種以上）、Plusウィジェット、時間帯別リマインダー全スロット |

> **MIND タブについて**: MINDタブはPlus限定です。Freeユーザーはロック画面が表示されます。

---

## 3. 実装方法（StoreKit 2）

### 3-1. App Store Connect 設定手順

1. App Store Connect → 対象アプリ → **サブスクリプション** を選択
2. **サブスクリプショングループ**「Fitingo Plus」を作成
3. 以下の2プランを登録：
   - `fitingo_plus_monthly`（¥480/月、7日間無料トライアル）
   - `fitingo_plus_yearly`（¥3,800/年、14日間無料トライアル）
4. 審査提出（サブスク機能は初回審査時に一緒に提出）

### 3-2. iOS 実装イメージ（StoreKit 2）

```swift
// PlusManager.swift
import StoreKit

@MainActor
class PlusManager: ObservableObject {
    @Published var isPlus = false
    static let shared = PlusManager()
    static let productIDs = [
        "fitingo_plus_monthly",
        "fitingo_plus_yearly"
    ]

    func checkSubscription() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewableSubscription {
                isPlus = !tx.isUpgraded
            }
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        if case .success(let verification) = result,
           case .verified(_) = verification {
            await checkSubscription()
        }
    }
}
```

```swift
// PlusGateView.swift（機能制限UI例）
struct PlusLockedSection: View {
    @EnvironmentObject var plus: PlusManager
    let features: [String]

    var body: some View {
        if !plus.isPlus {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(Color(hex: "#FF8C00"))
                    Text("Plus で解放")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(Color(hex: "#FF8C00"))
                    Spacer()
                    Button("アップグレード →") { /* PlusView表示 */ }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(hex: "#FF8C00"))
                        .cornerRadius(20)
                }
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#FF8C00").opacity(0.6))
                            .font(.system(size: 12))
                        Text(feature)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(hex: "#FFF8EC"))
            .cornerRadius(16)
        }
    }
}
```

### 3-3. Paywall 画面の必須要件（App Store審査）

- 価格・課金間隔を明確に表示
- 無料トライアル期間を明記
- キャンセル方法の説明（「設定 > Apple ID > サブスクリプション」）
- 「利用規約」「プライバシーポリシー」へのリンク（`https://fit.ktrips.net/privacy-policy/`）
- 「復元」ボタンの設置（`AppStore.sync()`）

---

## 4. 収益見込み試算

### 前提
- Apple手数料: 15%（Small Business Program適用）
- 年額/月額比率: 6:4（年額を訴求）
- 平均ARPU（月換算）: 月額¥480 × 40% + 年額¥317 × 60% ≈ **¥382/人/月**

| 月間DAU | 転換率 | Plus人数 | 月間売上（手数料引き後） |
|--------|--------|---------|----------------------|
| 100 | 3% | 3人 | 約 **¥970** |
| 500 | 5% | 25人 | 約 **¥8,100** |
| 2,000 | 7% | 140人 | 約 **¥45,300** |
| 5,000 | 8% | 400人 | 約 **¥129,500** |
| 10,000 | 10% | 1,000人 | 約 **¥324,700** |

---

## 5. 段階的ロールアウト計画

```
Phase 1: 公開直後（〜2ヶ月）
  ─ 全機能を無料で提供
  ─ レビュー・評価を積み上げる（★4以上を目標）
  ─ DAU・継続率を計測

Phase 2: 有料化開始（3ヶ月目〜）
  ─ AI機能・詳細分析・TOMO友達上限・MINDタブを有料化
  ─ 7日間無料トライアル付きで転換率を高める
  ─ 既存ユーザーには1ヶ月無料移行期間を提供

Phase 3: 機能拡充（6ヶ月目〜）
  ─ Plusウィジェット・テーマ追加
  ─ 年額プランの割引率を告知・プッシュ
  ─ 法人プラン（ジム・企業向け）の検討
```

---

## 6. その他収益化手段（補助）

| 手段 | 内容 | 推定月収 |
|-----|------|---------|
| **Withingsアフィリエイト** | 体重計ページからリンク（紹介料3〜8%） | 数千円〜 |
| **Kindle書籍誘導** | HelpView経由（`fit.ktrips.net/books`） | 数百円〜 |
| **買い切りテーマパック** | ¥250/パック（スパイラルデザイン等） | 変動 |
| **法人ライセンス** | ジム・企業向け一括契約 | 将来検討 |

---

## 7. 参考リンク

- [App Store Connect サブスクリプション設定](https://developer.apple.com/app-store/subscriptions/)
- [StoreKit 2 ドキュメント](https://developer.apple.com/documentation/storekit)
- [Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [プライバシーポリシー](https://fit.ktrips.net/privacy-policy/)
