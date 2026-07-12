# kfit（Fitingo）- 今度こそ、続く。記録ゼロ秒の90秒習慣化アプリ

ジムも、記録アプリも、3日で終わった。それは意志が弱いからではなく、記録が面倒だったから。
腕立て・スクワット・食事・語学・体重——数えるのも記録するのも、iPhoneとApple Watchが自動でやります。
あなたがすることは、最初は1日90秒だけ。

🌐 **Web:** https://kfitapp.web.app （https://fit.ktrips.net）
📱 **iOS + Apple Watch** 対応（マスコット/ブランド名: Fitingo）
📦 **GitHub:** https://github.com/ktrips/kfit

---

## 🎯 90秒モード（新規ユーザーのデフォルト画面）

継続活動日数が5日に達するまで、5タブ構成を見せず「今日の90秒」だけに絞った1画面で起動します。
FIT → DIET → FOOD → EDU の4モードを横スワイプで切り替え、各画面は次の3か所どこを押してもアクションが始まります。

| モード | やること | メッセージ |
|---|---|---|
| **FIT** | 90秒の自重トレーニング（モーション自動カウント） | [FIT 90秒] を押して始める、それだけ |
| **DIET** | 体重・体脂肪の記録（手入力/Withings連携/写真） | [DIET 90秒] を押して計測する、それだけ |
| **FOOD** | 食事写真をAIが自動解析（カロリー・PFC） | [FOOD 90秒] を押して撮る、それだけ |
| **EDU** | Duolingoのスクリーンショットから語学記録（iOSのみ） | [EDU 90秒] を押して記録する、それだけ |

5日連続で活動すると全機能（ROUTIN/FIT/MIND/FOOD/GOAL/TOMOタブ）が解放されます。

---

## 🎯 主な機能

| 機能 | Web | iOS | Watch |
|---|:---:|:---:|:---:|
| Googleログイン | ✅ | ✅ | — |
| 90秒モード（FIT/DIET/FOOD/EDU即実行ハブ） | ✅ | ✅ | — |
| トレーニング記録（手動） | ✅ | ✅ | ✅ |
| モーション自動検知 | — | ✅ | ✅ |
| GIFフォームアニメ（スクワット/ランジ等） | ✅ | ✅ | ✅ |
| カロリー目標トラッキング・カスタマイズ | ✅ | ✅ | ✅ |
| HealthKit連携 | — | ✅ | ✅ |
| PFCバランス分析・目標設定 | — | ✅ | — |
| 睡眠スコア分析 | — | ✅ | — |
| 食事・水分記録（手入力） | ✅ | ✅ | ✅ |
| **AIフォトログ**（撮るだけでカロリー・PFC自動解析） | — | ✅ | — |
| **AI語学記録**（Duolingoスクショ→例文・発音生成） | — | ✅ | — |
| Diet Goal / GOALタブ（体重・体脂肪・カロリー計画） | ✅ | ✅ | — |
| MIND（睡眠・HRVストレス分析、Freeは概要のみ・詳細はPlus） | ✅ | ✅ | — |
| **TOMOフィード**（「今日やった」だけを友達と共有） | ✅ | ✅ | — |
| 時間帯別目標（夜中/朝/昼/午後/夜） | ✅ | ✅ | ✅ |
| 90日チャレンジ（連続記録） | ✅ | ✅ | — |
| **90日再検査チャレンジLP**（未ログイン登録・健診タイアップ） | ✅ | — | — |
| **週次AIレポート共有カード**（URL付きWeb閲覧・未ログイン可） | ✅ | ✅ | — |
| 継続コホート計測（7/30/90日継続率） | ✅ | ✅ | — |
| アチーブメント | ✅ | — | — |
| リーダーボード | ✅ | — | — |
| **Fitingo Plus**（サブスクリプション） | ✅ | ✅ | — |
| キーボードショートカット | ✅ | — | — |
| リアルタイム同期 | ✅ | ✅ | ✅ |

---

## 🤖 AI機能（サーバー代理・APIキー不要がデフォルト）

Cloud Functions（`aiProxy`）がサーバー側キーで代理呼び出しするため、ユーザーは**APIキー設定なしで登録直後からAI機能が使えます**。
上級者は設定画面から自分のAPIキー（OpenAI/Anthropic/Google Gemini）を登録すれば無制限に利用可能です。

| 利用者 | クォータ | 備考 |
|---|---|---|
| 90秒モード中（活動0〜4日） | 全カテゴリ合計 **1回/日** | 「撮るだけで記録」を必ず体験させる |
| Free（活動5〜9日） | カテゴリ別 **1回/日** | 食事AI・語学AI それぞれ1回 |
| Free（活動10日以降） | **AI停止 → Plus誘導** | 継続実績を評価しつつアップグレードを提案 |
| Fitingo Plus | カテゴリ別 **3回/日** | 広告なし・全機能フルアクセス込み |
| 自分のAPIキー登録済み | 無制限（自己負担） | Free/Plus問わず常に無制限 |

デフォルトモデル: OpenAI `gpt-5.4-mini` / Anthropic `claude-haiku-4-5` / Google `gemini-3.1-flash-lite`（すべて現行世代の低価格モデル）。

---

## ⚡ パフォーマンス

- **30秒キャッシュ**: Firestoreクエリを最大90%削減
- **IndexedDB永続化**: オフライン対応
- **デバウンス**: Watch通信を70%削減
- **GIF描画**: バックグラウンド事前デコード + NSCacheでカクつき解消（90秒モード）

詳細: [PERFORMANCE_OPTIMIZATIONS.md](PERFORMANCE_OPTIMIZATIONS.md)

---

## 🔥 カロリートラッキング

| Exercise | kcal/rep | XP/rep |
|----------|----------|---------|
| Push-up | 0.5 | 2 |
| Squat | 0.6 | 2 |
| Sit-up | 0.3 | 1 |
| Lunge | 0.5 | 2 |
| Burpee | 1.0 | 5 |
| Plank | 0.1 | 1 |

**デフォルト目標**: 500 kcal/日（週間目標から自動計算）

---

## 🥗 PFCバランス分析（iOS）

HealthKitに記録された食事データからPFC（たんぱく質・脂質・炭水化物）を取得し、バランスをスコア化します。

| 栄養素 | 目標比率 | HealthKit識別子 |
|--------|---------|----------------|
| たんぱく質 | 15% | `.dietaryProtein` |
| 脂質 | 25% | `.dietaryFatTotal` |
| 炭水化物 | 60% | `.dietaryCarbohydrates` |

- **スコア範囲**: 0〜100点
- **評価**: 理想的 / 良好 / まずまず / 要改善 / バランス悪い
- **可視化**: ダッシュボードにドーナツ型PFC円グラフを表示
- **目標設定**: 「食事の計測」をONにすると目標スコア（50〜100点）を設定可能
- **IntakeSettings**でターゲット比率をカスタマイズ可能（`targetProteinPercent` / `targetFatPercent` / `targetCarbsPercent`）

---

## 😴 睡眠スコア分析（iOS・MINDタブ）

HealthKitの睡眠データを分析し、睡眠品質を0〜100点でスコア化します。Freeユーザーはスコア表示まで、詳細な平均値・回復提案はFitingo Plus限定です。

| 評価項目 | 配点 | 説明 |
|---------|------|------|
| 睡眠時間 | 最大50点 | 実績 ÷ 目標時間（設定値）× 50、上限100% |
| 就寝時刻 | 最大30点 | 24:00以前なら満点。以降10分遅れるごとに−1点 |
| 睡眠中断 | 最大20点 | 覚醒割合0%→20点、20%以上→0点（線形） |

- **評価**: 最高(90+) / 良好(80+) / 普通(70+) / 要改善(50+) / 不十分
- **ビジュアル**: 三分割リング（青: 睡眠時間 / ティール: 就寝時刻 / サーモン: 中断）、中央にスコアをスコア連動色で表示
- **データ精度**: Apple Watch のステージデータ（コア/深い/REM）を優先取得し、iPhone の InBed レコードとの二重カウントを自動排除

---

## 👥 TOMOフィード

共有されるのは「今日やった」という事実だけ。体重・食事の中身は共有されません。友達をGmailで追加し、いいね・コメントで励まし合います。Freeは友達3人まで、Plusは無制限。

## 💰 Fitingo Plus

| プラン | 月額 | 年額 |
|---|---|---|
| Free | 無料 | 無料 |
| **Fitingo Plus** | ¥480/月（7日間無料） | ¥3,800/年（14日間無料・約34%オフ） |

Plusで解放: AIクォータ3倍化+10日以降も継続利用、MIND全機能、FOOD/FIT写真フィード記録、TOMO友達無制限、BOOKS全文閲覧、Watchアプリ・ウィジェット、広告非表示。
詳細: [docs/monetization_plan.md](docs/monetization_plan.md)

---

## 🚀 クイックスタート

### Web
```bash
cd web
npm install
npm run dev  # http://localhost:5173
```

### iOS/Watch
```bash
cd ios
pod install
open kfit.xcworkspace
# Cmd+R
```

**重要**: `WatchHealthKitManager.swift`をXcodeで手動追加
```bash
./ADD_WATCH_HEALTHKIT.sh  # ヘルパースクリプト
```

詳細: [XCODE_SETUP.md](XCODE_SETUP.md)

---

## 📋 技術スタック

### Web
- React 18 + TypeScript + Vite
- Tailwind CSS + Fitingo Design System
- Zustand (状態管理)
- Firebase Auth + Firestore

### iOS/Watch
- SwiftUI + Combine
- CoreMotion (50Hz加速度計)
- WatchConnectivity (デバウンス付き)
- HealthKit (歩数・心拍数・平均心拍・HRV・睡眠・PFC栄養素)
- Vision + NaturalLanguage（Duolingoスクリーンショット OCR・言語検出）+ AVSpeechSynthesizer（発音再生）
- Firebase Auth + Firestore

### バックエンド
- Firebase Authentication
- Firestore (Persistent Cache有効)
- Firebase Hosting
- Cloud Functions（`aiProxy` / `generateWeeklyReport` / `computeRetentionStats` 等）
- Secret Manager（AI APIキー保管、`functions:config` は廃止対応済み）

---

## 🏗️ プロジェクト構成

```
kfit/
├── web/src/
│   ├── components/
│   │   ├── DashboardView.tsx          # メインダッシュボード
│   │   ├── NinetySecondMode.tsx       # 90秒モード（FIT/DIET/FOOD/EDU）
│   │   ├── ExerciseTrackerView.tsx    # 手動入力
│   │   ├── DailyWorkoutFlow.tsx       # 5種目シーケンシャルフロー
│   │   ├── MindView.tsx               # HRVストレス分析・回復提案（Plus部分ロック）
│   │   ├── IntakeView.tsx             # 食事・水分記録
│   │   ├── DietGoalView.tsx           # Diet Goal（体重・カロリー計画）
│   │   ├── SharedReportView.tsx       # 週次レポート共有カード（未ログイン閲覧）
│   │   ├── AchievementsView.tsx       # バッジ
│   │   ├── LeaderboardView.tsx        # 週間ランキング
│   │   └── challenge/ChallengeLP.tsx  # 90日再検査チャレンジLP
│   └── services/
│       ├── firebase.ts                # 30秒キャッシュ付き
│       ├── timeSlotService.ts         # 時間帯別目標
│       └── retentionService.ts        # 継続コホート計測
│
├── ios/kfit/
│   ├── kfitApp.swift                  # アプリ起点 + 90秒モードハブ
│   ├── Views/DashboardView.swift      # カロリー目標編集
│   ├── Views/MindView.swift           # HRVストレス分析・回復提案（Plus部分ロック）
│   ├── Views/WeeklyReportView.swift   # 週次AIレポート・共有カード発行
│   ├── Managers/
│   │   ├── AuthenticationManager.swift   # キャッシュ戦略 + AIProxyClient
│   │   ├── PremiumManager.swift          # Fitingo Plus + isPlus Firestore同期
│   │   ├── AIQuotaManager.swift          # AIクォータUI用マネージャ
│   │   ├── RetentionTracker.swift        # 継続コホート計測
│   │   ├── DuolingoTextExtractor.swift   # OCR・語学AI生成・TTS
│   │   ├── HealthKitManager.swift        # カロリー計算
│   │   └── iOSWatchBridge.swift          # デバウンス付き同期
│   └── kfit.entitlements
│
├── ios/kfitWatch/
│   ├── Views/WatchDashboardView.swift    # 健康データ表示
│   ├── Managers/
│   │   ├── WatchHealthKitManager.swift   # HealthKit統合
│   │   └── WatchConnectivityManager.swift
│   └── kfitWatch.entitlements
│
├── firebase/functions/index.js    # aiProxy / generateWeeklyReport / computeRetentionStats 等
├── SHARED_CONSTANTS.md            # プラットフォーム間共通定数
├── PERFORMANCE_OPTIMIZATIONS.md   # 最適化詳細
├── PLATFORM_FEATURES.md           # プラットフォーム別機能一覧
├── IMPLEMENTATION_SUMMARY.md      # 実装状況サマリー
└── XCODE_SETUP.md                # Xcode設定手順
```

---

## 🗄️ Firestore構造

```
users/{userId}/
├── profile                  # totalPoints, streak, isPlus
├── completed-exercises/     # 個別種目
├── completed-sets/          # セット単位（推奨）
├── weekly-goals/{weekId}    # 週間目標
├── ai-usage/{daily-YYYY-MM-DD}  # AIクォータ使用量（カテゴリ別）
├── settings/
│   ├── ai                  # カスタムAPIキー（自己登録時）
│   ├── calorie-goal        # カスタム目標
│   ├── weekly-goal         # セット目標
│   └── today-settings/     # タイムスロット目標
│       ├── globalGoals     # workoutEnabled, standEnabled,
│       │                   # sleepEnabled, sleepScoreThreshold,
│       │                   # pfcEnabled, pfcScoreThreshold
│       └── globalProgress  # workoutMinutes, standHours,
│                           # sleepScore, pfcScore
└── achievements/

shared-reports/{shareId}       # 週次レポート共有カード（未ログイン閲覧可）
challenge_registrations/{id}   # 90日再検査チャレンジ登録（未ログイン可）
challenge_analytics/{docId}    # チャレンジPV・登録数
public-stats/{docId}           # 公開継続率統計（7/30/90日）
leaderboards/{weekId}/entries/
```

**最適化**:
- 複合インデックス: `timestamp + exerciseId`
- キャッシュ優先: `getDocuments(source: .default)`
- バッチ更新: セット完了時に全種目まとめて送信

---

## 🎮 最近の主なアップデート

### 2026-07（a.1.7.x系）
- ✅ **Good Job! 称賛演出**: 禁酒・勉強・語学などその日のタスクを完了すると、マスコットと称賛メッセージのオーバーレイでやる気を維持（iOS/Web）
- ✅ **ヘルプに「Fitingoの約束」とFAQ**: プレスリリース型のブランドメッセージと購入前FAQ 10問をiOS/Webのヘルプ先頭に掲載
- ✅ **TOMOフィード再生ハート**: 友達の投稿を再生するとハート+1、再生した側にもポイント+10（a.1.7.10）
- ✅ **「今度こそ、続く」ランディングページ**: Web の最初の画面をブランドLPに刷新（a.1.7.1）
- ✅ **90秒モードのボタン化**: 上のコンテンツ窓・中心ボタン・バッジの3か所どこを押しても開始。モード別メッセージ（始める/計測する/撮る/記録する）に統一、FIT→DIET→FOOD→EDU順
- ✅ **GIF描画の高速化**: バックグラウンド事前デコード + NSCacheキャッシュで、90秒モードのGIFがサクサク・高画質に
- ✅ **AI APIキー廃止（サーバー代理）**: `aiProxy` Cloud Functionが代理呼び出し。登録直後からAPIキー設定なしでAI機能が使える。日次・カテゴリ別クォータ + 10日以降はPlus誘導
- ✅ **Secret Manager移行**: `functions:config`（2027年3月廃止予定）から脱却、`OPENAI_API_KEY`をSecret Managerで管理
- ✅ **週次AIレポート共有カード**: `fit.ktrips.net/r/{id}` で未ログインでも閲覧可能なURL付き共有
- ✅ **継続コホート計測**: 7/30/90日継続率をCloud Functionsで集計、LPに公開統計を表示
- ✅ **90日再検査チャレンジLP**: 健康診断で「要改善」だった人向けの未ログイン登録・PV計測
- ✅ **MINDタブ部分開放**: 睡眠スコアはFree、詳細分析（HRV・回復提案）はPlus限定のぼかしプレビュー+ロック
- ✅ **フォトログ二重登録バグ修正**: 新規アップロード時にHealthKitへカロリー等が2回登録される不具合を修正

### a.0.11.4 (2026-05-29)
- ✅ **Mandala スパイラルチャート** (iOS): 全目標を渦巻き曼荼羅で可視化。完了ノードは光るリング表示、未完了はフェード、中央に全体達成率%
- ✅ **HRVグラフ** (iOS): MINDタブで心拍変動のトレンドグラフを表示
- ✅ **呼吸UI強化** (iOS): ガイド付き呼吸セッションにアニメーション視覚フィードバック

### v0.10.5 (2026-05-23)
- ✅ **GIFフォームアニメ**: スクワット・ランジ実施中に正しいフォームのGIFアニメを表示（iOS・Watch）
- ✅ **GoalView 大幅拡張**: 週間消費/摂取傾向チャート・AIによるカロリー目標逆算
- ✅ **Web — MIND・食事・Diet Goal**: HRVストレス分析・回復提案、食事/水分記録、Diet Goal管理をWebに追加

### v0.9.23 (2026-05-22)
- ✅ **下部メニュー刷新**: カスタムタブバーへ変更し `ROUTIN` / `FIT` / `MIND` / `FOOD` / `GOAL` / `TOMO` を表示
- ✅ **MINDタブ追加**: HRV・ストレス指数と回復提案を表示
- ✅ **Diet Goalタブ追加**: 目標体重・体脂肪率・カロリー計画をタイムラインで表示

### v0.6.0 (2026-05-15)
- ✅ **PFCバランス分析・睡眠スコア分析** (iOS): HealthKitから自動スコア化
- ✅ **フォトログ改善**: JSON解析の堅牢化、全LLMのエラーハンドリング強化

### v0.5.0 以前
- ✅ アチーブメント・リーダーボード（Web）、Apple Watch完全対応、HealthKit統合、週間目標・90日チャレンジ、リアルタイム同期

---

## 🔐 環境変数

### Web (.env)
```bash
VITE_FIREBASE_API_KEY=
VITE_FIREBASE_AUTH_DOMAIN=kfitapp.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=kfitapp
VITE_FIREBASE_STORAGE_BUCKET=
VITE_FIREBASE_MESSAGING_SENDER_ID=
VITE_FIREBASE_APP_ID=
```

### iOS
`GoogleService-Info.plist` をFirebaseコンソールからダウンロード

### Firebase Functions Secrets
```bash
firebase functions:secrets:set OPENAI_API_KEY
```

---

## 🚢 デプロイ

### Web → Firebase Hosting
```bash
cd web && npm run build
firebase deploy --only hosting
```

### Cloud Functions
```bash
firebase deploy --only functions
```

### iOS TestFlight
```bash
# Xcode: Product → Archive
# Distribute App → App Store Connect
```

---

## 🧪 開発

```bash
# Web
npm run dev          # 開発サーバー
npm run build        # ビルド
npm run type-check   # TypeScript
npm run lint         # ESLint

# iOS
./ADD_WATCH_HEALTHKIT.sh  # Watch設定
```

---

## 📊 パフォーマンス指標

| 指標 | 最適化前 | 最適化後 | 改善率 |
|------|---------|---------|-------|
| iOS初回読み込み | 1.2s | 0.8s | 33% |
| iOSキャッシュ | 0.8s | 0.15s | 81% |
| Web初回読み込み | 1.5s | 1.0s | 33% |
| Webキャッシュ | 1.0s | 0.2s | 80% |
| Firestoreクエリ | 8回 | 3回 | 63% |
| Watch通信 | 100% | 30% | 70%削減 |

---

## 🗺️ ロードマップ

戦略プランの詳細: [docs/SamBezThieMuskJobs_plan.md](docs/SamBezThieMuskJobs_plan.md)

### 短期（次のアクション）
- [ ] 90秒モードをTestFlightで3〜5人に配布し、初回セットまでの時間を検証
- [ ] 90日再検査チャレンジLPをSNSに投稿し、登録率を検証
- [ ] App Store Connectにストア文言を反映
- [ ] AIクォータ残回数の常時表示UI

### 中期
- [ ] 90日再検査チャレンジの同期コホート機能とアプリ接続
- [ ] 健診ニッチ向けコンテンツ量産（書籍パイプライン汎用化）
- [ ] iOS/Watchアチーブメント・リーダーボードUI

### 長期
- [ ] 隣接ニッチ拡張（産後・単身赴任・更年期）
- [ ] 法人プラン（健康経営・ジム向け）

---

## 📄 ライセンス

MIT License

## 👤 作者

**Ktrips**
GitHub: [@ktrips](https://github.com/ktrips)

---

*Updated: 2026-07-11*
