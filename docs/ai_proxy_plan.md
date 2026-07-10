# AI API キー廃止 — サーバー代理方式 決定ドキュメント

作成日: 2026-07-08  
最終更新: 2026-07-11（日次カテゴリ別クォータに変更・APIキー不要で1日1回体験へ）  
出典: docs/SamBezThieMuskJobs_plan.md Part 2（Bezos）2-5-1「最優先の商品設計修正」

## 決定

**方式 B: サーバー代理呼び出し + 日次カテゴリ別クォータ制を採用する。**

| 案 | 内容 | 判定 |
|---|---|---|
| A. 現状維持（ユーザー API キー） | Plus 特典なのに購入後に API キー設定が必要 | ❌ 顧客は API キーという概念を知らない。PR の中核「写真だけで記録」が購入直後に崩れる |
| **B. サーバー代理 + クォータ** | Cloud Functions がサーバー側キーで代理呼び出し。日次回数制限でコスト管理 | ✅ 採用。ユーザー体験ゼロ設定・原価はプラン料金に織り込む |
| C. 買い切りクレジット | 都度クレジット購入 | ❌ 「サブスク疲れ」層に課金操作を増やすのは逆効果 |

## クォータ設計（2026-07-11 改定）

### 概念

- **カテゴリ**: `food`（AI食事フォトログ）/ `edu`（語学AI例文）/ `diet`（ダイエットAI）
- **90秒モード**: 5日チャレンジ達成前（`activeDays < 5`）の全ユーザーが対象
- **カスタムAPIキー**: ユーザーが自分の OpenAI キーを Firestore に登録した場合、クォータ消費なし・自己負担

| プラン | 上限 | ねらい |
|---|---|---|
| 90秒モード中（全ユーザー） | **全カテゴリ合計 1回/日** | 習慣入口で「AI体験」を必ず1度させる。ハードルゼロ |
| Free（5日達成後） | **カテゴリごと 1回/日** | 毎日使える体験を継続させ、Plus へのアップセルを自然に引き出す |
| Plus | **カテゴリごと 3回/日** | 本格利用ユーザーの満足度。実質上限を感じにくい設計 |
| カスタム API キー | **無制限**（自己負担） | パワーユーザー向け。Fitingo の原価ゼロで最高の体験を提供 |

### マーケティング上の意図

> **「APIキー不要・登録初日からAIが使える」** が最大の差別化ポイント。
>
> 競合（あすけん等）は高度なAIを有料または別設定で提供するが、Fitingo は
> インストール直後・ログイン直後から「📸 写真1枚で栄養素を分析」が動く。
> この「最初の10秒で価値を感じる体験」（Bezos型）こそが継続率・Plus転換率の鍵。

### 原価試算（gpt-4o-mini、食事写真1回 ≈ 1,500 tokens）

- 1 回 ≈ $0.001 前後
- Free ユーザーが food/edu 各1回/日使うと月最大 **約 ¥9/人**
- Plus（3回/日×2カテゴリ×30日）= 月最大 180 回 → **約 ¥27/人**
- Plus 月額 ¥480（手数料 15% 控除後 ¥408）に対し原価率 ~7%。実際の平均使用は上限の 2〜3 割と想定で原価率 2% 以下

## 実装状況

- ✅ `aiProxy` callable 関数（firebase/functions/index.js）
  - 認証必須 / `users/{uid}.isPlus` で Plus 判定
  - `category`（food/edu/diet/general）と `isNinetyMode` を受け取り日次カテゴリ別クォータを適用
  - `users/{uid}/ai-usage/daily-{YYYY-MM-DD}` に `{category}: count` フィールドで記録
  - `users/{uid}/settings/ai.openaiApiKey` にカスタムキーがあれば消費なし・そのキーで呼び出し
  - 画像（base64）+ プロンプトを受け、OpenAI chat/completions を代理呼び出し
  - キー設定（Secret Manager）: `firebase functions:secrets:set OPENAI_API_KEY`
  - ✅ 本番稼働（2026-07-10 初回、2026-07-11 日次クォータに改定）

- ✅ iOS `AIProxyClient.call(prompt:imageBase64:category:isNinetyMode:)`
  - `AuthenticationManager.analyzePhoto()` → `category: "food"`
  - `DuolingoTextExtractor.callLLMText()` → `category: "edu"`
  - 両者とも `RetentionTracker.shared.localActiveDayCount < 5` で `isNinetyMode` を判定

- ✅ iOS `AIQuotaManager.swift`（新規、2026-07-11）
  - Firestore の日次カウントをクライアント側でも参照可能
  - カスタムAPIキーの読み書き（`users/{uid}/settings/ai`）

- ✅ iOS `SettingsView` — `CustomAPIKeySheet`
  - `sk-` で始まるキーを入力 → Firestore に保存 → 以後無制限利用

- ✅ UI の変更（2026-07-11）
  - `LLMAPIKeyNotice`: 「APIキー不要・1日1回無料で利用できます」緑バナーに変更
  - `DailyIntakeView`: APIキー未設定でもボタン有効・解析実行
  - `EduLogManager`: APIキー未設定でも AI 例文生成を実行
  - クォータ超過時: 「今日の枠を使いました。明日また試してね！」フレンドリーメッセージ

## セキュリティ

- API キーはクライアントに一切配布しない（Functions Secret Manager のみ）
- カスタムキーは Firestore `users/{uid}/settings/ai` に保存（本人のみ読み書き可）
- App Check の導入を将来検討（callable の乱用防止）
- prompt 上限 8,000 字・タイムアウト 60 秒・失敗時はクォータ消費なし
