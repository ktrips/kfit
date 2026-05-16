# kfit プラットフォーム別機能一覧

最終更新: 2026-05-09

## 📱 iOS (iPhone)

### ✅ 実装済み機能

#### ダッシュボード
- **今日のセット状況**: 午前/午後セット数、達成状態表示
- **週間目標カード**: 週間セット進捗（完了数/目標数）、達成率、ペース判定
- **今日の記録**: セット単位で折りたたみ表示、各種目の回数・XP表示
- **今日の健康データ (Apple Health連携)**:
  - 歩数（todaySteps）
  - 消費カロリー（todayCalories）
  - 心拍数（latestHeartRate）
  - 睡眠時間（lastNightTotalHours）
  - 2x2グリッド表示
- **習慣スタック**: 設定した習慣の一覧表示
- **90日チャレンジ**: 連続記録（streak）と進捗バー
- **クイックメニュー**: 各機能へのショートカット

#### トレーニング記録
- **ExerciseTrackerView**: 手動記録UI
- **モーションセンサー**: Core Motion による自動カウント（腕立て、スクワット、腹筋）
- **リアルタイムフィードバック**: カウント表示、フォームスコア
- **複数種目対応**: Push-up, Squat, Sit-up, Lunge, Burpee, Plank
- **XP計算**: 種目別ポイント、フォームボーナス、ストリークボーナス

#### Apple Health連携
- **読み取り**:
  - 歩数（HKQuantityType.stepCount）
  - 消費カロリー（HKQuantityType.activeEnergyBurned）
  - 心拍数（HKQuantityType.heartRate）
  - 安静時心拍数（HKQuantityType.restingHeartRate）
  - 睡眠データ（HKCategoryType.sleepAnalysis）
- **書き込み**:
  - ワークアウト（HKWorkout）
  - 消費カロリー（activeEnergyBurned）
  - 種目ごとの記録保存

#### 履歴
- **HistoryView**: 過去14日分の記録
- **日別表示**: 各日のセット一覧
- **セット別表示**: 午前/午後、時刻、種目詳細、回数、XP

#### その他
- **週間目標設定**: WeeklyGoalView（種目別の週間目標）
- **通知管理**: 1日2回のリマインダー（午前10時、午後7時）
- **ストリーク管理**: 連続記録の自動計算（3日猶予）
- **Google認証**: Firebase Authentication

### ❌ 未実装機能
- 目標カロリー設定・達成度表示
- リーダーボード
- アチーブメント表示
- プッシュ通知（バッジのみ）
- ソーシャル機能（友達追加、共有）

---

## ⌚ Apple Watch

### ✅ 実装済み機能

#### ワークアウトフロー
- **WatchWorkoutFlowView**: 5種目の連続トレーニング
  - スクワット（20回）
  - 腕立て伏せ（15回）
  - レッグレイズ（15回）
  - プランク（45秒）
  - ランジ（20回）
- **目標達成オーバーレイ**: "Good job! 🎯" 表示（2.5秒）
- **XP表示**: セット完了時の合計XP

#### モーションセンサー
- **WatchMotionDetectionManager**: 
  - 加速度センサー（50Hz）
  - ジャイロセンサー（50Hz）
  - フレーム間変化検出（閾値: 0.03G）
  - 最小rep間隔: 0.15秒
  - リアルタイム加速度表示
- **自動カウント**: Push-up, Squat, Sit-up, Lunge, Burpee
- **手動カウント**: プランク、または手動モード切替時
- **フォームスコア**: ジャイロデータから安定性評価

#### iPhone連携
- **WatchConnectivityManager**:
  - 種目ごとのデータ送信（即時）
  - セット完了データ送信（まとめて）
  - iPhone→Watch: 統計データ同期（streak, todayReps, todayXP）
  - リアルタイム同期

#### その他
- **今日の統計表示**: 連続記録、今日のrep数、今日のXP
- **最近のワークアウト履歴**: 直近3件の種目表示

### ❌ 未実装機能
- Apple Health連携（歩数・カロリー・心拍数の表示）
- 週間目標表示
- 習慣スタック
- 詳細履歴
- 目標カロリー表示・達成度
- 独立動作（iPhone不要モード）

---

## 🌐 Web

### ✅ 実装済み機能

#### 週間目標ビュー (WeeklyGoalView)
- **週間セット進捗**:
  - 完了セット数 / 週間目標
  - 達成率（%）
  - ペース判定（今日まで目標との比較）
  - プログレスバー（緑/黄色）
- **1日のセット数設定**: ±ボタンで調整、週間目標の自動計算
- **今週のセット一覧**:
  - 日付区切り表示
  - 時刻、種目サマリー、合計rep・XP
  - 展開して各種目の詳細表示
  - 今日のセットはハイライト表示

#### その他
- **Google認証**: Firebase Authentication
- **リアルタイム同期**: Firestoreリスナー

### ❌ 未実装機能
- ダッシュボード（今日のセット状況、今日の記録）
- トレーニング記録UI（現在はiOS/Watchからのみ）
- 90日チャレンジ表示
- 習慣スタック
- 履歴表示（セット一覧以外）
- Apple Health相当のデータ表示（歩数・カロリー・心拍・睡眠）
- 目標カロリー設定・達成度
- 手動でのトレーニング記録入力
- アチーブメント
- リーダーボード
- プッシュ通知

---

## 🔄 プラットフォーム間の連携

### 実装済み
- **iOS ↔ Watch**: WatchConnectivityで双方向同期
  - Watch → iOS: ワークアウトデータ送信
  - iOS → Watch: 統計データ送信、ワークアウト開始シグナル
- **iOS ↔ Firebase**: リアルタイム同期
  - completed-exercises: 種目ごとの記録
  - completed-sets: セット単位の記録
  - users/profile: ユーザー情報、streak、totalPoints
  - weekly-goals: 週間目標設定
- **Web ↔ Firebase**: リアルタイム同期（同上）

### 未実装
- Watch単体での完全動作（iPhone不要）
- Webからのトレーニング記録投稿

---

## 📊 データモデル

### Firestore Collections

```
users/{userId}/
├── profile                    # ユーザー情報、totalPoints、streak、lastActiveDate
├── completed-exercises/       # 種目ごとの記録（timestamp, reps, points, exerciseId, formScore）
├── completed-sets/            # セット記録（timestamp, exercises[], totalXP, totalReps, source）
├── settings/weekly-goal       # 週間目標設定（dailySets）
├── weekly-goals/{weekId}      # 旧：種目別週間目標（非推奨）
└── habits/                    # 習慣スタック
```

### Apple Health連携データ
- **読み取り**: stepCount, activeEnergyBurned, heartRate, restingHeartRate, sleepAnalysis
- **書き込み**: HKWorkout, activeEnergyBurned

---

## 🎯 優先度別 未実装機能

### 高優先度（ユーザー要望）
1. **目標カロリー機能** (全プラットフォーム)
   - 1日の目標カロリー設定
   - 消費カロリー表示
   - 達成度（%）表示
   
2. **Watchに健康データ表示**
   - 歩数、カロリー、心拍数
   - Apple Health連携

3. **Web版ダッシュボード**
   - 今日のセット状況
   - 今日の記録
   - 90日チャレンジ
   - 健康データ（手動入力 or Apple Health API連携）

### 中優先度
4. **Webからのトレーニング記録**
   - 手動入力UI
   - 種目選択、回数入力
   
5. **アチーブメント機能**
   - バッジ表示
   - 達成条件管理

6. **リーダーボード**
   - 週間/月間ランキング
   - 友達との比較

### 低優先度
7. **ソーシャル機能**
   - 友達追加
   - 共有機能
   
8. **詳細分析**
   - グラフ表示
   - 傾向分析

---

## 💡 技術スタック

### iOS
- **言語**: Swift 5.9+
- **UI**: SwiftUI
- **センサー**: Core Motion (CMMotionManager, CMPedometer)
- **健康**: HealthKit
- **認証**: Firebase Authentication
- **DB**: Cloud Firestore
- **通知**: UserNotifications

### Watch
- **言語**: Swift 5.9+
- **UI**: SwiftUI (WatchOS)
- **センサー**: Core Motion
- **連携**: WatchConnectivity
- **HealthKit**: 未導入（権限のみ追加済み）

### Web
- **言語**: TypeScript
- **フレームワーク**: React 18 + Vite
- **状態管理**: Zustand
- **UI**: Tailwind CSS
- **認証**: Firebase Authentication
- **DB**: Cloud Firestore

---

## 🚀 次のステップ候補

### オプション1: 目標カロリー機能（推奨）
1. Firestoreに目標値保存（users/{userId}/settings/daily-goal）
2. iOS: 目標カロリー設定UI追加、達成度表示
3. Watch: 目標カロリー表示（コンパクト表示）
4. Web: 設定UI + 達成度表示

### オプション2: Watch健康データ表示
1. WatchOS用HealthKitManager作成
2. 権限リクエストフロー追加
3. 歩数・カロリー・心拍数表示（WatchHomeView）
4. リアルタイム更新

### オプション3: Web版ダッシュボード完全実装
1. DashboardView作成（iOSと同等）
2. 今日の記録、セット状況表示
3. 90日チャレンジ
4. 健康データ（手動入力UI）
5. トレーニング記録入力UI

どのオプションから進めますか？
