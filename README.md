# DuoFit - Duolingo スタイルのフィットネス習慣アプリ

毎日の運動をゲームにしよう。プッシュアップ・スクワット・シットアップをモーションセンサーで自動計測。XP・ストリーク・週間目標でフィットネスを習慣化。

🌐 **Web アプリ：** https://kfitapp.web.app  
📦 **GitHub：** https://github.com/ktrips/kfit

---

## 🎯 主な機能

| 機能 | Web | iOS | Apple Watch |
|---|:---:|:---:|:---:|
| Googleログイン | ✅ | ✅ | — |
| 連続ワークアウトフロー（5種目自動進行） | ✅ | ✅ | ✅ |
| モーション自動 rep 検知（デフォルト） | — | ✅ (50Hz) | ✅ (20Hz) |
| 手動カウンター（オプション） | ✅ | ✅ | ✅ |
| リアルタイムフォームスコア | — | ✅ | ✅ |
| HealthKit 連携 | — | ✅ | — |
| AI トレーニングプラン生成 | ✅ | ✅ | — |
| XP・ストリーク表示 | ✅ | ✅ | ✅ |
| 週間目標設定 | ✅ | ✅ | — |
| 90日チャレンジ | ✅ | ✅ | — |
| 履歴（過去14日） | ✅ | ✅ | ✅ (iOS連動) |
| 双方向データ同期 | — | ✅ (送受信) | ✅ (送受信) |
| 触覚フィードバック | — | — | ✅ |
| 全画面最適化 (iPhone 17対応) | — | ✅ | — |
| Firebase リアルタイム同期 | ✅ | ✅ | ✅ |

---

## ⭐ XP（ポイント）システム

| 種目 | XP / rep |
|---|---|
| 🤜 プッシュアップ | 2 XP |
| 🦵 スクワット | 2 XP |
| 🚶 ランジ | 2 XP |
| 🧘 シットアップ | 1 XP |
| 🧱 プランク | 1 XP / 秒 |
| 🔥 バーピー | 5 XP |

---

## 🚀 クイックスタート

### Web アプリをローカルで起動

```bash
cd web
cp .env.example .env   # Firebase 設定を記入
npm install
npm run dev
# → http://localhost:5173/
```

### iOS / Apple Watch アプリを Xcode で起動

```bash
cd ios
pod install
open kfit.xcworkspace
# Xcode でデバイスを選択 → Cmd+R
```

---

## 📋 技術スタック

### Web
- **React 18** + TypeScript + Vite
- **Tailwind CSS**（DuoFit カスタムデザインシステム）
- **Zustand**（状態管理）
- **Firebase** Auth + Firestore

### iOS / Apple Watch
- **SwiftUI** + Combine
- **CoreMotion**（加速度計 + ジャイロスコープ）
- **WatchConnectivity**（Watch ↔ iPhone 双方向同期）
- **HealthKit**（心拍数・アクティビティデータ連携）
- **Firebase** Auth + Firestore

### バックエンド
- **Firebase Authentication**（Google サインイン）
- **Firestore**（リアルタイムデータベース）
- **Firebase Hosting**（Web デプロイ先）
- **Cloud Functions**（ポイント集計・ストリーク管理）

### CI/CD
- **GitHub Actions** — lint・型チェック・ビルド（PR 時）
- **GitHub Actions** → **Firebase Hosting** 自動デプロイ（main push 時）

---

## 🏗️ プロジェクト構成

```
kfit/
├── web/                        # React Web アプリ
│   ├── src/
│   │   ├── components/         # UI コンポーネント
│   │   │   ├── LoginView.tsx
│   │   │   ├── DashboardView.tsx
│   │   │   ├── ExerciseTrackerView.tsx
│   │   │   ├── WeeklyGoalView.tsx
│   │   │   ├── HistoryView.tsx
│   │   │   └── HelpView.tsx
│   │   ├── services/firebase.ts  # Firestore SDK ラッパー
│   │   ├── store/appStore.ts     # Zustand ストア
│   │   └── App.tsx
│   ├── public/mascot.png         # DuoFit マスコット画像
│   ├── .env.example
│   └── package.json
│
├── ios/
│   ├── kfit/                   # iPhone アプリ
│   │   ├── Views/
│   │   │   ├── LoginView.swift        # DuoFit ブランド・マスコット
│   │   │   ├── DashboardView.swift    # XP・90日チャレンジ
│   │   │   └── ExerciseTrackerView.swift  # モーション検知・XP祝福画面
│   │   └── Managers/
│   │       ├── AuthenticationManager.swift
│   │       └── MotionDetectionManager.swift
│   │
│   └── kfitWatch/              # Apple Watch アプリ
│       ├── Views/
│       │   ├── WatchDashboardView.swift    # リアルデータ表示
│       │   └── WatchQuickWorkoutView.swift # XP祝福・触覚フィードバック
│       └── Managers/
│           ├── WatchMotionDetectionManager.swift
│           └── WatchConnectivityManager.swift  # 双方向同期
│
├── firebase/
│   ├── firestore.rules
│   ├── firestore.indexes.json
│   └── functions/index.js
│
├── .github/workflows/
│   ├── ci.yml       # lint・型チェック・ビルド（PR/push）
│   └── deploy.yml   # Firebase Hosting 自動デプロイ（main push）
│
├── .firebaserc      # Firebase プロジェクト: kfitapp
├── firebase.json
└── README.md
```

---

## 🗄️ Firestore データモデル

```
users/{userId}/
├── profile              # username, totalPoints, streak, lastActiveDate
├── completed-exercises/ # exerciseId, reps, points, timestamp, formScore
├── daily-goals/         # date, exerciseId, targetReps, completedReps
├── achievements/        # achievementId, earnedDate
└── statistics/          # 集計データ

exercises/               # 種目定義（全ユーザー共通・認証ユーザーが読み書き可）
leaderboards/{period}/   # 週次ランキング（entries サブコレクション）
```

---

## 🔐 Firestore セキュリティルール

```
exercises        → 認証ユーザーは読み書き可（初回シード用）
leaderboards     → 認証ユーザーは読み書き可
users/{userId}   → 本人のみ読み書き可（サブコレクション含む）
```

---

## 🚢 デプロイ

### Web → Firebase Hosting

```bash
cd web && npm run build
cd ..
firebase use kfitapp
firebase deploy --only hosting
```

または `main` ブランチへ push すると GitHub Actions が自動デプロイします。

### GitHub Secrets（CI/CD に必要）

| Secret 名 | 内容 |
|---|---|
| `VITE_FIREBASE_API_KEY` | Firebase Web API キー |
| `VITE_FIREBASE_AUTH_DOMAIN` | `kfitapp.firebaseapp.com` |
| `VITE_FIREBASE_PROJECT_ID` | `kfitapp` |
| `VITE_FIREBASE_STORAGE_BUCKET` | `kfitapp.firebasestorage.app` |
| `VITE_FIREBASE_MESSAGING_SENDER_ID` | 送信者 ID |
| `VITE_FIREBASE_APP_ID` | アプリ ID |
| `FIREBASE_SERVICE_ACCOUNT_KFITAPP` | サービスアカウント JSON |

---

## 🧪 開発コマンド

```bash
# Web
cd web
npm run dev          # 開発サーバー起動
npm run build        # プロダクションビルド
npm run lint         # ESLint
npm run type-check   # TypeScript 型チェック

# iOS / Watch（Xcode）
xcodebuild -scheme kfit build        # iOS ビルド
xcodebuild -scheme kfitWatch build   # Watch ビルド
```

---

## 📱 iPhone へのインストール方法

1. Xcode で `ios/kfit.xcworkspace` を開く
2. iPhone を USB 接続
3. **Signing & Capabilities** → Team に Apple ID を設定
4. Bundle Identifier を一意な値に変更（例：`com.yourname.duofit`）
5. `GoogleService-Info.plist` を Firebase コンソールからダウンロードして追加
6. **Cmd+R** でビルド＆インストール

---

## 🗺️ 今後の予定

- [ ] App Store 申請
- [ ] プッシュ通知（毎日のリマインダー）
- [ ] フレンド機能・ソーシャルチャレンジ
- [ ] より多くの種目サポート
- [ ] ML ベースのフォーム分析強化
- [ ] カスタムドメイン（fit.ktrips.net）

## 📝 最近の更新

### v0.6.x (2026-05)
- ✅ **連続ワークアウトフロー**: iOS・Watch・Webで5種目を自動進行（手動選択不要）
- ✅ **Apple Watch 過去記録連動**: iOS→Watch双方向同期で履歴表示
- ✅ **iPhone全画面最適化**: iPhone 17対応、ヘッダー/ボタン配置改善
- ✅ **データ同期改善**: ExerciseTrackerView終了時の自動再読み込み

### v0.4.x
- ✅ Apple Watch アプリ対応（モーション検出・触覚フィードバック）
- ✅ HealthKit 統合（心拍数・アクティビティデータ）
- ✅ AI トレーニングプラン生成機能
- ✅ モーション検出をデフォルトに、手動入力はオプション化
- ✅ iOS に週間目標・履歴・ヘルプ画面を追加
- ✅ セット記録精度向上

---

## 📄 ライセンス

MIT License

## 👤 作者

**Ktrips**  
GitHub: [@ktrips](https://github.com/ktrips)

---

*Last Updated: May 2026 — Version 0.6.1*
