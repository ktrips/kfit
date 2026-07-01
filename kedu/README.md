# kedu

kfit の **TOMO ページ**を独立した iOS アプリとして提供するプロジェクト。

## 概要

- **TOMOフィード**: kfit でアップロードされた写真・投稿をそのまま閲覧・交流できる
- **同じ Firebase**: kfit と同一の Firestore データを参照（投稿・写真・ユーザー情報を共有）
- **同じソースコード**: kfit の各ファイルをそのまま参照（コードの重複なし）
- **Apple Health 連携**: kfit と同じ HealthKit データソース

## 参照している kfit ファイル（27ファイル）

| カテゴリ | ファイル |
|---------|---------|
| Extensions | Color+Duo.swift, DebugLog.swift, UIImage+PhotoEnhance.swift |
| Models | IntakeSettings.swift, DailyIntake.swift, DailyFixedGoals.swift, TimeSlotGoals.swift, HabitStack.swift, DietGoalSettings.swift |
| Managers | AuthenticationManager.swift, PremiumManager.swift, HealthKitManager.swift, TimeSlotManager.swift, DuolingoTextExtractor.swift, HabitStackManager.swift, NotificationManager.swift, PendingShareProcessor.swift |
| Views | TomoView.swift, FoodView.swift, GoalView.swift, GIFAnimationView.swift, LoginView.swift, MindfulnessSessionView.swift, StandPomodoroView.swift |
| Components | SharedAppComponents.swift, PremiumBadge.swift, PremiumView.swift |

## セットアップ手順

### 1. Xcode でプロジェクトを開く
```
open /Users/kenichi.yoshida/Git/kfit/kedu/kedu.xcodeproj
```

### 2. Swift Package 依存関係を解決（Xcode が自動実行）
- Firebase iOS SDK (FirebaseAuth, FirebaseFirestore)
- GoogleSignIn-iOS

### 3. Signing & Capabilities
- Team: N5H836M425（自動署名）
- Bundle ID: `com.ktrips.kedu`
- HealthKit capability を追加（Xcode > Target > Signing & Capabilities）

### 4. GoogleService-Info.plist
- kfit のものをコピー済み（同じ Firebase プロジェクトを使用）
- 別の Firebase プロジェクトを使う場合は差し替えてください

### 5. ビルド & 実行
- Xcode で **kedu** スキームを選択
- Cmd+R でシミュレーターまたは実機で起動

## アーキテクチャ

```
kedu (独立 iOS アプリ)
├── keduApp.swift           ← エントリポイント（Firebase 初期化・認証）
├── kedu/Info.plist         ← HealthKit・カメラ・Google URL scheme 記述
├── kedu/kedu.entitlements  ← HealthKit entitlement
├── GoogleService-Info.plist← Firebase 設定（kfit と同じ）
└── [kfit ソース参照]
    ├── TomoView.swift      ← メインビュー
    ├── FoodView.swift      ← 食事写真詳細
    ├── GoalView.swift      ← FIT写真詳細
    └── ...全マネージャー・モデル
```

## データ共有の仕組み

kfit と kedu は同じ Firebase プロジェクトの Firestore にアクセスするため：
- kfit で投稿した写真は kedu の TOMO フィードにも表示される
- kedu でいいね・コメントした内容は kfit 側にも反映される
- ユーザー認証（Google Sign-In）は共通
