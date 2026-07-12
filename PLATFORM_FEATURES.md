# kfit（Fitingo）プラットフォーム別機能一覧

最終更新: 2026-07-12

対象プラットフォーム: iOS（iPhone）/ Apple Watch / Web

---

## 📱 iOS（iPhone）

### ✅ 実装済み機能

#### 90秒モード（新規ユーザーのデフォルト画面）
- 継続活動日数5日未満のユーザーは起動毎に90秒モードで開始（5日達成後はダッシュボードがデフォルト）
- **FIT / DIET / FOOD / EDU** の4モードを横スワイプで切替
- 各モード共通: 上のコンテンツ窓（GIF/写真/絵文字）・中心の大型ボタン・バッジの3か所どこを押してもアクションが始まる
- 7日進捗ドット、モード別Tips、GIFローテーション（12秒毎）

#### ダッシュボード（ROUTINタブ）
- Mandalaスパイラルチャート: 全目標を渦巻きで可視化、達成ノードは光るリング表示
- 今日の健康データ（歩数・消費カロリー・心拍数・睡眠時間、Apple Health連携）
- 90日チャレンジ: 連続記録（streak）と進捗バー
- カロリー収支カード（体重・体脂肪の最新値も表示）

#### FIT（トレーニング）
- ExerciseTrackerView: 手動記録UI
- Core Motion による自動カウント（腕立て・スクワット・腹筋・ランジ・バーピー・プランク）
- GIFフォームアニメ（スクワット・ランジ等、バックグラウンド事前デコード + キャッシュで高速再生）
- フォームスコア（ジャイロデータから安定性評価）

#### FOOD（食事記録）
- 手入力での食事・水分記録、PFCバランス分析（0〜100点スコア、ドーナツ円グラフ）
- **AIフォトログ**: 写真を撮るだけでカロリー・PFCを自動解析（`aiProxy`経由、APIキー設定不要）
- 直近フォトのスライドショー表示、TOMOフィードへの公開選択

#### GOAL（Diet Goal・体重管理）
- 目標体重・体脂肪率・目標日を設定し、スタート/今日/ゴールをタイムライン表示
- 週間消費/摂取傾向チャート、AIによるカロリー目標逆算
- DIET 90秒モードからの体重記録（手入力/Withings連携/写真）

#### MIND（睡眠・ストレス分析）
- 睡眠スコア分析（睡眠時間50%・就寝時刻30%・睡眠中断20%の3要素、0〜100点）
- HRV・ストレス指数のグラフ表示、深呼吸・ストレッチ・散歩等の回復提案
- **Free/Plus部分開放**: 睡眠スコアはFree、詳細分析（平均値・回復提案）はPlusのぼかしプレビュー+ロック

#### EDU（語学記録）※iOSのみ
- Duolingoのスクリーンショットから、Vision OCR + NaturalLanguageで外国語フレーズを自動抽出
- AI（`aiProxy`経由）による文法解説・例文生成、AVSpeechSynthesizerでの発音再生
- TOMOフィードへの学習記録共有

#### TOMOフィード
- Gmail経由で友達追加、運動・食事・語学の記録を「今日やった」ことだけ共有（詳細な数値は非公開）
- いいね・コメント機能。Freeは友達3人まで、Plusは無制限
- 再生ハート: 友達の投稿（語学音声など）を再生するとハート+1、再生した側にもポイント+10

#### Fitingo Plus（サブスクリプション）
- StoreKit 2実装（`fitingo_plus_monthly` ¥480/月、`fitingo_plus_yearly` ¥3,800/年）
- `PremiumManager`（`isPlus`）の状態変化をFirestore `users/{uid}.isPlus` に自動同期し、サーバー側（aiProxy）のクォータ判定に反映

#### Apple Health連携
- **読み取り**: 歩数、消費カロリー、心拍数、安静時心拍数、睡眠データ、PFC栄養素
- **書き込み**: ワークアウト、消費カロリー、食事のPFC栄養素、体重・水分・カフェイン記録

#### 時間帯別目標・カスタム活動
- 1日を5つの時間帯（夜中/朝/昼/午後/夜）に分けて、トレーニング・食事kcal・水分ml・カスタム活動（禁酒🚫・勉強📖・読書📚など）を設定
- **Good Job! 称賛演出**: 禁酒・勉強・語学などのタスクを完了すると、マスコット + 称賛メッセージのオーバーレイを表示してやる気を維持（成功ハプティクス付き）

#### ヘルプ
- 「📣 Fitingoの約束 — 今度こそ、続く。」（プレスリリース型ブランドメッセージ）と「❓ よくある質問（FAQ）10問」をヘルプ先頭に掲載

#### 通知・設定
- 時間帯別リマインダー（夜中/朝/昼/午後/夜の5区分）
- LLM設定: デフォルトはサーバー経由AI（設定不要）、上級者向けに自分のAPIキー登録も選択可能（折りたたみUI）

### ❌ 未実装機能
- アチーブメント・リーダーボードのiOS UI（現状Web版のみ）
- AIクォータ残回数の常時表示（現状はエラー時のPlus誘導文言のみ）

---

## ⌚ Apple Watch

### ✅ 実装済み機能

#### ワークアウトフロー
- 5種目の連続トレーニング（スクワット・腕立て伏せ・レッグレイズ・プランク・ランジ）
- 目標達成オーバーレイ、セット完了時の合計XP表示

#### モーションセンサー
- 加速度計・ジャイロセンサー（50Hz）によるフォーム自動カウント
- フォームスコア（安定性評価）

#### HealthKit連携
- 歩数・心拍数・消費カロリー・睡眠データの取得
- Watch Face風ページ・ウェルネスページ（睡眠・HRV・ストレッチ情報）

#### iPhone連携
- WatchConnectivityによる双方向同期（デバウンス付き、通信量70%削減）
- iPhone → Watch: 統計データ（streak, todayReps, todayXP）・ワークアウト開始シグナル送信

### ❌ 未実装機能
- 90秒モード（FIT/DIET/FOOD/EDU）
- AIフォトログ・EDU語学記録
- アチーブメント・リーダーボード
- 独立動作（iPhone不要モード）

---

## 🌐 Web

### ✅ 実装済み機能

#### ランディングページ
- 未ログインの最初の画面は「今度こそ、続く。」ブランドLP（継続率の公開統計バッジ付き）

#### 90秒モード
- iOS同様、FIT/DIET/FOOD/EDUの4モードをscroll-snapカルーセルで横スワイプ切替
- ボタン化されたコンテンツ窓・バッジ、モード別メッセージ
- **注意**: EDU（語学記録）はWeb未実装のため、EDUモードのボタンはMINDページへ遷移する暫定動作

#### ダッシュボード
- 今日のセット状況、週間セット目標（進捗バー・達成率・ペース判定）
- 90日チャレンジ表示

#### FOOD / MIND / GOAL
- IntakeView（食事・水分記録）、MindView（HRVストレス分析・回復提案、Plus部分ロック）
- DietGoalView（体重・体脂肪・カロリー計画管理）

#### TOMOフィード
- iOSと同じ「今日やった」だけの共有、いいね・コメント

#### 時間帯別目標・Good Job! 演出
- 時間帯別のカスタム活動（禁酒・勉強・読書など）のチェックオフ
- タスク完了時にマスコット + 称賛メッセージの「Good Job!」オーバーレイを表示

#### ヘルプ
- 「Fitingoの約束」（プレスリリース型メッセージ）とFAQ 10問をヘルプ先頭に掲載（iOSと同内容）

#### アチーブメント・リーダーボード
- 11種類のバッジ表示（獲得済み/未獲得 + 進捗バー）
- 週間ランキング（トップ3表彰台 + 自分の順位ハイライト）

#### 90日再検査チャレンジLP・週次レポート共有カード
- `ChallengeLP`: 未ログインで登録・PV計測可能な健診タイアップLP
- `SharedReportView`: `fit.ktrips.net/r/{shareId}` で未ログイン閲覧可能な週次AIレポートカード

#### その他
- Google認証、リアルタイム同期（Firestoreリスナー）
- キーボードショートカット（トレーニング記録入力）

### ❌ 未実装機能
- モーションセンサーによる自動カウント（手動入力のみ）
- EDU語学記録（Duolingoスクショ解析）— 現状MINDへの暫定遷移
- Apple Watch相当のリアルタイム同期（Web単体では非対応）

---

## 🔄 プラットフォーム間の連携

### 実装済み
- **iOS ↔ Watch**: WatchConnectivityで双方向同期
- **iOS/Web ↔ Firebase**: リアルタイム同期（completed-exercises, completed-sets, users/profile, ai-usage 等）
- **iOS ↔ Cloud Functions**: `aiProxy`（AI代理呼び出し）、`generateWeeklyReport`（週次AIコメント）
- **isPlus同期**: iOSの購入/復元状態をFirestoreへ書き込み、サーバー側AIクォータ判定に反映

### 未実装
- Watch単体での完全動作（iPhone不要）
- Web版のモーション自動検知・EDU語学記録

---

## 📊 データモデル（抜粋）

### Firestore Collections

```
users/{userId}/
├── profile                    # ユーザー情報、totalPoints、streak、isPlus
├── completed-exercises/       # 種目ごとの記録
├── completed-sets/            # セット記録
├── ai-usage/{daily-YYYY-MM-DD}  # AIクォータ使用量（カテゴリ別）
├── settings/
│   ├── ai                    # カスタムAPIキー（自己登録時）
│   └── weekly-goal           # 週間目標設定
└── achievements/

shared-reports/{shareId}       # 週次レポート共有カード
challenge_registrations/{id}   # 90日再検査チャレンジ登録
public-stats/{docId}           # 公開継続率統計（7/30/90日）
leaderboards/{weekId}/entries/
```

### Apple Health連携データ
- **読み取り**: stepCount, activeEnergyBurned, heartRate, restingHeartRate, sleepAnalysis, dietaryProtein/FatTotal/Carbohydrates
- **書き込み**: HKWorkout, activeEnergyBurned, dietary系栄養素

---

## 💡 技術スタック

### iOS
- **言語**: Swift 5.9+
- **UI**: SwiftUI
- **センサー**: Core Motion (CMMotionManager)
- **健康**: HealthKit
- **AI/OCR**: Vision, NaturalLanguage, AVSpeechSynthesizer（EDU用）
- **認証**: Firebase Authentication
- **DB**: Cloud Firestore
- **課金**: StoreKit 2

### Watch
- **言語**: Swift 5.9+
- **UI**: SwiftUI (WatchOS)
- **センサー**: Core Motion
- **連携**: WatchConnectivity

### Web
- **言語**: TypeScript
- **フレームワーク**: React 18 + Vite
- **状態管理**: Zustand
- **UI**: Tailwind CSS
- **認証**: Firebase Authentication
- **DB**: Cloud Firestore

### バックエンド
- Cloud Functions（Node.js 20）: `aiProxy` / `generateWeeklyReport` / `computeRetentionStats` / `calculatePoints` / `updateStreaks` / `checkAchievements` / `generateWeeklyLeaderboard`
- Secret Manager（AI APIキー保管）

---

## 🎯 優先度別 未実装機能

### 高優先度
1. **AIクォータ残回数の常時表示UI**（iOS）
2. **Web版EDU語学記録の実装**（現状MINDへの暫定遷移を解消）
3. **iOS/Watchアチーブメント・リーダーボードUI**（現状Web版のみ）

### 中優先度
4. **90日再検査チャレンジの同期コホート機能とアプリ接続**
5. **Watch版90秒モード**（FIT/DIET/FOOD/EDU）

### 低優先度
6. **法人プラン**（健康経営・ジム向け）
7. **隣接ニッチ拡張**（産後・単身赴任・更年期向けコンテンツ）

---

## 🚀 次のステップ

戦略プランと優先順位の詳細は [docs/SamBezThieMuskJobs_plan.md](docs/SamBezThieMuskJobs_plan.md) を参照。

現在の最優先アクション:
1. 90秒モードをTestFlightで3〜5人に配布し、初回セットまでの時間を検証
2. 90日再検査チャレンジLPをSNSに投稿し、登録率を検証
3. App Store Connectにストア文言を反映
