# AI API キー廃止 — サーバー代理方式 決定ドキュメント

作成日: 2026-07-08
出典: docs/SamBezThieMuskJobs_plan.md Part 2（Bezos）2-5-1「最優先の商品設計修正」

## 決定

**方式 B: サーバー代理呼び出し + 月次クォータ制を採用する。**

| 案 | 内容 | 判定 |
|---|---|---|
| A. 現状維持（ユーザー API キー） | Plus 特典なのに購入後に API キー設定が必要 | ❌ 顧客は API キーという概念を知らない。PR の中核「写真だけで記録」が購入直後に崩れる |
| **B. サーバー代理 + クォータ** | Cloud Functions がサーバー側キーで代理呼び出し。月次回数制限でコスト管理 | ✅ 採用。ユーザー体験ゼロ設定・原価はプラン料金に織り込む |
| C. 買い切りクレジット | 都度クレジット購入 | ❌ 「サブスク疲れ」層に課金操作を増やすのは逆効果。B のクォータで実質同等 |

## クォータ設計

| プラン | 月間 AI 呼び出し | ねらい |
|---|---|---|
| Free | 5 回 | オンボーディングで「撮るだけで記録」を必ず体験させる（Bezos: 最初の10秒） |
| Plus | 300 回 | 1 日 10 回相当。実質無制限の体感 |

### 原価試算（gpt-4o-mini、食事写真1回 ≈ 1,500 tokens 入出力）

- 1 回 ≈ $0.001 前後 → Plus ユーザーが月 300 回使い切っても **約 ¥50/人**
- Plus 月額 ¥480（手数料 15% 控除後 ¥408）に対し原価率 ~12%。実際の平均使用は上限の 1〜2 割と想定され、原価率は数 % に収まる

## 実装状況

- ✅ `aiProxy` callable 関数（firebase/functions/index.js）
  - 認証必須 / users/{uid}.isPlus で Plus 判定 / users/{uid}/ai-usage/{YYYY-MM} で月次カウント
  - 画像（base64）+ プロンプトを受け、OpenAI chat/completions を代理呼び出し
  - キー設定（Secret Manager 方式・2026-07-10 移行）: `firebase functions:secrets:set OPENAI_API_KEY` → `firebase deploy --only functions`
  - ✅ 本番稼働確認（2026-07-10、Secret v1 が aiProxy/generateWeeklyReport にアタッチ済み）

## 残タスク（iOS 側の移行）

1. ✅ **isPlus の Firestore 書き込み**: PlusManager の `isPlus` didSet + setup() 完了時に `users/{uid}.isPlus` を同期（2026-07-10）
2. ✅ **呼び出しの切り替え**: API キー未設定時は `AIProxyClient`（callable REST を FirebaseFunctions SDK 非依存で叩く軽量クライアント）経由に置換。キー設定済みユーザーは従来経路を維持（2026-07-10）
   - ※ SDK を使わない理由: AuthenticationManager/DuolingoTextExtractor は kedu ターゲットにもソース共有されており、kedu は FirebaseFunctions pod を持たないため
3. ✅ **設定 UI の変更**: LLMSettingsView を「設定不要（サーバー経由）」の説明 + Free/Plus クォータ表示に刷新し、キー入力欄は「🔧 上級者向け」の折りたたみに降格（2026-07-10）
4. **クォータ UI**: 残回数の常時表示は未実装（`resource-exhausted` のエラー文言表示のみ）
5. monetization_plan.md / 付録A の「※別途 API キー要」注記の削除 ← 未確認

## セキュリティ

- API キーはクライアントに一切配布しない（Functions config のみ）
- App Check の導入を将来検討（callable の乱用防止）
- prompt 上限 8,000 字・タイムアウト 60 秒・失敗時はクォータ消費なし
