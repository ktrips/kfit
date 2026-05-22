# kfit iOS App (v0.9.23)

A SwiftUI-based iOS fitness app with motion sensor exercise detection, Apple Watch support, Firebase backend integration, and AI-powered nutrition analysis.

## Features

- **Google Authentication** - Sign in with Google
- **Motion Detection (Default)** - Automatic rep counting using Core Motion (50Hz accelerometer/gyroscope)
- **Manual Counter (Optional)** - Fallback manual rep input
- **Apple Watch Support** - Companion watchOS app with motion detection (20Hz) and haptic feedback
- **HealthKit Integration** - Read heart rate, activity, sleep, and PFC nutrition data from Apple Health
- **PFC Balance Analysis** - Score-based protein/fat/carbs balance tracking (0–100 points) with donut chart visualization
- **Sleep Score Analysis** - Multi-factor sleep quality scoring (0–100 points) based on duration, bedtime, and interruptions
- **Daily Global Goals** - Set targets for workout, stand, sleep score, and PFC balance score
- **Photo Log (AI Food Analysis)** - Analyze food photos with OpenAI / Anthropic Claude / Google Gemini 2.5 Flash
- **Diet Goal Tab** - Target weight/body-fat/date, calorie plan, weekly burn/intake trends, and schedule progress
- **MIND Tab** - Current/average heart rate, HRV-based stress score, and personalized recovery suggestions
- **AI Training Plans** - Generate personalized workout plans
- **Weekly Goals** - Set and track weekly exercise targets
- **History View** - Review past 14 days of workouts
- **Form Scoring** - Real-time form quality feedback based on motion patterns
- **Daily Dashboard** - View streaks, XP, sleep score, PFC chart, and 90-day challenge progress
- **Activity Score** - Aggregate Move/Exercise/Stand ring achievement percentage in activity card
- **HRV Stress Estimation** - Piecewise linear stress score (0–100) from average HRV value
- **Grouped Training History** - Exercise history grouped by type; tap group to expand individual sets
- **Time-based Stretch Goal** - Stretch goal measured in minutes (Reflect sessions only); configurable per time slot
- **Five Time Slots** - Midnight, morning, noon, afternoon, and evening goals with custom activities
- **Compact Bottom Menu** - Custom tab bar with FIT / GOAL / MIND / Record / Settings / More
- **Fitingo Adaptive CTA** - Large mascot button changes image, message, and color based on training progress
- **Fitingo Widgets** - Small/medium/large home widgets with progress-based background color and Fitingo mascot
- **Weekly Weight/Fat Trend** - ±X kg/7日 and ±X%/7日 shown below current values in activity card
- **Real-time Sync** - Firebase Firestore syncs with Web and Watch apps
- **Watch Connectivity** - Bidirectional data sync between iPhone and Apple Watch

## Tech Stack

- **SwiftUI** - Modern UI framework
- **Combine** - Reactive programming
- **CoreMotion** - Motion sensor integration (50Hz on iPhone, 20Hz on Watch)
- **WatchConnectivity** - iPhone ↔ Apple Watch bidirectional sync
- **HealthKit** - Heart rate, activity, and sleep data integration
- **Firebase** - Authentication & Firestore database
- **GoogleSignIn** - OAuth authentication

## Requirements

- iOS 15.0+
- watchOS 8.0+ (for Apple Watch app)
- Xcode 14.0+
- CocoaPods (for Firebase dependencies)
- Physical device with accelerometer/gyroscope (motion detection won't work in simulator)

## Setup

### 1. Install Dependencies

```bash
cd ios
pod install
open kfit.xcworkspace
```

### 2. Configure Firebase

1. Download `GoogleService-Info.plist` from Firebase Console (airgo-trip project)
2. Add to Xcode project:
   - Select `kfit.xcodeproj` → `kfit` target
   - Go to `Build Phases` → `Copy Bundle Resources`
   - Add `GoogleService-Info.plist`

### 3. Configure Google Sign-In

1. Go to Firebase Console → Authentication → Google provider
2. Copy the URL Scheme (usually `com.googleusercontent.apps.YOUR_CLIENT_ID`)
3. In Xcode: Project → Targets → kfit → Info
4. Add the URL Scheme under `URL Types`

### 4. Build and Run

```bash
xcodebuild -scheme kfit -configuration Debug build
```

Or open in Xcode and press Cmd+R

## Project Structure

```
ios/
├── kfit/                      # iPhone App
│   ├── kfitApp.swift
│   ├── Managers/
│   │   ├── AuthenticationManager.swift   # Auth + PhotoLogManager (AI食事分析)
│   │   ├── MotionDetectionManager.swift
│   │   ├── HealthKitManager.swift        # PFC/睡眠スコア分析含む
│   │   └── TimeSlotManager.swift         # タイムスロット目標・進捗管理
│   ├── Models/
│   │   ├── IntakeSettings.swift          # PFC目標比率, LLM設定
│   │   └── TimeSlotGoals.swift           # 睡眠/PFC目標・進捗モデル
│   ├── Views/
│   │   ├── LoginView.swift
│   │   ├── DashboardView.swift           # PFC円グラフ, 睡眠スコアカード
│   │   ├── DailyIntakeView.swift         # PFCバランス分析セクション
│   │   ├── GoalView.swift                # Diet Goal / タイムライン / 週間消費・摂取傾向
│   │   ├── MindView.swift                # 心拍・HRV・ストレス分析 / 回復提案
│   │   ├── DietGoalSettingsView.swift    # 体重・体脂肪・カロリー目標設定
│   │   ├── TimeSlotGoalsView.swift       # 睡眠/PFC目標設定UI
│   │   ├── ExerciseTrackerView.swift
│   │   ├── WeeklyGoalView.swift
│   │   ├── HistoryView.swift
│   │   ├── HelpView.swift
│   │   └── WorkoutPlanView.swift
│   └── Info.plist
│
└── kfitWatch/                 # Apple Watch App
    ├── kfitWatchApp.swift
    ├── Managers/
    │   ├── WatchMotionDetectionManager.swift
    │   └── WatchConnectivityManager.swift
    ├── Views/
    │   ├── WatchDashboardView.swift
    │   └── WatchQuickWorkoutView.swift
    └── Info.plist
```

## Core Motion Implementation

### Motion Detection Algorithm

The app detects exercise reps by analyzing accelerometer data:

1. **Calibration** - Establishes baseline acceleration when device is stationary
2. **Peak Detection** - Monitors acceleration spikes above threshold
3. **Rep Counting** - Counts complete cycles (down + up motion)
4. **Form Scoring** - Measures motion consistency (standard deviation)

### Supported Exercises

- **Push-ups** - Vertical acceleration pattern
- **Squats** - Vertical position with gyroscope stability check
- **Sit-ups** - Forward/backward torso motion with rotation tracking

## Firebase Integration

### Firestore Collections

- `users/{userId}/completed-exercises` - Workout logs
- `users/{userId}/daily-goals` - Daily targets
- `exercises` - Global exercise definitions

### Real-time Sync

- Uses `Firestore.firestore().addSnapshotListener()` for real-time updates
- Offline support via Firestore offline persistence
- Automatic conflict resolution (last-write-wins)

## Performance Optimization

- **Accelerometer sampling** - 50 Hz for accurate rep detection
- **Motion filtering** - Baseline subtraction to reduce noise
- **Batch writes** - Groups multiple exercises into single Firestore write
- **Image caching** - Local storage of exercise form images

## Testing

### Unit Tests

```bash
xcodebuild -scheme kfit test
```

### Manual Testing Checklist

- [ ] Google Sign-in works
- [ ] Exercise selection displays all 3 exercises
- [ ] Manual rep counter increments/decrements
- [ ] Motion detection starts/stops properly
- [ ] Form score updates in real-time
- [ ] Workout saves to Firestore
- [ ] Dashboard refreshes after logging workout
- [ ] Sign out clears user data

## Troubleshooting

### Motion Detection Not Working

1. Check that app has motion sensor permissions
2. Verify `CMMotionManager` is available on device
3. Ensure app is running on physical device (simulator has limited motion support)
4. Check that `startDetection()` is called

### Firebase Auth Fails

1. Verify `GoogleService-Info.plist` is included in Xcode project
2. Check URL Scheme is correctly configured
3. Ensure Google OAuth is enabled in Firebase Console
4. Verify test device is added to Firebase auth whitelist

### Form Score Not Updating

1. Check `MotionDetectionManager.formScore` is being updated
2. Verify accelerometer data is being received
3. Ensure motion threshold is appropriate for exercise type

## Recent Updates

### v0.9.23 (2026-05-22)
- ✅ **下部メニュー刷新**: カスタムタブバーで `FIT` / `GOAL` / `MIND` / `記録` / `設定` / `その他` を表示。記録ボタンは中央寄りの白い丸ボタンとして表示
- ✅ **MINDタブ追加**: 現在の心拍数・HRV・ストレス状態、1日の平均心拍・平均HRV・平均ストレスを表示し、深呼吸、Reflect/ストレッチ、散歩、マッサージ、水分補給などを提案
- ✅ **Diet Goalタブ追加**: 目標体重・体脂肪率・目標日・開始値・摂取/消費カロリー目標を設定。スタート/今日/ゴールの体重・体脂肪と差分をタイムライン表示
- ✅ **Fitingoボタン刷新**: 大型カード内にマスコットを大きく表示。開始時/遅れ/達成に応じて画像・メッセージ・背景色が変化
- ✅ **ホームヘッダー更新**: `Fitingo` 横に `M/d(E)` 形式の日付を表示。今日の状況カードはヘッダー非表示で上詰め
- ✅ **時間帯別目標を5区分化**: 夜中(0:00–6:00)を追加し、夜中・朝・昼・午後・夜で管理
- ✅ **食事/水分目標を数値化**: 食事kcal・水分mlで目標と実績を管理し、日次目標を時間帯へ配分
- ✅ **カスタムアクティビティ**: 時間帯ごとに任意の習慣を追加し、目標達成に含められるように更新
- ✅ **Watchダッシュボード拡張**: 摂取記録・メイン・ウェルネス・Health・Watch Face風ページに拡張。Watch Face風ページは日付/連続記録を右上に配置し、タスクアイコンサイズを調整
- ✅ **Widget刷新**: Fitingoマスコット、日付時刻、進捗色連動背景、目標別進捗リストを表示

### v0.9.22 (2026-05-20)
- ✅ **アクティビティスコア**: Move・エクササイズ・スタンド各リングの達成率を平均した総合スコア（0–100%）をアクティビティカードのヘッダーに表示。色分け（緑≥100%、オレンジ≥70%、赤<70%）
- ✅ **HRVストレス推定**: 平均HRVから区分線形でストレススコア（0–100）を算出し、HealthViewのHRVカードにスコア・レベルラベル・プログレスバーで表示
- ✅ **トレーニング履歴グループ表示**: 今日の状況の履歴を種目別にまとめ表示、タップで個別セット（時刻・rep・XP）に展開
- ✅ **ストレッチ目標を時間（分）制に変更**: 従来の回数から分数（デフォルト3分）に変更。Apple Watch の Reflect セッションのみをストレッチとしてカウント
- ✅ **マインドフルネスカウント精密化**: 1分以内（≤1.5分）の Breathe/短時間セッションのみをマインドフルネス回数としてカウント
- ✅ **履歴に体脂肪率表示**: 今日の状況の体重行に体脂肪率（%）を併記
- ✅ **アクティビティカードに週次増減表示**: 体重・体脂肪の7日間増減（±X kg/7日, ±X%/7日）を小さく表示
- ✅ **睡眠カードのレイアウトをコンパクト化**: スコアサークル縮小、ステージバー高さ削減、パディング最適化
- ✅ **Fitingoヘッダーアイコン拡大・カロリー収支削除**: 右側アイコンを20%拡大、カロリー収支の数値表示を削除
- ✅ **ヘルプ・README更新**: 全仕様変更をヘルプビューとREADMEに反映（v0.9.22）

### v0.6.0 (May 2026)
- ✅ **PFCバランス分析**: HealthKitからたんぱく質・脂質・炭水化物を取得しスコア化（0-100点）
- ✅ **睡眠スコア分析**: 睡眠時間・深い睡眠・REM・連続性を総合的にスコア化
- ✅ **PFC・睡眠目標**: タイムスロット目標に睡眠スコア・PFCスコアの目標追加
- ✅ **PFC円グラフ**: ダッシュボードにドーナツ型グラフでPFC比率を可視化
- ✅ **フォトログ改善**: JSON解析ロジック堅牢化（マークダウン・コードブロック除去）
- ✅ **LLMエラーハンドリング強化**: OpenAI/Anthropic/Google全APIのステータスコード+レスポンスログ
- ✅ **Gemini 2.5 Flash対応**: `gemini-2.5-flash` 系に更新
- ✅ **UIリファイン**: マスコット画像表示、カロリー収支カラー（赤字=赤、黒字=黄色）
- ✅ **マインドフルネス**: Apple Watchのマインドフルネスアプリを直接起動

### v0.4.x (以前)
- ✅ Apple Watch companion app with motion detection and haptic feedback
- ✅ HealthKit integration (heart rate, activity, sleep data)
- ✅ AI Training Plan generation
- ✅ Weekly Goals view
- ✅ History view (past 14 days)
- ✅ Help/FAQ view
- ✅ Motion detection as default (manual as optional fallback)
- ✅ Set recording accuracy improvements
- ✅ iOS/Watch data consistency fixes
- ✅ Full-screen support and text contrast improvements
- ✅ Client-side streak and XP calculation

## Future Enhancements

- [ ] App Store submission
- [ ] PFC目標比率のカスタマイズUI
- [ ] 睡眠トレンドグラフ（週次）
- [ ] Advanced form analysis with machine learning
- [ ] Push notifications for workout reminders
- [ ] Social leaderboards and friend challenges
- [ ] Workout video tutorials
- [ ] More exercise types and variations

## Dependencies

Add to Podfile:

```ruby
pod 'Firebase/Core'
pod 'Firebase/Auth'
pod 'Firebase/Firestore'
pod 'GoogleSignIn'
```

## Version

Current version: **0.9.23** (2026-05-22)

## License

MIT
