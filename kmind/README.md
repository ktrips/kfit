# kmind

MIND 機能に特化したスタンドアロン iOS + Apple Watch アプリ。

kfit アプリの MIND ページをそのまま本体として使います。
**ソースファイルは ios/kfit/ に1つだけ存在し**、kmind.xcodeproj は「参照追加（コピーなし）」で取り込むため、
どちらのプロジェクトで編集しても同じファイルが更新されます。

## ファイル構成

```
kfit/
├── ios/kfit/                         ← 物理ファイルの置き場
│   ├── Views/
│   │   ├── MindView.swift            ← kmind のメイン画面
│   │   ├── MindfulnessSessionView.swift  ← 瞑想・ストレッチセッション（DashboardView から抽出）
│   │   ├── PremiumView.swift         ← Plus アップグレード画面
│   │   └── Components/PremiumBadge.swift  ← PlusFullLockView
│   ├── Managers/
│   │   ├── HealthKitManager.swift    ← 睡眠・HRV・瞑想データ
│   │   ├── TimeSlotManager.swift     ← 時間帯別目標
│   │   ├── PremiumManager.swift      ← Plus/Free 管理
│   │   └── AuthenticationManager.swift
│   ├── Models/
│   │   ├── DailyFixedGoals.swift     ← SettingsView から抽出（新規）
│   │   ├── TimeSlotGoals.swift
│   │   └── IntakeSettings.swift
│   └── Extensions/Color+Duo.swift   ← UIScale・カラー定義
│
├── kfitWatch/                        ← Watch 物理ファイル
│   └── Managers/WatchHealthKitManager.swift  ← kmindWatch も参照
│
└── kmind/                            ← kmind 専用ファイル（ここ）
    ├── kmind/
    │   ├── kmindApp.swift            ← iOS エントリーポイント（MIND + 設定タブ）
    │   └── kmindRootView.swift       ← 旧プレースホルダー（不要になったら削除可）
    └── kmindWatch/
        ├── kmindWatchApp.swift       ← Watch エントリーポイント
        └── WatchMindAppView.swift    ← 睡眠・HRV・瞑想の3ページ Watch UI
```

## Xcode セットアップ手順

### 1. kmind.xcodeproj を新規作成

```
Xcode → File → New → Project → iOS → App
  Product Name: kmind
  Bundle ID:    com.yourname.kmind
  保存先:        /Users/kenichi.yoshida/Git/kfit/kmind/
```

### 2. Watch ターゲットを追加

```
File → New → Target → watchOS → Watch App
  Product Name: kmindWatch
  ペアリング:   kmind（iOS）
```

### 3. 既存ファイルをターゲットに追加（コピーなし）

**iOS ターゲット（kmind）に追加するファイル:**
```
File → Add Files to "kmind" → Copy items if needed: OFF
```

| ファイル | パス |
|---------|------|
| kmindApp.swift | kmind/kmind/kmindApp.swift |
| MindView.swift | ios/kfit/Views/MindView.swift |
| MindfulnessSessionView.swift | ios/kfit/Views/MindfulnessSessionView.swift |
| PremiumBadge.swift | ios/kfit/Views/Components/PremiumBadge.swift |
| PremiumView.swift | ios/kfit/Views/PremiumView.swift |
| HealthKitManager.swift | ios/kfit/Managers/HealthKitManager.swift |
| TimeSlotManager.swift | ios/kfit/Managers/TimeSlotManager.swift |
| PremiumManager.swift | ios/kfit/Managers/PremiumManager.swift |
| AuthenticationManager.swift | ios/kfit/Managers/AuthenticationManager.swift |
| NotificationManager.swift | ios/kfit/Managers/NotificationManager.swift |
| iOSWatchBridge.swift | ios/kfit/Managers/iOSWatchBridge.swift |
| DailyFixedGoals.swift | ios/kfit/Models/DailyFixedGoals.swift |
| TimeSlotGoals.swift | ios/kfit/Models/TimeSlotGoals.swift |
| IntakeSettings.swift | ios/kfit/Models/IntakeSettings.swift |
| DailyIntake.swift | ios/kfit/Models/DailyIntake.swift |
| Color+Duo.swift | ios/kfit/Extensions/Color+Duo.swift |
| GIFAnimationView.swift | ios/kfit/Views/GIFAnimationView.swift |

**Watch ターゲット（kmindWatch）に追加するファイル:**

| ファイル | パス |
|---------|------|
| kmindWatchApp.swift | kmind/kmindWatch/kmindWatchApp.swift |
| WatchMindAppView.swift | kmind/kmindWatch/WatchMindAppView.swift |
| WatchHealthKitManager.swift | ios/kfitWatch/Managers/WatchHealthKitManager.swift |
| WatchConnectivityManager.swift | ios/kfitWatch/Managers/WatchConnectivityManager.swift |

### 4. Firebase を追加

```
File → Add Package Dependencies
  https://github.com/firebase/firebase-ios-sdk
  → FirebaseAuth, FirebaseFirestore を選択
```

GoogleService-Info.plist を kmind ターゲットに追加（kfit と別の Firebase プロジェクトまたは同一）

### 5. HealthKit Capability を追加

```
Signing & Capabilities → + Capability → HealthKit
  （kmind iOS ターゲットと kmindWatch ターゲット両方）
```

## MIND 機能の更新方法

**1か所変更 → kfit・kmind 両方に自動反映**

```
ios/kfit/Views/MindView.swift を編集
  ↓
kfit.xcodeproj でも kmind.xcodeproj でも即座に反映
（同じ物理ファイルを参照しているため）
```

## Bundle ID 一覧

| ターゲット | Bundle ID |
|-----------|-----------|
| kfit | com.yourname.kfit |
| kmind | com.yourname.kmind |
| kfitWatch | com.yourname.kfit.watchkitapp |
| kmindWatch | com.yourname.kmind.watchkitapp |
