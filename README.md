# DuoFit - Duolingoスタイルのフィットネス習慣アプリ

毎日の運動をゲーム化。プッシュアップ・スクワット・シットアップをモーションセンサーで自動計測。XP・ストリーク・週間目標でフィットネスを習慣化。

🌐 **Web:** https://kfitapp.web.app  
📱 **iOS + Apple Watch** 対応  
📦 **GitHub:** https://github.com/ktrips/kfit

---

## 🎯 主な機能

| 機能 | Web | iOS | Watch |
|---|:---:|:---:|:---:|
| Googleログイン | ✅ | ✅ | — |
| トレーニング記録（手動） | ✅ | ✅ | ✅ |
| モーション自動検知 | — | ✅ | ✅ |
| GIFフォームアニメ（スクワット/ランジ） | — | ✅ | ✅ |
| カロリー目標トラッキング | ✅ | ✅ | ✅ |
| カロリー目標カスタマイズ | ✅ | ✅ | — |
| HealthKit連携 | — | ✅ | ✅ |
| PFCバランス分析 | — | ✅ | — |
| 睡眠スコア分析 | — | ✅ | — |
| PFC・睡眠目標設定 | — | ✅ | — |
| 食事・水分記録 | ✅ | ✅ | ✅ |
| Diet Goal（体重・体脂肪・カロリー計画） | ✅ | ✅ | — |
| MIND（ストレス分析・回復提案） | ✅ | ✅ | — |
| 時間帯別目標（夜中/朝/昼/午後/夜） | ✅ | ✅ | ✅ |
| Reflect連携ストレッチ目標 | — | ✅ | ✅ |
| 今日のセット表示 | ✅ | ✅ | ✅ |
| 週間セット目標 | ✅ | ✅ | — |
| 90日チャレンジ | ✅ | ✅ | — |
| フォトログ（AI食事分析） | — | ✅ | — |
| アチーブメント | ✅ | — | — |
| リーダーボード | ✅ | — | — |
| キーボードショートカット | ✅ | — | — |
| リアルタイム同期 | ✅ | ✅ | ✅ |

---

## ⚡ パフォーマンス

- **30秒キャッシュ**: Firestoreクエリを最大90%削減
- **IndexedDB永続化**: オフライン対応
- **デバウンス**: Watch通信を70%削減
- **ダッシュボード読み込み**: 0.15s (iOS), 0.2s (Web)

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

## 😴 睡眠スコア分析（iOS）

HealthKitの睡眠データを分析し、睡眠品質を0〜100点でスコア化します。

| 評価項目 | 配点 | 説明 |
|---------|------|------|
| 睡眠時間 | 最大50点 | 実績 ÷ 目標時間（設定値）× 50、上限100% |
| 就寝時刻 | 最大30点 | 24:00以前なら満点。以降10分遅れるごとに−1点 |
| 睡眠中断 | 最大20点 | 覚醒割合0%→20点、20%以上→0点（線形） |

- **評価**: 最高(90+) / 良好(80+) / 普通(70+) / 要改善(50+) / 不十分
- **ビジュアル**: 三分割リング（青: 睡眠時間 / ティール: 就寝時刻 / サーモン: 中断）、中央にスコアをスコア連動色で表示
- **目標設定**: 「睡眠の計測」をONにすると目標スコア（50〜100点）・目標時間を設定可能
- **Firestoreに保存**: `globalProgress.sleepScore` として日々記録（DashboardとTimeSlotManagerで同一数値を共有）
- **データ精度**: Apple Watch のステージデータ（コア/深い/REM）を優先取得し、iPhone の InBed レコードとの二重カウントを自動排除。取得時間帯: 前日15:00〜当日14:00

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
- Tailwind CSS + DuoFit Design System
- Zustand (状態管理)
- Firebase Auth + Firestore

### iOS/Watch
- SwiftUI + Combine
- CoreMotion (50Hz加速度計)
- WatchConnectivity (デバウンス付き)
- HealthKit (歩数・心拍数・平均心拍・HRV・睡眠・PFC栄養素)
- Firebase Auth + Firestore
- LLM統合: OpenAI / Anthropic / Google Gemini 2.5 Flash（フォトログAI分析）

### バックエンド
- Firebase Authentication
- Firestore (Persistent Cache有効)
- Firebase Hosting
- Cloud Functions

---

## 🏗️ プロジェクト構成

```
kfit/
├── web/src/
│   ├── components/
│   │   ├── DashboardView.tsx          # メインダッシュボード
│   │   ├── ExerciseTrackerView.tsx    # 手動入力
│   │   ├── DailyWorkoutFlow.tsx       # 5種目シーケンシャルフロー
│   │   ├── MindView.tsx               # HRVストレス分析・回復提案
│   │   ├── IntakeView.tsx             # 食事・水分記録
│   │   ├── DietGoalView.tsx           # Diet Goal（体重・カロリー計画）
│   │   ├── AchievementsView.tsx       # 11種類のバッジ
│   │   ├── LeaderboardView.tsx        # 週間ランキング
│   │   └── WeeklyGoalView.tsx         # 週間目標設定
│   ├── services/
│   │   ├── firebase.ts                # 30秒キャッシュ付き
│   │   ├── timeSlotService.ts         # 時間帯別目標
│   │   └── wellnessService.ts         # HRV・ストレス計算
│   └── types/
│       ├── timeSlot.ts
│       └── wellness.ts
│
├── ios/kfit/
│   ├── Views/DashboardView.swift      # カロリー目標編集
│   ├── Views/GoalView.swift           # Diet Goalタイムライン
│   ├── Views/MindView.swift           # HRVストレス分析・回復提案
│   ├── Managers/
│   │   ├── AuthenticationManager.swift   # キャッシュ戦略
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
├── SHARED_CONSTANTS.md            # プラットフォーム間共通定数
├── PERFORMANCE_OPTIMIZATIONS.md   # 最適化詳細
├── IMPLEMENTATION_SUMMARY.md      # 実装完了機能一覧
└── XCODE_SETUP.md                # Xcode設定手順
```

---

## 🗄️ Firestore構造

```
users/{userId}/
├── profile                  # totalPoints, streak
├── completed-exercises/     # 個別種目
├── completed-sets/          # セット単位（推奨）
├── weekly-goals/{weekId}    # 週間目標
├── settings/
│   ├── calorie-goal        # カスタム目標
│   ├── weekly-goal         # セット目標
│   └── today-settings/     # タイムスロット目標
│       ├── globalGoals     # workoutEnabled, standEnabled,
│       │                   # sleepEnabled, sleepScoreThreshold,
│       │                   # pfcEnabled, pfcScoreThreshold
│       └── globalProgress  # workoutMinutes, standHours,
│                           # sleepScore, pfcScore
└── achievements/

leaderboards/{weekId}/entries/
```

**最適化**: 
- 複合インデックス: `timestamp + exerciseId`
- キャッシュ優先: `getDocuments(source: .default)`
- バッチ更新: セット完了時に全種目まとめて送信

---

## 🎮 新機能

### a.0.11.4 (2026-05-29)
- ✅ **Mandala スパイラルチャート** (iOS): 全目標を渦巻き曼荼羅で可視化。完了ノードは光るリング表示、未完了はフェード、中央に全体達成率%
- ✅ **Mandala タップ遷移** (iOS): 💪→トレーニング、🧘→1分瞑想、🤸→3分ストレッチ、💧→水200ml記録、🍽️→朝食400kcal記録
- ✅ **Mandala ヘッダー1行化** (iOS): 🌀 Mandala・日付・完了数A/B・⚙️設定アイコンが1行で折り返しなし
- ✅ **Mandala ノード重なり解消** (iOS): 適応アルキメデス螺旋アルゴリズムでノード数にかかわらず全ノード間隔を数学的に保証
- ✅ **HRVグラフ** (iOS): MINDタブで心拍変動のトレンドグラフを表示
- ✅ **呼吸UI強化** (iOS): ガイド付き呼吸セッションにアニメーション視覚フィードバック
- ✅ **ウェルネス機能拡充** (iOS/Watch): 睡眠・HRV・ストレッチの詳細データをWatch・iOSで強化
- ✅ **パフォーマンス最適化** (iOS): ウィジェット更新デバウンス、O(n+m)摂取量同期、マインドフルネスキャッシュ

### v0.10.5 (2026-05-23)
- ✅ **GIFフォームアニメ**: スクワット・ランジ実施中に正しいフォームのGIFアニメを表示（iOS・Watch）
- ✅ **GoalView 大幅拡張**: 週間消費/摂取傾向チャート・週間カロリー収支グラフ追加。AIによるカロリー目標逆算（目標体重・期間・体脂肪率から最適摂取kcalを計算）
- ✅ **DietGoalSettings**: 目標体重・体脂肪率・日付・摂取/消費カロリー目標をまとめて編集する専用設定画面を追加（iOS）
- ✅ **MindView iOS強化**: 現在/平均の心拍・HRV・ストレス指数に加え、具体的な回復提案をタップ遷移付きで表示
- ✅ **Web — MIND・食事・Diet Goal**: HRVストレス分析・回復提案（MindView）、食事/水分記録（IntakeView）、Diet Goal管理（DietGoalView）を Web に追加
- ✅ **Watch ダッシュボード拡張**: ウェルネスページに睡眠・HRV・ストレッチ情報を追加。Watch Face風ページのレイアウト改善

### v0.9.23 (2026-05-22)
- ✅ **Fitingoホーム刷新**: ヘッダーに `M/d(E)` 形式の日付を表示し、今日の状況カードはヘッダー非表示で上詰め表示
- ✅ **Fitingoボタン強化**: 大型カード内にマスコットを大きく表示。進捗に応じて通常/JDI/炎マスコットとメッセージ、背景色（グリーン〜シアン → 黄 → オレンジ → 赤）が変化
- ✅ **下部メニュー刷新**: 標準TabViewからコンパクトなカスタムタブバーへ変更し、`FIT` / `GOAL` / `MIND` / `記録` / `設定` / `その他` を表示
- ✅ **MINDタブ追加**: 現在/平均の心拍数・HRV・ストレス指数を表示し、深呼吸、Reflect/ストレッチ、散歩、マッサージ、水分補給などの具体的な回復提案を表示
- ✅ **Diet Goalタブ追加**: 目標体重・目標体脂肪率・目標日・開始値・摂取/消費カロリー目標を設定し、スタート/今日/ゴールの体重・体脂肪・差分をタイムラインで表示
- ✅ **時間帯別目標の拡張**: 夜中(0–6時)を追加し、夜中/朝/昼/午後/夜の5区分で管理
- ✅ **食事/水分目標を数値化**: 食事はkcal、水分はmlの目標として管理し、1日目標を時間帯へ配分
- ✅ **Reflectストレッチ目標**: Apple WatchのReflectセッションを分数でカウントし、ストレッチ目標に反映
- ✅ **カスタムアクティビティ**: 時間帯ごとに任意の習慣（読書、Duolingo、勉強など）を追加・達成管理
- ✅ **Watchページ拡張**: 摂取記録/メイン/ウェルネス/Health/Watch Face風ページの5ページ構成に更新。Watch Face風ページは日付・連続記録を右上に表示し、タスクアイコンを見やすく調整
- ✅ **Widget刷新**: Fitingoアイコン、日付時刻、進捗色連動背景、目標別進捗リストを表示

### v0.9.21 (2026-05-19)
- ✅ **睡眠スコア計算式刷新**: 睡眠時間50% + 就寝時刻30% + 睡眠中断20%の3要素に変更
  - 就寝時刻: 24:00以前満点、以降10分毎に−1点
  - カードと今日の状況で同じスコアを表示（`targetHours`を統一）
- ✅ **睡眠カード: 三分割リング表示**: 青(時間)/ティール(就寝)/サーモン(中断)の弧が各コンポーネントの達成度を表示
  - 評価テキスト・中央スコアをスコア連動色（緑/紫/オレンジ/赤）で表示
  - 内訳に目標値カッコ付き（例: `5.2h/7h`, `23:45`, `12分`）
- ✅ **アクティビティリングカード**: 睡眠カード直下に移動（ページ上部へ）
- ✅ **Widget改善**: 横長・大画面にFitingoアイコン(26pt)＋日付時刻（`M/d (EEE) H:mm`）を1行表示
  - 指標HStackを下方向にオフセット、アイコン・フォントを拡大

### v0.9.20 (2026-05-18)
- ✅ **Fitingo ボタン表情切り替え**: 目標遅れ時は炎マスコット (`fitingo_fire`)、通常時は通常マスコット (`fitingo_button_mascot`)
- ✅ **カロリー収支カード**: 体重・体脂肪（Apple Health最新値）をバーカード内に表示
- ✅ **睡眠スコア精度向上**: Apple Watch のステージデータ優先取得 + iPhone InBed レコード自動除外による二重カウント解消; 取得時間帯を前日15:00〜当日12:00に修正
- ✅ **ヘッダー達成度%統一**: タイトル行の達成度バッジを `completionPercentage`（目標数ベース）に統一

### v0.6.0 (2026-05-15)
- ✅ **PFCバランス分析** (iOS): HealthKitからたんぱく質・脂質・炭水化物を取得しスコア化
- ✅ **睡眠スコア分析** (iOS): 睡眠品質を0-100点でスコア化、ダッシュボードに表示
- ✅ **PFC・睡眠目標設定**: 1日全体の目標にPFCスコア・睡眠スコアの目標を追加
- ✅ **PFC円グラフ** (iOS): ダッシュボードにドーナツ型グラフでPFC比率を可視化
- ✅ **フォトログ改善**: JSON解析の堅牢化（マークダウン除去）、全LLMのエラーハンドリング強化
- ✅ **Gemini 2.5 Flash対応**: Google AIモデルを `gemini-2.5-flash` 系に更新
- ✅ **UIリファイン**: マスコット画像表示、カロリー収支カラー改善（赤字=赤、黒字=黄色）
- ✅ **フォトログボタン移動**: ダッシュボードのクイックメニューに統合
- ✅ **マインドフルネス**: Apple Watchのマインドフルネスアプリを直接起動

### v0.5.0 (2026-05-10)
- ✅ **パフォーマンス最適化**: 読み込み時間87%改善
- ✅ **アチーブメントシステム** (Web): 11種類のバッジ
- ✅ **リーダーボード** (Web): 週間ランキング
- ✅ **カロリー目標カスタマイズ** (iOS/Web)
- ✅ **Watch HealthKit統合**: 歩数・心拍数・睡眠
- ✅ **キャッシュ戦略**: 30秒TTL + 永続化
- ✅ **共通定数統一**: SHARED_CONSTANTS.md

### v0.4.x
- ✅ Apple Watch完全対応
- ✅ HealthKit統合 (iOS)
- ✅ セット単位記録
- ✅ 週間目標・90日チャレンジ
- ✅ リアルタイム同期

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

---

## 🚢 デプロイ

### Web → Firebase Hosting
```bash
cd web && npm run build
firebase deploy --only hosting
```

GitHub Actions自動デプロイ: `main`ブランチpush時

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

### 短期
- [ ] Image lazy loading
- [ ] Service Worker
- [ ] 履歴ページネーション
- [ ] PFC目標比率のカスタマイズUI

### 中期
- [ ] iOS/WatchアチーブメントUI
- [ ] プッシュ通知
- [ ] Cloud Functions最適化
- [ ] 睡眠トレンドグラフ（週次）

### 長期
- [ ] フレンド機能
- [ ] カスタムドメイン
- [ ] App Store申請

---

## 📄 ライセンス

MIT License

## 👤 作者

**Ktrips**  
GitHub: [@ktrips](https://github.com/ktrips)

---

*Version a.0.11.4 — Updated: May 29, 2026*
