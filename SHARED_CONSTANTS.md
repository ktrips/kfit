# 共通定数定義

## カロリー消費率（kcal/rep）

| Exercise ID | kcal/rep | 実装場所 |
|-------------|----------|----------|
| pushup, push-up | 0.5 | iOS: HealthKitManager.swift, Web: firebase.ts, Watch: 同期 |
| squat | 0.6 | 同上 |
| situp, sit-up | 0.3 | 同上 |
| lunge | 0.5 | 同上 |
| burpee | 1.0 | 同上 |
| plank | 0.1 | 同上 |
| default | 0.4 | 同上 |

## ポイント計算（XP/rep）

| Exercise ID | basePoints | 実装場所 |
|-------------|------------|----------|
| pushup, push-up | 2 | iOS: Firestore, Web: firebase.ts |
| squat | 2 | 同上 |
| situp, sit-up | 1 | 同上 |
| lunge | 2 | 同上 |
| burpee | 5 | 同上 |
| plank | 1 | 同上 |

## デフォルト目標

| 設定項目 | デフォルト値 | 説明 |
|---------|------------|------|
| 目標カロリー | 500 kcal | 週間目標から計算、なければ500 |
| 1日の目標セット数 | 2 セット | ユーザーカスタマイズ可能 |
| 週間目標 | 5日間 | 月〜金（平日） |
| 90日チャレンジ | 90日連続 | 固定 |

## Firestore コレクション構造

```
users/{userId}/
├── profile                          # 1ドキュメント（頻繁に更新）
├── completed-exercises/{docId}      # 個別記録（1種目 = 1ドキュメント）
├── completed-sets/{docId}           # セット記録（推奨：複数種目を1ドキュメントにまとめる）
├── weekly-goals/{weekId}            # 週間目標（weekId = Monday's date）
├── settings/
│   ├── calorie-goal                # カロリー目標設定
│   └── weekly-goal                 # 週間設定
└── achievements/{achievementId}     # 獲得バッジ

leaderboards/{weekId}/
└── entries/{userId}                 # 週間ランキング
```

## Watch Connectivity ペイロード

### iOS → Watch (stats更新)
```json
{
  "streak": Int,
  "todayReps": Int,
  "todayXP": Int,
  "calorieTarget": Int,
  "calorieConsumed": Int,
  "caloriePercent": Int,
  "todayExercises": Data // JSON encoded array
}
```

### Watch → iOS (workout記録)
```json
{
  "workout": Data,           // 個別種目
  "completed_set": Data,     // セット完了（推奨）
  "workout_recorded": true
}
```

### iOS → Watch (自動起動シグナル)
```json
{
  "action": "start_workout",
  "ts": TimeInterval
}
```

## パフォーマンス最適化指針

### 1. データ取得の効率化
- ✅ 必要最小限のフィールドのみ取得
- ✅ 複合インデックスの活用
- ✅ ページネーション（履歴表示など）
- ✅ キャッシュの活用

### 2. リアルタイム同期の最適化
- ✅ バッチ更新（複数種目を1つのsetとして送信）
- ✅ デバウンス（頻繁な更新を抑制）
- ✅ 差分更新のみ送信

### 3. Watch Connectivity最適化
- ✅ reachableの場合のみsendMessage使用
- ✅ 非reachableの場合はupdateApplicationContext
- ✅ ペイロードサイズの最小化（JSON圧縮）

### 4. ローカルキャッシュ戦略
- iOS: UserDefaults（軽量データ）、Core Data（オフライン対応）
- Web: IndexedDB（大量データ）、LocalStorage（設定）
- Watch: UserDefaults（最小限）

### 5. クエリ最適化
- ✅ whereField + orderBy の複合インデックス
- ✅ limit()で取得件数を制限
- ✅ startAfter()でページネーション

## Firestore 複合インデックス（必要）

```
Collection: users/{userId}/completed-exercises
Fields: timestamp (Ascending), exerciseId (Ascending)

Collection: users/{userId}/completed-sets
Fields: timestamp (Descending)

Collection: leaderboards/{weekId}/entries
Fields: rank (Ascending)
```

## メモリ使用量の目安

| プラットフォーム | 目安 | 対策 |
|----------------|------|------|
| iOS | ~50MB | 画像キャッシュの制限、古いデータの削除 |
| Watch | ~20MB | 必要最小限のデータのみ保持 |
| Web | ~30MB | ServiceWorkerでキャッシュ管理 |

## 同期タイミング

| イベント | iOS | Watch | Web |
|---------|-----|-------|-----|
| アプリ起動 | Firestore読み込み | iOS問い合わせ | Firestore読み込み |
| 運動記録 | 即座にFirestore書き込み | iOS経由で書き込み | 即座にFirestore書き込み |
| stats更新 | リアルタイムリスナー | iOS push | リアルタイムリスナー |

## コード重複削減

### カロリー計算ロジック
- iOS: `HealthKitManager.caloriesPerRep`
- Web: `firebase.ts/CALORIES_PER_REP`
- → 両者で同じ値を使用（このドキュメントで管理）

### 週間目標の週ID計算
- iOS: `getCurrentWeekId()` in AuthenticationManager
- Web: `getCurrentWeekId()` in firebase.ts
- → 同じロジック（月曜日の日付をISO8601形式）

### 種目絵文字マッピング
- iOS: DashboardView, Watch: WatchDashboardView
- Web: DashboardView.tsx, ExerciseTrackerView.tsx
- → 統一されたマッピング（このドキュメントで管理）

## 絵文字マッピング

| Exercise ID | Emoji |
|-------------|-------|
| pushup, push-up | 💪 |
| squat | 🏋️ |
| situp, sit-up | 🔥 |
| lunge | 🦵 |
| burpee | ⚡ |
| plank | 🧘 |
| default | 🏃 |
