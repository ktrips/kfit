# kfit（Fitingo）実装状況サマリー

最終更新: 2026-07-12

このドキュメントは kfit（Fitingo）の現時点での実装状況をまとめたものです。個別のUP DATE履歴は [README.md の「最近の主なアップデート」](README.md#-最近の主なアップデート) を参照してください。

---

## プロダクトの現在地

**「今度こそ、続く。」** — 記録ゼロ秒・90秒から始める習慣化アプリとして、2026年7月時点で以下がすべて本番稼働しています。

1. **90秒モード**: 新規ユーザーは5タブを見せず、FIT/DIET/FOOD/EDUの4モードを横スワイプする1画面から開始。7日連続活動で全機能が解放される
2. **AIフォトログ（サーバー代理）**: Cloud Functions `aiProxy` がサーバー側APIキーで代理呼び出し。ユーザーはAPIキー設定不要で登録直後からAI食事解析・語学記録が使える
3. **TOMOフィード**: 「今日やった」ことだけを友達と共有するプライバシー配慮型ソーシャル機能。投稿の再生でハート+1・再生側にポイント+10
4. **週次AIレポート共有カード**: `fit.ktrips.net/r/{id}` で未ログインでも閲覧できるURL付き共有
5. **90日再検査チャレンジ**: 健康診断で「要改善」だった人向けの未ログイン登録・PV計測LP
6. **Fitingo Plus**: ¥480/月・¥3,800/年のサブスクリプションで、AIクォータ拡大・MIND全機能・広告非表示等を提供
7. **Good Job! 称賛演出**: 禁酒・勉強・語学などその日のタスク完了時にマスコット + 称賛メッセージで動機を維持（iOS/Web）
8. **ヘルプ内PR/FAQ**: 「Fitingoの約束」ブランドメッセージと購入前FAQ 10問をアプリ内から参照可能

---

## プラットフォーム機能対応表

| 機能 | iOS | Watch | Web | 備考 |
|------|-----|-------|-----|------|
| 90秒モード（FIT/DIET/FOOD/EDU） | ✅ | - | ✅ | WebのEDUはMINDへ暫定遷移 |
| モーション自動カウント | ✅ | ✅ | - | 手動記録は全プラットフォーム対応 |
| AIフォトログ（食事） | ✅ | - | - | `aiProxy`経由、APIキー不要 |
| AI語学記録（Duolingoスクショ） | ✅ | - | - | Web未実装 |
| MIND（睡眠・HRVストレス） | ✅ | 一部 | ✅ | Free=概要のみ、Plus=詳細分析 |
| Diet Goal（体重・カロリー計画） | ✅ | - | ✅ | |
| TOMOフィード | ✅ | - | ✅ | |
| 週次AIレポート共有カード | ✅ | - | ✅ | 発行はiOS、閲覧は未ログインWeb |
| 90日再検査チャレンジLP | - | - | ✅ | 未ログイン登録・PV計測 |
| 継続コホート計測（7/30/90日） | ✅ | - | ✅ | Cloud Functionsで集計 |
| アチーブメント | - | - | ✅ | 7種類のバッジ |
| リーダーボード | - | - | ✅ | 週間ランキング |
| Fitingo Plus（課金） | ✅ | - | ✅ | StoreKit 2（iOS）/ Web版はビュー連携 |
| HealthKit連携 | ✅ | ✅ | - | |

---

## 技術スタック

### iOS/Watch
- **言語**: Swift 5.9+
- **フレームワーク**: SwiftUI, HealthKit, WatchConnectivity, Core Motion, StoreKit 2
- **AI/OCR**: Vision, NaturalLanguage, AVSpeechSynthesizer
- **バックエンド**: Firebase Firestore, Cloud Functions（callable）
- **認証**: Firebase Authentication

### Web
- **言語**: TypeScript
- **フレームワーク**: React 18, Vite
- **状態管理**: Zustand
- **スタイル**: Tailwind CSS
- **バックエンド**: Firebase Firestore
- **認証**: Firebase Authentication (Google Sign-In)

### バックエンド（Cloud Functions）
- `aiProxy`: AI代理呼び出し（食事フォトログ・語学記録）。日次・カテゴリ別クォータ管理
- `generateWeeklyReport`: 週次AIコーチングコメント生成
- `computeRetentionStats`: 7/30/90日継続率の集計（毎週スケジュール実行）
- `calculatePoints` / `updateStreaks` / `checkAchievements` / `generateWeeklyLeaderboard`: ポイント・ストリーク・アチーブメント・週間ランキング
- Secret Manager: `OPENAI_API_KEY` を管理（`functions:config`廃止対応済み）

---

## Firestoreデータ構造

```
users/{userId}/
├── profile                          # ユーザープロフィール、totalPoints、streak、isPlus
├── completed-exercises/             # 個別エクササイズ記録
├── completed-sets/                  # セット完了記録
├── ai-usage/{daily-YYYY-MM-DD}      # AIクォータ使用量（カテゴリ別）
├── settings/
│   ├── ai                          # カスタムAPIキー（自己登録時）
│   └── calorie-goal                # カロリー目標設定
└── achievements/                    # 獲得バッジ

shared-reports/{shareId}             # 週次レポート共有カード
challenge_registrations/{docId}      # 90日再検査チャレンジ登録
challenge_analytics/{docId}          # チャレンジPV・登録数
public-stats/{docId}                 # 公開継続率統計
leaderboards/{weekId}/entries/       # 週間ランキング
```

---

## AIクォータ設計（`aiProxy`）

| 利用者 | クォータ | 判定基準 |
|---|---|---|
| 90秒モード中（活動0〜4日） | 全カテゴリ合計 1回/日 | クライアント申告の `activeDays` |
| Free（活動5〜9日） | カテゴリ別 1回/日 | `users/{uid}.isPlus == false` |
| Free（活動10日以降） | AI停止 → Plus誘導 | `AI_FREE_MAX_DAYS = 10` |
| Fitingo Plus | カテゴリ別 3回/日 | `users/{uid}.isPlus == true` |
| カスタムAPIキー登録済み | 無制限（自己負担） | `users/{uid}/settings/ai.openaiApiKey` |

デフォルトモデル: `gpt-5.4-mini`（OpenAI）。

---

## デプロイ状況

### 本番稼働中
- Firebase Hosting（Web） — https://kfitapp.web.app / https://fit.ktrips.net
- Cloud Functions（aiProxy, generateWeeklyReport, computeRetentionStats 等）
- Firestore rules・indexes
- Secret Manager（OPENAI_API_KEY）

### 未実施
- iOS App Store 提出（現在TestFlight配布前段階）
- App Store Connect へのストア文言反映（`docs/appstore_metadata.md` は準備済み）

---

## デプロイ手順

### Web
```bash
cd web
npm run build
firebase deploy --only hosting
```

### Cloud Functions
```bash
firebase functions:secrets:set OPENAI_API_KEY   # 初回のみ
firebase deploy --only functions
```

### iOS
1. Xcodeで `ios/kfit.xcworkspace` を開く
2. Product → Archive
3. Distribute App → App Store Connect / TestFlight

---

## 開発環境

- **Xcode**: 15.0+
- **Node.js**: 18+
- **iOS Deployment Target**: 17.6+
- **watchOS Deployment Target**: 11.6+
- **Web Browsers**: Chrome/Safari/Firefox（最新版）

---

## 今後の拡張候補

戦略的な優先順位は [docs/SamBezThieMuskJobs_plan.md](docs/SamBezThieMuskJobs_plan.md) の「次のアクション」を参照。技術的な残タスクは以下の通り:

1. **AIクォータ残回数の常時表示UI**（現状はエラー時のPlus誘導文言のみ）
2. **Web版EDU語学記録**（現状MINDへの暫定遷移を解消）
3. **iOS/Watchアチーブメント・リーダーボードUI**（現状Web版のみ）
4. **90日再検査チャレンジの同期コホート機能とアプリ接続**
5. **法人プラン**（健康経営・ジム向け一括契約）

---

## 連絡先

プロジェクト管理者: kenichi.yoshida
リポジトリ: https://github.com/ktrips/kfit
