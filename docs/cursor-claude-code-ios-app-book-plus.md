# Cursor + Claudeで個人アプリを作り、Kindleで出版し、Plusで稼ぐ方法

**AI個人開発の「作る・届ける・収益化する」完全ガイド — Plus Edition**

著者：吉田 顕一（Ken Yoshida）

---

> **本書について**
>
> 本書は『Cursor + ClaudeでiPhoneアプリ・Apple Watchフィットネスアプリを週末だけで作る方法』の続編・拡張版です。
>
> 前作では「作る」ことに集中しました。本作では、作ったアプリを**届け・収益化し・書籍として発信する**工程を加えます。
>
> テーマは3つ。**① Kindle電子書籍の作り方**（MarkdownからKDP出版まで）、**② フリーミアム設計（Free vs Plus）の実装**（StoreKit 2・gating UI）、**③ アプリを拡散するマーケティング計画**（ASO・SNS・コンテンツ戦略）です。
>
> サンプルアプリは前作と同じ「Fitingo」ですが、本作ではそのアプリを**実際にApp Storeで公開し、ユーザーを獲得し、サブスクリプションで収益を得る**フェーズまでを扱います。

<div style="page-break-after: always;"></div>

## 免責事項・著作権表示

<small>

**本書に関する免責事項（Disclaimer）**

本書（以下「本書」）は、個人開発プロジェクト「kfit」（サンプルアプリ）の開発・収益化過程を題材にした技術解説書であり、情報提供のみを目的として作成されています。著者・吉田顕一は、以下の事項について一切の責任を負いません。

本書で紹介するサービス・手法による収益は保証されません。App Store収益・Kindle出版収益は著者の実績例であり、同様の成果を保証するものではありません。各サービスの利用は、それぞれの最新の利用規約・ライセンスに従ってください。

本書で言及するサービス: Cursor（Anysphere, Inc.）／Claude（Anthropic, PBC）／GitHub（Microsoft Corporation）／Swift・SwiftUI・Xcode・HealthKit・StoreKit・Apple Watch・App Store（Apple Inc.）／Firebase（Google LLC）／Kindle Direct Publishing・Amazon（Amazon.com, Inc.）／X（旧Twitter）（X Corp.）／TikTok（ByteDance Ltd.）。

*Copyright © 2026 Ken Yoshida（吉田顕一）. All rights reserved. 本書の無断転載・複製・配布を禁じます。*

</small>

<div style="page-break-after: always;"></div>

## 目次

- [はじめに ─ 「作る・届ける・稼ぐ」のAI時代版](#はじめに)
- [第一章: フリーミアム設計 ─ Free と Plus の線引き](#第一章-フリーミアム設計)
- [第二章: StoreKit 2 でサブスクリプションを実装する](#第二章-storekit-2-でサブスクリプションを実装する)
- [第三章: Plus Gating UI ─ 機能制限画面の設計と実装](#第三章-plus-gating-ui)
- [第四章: Markdown から Kindle 本を作る](#第四章-markdown-から-kindle-本を作る)
- [第五章: KDP（Kindle Direct Publishing）で出版する](#第五章-kdp-で出版する)
- [第六章: App Store 最適化（ASO）](#第六章-app-store-最適化aso)
- [第七章: SNS・コンテンツマーケティング戦略](#第七章-sns-コンテンツマーケティング戦略)
- [第八章: アプリを拡散するための具体的な施策プラン](#第八章-アプリを拡散する施策プラン)
- [第九章: 収益見込みと KPI 管理](#第九章-収益見込みと-kpi-管理)
- [終わりに](#終わりに)
- [付録A: Free / Plus 機能比較表（最新版）](#付録a-free--plus-機能比較表)
- [付録B: KDP 出版チェックリスト](#付録b-kdp-出版チェックリスト)
- [付録C: マーケティング施策チェックリスト](#付録c-マーケティング施策チェックリスト)

<div style="page-break-after: always;"></div>

## はじめに

「アプリを作ることはできた。でも、誰にも使ってもらえない」──個人開発者の多くが直面する壁です。

CursorとClaudeを使えば、一人でWebアプリ・iOSアプリ・Apple Watchアプリを作れます。しかし、作ること自体が目的でない限り、**届ける・使ってもらう・収益化する**という工程が必要になります。

本書では、前作（技術実装編）で作ったFitingoアプリを題材に、次の3つのフェーズを扱います。

```
Phase A: 収益化設計
  ─ Free と Plus の機能を分ける
  ─ StoreKit 2 でサブスクリプションを実装する
  ─ 機能制限 UI（gating）を設計・実装する

Phase B: 書籍化・コンテンツ化
  ─ 開発過程を Markdown でドキュメント化する
  ─ python-docx で Kindle 対応の DOCX を生成する
  ─ KDP（Kindle Direct Publishing）で出版する

Phase C: 拡散・マーケティング
  ─ App Store 最適化（ASO）でオーガニックユーザーを増やす
  ─ X・TikTok・Qiita で開発ログを発信する
  ─ 段階的なリリースとユーザー獲得プランを実行する
```

3つのフェーズはお互いに連携します。Kindle本がアプリのマーケティングになり、アプリがKindle本の販促になります。これが個人開発の「複利的な成長」です。

<div style="page-break-after: always;"></div>

---

## 第一章: フリーミアム設計

<div style="page-break-after: always;"></div>

### 1-1. なぜフリーミアムか

有料アプリとフリーミアムアプリのどちらが良いかは、アプリのジャンルとターゲットによります。フィットネス・習慣化アプリにおいては、フリーミアムが有効です。理由は3つあります。

1. **インストール障壁の排除** ── 無料でダウンロードできると、試してみるユーザーが増えます。
2. **習慣形成後に課金** ── 3〜7日アプリを使い、習慣になったタイミングで課金へ誘導できます。
3. **App Store最適化に有利** ── 無料アプリはインストール数が多くなるため、ASO（検索順位）に好影響があります。

Duolingo・Habitica・MyFitnessPalなど、フィットネス・習慣化アプリの多くがフリーミアムを採用しています。

### 1-2. 何を無料にして、何を有料にするか

フリーミアム設計の最も重要な判断は、**「無料で使えると思わせながら、本当に価値ある部分を有料にする」**という線引きです。

**悪い例（有料化が失敗するパターン）：**
- 基本機能すら使えない（記録すらできない）
- 有料化の説明なしに機能制限だけ表示する
- Free ユーザーに「何もできない感」を与える

**良い例（転換率が上がるパターン）：**
- 記録・基本確認はすべて Free で使える
- 分析・AI・Watch など「続けたい人」が欲しい機能を Plus にする
- 「今日もFreeで使えた → でも分析が見たい → Plusに上げよう」という動機を作る

### 1-3. Fitingo の Free / Plus 設計

![Fitingo Plus アップグレード画面](screenshots/plus/plus-upgrade-screen.png)

Fitingo の Free / Plus の線引きは次の考え方に基づいています。

**Free ユーザーに与えるもの:**
- 毎日アプリを開く理由（スパイラル・記録・タイムライン）
- 継続できたという達成感（XPポイント・ストリーク）
- アプリの価値を体験できる最小セット

**Plus ユーザーにだけ解放するもの:**
- データを深く分析したい人向け機能（統合レポート・PFC・睡眠スコア）
- AI活用（写真栄養解析・AIコーチング）
- 体験の幅を広げる機能（MIND タブ・Apple Watch・FIT/FOOD フィード写真）
- 広告なし

| カテゴリ | Free | Plus |
|---------|------|------|
| **全般** | 広告あり | 広告なし・全機能アクセス |
| **FIT** | アクティビティ記録・基本表示 | 詳細分析・目標自動調整・FITフィード写真 |
| **FOOD** | 手入力食事ログ・PFC表示 | フォトログAI解析・週次レポート・FOODフィード写真 |
| **MIND** | ロック画面（タブ全体非表示） | 睡眠・マインドフル記録・睡眠スコア・AIコーチング |
| **ROUTIN** | スパイラル・基本ゴール | FIT/FOOD/MIND統合レポート・カロリー収支 |
| **TOMO** | 友達3人まで・自分の投稿 | 友達無制限・フレンドフィード全閲覧 |
| **BOOKS** | — | Kindle本をWebで全文読む |
| **Apple Watch** | — | Watchアプリ・モーション検出・Watchウィジェット |
| **カスタマイズ** | スパイラルテーマ1種・通知1スロット | テーマ10種以上・全スロット通知 |

### 1-4. 価格設定の考え方

| プラン | 月額 | 年額 | 備考 |
|-------|------|------|------|
| **Free** | 無料 | 無料 | — |
| **Fitingo Plus** | ¥480/月 | ¥3,800/年 | 年額で約34%オフ。年額を訴求してLTV最大化 |

Duolingo（¥960/月）の半額、Habitica（無料〜）より上位という位置づけです。フィットネス・健康カテゴリでは¥300〜¥600/月が「気軽に試せる」ゾーンです。

**年額プランの訴求ポイント:**
- 「月200円以下」という表現に言い換えられる
- 1回のコーヒー代でApple Watchアプリが使える
- 無料トライアル（7日間）がついているため、試してから決断できる

<div style="page-break-after: always;"></div>

---

## 第二章: StoreKit 2 でサブスクリプションを実装する

<div style="page-break-after: always;"></div>

### 2-1. App Store Connect での設定

StoreKit 2 を使うには、まず App Store Connect でサブスクリプション商品を登録します。

#### ① サブスクリプショングループの作成

1. App Store Connect → 対象アプリ → **サブスクリプション**
2. **+** でサブスクリプショングループを作成：「Fitingo Plus」
3. グループ内に2つのプランを登録：

| 製品ID | 表示名 | 価格 | 無料トライアル |
|--------|--------|------|--------------|
| `fitingo_plus_monthly` | Fitingo Plus（月額） | ¥480 | 7日間 |
| `fitingo_plus_yearly` | Fitingo Plus（年額） | ¥3,800 | 14日間 |

#### ② ローカライズ

日本語の表示名・説明文を入力します。

```
表示名: Fitingo Plus
説明: FIT・FOOD・MIND・Apple Watch・広告なし。すべての機能を解放して習慣を加速させましょう。
```

### 2-2. StoreKit 2 の実装（PlusManager）

`PlusManager.swift` はアプリ全体でシングルトンとして使います。

```swift
// ios/kfit/Managers/PlusManager.swift
import StoreKit

@MainActor
final class PlusManager: ObservableObject {
    static let shared = PlusManager()

    // サブスクリプション製品ID
    static let productIDs = ["fitingo_plus_monthly", "fitingo_plus_yearly"]

    @Published var isPlus: Bool = false
    @Published var products: [Product] = []
    @Published var isLoading: Bool = false

    private var updates: Task<Void, Never>?

    init() {
        // シークレットコード解放もチェック
        if UserDefaults.standard.bool(forKey: "isPlus_secret") {
            isPlus = true
        }
        // トランザクション監視を開始
        updates = Task { await listenForTransactions() }
        Task { await checkSubscriptionStatus() }
    }

    deinit { updates?.cancel() }

    // MARK: - 製品取得
    func fetchProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            print("PlusManager: fetchProducts error:", error)
        }
    }

    // MARK: - 購入処理
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let tx) = verification {
                await tx.finish()
                await checkSubscriptionStatus()
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    // MARK: - サブスクリプション確認
    func checkSubscriptionStatus() async {
        // シークレットコードが有効な場合はスキップ
        if UserDefaults.standard.bool(forKey: "isPlus_secret") {
            isPlus = true
            return
        }
        // Admin ユーザーは常に Plus
        if let email = UserDefaults.standard.string(forKey: "userEmail"),
           email == "kenichiyoshida13@gmail.com" {
            isPlus = true
            return
        }
        var hasValid = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productType == .autoRenewableSubscription,
               Self.productIDs.contains(tx.productID),
               !tx.isUpgraded {
                hasValid = true
            }
        }
        isPlus = hasValid
    }

    // MARK: - 購入復元
    func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    // MARK: - リアルタイム監視
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result {
                await tx.finish()
                await checkSubscriptionStatus()
            }
        }
    }

    // MARK: - シークレットコード解放
    func unlockWithCode(_ code: String) -> Bool {
        if code == "kfit5526" {
            UserDefaults.standard.set(true, forKey: "isPlus_secret")
            isPlus = true
            return true
        }
        return false
    }
}
```

[プロンプト例]: PlusManager を実装してサブスクリプション管理を一元化する
```text
iOS アプリで Fitingo Plus サブスクリプションを管理する PlusManager.swift を実装してください。
要件:
- StoreKit 2 を使用（iOS 15+対応）
- 製品ID: fitingo_plus_monthly, fitingo_plus_yearly
- @Published isPlus でアプリ全体に状態を配布
- シークレットコード「kfit5526」で無料解放
- Admin ユーザー（kenichiyoshida13@gmail.com）は常に Plus
- トランザクション更新をリアルタイム監視
- @MainActor で UI スレッドに公開
既存コードを読んでから実装してください。
```

### 2-3. Paywall（購入画面）の必須要件

App Store 審査を通過するために、Paywall 画面には以下が必要です。

| 要件 | 内容 |
|------|------|
| 価格明示 | ¥480/月、¥3,800/年 を必ず表示 |
| 無料トライアル明記 | 「7日間無料体験」を目立つ場所に |
| キャンセル方法 | 「設定 → Apple ID → サブスクリプション」 |
| 利用規約リンク | `https://fit.ktrips.net/privacy-policy/` |
| 復元ボタン | `AppStore.sync()` を呼ぶ「購入を復元」ボタン |
| 課金間隔 | 「毎月自動更新」「毎年自動更新」を明記 |

<div style="page-break-after: always;"></div>

---

## 第三章: Plus Gating UI

<div style="page-break-after: always;"></div>

### 3-1. Gating UI の設計方針

機能制限を表示するとき、ユーザー体験を壊さない設計が重要です。Fitingo では次の原則を採用しています。

**Gating の3つの原則:**

1. **1ページに1箇所** ── ページ内に複数のロック表示は出さない。「Plus で解放」という統一メッセージにまとめる
2. **何が解放されるか明示** ── 「Plusにするとこれが使えます」という機能リストを表示する
3. **ネガティブではなくポジティブに** ── 「使えません」ではなく「Plusで使えます」という表現にする

### 3-2. ページレベルの Gating（MIND タブ）

![MIND タブ Free ユーザー向けロック画面](screenshots/plus/mind-gate-screen.png)

MIND タブは全体がPlus限定です。フルページのロック画面を表示します。

```swift
// MindView の入り口で Plus チェック
struct MindView: View {
    @EnvironmentObject private var plus: PlusManager
    @State private var showPlusView = false

    var body: some View {
        Group {
            if plus.isPlus {
                MindContentView()
            } else {
                MindPlusGateView { showPlusView = true }
            }
        }
        .sheet(isPresented: $showPlusView) {
            PlusView()
        }
    }
}

struct MindPlusGateView: View {
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "#CE82FF"))

            Text("MIND タブは Plus 限定")
                .font(.system(size: 22, weight: .black))

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    "睡眠・マインドフルネス記録",
                    "睡眠スコア分析",
                    "AI コーチングコメント",
                    "ポモドーロタイマー統合"
                ], id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#CE82FF"))
                        Text(feature)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding()
            .background(Color(hex: "#CE82FF").opacity(0.08))
            .cornerRadius(16)

            Button(action: onUpgrade) {
                Text("Plus にアップグレード →")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#CE82FF"))
                    .cornerRadius(30)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### 3-3. セクションレベルの Gating（ROUTIN ページ）

![ROUTIN ページの Plus ロックセクション](screenshots/plus/routin-plus-locked.png)

ROUTIN ページは「Freeで見えるセクション」と「Plusが必要なセクション」が混在します。

```swift
// PlusLockedSection: 機能リストを表示してアップグレードを促す
struct PlusLockedSection: View {
    let features: [String]
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(Color(hex: "#FF8C00"))
                Text("Plus で解放")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color(hex: "#FF8C00"))
                Spacer()
                Button("アップグレード →", action: onUpgrade)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(hex: "#FF8C00"))
                    .cornerRadius(20)
            }
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#FF8C00").opacity(0.7))
                        .font(.system(size: 12))
                    Text(feature)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color(hex: "#FFF8EC"))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}
```

使用例（ROUTIN ページ）:

```swift
if plus.isPlus {
    tripleRingCard
    calorieBalanceBarCard
} else {
    PlusLockedSection(
        features: [
            "FIT・FOOD・MIND 統合レポート",
            "カロリー収支レポート",
            "Kindle書籍がWebで全文開放"
        ],
        onUpgrade: { showPlusView = true }
    )
}
```

### 3-4. ボタンレベルの Gating（フォトログボタン）

![FOOD タブの Plus 限定バッジ付きフォトログボタン](screenshots/food/IMG_3513.jpg)

ボタン自体は表示しつつ、Freeユーザーが押すと Plus 画面を表示します。

```swift
Button {
    if plus.isPlus {
        showPhotoLog = true
    } else {
        showPlusView = true
    }
} label: {
    ZStack(alignment: .topTrailing) {
        Label("AI食事フォトログ", systemImage: "camera.fill")
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.duoGreen)
            .foregroundColor(.white)
            .cornerRadius(20)

        if !plus.isPlus {
            // Plus限定バッジ
            Text("Plus限定")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color(hex: "#FF8C00"))
                .cornerRadius(6)
                .offset(x: 6, y: -6)
        }
    }
}
```

[プロンプト例]: Plus Gating UI をページ全体に一貫して適用する
```text
iOS アプリの各ページで Plus gating を適用してください。
方針:
- MIND タブ: 全体をロック。MindPlusGateView を表示
- ROUTIN ページ: tripleRingCard と calorieBalanceBarCard を PlusLockedSection で置き換え
- FIT/FOOD ページ: フォトログボタンに Plus限定バッジを表示。押したら PlusView を表示
- 1ページに1箇所のみ gating メッセージを出す
- 機能リストは各ページの実際の Plus 機能を列挙する
PlusManager.shared.isPlus で判定し、@EnvironmentObject を使ってください。
```

<div style="page-break-after: always;"></div>

---

## 第四章: Markdown から Kindle 本を作る

<div style="page-break-after: always;"></div>

### 4-1. なぜ Markdown で書くのか

Kindle 本は最終的に `.epub` または `.docx` 形式で入稿します。Markdown は次の理由で最適な執筆フォーマットです。

- **Git で差分管理できる** ── 章ごとの修正が履歴として残る
- **Claude で章を書かせやすい** ── プロンプトで章の追加・修正が簡単
- **コードブロックがそのまま書ける** ── 技術書の執筆に向いている
- **後からフォーマット変換できる** ── DOCX・PDF・HTML どれにも変換できる

### 4-2. ディレクトリ構成

```
docs/
├── cursor-claude-code-ios-app-book.md     # 本文 Markdown
├── cursor-claude-code-ios-app-book-plus.md  # 本書（Plus Edition）
├── build_book_docx.py                     # DOCX 生成スクリプト
├── restyle_book_docx.py                   # スタイル再適用スクリプト
├── screenshots/                           # 本文に埋め込む画像
│   ├── tools/
│   ├── fit/
│   ├── food/
│   └── watch/
└── output/
    ├── book.docx                          # Kindle 入稿用 DOCX
    └── book.pdf                           # 印刷用 PDF（KDP ペーパーバック）
```

### 4-3. python-docx で Kindle 対応 DOCX を生成する

![Cursor IDE で Markdown を編集している画面](screenshots/tools/cursor-ide-overview.png)

KDP（Kindle Direct Publishing）に入稿する DOCX は、**見出しスタイルが正しく設定されていること**が重要です。見出しスタイルがないと Kindle の目次ナビゲーションが機能しません。

`build_book_docx.py` の主要部分の説明：

```python
#!/usr/bin/env python3
"""
Markdown → Kindle 対応 DOCX 変換スクリプト

必要なパッケージ:
  pip install python-docx Pillow
"""

from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

# ── 配色パレット（Fitingo ブランドカラー）
GREEN   = "58CC02"   # Fitingo グリーン（H1・章タイトル）
ORANGE  = "FF8C00"   # オレンジ（H2・節タイトル）
BLUE    = "1CB0F6"   # ブルー（H3・小見出し）
INK     = "37474F"   # 本文（やわらかいダークスレート）
JP_FONT = "Hiragino Sans"  # 日本語フォント

def build_document(md_path: str, out_path: str):
    doc = Document()
    setup_styles(doc)

    with open(md_path, encoding="utf-8") as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")

        # 見出し（Kindleナビゲーション用に必ず Heading スタイルを使う）
        if line.startswith("# "):
            p = doc.add_heading(line[2:], level=1)
            apply_heading_style(p, GREEN, 22)
        elif line.startswith("## "):
            p = doc.add_heading(line[3:], level=2)
            apply_heading_style(p, ORANGE, 16)
        elif line.startswith("### "):
            p = doc.add_heading(line[4:], level=3)
            apply_heading_style(p, BLUE, 13)

        # コードブロック
        elif line.startswith("```"):
            lang = line[3:].strip()
            i += 1
            code_lines = []
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(lines[i].rstrip("\n"))
                i += 1
            add_code_block(doc, "\n".join(code_lines))

        # 表（Markdown テーブル）
        elif line.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].startswith("|"):
                table_lines.append(lines[i].rstrip("\n"))
                i += 1
            add_table(doc, table_lines)
            continue

        # 画像
        elif line.startswith("!["):
            img_path = extract_image_path(line)
            if img_path:
                add_image(doc, img_path)

        # 段落区切り
        elif line.strip() == "" or line.startswith("<div"):
            pass  # 空行はスキップ

        # 通常テキスト
        else:
            p = doc.add_paragraph()
            add_inline_markup(p, line)

        i += 1

    doc.save(out_path)
    print(f"✅ 生成完了: {out_path}")
```

[プロンプト例]: Markdown から Kindle 対応 DOCX を生成するスクリプトを実装させる
```text
docs/cursor-claude-code-ios-app-book.md から、Kindle Direct Publishing 入稿用の .docx を生成する
Python スクリプトを作ってください。

要件:
- python-docx を使う
- Heading 1/2/3 スタイルを使う（Kindle のナビゲーション目次に必要）
- 見出しの色: H1=緑(#58CC02)、H2=オレンジ(#FF8C00)、H3=ブルー(#1CB0F6)
- コードブロックはグレー背景で等幅フォント
- Markdown テーブルを docx テーブルに変換
- 画像を縮小して埋め込み（最大幅 5.5 インチ）
- 日本語フォント: Hiragino Sans
- `---` は改ページ（<w:pageBreak>）に変換
- 出力先: docs/output/book.docx

まず構造を説明してから実装してください。
```

### 4-4. DOCX → PDF 変換（ペーパーバック用）

KDP でペーパーバック（印刷本）も出版する場合は、PDF が必要です。

```bash
# LibreOffice を使って DOCX → PDF 変換（macOS）
/Applications/LibreOffice.app/Contents/MacOS/soffice \
  --headless \
  --convert-to pdf \
  --outdir docs/output/ \
  docs/output/book.docx

# または pandoc を使う（Homebrew でインストール）
brew install pandoc
pandoc docs/cursor-claude-code-ios-app-book.md \
  -o docs/output/book.pdf \
  --pdf-engine=xelatex \
  -V CJKmainfont="Hiragino Sans"
```

### 4-5. 原稿チェックリスト（KDP 入稿前）

Kindle 本の原稿を仕上げる前に確認すべき点：

| チェック項目 | 内容 |
|------------|------|
| 見出し構造 | H1（章）→ H2（節）→ H3（小見出し）の順番が崩れていない |
| 目次リンク | 目次の各行が本文見出しに正しくリンクされている |
| 画像解像度 | 300dpi 以上（ペーパーバック）、72dpi 以上（電子書籍） |
| コードブロック | 長い行が折り返されている（Kindle は横スクロール非対応） |
| 著作権表示 | 免責事項・Copyright が冒頭に記載されている |
| スクリーンショット | 他社製品の画像は引用・説明目的の範囲内 |
| ISBN | 電子書籍は KDP が無料提供。ペーパーバックも KDP 提供可 |

<div style="page-break-after: always;"></div>

---

## 第五章: KDP で出版する

<div style="page-break-after: always;"></div>

### 5-1. KDP とは

Kindle Direct Publishing（KDP）は Amazon が提供する電子書籍・ペーパーバックの自費出版プラットフォームです。無料で出版でき、ロイヤリティ（売上の35〜70%）を受け取れます。

**個人開発者が KDP を使うメリット:**
- アプリのマーケティングコンテンツになる
- 「本を書いた人が作ったアプリ」という信頼性が増す
- Kindle 読者がアプリユーザーになる相互送客ができる

### 5-2. 電子書籍の出版手順

#### ① KDP アカウント作成

1. https://kdp.amazon.co.jp にアクセス
2. Amazon アカウントでログイン（または新規作成）
3. 著者情報・銀行口座（印税振込先）を登録

#### ② 新タイトルを追加

1. KDP ダッシュボード → **新しいタイトルを追加** → **Kindle 電子書籍**
2. 書誌情報を入力：

| 項目 | Fitingo 本の設定例 |
|------|----------------|
| タイトル | Cursor + ClaudeでiPhoneアプリを週末だけで作る方法 |
| サブタイトル | SwiftUI・Apple Health・Apple WatchのAI個人開発完全ガイド |
| 著者名 | 吉田 顕一（Ken Yoshida） |
| 言語 | 日本語 |
| カテゴリ | コンピューター・IT → プログラミング |
| キーワード | Cursor、Claude、SwiftUI、HealthKit、Apple Watch、iOS開発、個人開発 |

#### ③ 原稿アップロード

1. **DOCX ファイル**（`book.docx`）をアップロード
2. Kindle プレビューアーで確認（PC・スマートフォン・Kindle 端末でのレイアウト確認）
3. 目次ナビゲーションが機能しているか確認

#### ④ 表紙の作成

表紙サイズ: 縦1600×横2560px（推奨）。JPEG または PNG。

表紙制作の選択肢:
- **Canva**（無料・テンプレートあり）── 最も手軽
- **KDP カバークリエーター**（KDP 内蔵）── 無料
- **Figma** ── デザイナー向け

[プロンプト例]: Claude に表紙デザインのコンセプトを考えさせる
```text
以下の本の表紙デザインコンセプトを考えてください。
タイトル: 「Cursor + Claudeで個人アプリを作り、Kindleで出版し、Plusで稼ぐ方法」
著者: 吉田 顕一
ターゲット読者: 30〜45歳、IT系会社員、副業・個人開発に興味がある
雰囲気: 技術書だがとっつきやすい。Fitingo アプリのブランドカラー（緑・オレンジ）を活かしたい
Canva で作れるレイアウト案を3つ提案してください。
```

#### ⑤ 価格設定

| ロイヤリティ | 価格帯 | 条件 |
|------------|-------|------|
| **70%** | ¥250〜¥1,250 | 推奨プラン |
| **35%** | それ以外 | 価格制限なし |

日本では ¥499〜¥799 程度が技術系同人本・個人出版の相場です。

### 5-3. ペーパーバックの出版

KDP ではペーパーバック（印刷本）も出版できます。電子書籍と同じ原稿から PDF を生成して入稿します。

**ペーパーバック設定（推奨）:**

| 項目 | 設定 |
|-----|------|
| サイズ | B5（182×257mm）または A5（148×210mm） |
| 用紙 | クリームカラー（読みやすい） |
| カバー | 光沢（表紙が鮮やか） |
| ページ数 | 100〜300ページが読みやすい |

**印刷費（参考）:**

| ページ数 | 印刷費（Amazon.co.jp発注） |
|---------|--------------------------|
| 150ページ | 約¥500 |
| 250ページ | 約¥750 |
| 350ページ | 約¥1,000 |

ペーパーバックは「定価 - 印刷費 - Amazon手数料 = 著者収益」の計算になります。

### 5-4. Kindle 本とアプリを連携させる

Kindle 本の中でアプリのダウンロードを促し、アプリの中で Kindle 本の購読を促す相互送客が効果的です。

**Kindle 本 → アプリへの誘導（本文に記載）:**
```
📱 Fitingo アプリ（iOS）
本書のサンプルアプリをApp Storeからダウンロードできます。
https://apps.apple.com/jp/app/kfit-fitingo/id[APP_ID]
```

**アプリ → Kindle 本への誘導（アプリ内の設定画面に表示）:**
```
📚 Kindleで全文読む（Plus限定）
本書の執筆過程・実装解説を収めたKindle本をWebで全文読めます。
※ Fitingo Plus ユーザー限定
```

<div style="page-break-after: always;"></div>

---

## 第六章: App Store 最適化（ASO）

<div style="page-break-after: always;"></div>

### 6-1. ASO とは

ASO（App Store Optimization）は、App Store の検索結果でアプリが上位に表示されるよう最適化する施策です。SEO のアプリ版です。

個人開発では広告費をかけられないため、**オーガニック（自然流入）をいかに増やすか**がグロースの鍵になります。

### 6-2. タイトル・サブタイトルの設計

App Store のアルゴリズムは、**タイトルとサブタイトルのキーワードを重視**します。

| 項目 | 制限 | Fitingo の設定 |
|------|------|--------------|
| アプリ名 | 30文字 | kfit – 習慣スパイラル |
| サブタイトル | 30文字 | 毎日の運動・食事・睡眠を1画面で |

**キーワード選定のポイント:**
- 検索ボリュームが中程度で競合が少ないキーワードを選ぶ
- 「フィットネス」より「習慣化アプリ」、「ダイエット」より「カロリー記録」が狙いやすい
- Apple Watch との連携はキーワードになる

**Fitingo のターゲットキーワード（例）:**

| キーワード | 競合 | 検討 |
|----------|------|------|
| 習慣化アプリ | 中 | タイトル・説明文に含める |
| ヘルスケア記録 | 高 | 説明文のみ |
| Apple Watch 運動記録 | 低〜中 | サブタイトル候補 |
| カロリー管理 無料 | 高 | 説明文のみ |
| マインドフルネス 記録 | 低 | キーワード欄に設定 |

### 6-3. 説明文のライティング

App Store 説明文の最初の3行（折りたたまれる前）が最も重要です。

**Fitingo 説明文（冒頭3行の例）:**
```
毎日の運動、食事、睡眠、マインドフルネス——
すべての習慣を美しいスパイラルで記録・可視化する、次世代の習慣管理アプリです。

Apple Watch 連携・HealthKit 完全対応。Duolingo のように習慣が続く設計。
```

**説明文のテンプレート（Claude に書かせる）:**

[プロンプト例]: App Store 説明文を Claude に書かせる
```text
以下のアプリの App Store 説明文を書いてください。

アプリ名: Fitingo（kfit）
ジャンル: 習慣化・フィットネス
主要機能:
- スパイラル表示で今日の目標達成状況を可視化
- Apple Watch 連携・HealthKit 対応
- フォトログ AI 食事分析
- 睡眠・マインドフルネス記録
- 友達とシェアできる TOMO フィード
ターゲット: 健康習慣を作りたい 25〜45 歳の日本人

要件:
- 冒頭 3 行で心をつかむ
- 機能説明は絵文字付きの箇条書き
- 4,000文字以内
- Apple Watch・HealthKit のキーワードを自然に含める
```

### 6-4. スクリーンショットの設計

スクリーンショットは App Store で最初に目に入る**ビジュアル広告**です。

**スクリーンショット設計の3原則:**

1. **最初の2枚で勝負** ── 一覧表示では2枚しか見えないため、1・2枚目が全て
2. **キャプションを入れる** ── スクリーンショットの上下にキャッチコピーを添える
3. **ダークモード対応を1枚** ── ダークモード派ユーザーへのアピールになる

**Fitingo のスクリーンショット構成（推奨）:**

![ROUTIN スパイラル画面（達成状態）](screenshots/main/IMG_3530.jpg)

| 順番 | 画面 | キャプション案 |
|-----|------|-------------|
| 1 | ROUTIN スパイラル（達成状態） | 今日の習慣が一目でわかる |
| 2 | FIT・FOOD・MIND 統合リング | 体・食・心をひとつの画面で |
| 3 | FOOD フォトログ AI解析 | 写真を撮るだけで栄養を記録 |
| 4 | MIND 睡眠スコア | 昨夜の睡眠を点数で把握 |
| 5 | Apple Watch 渦巻き | Watchでもスパイラルを確認 |
| 6 | TOMO フィード | 友達と一緒に続けられる |

**スクリーンショット制作ツール:**
- **Canva** ── テンプレートで素早く作れる
- **Figma** ── デザインに時間をかけられるなら最良
- **AppLaunch** ── App Store 用スクリーンショット専用ツール

<div style="page-break-after: always;"></div>

---

## 第七章: SNS・コンテンツマーケティング戦略

<div style="page-break-after: always;"></div>

### 7-1. 個人開発者が使うべき SNS チャンネル

| SNS | 特徴 | Fitingo での活用 |
|-----|------|---------------|
| **X（旧 Twitter）** | 開発者コミュニティが活発。「#個人開発」「#iOS開発」タグが機能する | 開発ログ・機能追加の告知 |
| **Qiita** | 技術記事のSEO効果が高い。検索流入でアプリを知ってもらう | 実装詳細の技術記事 |
| **Zenn** | 本（book）形式で体系的にまとめられる | 本書と同内容の無料版 |
| **TikTok / Instagram Reels** | 健康習慣ジャンルのリーチが大きい | アプリ使い方の30秒動画 |
| **note** | 開発ストーリー・ビジネス観点のブログ | マネタイズ戦略・開発日記 |
| **YouTube** | 長尺での説明。SEO効果が高い | 開発過程の解説動画 |

### 7-2. X（旧 Twitter）での発信戦略

X での個人開発アカウントは「**ビルドログ（Build in Public）**」スタイルが最も効果的です。

**Build in Public とは:**
開発の進捗・失敗・学びをリアルタイムで発信し、フォロワーと一緒に成長するスタイルです。完成品の告知より、**プロセスへの共感**でフォロワーを獲得します。

**投稿パターン（ローテーション）:**

| 曜日 | テーマ | 内容例 |
|-----|--------|--------|
| 月 | 週の目標 | 「今週は Plus サブスクリプションを実装します」 |
| 水 | 進捗・スクショ | 「FoodView に Plus 限定バッジを追加。こういうUIです👇」 |
| 金 | 学び・気づき | 「StoreKit 2 でハマったこと3つ。isUpgraded の罠」 |
| 日 | 振り返り | 「今週の作業時間: 8h。実装完了: ×、学び: ✓」 |

**X での告知テンプレート（Claude に生成させる）:**

[プロンプト例]: 機能追加の X 投稿を Claude に書かせる
```text
Fitingo アプリに Plus サブスクリプション機能を実装しました。
X（旧 Twitter）用の投稿文を書いてください。

実装した内容:
- StoreKit 2 でサブスクリプション購入フローを実装
- MIND タブを Plus 限定にゲーティング
- フォトログボタンに「Plus限定」バッジを追加

要件:
- 個人開発者らしい等身大の言葉で
- スクリーンショットに付けるキャプションも
- 280文字以内（日本語）
- ハッシュタグ: #個人開発 #iOS #SwiftUI を含める
```

### 7-3. Qiita / Zenn での技術記事戦略

技術記事は**長期的な SEO 資産**になります。一度書いた記事が半年後もアプリへの流入を生み続けます。

**Fitingo 関連で書ける技術記事のテーマ（例）:**

| 記事タイトル | 検索キーワード |
|-----------|-------------|
| StoreKit 2 でサブスクリプションを実装する完全ガイド | StoreKit 2 実装 |
| SwiftUI で Plus Gating UI を作る | SwiftUI フリーミアム |
| HealthKit から睡眠データを取得して表示する | HealthKit 睡眠 |
| Apple Watch アプリを Plus 限定にする方法 | WatchConnectivity Plus |
| python-docx で Kindle 対応 DOCX を自動生成する | python-docx Kindle |
| Cursor + Claude でフィットネスアプリを週末で作った話 | Cursor Claude iOS |

[プロンプト例]: 技術記事の下書きを Claude に書かせる
```text
以下の技術記事の下書きを書いてください。
Qiita / Zenn 向けです。

タイトル: 「StoreKit 2 でサブスクリプションを実装する ─ PlusManager パターン」
対象読者: iOS 開発初中級者。StoreKit 2 を初めて使う人
記事の構成:
1. StoreKit 2 と StoreKit 1 の違い（表で比較）
2. App Store Connect での商品登録手順
3. PlusManager.swift の実装（コード全文）
4. Paywall 画面の必須要件
5. ハマりポイント3つ（isUpgraded、テスト方法、シミュレーターでの動作）
コードブロックは完全なコードを載せる。
ハマりポイントは具体的に。
```

### 7-4. TikTok / Instagram Reels での動画戦略

健康・フィットネスカテゴリは動画プラットフォームとの相性が良いです。

**30秒動画の構成（フォーマット）:**

```
[0〜3秒]  フック ── 「Apple WatchでiPhoneの習慣アプリを操作できます」
[3〜20秒] 実演 ── アプリの画面操作をリアルタイムで見せる
[20〜27秒] 機能説明 ── 字幕で「FIT/FOOD/MINDを一画面で管理」
[27〜30秒] CTA ── 「プロフィールのリンクから無料ダウンロード」
```

**動画コンテンツのアイデア:**

| テーマ | フック |
|--------|--------|
| スパイラルが完成する瞬間 | 「今日の全ゴールを達成した瞬間 🌀」 |
| フォトログで即座に解析 | 「ランチを撮るだけでカロリーがわかる」 |
| Apple Watch 渦巻き | 「Apple Watch でもスパイラルが見える」 |
| 友達と記録を共有 | 「Duolingo みたいに友達と習慣を競える」 |
| 睡眠スコア | 「昨夜の睡眠が100点満点で何点か教えます」 |

<div style="page-break-after: always;"></div>

---

## 第八章: アプリを拡散する施策プラン

<div style="page-break-after: always;"></div>

### 8-1. リリース前（プレローンチ）

アプリを公開する前から認知を作っておくことで、初日のダウンロード数が増えます。

**リリース前 4週間のタスク:**

```
Week -4（公開4週前）
  ─ App Store Connect でアプリ情報を入力・審査提出
  ─ X で「開発中」投稿を開始（毎日1回）
  ─ ランディングページ（fit.ktrips.net）をPublicにする
  ─ TestFlight で知人10人にベータテストを依頼

Week -3（公開3週前）
  ─ Qiita に開発記事1本公開（Cursor + Claude で iOS アプリを作った話）
  ─ X でスクリーンショット公開（3回）
  ─ App Store のスクリーンショットとプレビュー動画を制作

Week -2（公開2週前）
  ─ Apple の审查が通ったら「リリース準備完了」を X で告知
  ─ X で機能紹介スレッドを投稿（5機能を1ツイートずつ）
  ─ note に「なぜこのアプリを作ったか」の記事を投稿

Week -1（公開1週前）
  ─ ベータテスターのフィードバックを反映
  ─ カウントダウン投稿「あと7日でリリース」
  ─ Kindle 本の原稿を仕上げ・KDP に入稿
```

### 8-2. リリース日施策

リリース日は最もレビューを集めやすいゴールデンタイムです。

**リリース日のタスク:**

1. **X でリリース告知投稿**（スクリーンショット付き・App Store リンク）
2. **友人・知人・Slack/Discord に直接シェア**（最初の10レビューが最重要）
3. **Qiita / Zenn に告知記事**（「リリースしました」の記事は拡散されやすい）
4. **SNS グループへの投稿**（個人開発 Slack、SwiftUI Discord、健康アプリコミュニティ）
5. **Hacker News / Product Hunt への投稿**（英語版がある場合）

**レビューを依頼するプロンプト（知人への DM）:**

```text
フィットネス習慣化アプリ「Fitingo」をリリースしました！

Apple Watchと連携して、運動・食事・睡眠を1画面で管理できるアプリです。

無料でダウンロードできます（Plus プランもあり）。
もし使ってみていただけたら、App Store のレビューをいただけると大変助かります。

https://apps.apple.com/jp/app/kfit-fitingo/id[APP_ID]
```

### 8-3. リリース後の継続施策（3〜12ヶ月）

初回リリースより、**継続的な改善と発信**がユーザー増加の鍵です。

**月次施策サイクル:**

```
毎週（継続）:
  ─ X に開発ログ・機能紹介を投稿（週2〜3回）
  ─ App Store Connect のコンバージョン率を確認
  ─ レビューへの返信（否定的なレビューへの対応が特に重要）

毎月:
  ─ 小さな機能追加または改善のリリース（アップデートで上位表示効果）
  ─ Qiita に技術記事 1本
  ─ ユーザーインタビュー（ベータテスターや知人に感想を聞く）

3ヶ月ごと:
  ─ App Store のスクリーンショットをリフレッシュ
  ─ キーワードの見直し（App Store の Analytics でどのキーワードで流入したか確認）
  ─ Kindle 本の内容を更新（アプリの機能追加に合わせて）
```

### 8-4. コミュニティ形成

アプリの長期的な成長には、ユーザーコミュニティが不可欠です。

**コミュニティ形成の施策:**

| 施策 | 内容 | 工数 |
|------|------|------|
| X の専用アカウント | @fitingo_app などのアカウントでアプリ専用発信 | 低 |
| Discord サーバー | ユーザーが直接フィードバックを出せる場 | 中 |
| TOMO フィード活性化 | アプリ内の TOMO フィードをコミュニティとして育てる | 低 |
| ユーザー事例の発信 | 「このユーザーが30日続けた」などの成功事例を X で紹介 | 低 |
| ベータテスター招待 | 新機能のベータテスターを X 経由で募集 | 低 |

![Apple Watch スパイラル画面](screenshots/watch/incoming-CE070953.png)

### 8-5. Kindle 本とアプリの相互送客

Kindle 本とアプリを組み合わせた「エコシステム」を作ることが、個人開発者の差別化になります。

```
読者がKindle本を購入
    ↓
本の中でアプリをダウンロードする
    ↓
アプリ内で「Kindle本をWebで読む」ボタン（Plus限定）
    ↓
Plusにアップグレード
    ↓
「本で学んだことをアプリで実践する」体験が完結
    ↓
SNSでシェア → 次の読者・ユーザーへ
```

**この連携を実現するための施策:**

1. **アプリ内に Kindle 本へのリンク**（設定画面・ヘルプ）
2. **Kindle 本内にアプリのダウンロードリンク**（QR コード・URL）
3. **Kindle 本購入者へのシークレットコード配布**（本の奥付に「kfit5526 で Plus 解放」と記載）
4. **X でクロスプロモーション**（「Kindle 本が出ました × アプリを使いながら読むとより理解しやすい」）

<div style="page-break-after: always;"></div>

---

## 第九章: 収益見込みと KPI 管理

<div style="page-break-after: always;"></div>

### 9-1. 収益の複数チャンネル

Fitingo の収益は1チャンネルではなく、複数を組み合わせます。

| チャンネル | 単価 | 想定月収（成熟時） | 特記 |
|---------|------|---------------|------|
| **Plus サブスク（月額）** | ¥408/月（手数料後） | ¥40,000〜¥400,000 | 主収益 |
| **Plus サブスク（年額）** | ¥3,230/年（手数料後） | 同上に含む | LTV 最大化 |
| **Kindle 本（電子書籍）** | ¥150〜¥350/冊（ロイヤリティ） | ¥5,000〜¥50,000 | 間接的な集客 |
| **Kindle 本（ペーパーバック）** | ¥200〜¥400/冊 | ¥2,000〜¥20,000 | — |
| **Withings アフィリエイト** | 3〜8% | 数千円〜 | 体重計ページからリンク |
| **テーマパック（買い切り）** | ¥213/パック（手数料後） | 変動 | 将来追加 |

### 9-2. Plus 転換率の目標

| 月間 DAU | 転換率目標 | Plus 人数 | 月間売上（手数料後） |
|---------|----------|----------|-----------------|
| 100 | 3% | 3人 | 約 **¥1,200** |
| 500 | 5% | 25人 | 約 **¥9,500** |
| 2,000 | 7% | 140人 | 約 **¥53,500** |
| 5,000 | 8% | 400人 | 約 **¥153,000** |
| 10,000 | 10% | 1,000人 | 約 **¥382,000** |

※ ARPU（月換算）= 月額¥408 × 40% + 年額¥269/月換算 × 60% ≈ ¥382/人/月

### 9-3. KPI 管理（App Store Connect Analytics）

App Store Connect の Analytics で確認すべき指標：

| KPI | 目標 | 確認頻度 |
|-----|------|---------|
| **インプレッション数** | 毎週増加 | 週次 |
| **プロダクトページビュー** | インプレッションの20%以上 | 週次 |
| **コンバージョン率** | 2〜5%（業界平均） | 月次 |
| **セッション継続率（7日）** | 30%以上 | 月次 |
| **セッション継続率（30日）** | 15%以上 | 月次 |
| **Plus 転換率** | 5〜10% | 月次 |
| **チャーンレート（解約率）** | 月5%以下 | 月次 |
| **平均セッション時間** | 3分以上 | 月次 |

[プロンプト例]: App Store Analytics データを分析して改善案を出させる
```text
以下は Fitingo アプリの App Store Analytics データです（先月）。
改善優先度と施策案を出してください。

インプレッション数: 1,200
プロダクトページビュー: 180（コンバージョン率 15%）
インストール数: 45
7日継続率: 22%
30日継続率: 8%
Plus 転換数: 2（転換率 4.4%）

特に継続率が低いため、オンボーディング改善が必要だと思っています。
具体的な改善案を3つ出してください。
```

### 9-4. 段階的ロールアウト計画

```
Phase 1: 公開直後（〜2ヶ月）
  ─ 全機能を無料で提供（Plus もシークレットコードで解放）
  ─ 10件以上のレビューを獲得し、★4以上を目標
  ─ DAU・継続率・クラッシュ率を計測・改善

Phase 2: 有料化開始（3ヶ月目〜）
  ─ StoreKit 2 サブスクリプションを有効化
  ─ 7日間無料トライアル付きで転換率を高める
  ─ 既存ユーザーには1ヶ月無料移行期間を提供
  ─ Kindle 本のリリースでアプリ認知を拡大

Phase 3: 機能拡充・コミュニティ（6ヶ月目〜）
  ─ Plus ウィジェット・テーマ追加
  ─ 年額プランの割引率を告知・プッシュ
  ─ ユーザーインタビューで次バージョンを計画
  ─ Discord / X コミュニティ形成

Phase 4: スケール（12ヶ月目〜）
  ─ 英語対応（App Store のローカライゼーション）
  ─ 法人・ジム向けライセンスプランの検討
  ─ 第2弾 Kindle 本の執筆
```

<div style="page-break-after: always;"></div>

---

## 終わりに

本書を通じて、「作る・届ける・稼ぐ」の3つのフェーズを扱いました。

アプリを作ることは始まりにすぎません。Kindleで本を書き、X で発信し、App Store で最適化し、Plus で収益化する。これらは別々の作業ではなく、一つのループです。

アプリが使われれば記事のネタが生まれます。記事がユーザーを連れてきます。ユーザーのフィードバックがアプリを良くします。良いアプリが Kindle 本の信頼性を高めます。

CursorとClaudeがあれば、このループを一人で回せます。完璧なアプリを作ってから発信するのではなく、**作りながら発信し、発信しながら改善する**。それが2026年の個人開発の正解です。

まず小さく始めてください。X に1投稿、Qiita に1記事、App Store に1スクリーンショット。それが積み重なって、大きな資産になります。

---

*本書のサンプルアプリ Fitingo（kfit）は個人開発プロジェクトです。GitHubで公開中: https://github.com/ktrips/kfit*

<div style="page-break-after: always;"></div>

---

## 付録A: Free / Plus 機能比較表（最新版）

2026年6月時点の Fitingo Free / Plus 機能比較です。

| カテゴリ | 機能 | Free | Plus |
|---------|------|------|------|
| **全般** | 広告なし | — | ✓ |
| | 全機能フルアクセス | — | ✓ |
| **FIT** | アクティビティ記録・基本表示 | ✓ | ✓ |
| | 詳細アクティビティ分析 | — | ✓ ※AI要APIキー |
| | 目標自動調整提案 | — | ✓ ※AI要APIキー |
| | FIT フィード写真記録 | — | ✓ |
| **FOOD** | 食事ログ記録（手入力）・PFC表示 | ✓ | ✓ |
| | フォトログ AI 栄養解析 | — | ✓ ※AI要APIキー |
| | 週次・月次 食事レポート | — | ✓ |
| | FOOD フィード写真記録 | — | ✓ |
| **MIND** | 睡眠・マインドフル記録 | — | ✓ |
| | 睡眠スコア分析 | — | ✓ |
| | AI コーチングコメント | — | ✓ ※AI要APIキー |
| **ROUTIN** | スパイラル・基本ゴール | ✓ | ✓ |
| | FIT/FOOD/MIND 統合レポート | — | ✓ |
| | カロリー収支レポート | — | ✓ |
| **TOMO** | 友達追加 | 3人まで | 無制限 |
| | フレンドフィード閲覧 | 一部 | すべて |
| **BOOKS** | Kindle 本を Web で全文読む | — | ✓ |
| | 書籍のオフライン保存 | — | ✓ |
| **Apple Watch** | Watch アプリ | — | ✓ |
| | Watch モーション運動検出 | — | ✓ |
| | Watch ウィジェット | — | ✓ |
| **カスタマイズ** | スパイラルテーマ | 1種 | 10種以上 |
| | Plus ウィジェット | — | ✓ |
| | 時間帯リマインダー | 1スロット | 全スロット |

> **AI 機能について**: AI 機能（栄養解析・コーチング・目標提案）は Plus プランで使えますが、別途 SETTINGS → LLM設定 から API キーの設定が必要です。

<div style="page-break-after: always;"></div>

---

## 付録B: KDP 出版チェックリスト

### 原稿チェック

- [ ] タイトル・著者名が確定している
- [ ] 免責事項・Copyright が冒頭に記載されている
- [ ] 目次が本文見出しにリンクされている
- [ ] すべての見出しに Heading 1/2/3 スタイルが適用されている
- [ ] コードブロックが等幅フォントになっている
- [ ] Markdown テーブルが docx テーブルに変換されている
- [ ] 画像が正しく埋め込まれている（最大幅 5.5 インチ）
- [ ] 脱字・誤字チェック完了
- [ ] 他社ロゴ・スクリーンショットの使用が引用範囲内

### KDP 登録チェック

- [ ] KDP アカウント作成・銀行口座登録完了
- [ ] タイトル・サブタイトル・著者名入力完了
- [ ] 説明文（4,000文字以内）入力完了
- [ ] カテゴリ選択完了（2カテゴリまで）
- [ ] キーワード設定完了（7つまで）
- [ ] 表紙画像アップロード完了（縦1600×横2560px 以上）
- [ ] 原稿（DOCX）アップロード完了
- [ ] Kindle プレビューアーで確認完了
- [ ] 価格設定完了（ロイヤリティ 70% 対象価格帯か確認）
- [ ] KDP セレクト登録の要否を決定

### 出版後チェック

- [ ] Amazon の商品ページ URL を確認・保存
- [ ] X・Qiita・note で出版告知投稿
- [ ] アプリ内の Kindle 本リンクを本番 URL に更新
- [ ] KDP Analytics でページ読み取り数（KENPC）を確認

<div style="page-break-after: always;"></div>

---

## 付録C: マーケティング施策チェックリスト

### リリース前（4週前〜）

- [ ] App Store Connect にアプリ情報を入力・審査提出
- [ ] X アカウント作成（専用アカウントまたは個人アカウント）
- [ ] ランディングページ（fit.ktrips.net）を公開
- [ ] TestFlight でベータテスト（10人以上）
- [ ] Qiita に開発記事1本公開
- [ ] App Store スクリーンショット・プレビュー動画を制作

### リリース日

- [ ] X でリリース告知（スクリーンショット + App Store リンク）
- [ ] 友人・知人へ直接 DM でレビュー依頼
- [ ] Qiita / Zenn に「リリースしました」記事を投稿
- [ ] 個人開発 Slack / Discord へ投稿
- [ ] App Store の Ratings & Reviews 画面をブックマーク

### リリース後（週次・月次）

- [ ] X に週2〜3回の開発ログ投稿（継続）
- [ ] App Store Connect Analytics を週次確認
- [ ] 1ヶ月以内に最初のアップデートリリース
- [ ] Qiita に月1本の技術記事（継続）
- [ ] レビューへの返信（特に否定的レビューは24時間以内）

### 3ヶ月後の見直し

- [ ] App Store のスクリーンショットをリフレッシュ
- [ ] キーワード・説明文を改定（Analytics の検索キーワードを参照）
- [ ] Kindle 本の内容を更新
- [ ] Plus 転換率・継続率を分析し、gating 設計を見直す
- [ ] 次の大型機能のロードマップを X で発信
