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
| カロリー目標トラッキング | ✅ | ✅ | ✅ |
| カロリー目標カスタマイズ | ✅ | ✅ | — |
| HealthKit連携 | — | ✅ | ✅ |
| 今日のセット表示 | ✅ | ✅ | ✅ |
| 週間セット目標 | ✅ | ✅ | — |
| 90日チャレンジ | ✅ | ✅ | — |
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
- HealthKit (歩数・心拍数・睡眠)
- Firebase Auth + Firestore

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
│   │   ├── AchievementsView.tsx       # 11種類のバッジ
│   │   ├── LeaderboardView.tsx        # 週間ランキング
│   │   └── WeeklyGoalView.tsx         # 週間目標設定
│   └── services/firebase.ts           # 30秒キャッシュ付き
│
├── ios/kfit/
│   ├── Views/DashboardView.swift      # カロリー目標編集
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
│   └── weekly-goal         # セット目標
└── achievements/

leaderboards/{weekId}/entries/
```

**最適化**: 
- 複合インデックス: `timestamp + exerciseId`
- キャッシュ優先: `getDocuments(source: .default)`
- バッチ更新: セット完了時に全種目まとめて送信

---

## 🎮 新機能

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

### 中期
- [ ] iOS/WatchアチーブメントUI
- [ ] プッシュ通知
- [ ] Cloud Functions最適化

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

*Version 0.5.0 — Updated: May 10, 2026*
