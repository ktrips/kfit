# kfit iOS App (v0.6.0)

A SwiftUI-based iOS fitness app with motion sensor exercise detection, Apple Watch support, Firebase backend integration, and AI-powered nutrition analysis.

## Features

- **Google Authentication** - Sign in with Google
- **Motion Detection (Default)** - Automatic rep counting using Core Motion (50Hz accelerometer/gyroscope)
- **Manual Counter (Optional)** - Fallback manual rep input
- **Apple Watch Support** - Companion watchOS app with motion detection (20Hz) and haptic feedback
- **HealthKit Integration** - Read heart rate, activity, sleep, and PFC nutrition data from Apple Health
- **PFC Balance Analysis** - Score-based protein/fat/carbs balance tracking (0–100 points) with donut chart visualization
- **Sleep Score Analysis** - Multi-factor sleep quality scoring (0–100 points) based on duration, deep sleep, and REM
- **Daily Global Goals** - Set targets for workout, stand, sleep score, and PFC balance score
- **Photo Log (AI Food Analysis)** - Analyze food photos with OpenAI / Anthropic Claude / Google Gemini 4 Flash
- **AI Training Plans** - Generate personalized workout plans
- **Weekly Goals** - Set and track weekly exercise targets
- **History View** - Review past 14 days of workouts
- **Form Scoring** - Real-time form quality feedback based on motion patterns
- **Daily Dashboard** - View streaks, XP, sleep score, PFC chart, and 90-day challenge progress
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

### v0.6.0 (May 2026)
- ✅ **PFCバランス分析**: HealthKitからたんぱく質・脂質・炭水化物を取得しスコア化（0-100点）
- ✅ **睡眠スコア分析**: 睡眠時間・深い睡眠・REM・連続性を総合的にスコア化
- ✅ **PFC・睡眠目標**: タイムスロット目標に睡眠スコア・PFCスコアの目標追加
- ✅ **PFC円グラフ**: ダッシュボードにドーナツ型グラフでPFC比率を可視化
- ✅ **フォトログ改善**: JSON解析ロジック堅牢化（マークダウン・コードブロック除去）
- ✅ **LLMエラーハンドリング強化**: OpenAI/Anthropic/Google全APIのステータスコード+レスポンスログ
- ✅ **Gemini 4 Flash対応**: `gemini-4-flash-202603` に更新
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

Current version: **0.6.0** (May 2026)

## License

MIT
