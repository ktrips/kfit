# Cursor + ClaudeでiPhoneアプリ・Apple Watchフィットネスアプリを週末だけで作る方法

**Cursor と Claude で SwiftUI・Apple Health・モーションセンサー を動かす個人アプリ開発完全ガイド**

著者：吉田 顕一（Ken Yoshida）


---

> **本書について**
>
> 「週末だけでiOS・Apple Watchアプリを作りたい」——そんな個人開発者のために書いた実践書です。
>
> CursorというAI統合IDEを開発の中心に置き、Claude Sonnet/Opusを活用しながら、SwiftUI・Apple Health（HealthKit）・モーションセンサー（Core Motion）・Apple Watch連携を実装します。Xcodeはビルド・署名・実機デプロイ専用のツールとして使います。
>
> 題材はフィットネス習慣化アプリ「Fitingo」。マンダラ目標表示・AI食事分析・HRVストレス分析・ポモドーロタイマーなど、盛りだくさんの機能を**Claudeとペアプロしながら**一人で完成させる全工程を収録しています。

<div style="page-break-after: always;"></div>

## 免責事項・著作権表示

**本書に関する免責事項（Disclaimer）**

本書（以下「本書」）は、個人開発プロジェクト「kfit」（サンプルアプリ）の開発過程を題材にした技術解説書であり、情報提供のみを目的として作成されています。著者・吉田顕一は、以下の事項について一切の責任を負いません。

**サンプルアプリについて**

- 本書で紹介する「kfit」および「Fitingo」（以下「サンプルアプリ」）は、著者が個人的に開発・公開しているサンプルアプリです。
- サンプルアプリの動作・機能・品質について、いかなる保証も行いません。
- サンプルアプリの使用により生じた損害（直接的・間接的・偶発的損害を含む）について、著者は一切の責任を負いません。
- 本書のソースコード・プロンプト例は教育目的のサンプルであり、本番環境への適用による損害についても同様に責任を負いません。

**第三者のサービス・製品について**

本書では以下のサービス・製品・ブランドを参照・言及していますが、著者はこれらの企業・団体とは一切関係がなく、公式に承認・推奨・提携しているものではありません。各サービスの利用は、それぞれの利用規約・ライセンスに従ってください。

| 名称 | 権利者 |
|------|--------|
| Cursor | Anysphere, Inc. |
| Claude / Claude Opus / Claude Sonnet | Anthropic, PBC |
| GitHub / GitHub Copilot | GitHub, Inc. (Microsoft Corporation) |
| Duolingo | Duolingo, Inc. |
| Swift / SwiftUI / Xcode / HealthKit / Core Motion | Apple Inc. |
| Firebase / Firestore | Google LLC |
| iPhone / Apple Watch / macOS | Apple Inc. |

本書に登場する各社のロゴ・商標・スクリーンショット・製品名は、それぞれの権利者に帰属します。これらの使用は、説明・解説目的の引用の範囲内であり、権利者の承認を意味するものではありません。また、著者は各サービスの利用方法・コスト・機能変更・利用規約変更によって生じるいかなる損害についても責任を負いません。

**情報の正確性について**

本書の内容は執筆時点（2026年）の情報に基づいており、各サービスの仕様・価格・機能は予告なく変更される場合があります。最新情報は各サービスの公式ドキュメントを参照してください。

---

*Copyright © 2026 Ken Yoshida（吉田顕一）. All rights reserved.*
*本書の無断転載・複製・配布を禁じます。*

<div style="page-break-after: always;"></div>

## 目次

- [はじめに](#はじめに)
- [第一章: AI時代のアプリ開発](#第一章-ai時代のアプリ開発)
- [第二章: アプリの全体像](#第二章-アプリの全体像)
- [第三章: 開発のための環境準備](#第三章-開発のための環境準備)
- [コラム1: LLM比較、どれが最もコスパがいい？](#コラム1-llm比較どれが最もコスパがいい)
- [第四章: Webアプリ開発](#第四章-webアプリ開発)
- [コラム2: iPhoneからClaude CodeとGitHubで開発を続ける](#コラム2-iphoneからclaude-codeとgithubで開発を続ける)
- [第五章: iOSアプリ開発](#第五章-iosアプリ開発)
- [第六章: Apple Watchアプリ開発](#第六章-apple-watchアプリ開発)
- [第七章: テスト、デバッグ、リリース](#第七章-テストデバッグリリース)
- [第八章: まとめと開発ポイント](#第八章-まとめと開発ポイント)
- [終わりに](#終わりに)

<div style="page-break-after: always;"></div>

## はじめに

個人でアプリを作るハードルは、以前より大きく下がりました。理由の一つは、CursorのようなAI統合IDEと、Claude Sonnet/Opusのような高性能LLMを組み合わせて使えるようになったことです。

本書では、Cursorを開発の中心に置きます。ファイル操作、コード編集、検索、ターミナル、Git連携、差分確認、複数LLMの切り替えをCursor上で行い、Claude Sonnet/OpusをCursorから呼び出して設計相談、実装、レビュー、ドキュメント作成を進めます。

Xcodeは、iOS/Watchアプリの開発で欠かせないツールですが、本書では「コードを書く中心」ではなく「Appleプラットフォームへビルド・署名・デプロイするための環境」として扱います。SwiftUIコードの編集や調査はCursorで行い、実機起動、Capabilities設定、Signing、Archive、App Store提出準備はXcodeで行うという役割分担です。

題材にするのは、フィットネス習慣化アプリ「Fitingo」です。サンプルアプリは、Web、iOS、Apple Watchに対応し、運動記録、Apple Health連携、モーションセンサーによるレップ計測、HRVストレス分析、食事・水分管理、Watchの渦巻き目標表示、Firebase同期などを含みます。

### 本書で学べること

- CursorをIDEとして使う開発スタイル
- Cursorでのファイル操作、検索、ターミナル、Git連携
- GitHubとの連携、Issue、Pull Request、レビューの流れ
- `CLAUDE.md` と `rules.md` によるAI開発ルールの整備
- CursorからClaude Sonnet/Opusを使い分ける考え方
- XcodeをiOS/Watchデプロイ環境として使う方法
- iPhoneとApple Watchへの実機デプロイ手順
- React + TypeScriptによるWebアプリ開発
- SwiftUIによるiOSアプリ開発
- Apple Health、HealthKit、Core Motionの使い方
- Apple WatchアプリとWatchConnectivity
- テスト、デバッグ、リリース前チェック

<div style="page-break-after: always;"></div>

## 第一章: AI時代のアプリ開発

<div style="page-break-after: always;"></div>

### 1-1. AI時代の開発は何が変わったのか

以前の個人開発では、分からないことがあるたびに検索し、ドキュメントを読み、サンプルコードを探し、自分のプロジェクトに合わせて書き換える必要がありました。今も基礎理解は重要ですが、CursorとClaude Sonnet/Opusを組み合わせると、調査と実装の速度が大きく変わります。

たとえば、「iOSのMINDページに過去7日のHRV平均グラフを表示したい」と考えたとします。従来なら、HealthKitのHRV取得方法、SwiftUIのグラフ描画、既存画面の構成、データ更新タイミングをそれぞれ調べる必要があります。Cursorでプロジェクトを開き、Claude Sonnetに関連ファイルを調査させれば、既存コードを前提にした実装方針を短時間で得られます。

> **⚠️ AIは万能ではありません**
>
> アプリの方向性、ユーザー体験、健康データの扱い、ストア審査に関わる表現などは、人間が判断する必要があります。AI時代の開発では、**人間がプロダクトの意思決定を行い、AIが実装と調査を支援する**役割分担が重要です。

<div style="page-break-after: always;"></div>

### 1-2. Cursorを開発環境の中心にする

Cursorは、AI機能を備えたIDEです。Visual Studio Codeに近い操作感で、プロジェクトフォルダを開き、ファイルを編集し、検索し、ターミナルを使い、Git差分を確認しながら、AIに相談できます。

**本書でCursorを使う用途：**

- プロジェクト全体を開く
- ファイルを検索する
- Swift、TypeScript、Markdownを編集する
- ターミナルでnpmやgitコマンドを実行する
- Git差分を確認する
- Claude Sonnet/Opusなど複数LLMを切り替えて使う
- AIに実装、レビュー、説明、ドキュメント作成を依頼する

Cursorの強みは、プロジェクト全体を見ながらAIと会話できることです。サンプルアプリのように、Web、iOS、Watchが同じリポジトリにある場合、横断的な調査に向いています。

**Cursorでよく使うプロンプト例：**

[プロンプト例]: ファイルの役割と主要パターンを初心者向けに説明させる
```text
このファイルの役割を初心者向けに説明してください。
特に、@StateObject、@Published、Task、async/awaitがどう使われているか知りたいです。
```

[プロンプト例]: Webで複数プラットフォームへの影響範囲を調査させる
```text
この機能はWeb、iOS、Watchに影響しそうです。
関連ファイルを調査し、どこを変更すべきか整理してください。
まだコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 1-3. Claude Sonnet/OpusをCursorから使う

本書では、Claudeを主にCursorから呼び出して使います。つまり、ターミナルで独立したClaude Codeを使うことを前提にするのではなく、Cursorのチャットやエージェント機能からClaude Sonnet/Opusを選び、開いているリポジトリの文脈を渡して作業します。

| モデル | 使いどころ |
|---|---|
| **Sonnet** | 日常的な実装、調査、軽いリファクタリング、エラー修正 |
| **Opus** | 大きな設計判断、複雑なバグ調査、アーキテクチャ整理、長文ドキュメント作成 |

たとえば、単純なUI文言変更やTypeScriptエラー修正はSonnetで十分です。一方、iOSとWatchの同期ずれ、HealthKitとUserDefaultsとWatchConnectivityをまたぐ問題などは、Opusに調査と設計を頼むと安定します。

[プロンプト例]: 軽微なUI修正をSonnet（標準モデル）に限定して依頼する
```text
この変更は小さなUI修正なので、Sonnetで実装してください。
既存のデザインに合わせ、不要なリファクタリングは避けてください。
```

[プロンプト例]: 複数プラットフォームをまたぐ問題をOpus（高性能モデル）で調査させる
```text
この問題はiOS、Watch、HealthKit、WatchConnectivityをまたぎます。
Opusで関連ファイルを広く調査し、原因候補と修正方針を出してください。
まだコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 1-4. Claude Codeについての位置づけ

Claude Codeは、ターミナルからClaudeを使ってリポジトリ内作業を進めるエージェント型ツールです。便利な選択肢ですが、本書の基本方針では、主な開発体験はCursor内に集約します。

Claude Codeを使う場面は、たとえば次のような場合です。

- Cursor外のターミナル中心で作業したい
- CIやスクリプトと近い形で調査したい
- 長い自動修正や一括作業をCLIで行いたい

ただし、初心者にはまずCursor上で、ファイル、差分、チャット、ターミナルを一つの画面で見ながら進める方法をおすすめします。Git差分を目で確認しやすく、AIが何を変更したか追いやすいためです。

<div style="page-break-after: always;"></div>

### 1-5. 良いプロンプトの基本形

AIに依頼するときは、次の要素を入れると失敗が減ります。

| 要素 | 内容 |
|---|---|
| 対象画面・ファイル | どの画面、どのファイルか |
| 実現したい体験 | ユーザーがどう操作するか |
| データの取得元 | HealthKit、Firestore、UserDefaults など |
| 保存先 | どこに保存するか |
| やってほしくないこと | UIを崩さない、他の機能を壊さないなど |
| 確認してほしいこと | lintエラー確認、型チェックなど |

**良い例：**

[プロンプト例]: 具体的で的確な実装依頼の良い例
```text
iOSのMINDページで、今日のまとめの3分ストレッチの下に、過去7日のHRV平均グラフを表示してください。
20msの赤い基準線を入れてください。
HealthKitManagerに7日平均を取得する処理を追加し、MindViewで表示してください。
既存のSwiftUIデザインに合わせ、不要なリファクタリングは避けてください。
```

**作業前の制約プロンプト：**

[プロンプト例]: 作業前に既存変更を守るための制約指示
```text
既存のユーザー変更を戻さないでください。
関連ファイルを読んでから実装してください。
不要なリファクタリングは避けてください。
変更後に関連ファイルのlinter/診断を確認してください。
実装内容と未確認事項を最後に短く報告してください。
```

<div style="page-break-after: always;"></div>

### 1-6. GitHubとAI開発の関係

CursorとClaudeを使った開発では、GitHubは単なるコード置き場ではありません。作業履歴、Issue、Pull Request、レビュー、CI結果、リリース管理をまとめる中心になります。AIに実装を依頼するほど、GitHub上で差分を管理し、人間が確認できる状態にしておくことが重要です。

**初心者が最初に覚えるべきGitHub連携：**

1. リポジトリをGitHubに作る
2. ローカルのCursorでそのリポジトリを開く
3. 変更をGitで確認する
4. Pull Requestで変更内容を説明する
5. CIやレビュー結果を見て修正する

CursorではGit差分を見ながらClaudeに修正を依頼できます。ただし、最終的にマージするかどうかは人間が判断します。

[プロンプト例]: GitHubの基本ワークフローを説明させる
```text
このプロジェクトをGitHubで管理します。
初心者向けに、clone、branch作成、commit、push、Pull Request作成、レビュー対応、mergeまでの流れを説明してください。
Cursor上でどの操作を確認できるかも含めてください。
```

<div style="page-break-after: always;"></div>

### 1-7. `CLAUDE.md` と `rules.md` の役割

AI開発では、毎回同じ注意事項をチャットに書くのは大変です。そこで、プロジェクト内にAI向けのルールファイルを置きます。代表的なのが `CLAUDE.md` や `rules.md` です。

**`CLAUDE.md` に書くとよい項目：**

[プロンプト例]: CLAUDE.md のプロジェクトルール例
```text
# Project Rules

## Project Overview
- アプリ名
- 対応プラットフォーム
- 主要機能
- 技術スタック

## Development Commands
- Webの起動コマンド
- type-checkコマンド
- iOSの開き方
- Firebaseのデプロイ方法

## Safety Rules
- ユーザーの変更を戻さない
- 破壊的なgit操作をしない
- コミット前に差分を見せる
- APIキーや.envをコミットしない

## Architecture Notes
- 主要ディレクトリ
- データ同期の流れ
- HealthKitやWatchConnectivityの注意点
```

**`rules.md` に書くとよい項目：**

[プロンプト例]: rules.md のコーディングルール例
```text
# Coding Rules

- 既存の設計に合わせる
- 不要なリファクタリングをしない
- SwiftUIの巨大なViewは小さく分割する
- HealthKitデータは未取得を正常系として扱う
- Watch UIでは文字を増やしすぎない
- Webではtype-checkを通す
- 変更後は確認結果と未確認事項を報告する
```

[プロンプト例]: CLAUDE.md の改善案を生成させる
```text
このプロジェクトのCLAUDE.mdを改善したいです。
README、ios/README.md、web/README.mdを読み、AIが開発時に参照すべきルールを整理してください。
コミット、プッシュ、HealthKit、WatchConnectivity、Firebase、Web type-checkの注意点を含めてください。
```

<div style="page-break-after: always;"></div>

## 第二章: アプリの全体像

<div style="page-break-after: always;"></div>

### 2-1. サンプルアプリとは何を作るのか

サンプルアプリは、「毎日の運動を習慣にする」ことを目的にしたフィットネスアプリです。Duolingoのように、短い達成感、連続記録、ポイント、キャラクター表示を使い、ユーザーが毎日少しずつ体を動かすきっかけを作ります。

本書で作るのは、**iPhone・Apple Watch・Webの3プラットフォームに対応したアプリ**です。まず完成形のスクリーンショットで、何を作るのか全体像をつかみましょう。

---

#### iOSアプリ ─ メインページ（メイン画面）

**マンダラ形式の渦巻き目標表示**が最大の特徴です。時間帯（朝・昼・午後・夜）ごとに、トレーニング・食事・水分・マインドフルネスなど各タスクがノードとして円形に並び、達成するたびにノードが色づいていきます。

![メインページ メインのマンダラ表示](screenshots/main/IMG_3498.jpg)

*▲ 中央に今日の達成率（%）を表示し、外周のノードが各タスクの完了状況を色で示す。ストリーク日数・今日の日付・達成率がヘッダーに一覧表示される*

---

#### iOSアプリ ─ ホーム画面ウィジェット

iOSのホーム画面にウィジェットを配置して、アプリを開かずに今日の進捗を確認できます。

![ホーム画面ウィジェット カレンダー付き大型タイプ](screenshots/main/IMG_3536.png)

*▲ 連続日数・達成度・カロリー収支・XPポイントを4マスで表示。カレンダーと並べた大型ウィジェットで、日々の習慣の定着状況を一目で把握できる*

![ホーム画面ウィジェット 小型タイプ](screenshots/main/IMG_3535.PNG)

*▲ ホーム画面の小型ウィジェット。40日連続・達成度9%・カロリー収支・XPのほか、トレーニング・マインドフル・食事・水分の今日の進捗も表示*

---

#### Apple Watchアプリ ─ 3つの画面

Watchアプリは独立したアプリとして動作し、iPhone不在でも記録できます。

**① アプリ一覧 ─ サンプルアプリのアイコン**

![Apple Watchアプリ一覧 サンプルアプリアイコン](screenshots/watch/incoming-A45FB3CB.png)

*▲ Apple Watchのアプリ一覧画面。中央にサンプルアプリのキャラクター（FITINGO）アイコンが表示される*

**② メインダッシュボード ─ Watchでもマンダラ表示**

![Apple Watch メインダッシュボード マンダラ達成率46%](screenshots/watch/incoming-D1E00771.png)

*▲ Watchのメイン画面。iPhoneと同様のマンダラ形式で今日の達成率（46%）を表示。TRAIN・MINDの進捗、日付、連続ストリーク数をコンパクトに配置*

**③ トレーニング開始 ─ タップ1回でセット開始**

![Apple Watch 今日のFitingoトレーニング開始画面](screenshots/watch/incoming-CE070953.png)

*▲ トレーニング回数・マインドフル回数を上部に表示し、「今日のFitingoトレーニング」ボタンをタップするだけでセットを開始できる。腕を動かしながらでも操作しやすい大型ボタン*

---

**主な構成まとめ：**

| プラットフォーム | 技術 | 主な機能 |
|---|---|---|
| **iOSアプリ** | SwiftUI | マンダラメイン、Apple Health、Core Motion、フォトログ、MIND、FIT、ウィジェット |
| **Apple Watchアプリ** | SwiftUI for watchOS | マンダラ表示、クイック記録、心拍/HRV、瞑想/ストレッチ、トレーニング |
| **Webアプリ** | React + TypeScript + Vite | ダッシュボード、手動記録、週間目標、90日チャレンジ、設定 |

<div style="page-break-after: always;"></div>

### 2-2. 技術スタック

[プロンプト例]: （実装・調査プロンプトの例）
```text
Web:
├── React 18
├── TypeScript
├── Vite
├── Tailwind CSS
├── Firebase Authentication
└── Firestore

iOS:
├── SwiftUI
├── HealthKit
├── Core Motion
├── Firebase iOS SDK
└── WidgetKit

Apple Watch:
├── SwiftUI for watchOS
├── HealthKit
├── Core Motion
├── WatchConnectivity
└── Haptics

開発環境:
├── Cursor
├── Claude Sonnet/Opus
├── Xcode
├── Git / GitHub
├── Node.js / npm
├── CocoaPods
└── Firebase CLI
```

<div style="page-break-after: always;"></div>

### 2-3. データの流れ

[プロンプト例]: （実装・調査プロンプトの例）
```text
Webで記録
  → Firestore
  → iOSが読み込み
  → DashboardやHistoryに表示

iOSで運動記録
  → Firestoreへ保存
  → Webに反映
  → Watchへ今日の進捗を同期

Watchで運動完了
  → WatchConnectivityでiOSへ送信
  → iOSがFirestoreへ保存
  → Webにも反映

Apple Health
  → iOS/WatchがHealthKitから取得
  → Dashboard、MIND、FIT、Watch履歴に表示
```

> **📌 役割分担のポイント**
>
> - **Firestore**: クラウド同期、複数デバイス間の状態共有
> - **HealthKit**: 心拍・HRV・睡眠・歩数などの健康データ
> - **WatchConnectivity**: iPhoneとApple Watchの近距離リアルタイム同期

<div style="page-break-after: always;"></div>

### 2-4. 全体像をClaudeに説明させるプロンプト

[プロンプト例]: プロジェクト全体の構成をClaudeに把握させる
```text
このプロジェクトは、Web、iOS、Apple Watch対応のフィットネス習慣化アプリです。
README、CLAUDE.md、ios/README.md、web/README.mdを読んで、全体像を初心者向けに説明してください。
まだコード変更はしないでください。
```

[プロンプト例]: ディレクトリ構成とデータ同期の流れを説明させる
```text
このリポジトリの主要ディレクトリを調査し、Web、iOS、Watch、Firebaseがどのように分かれているか説明してください。
データ同期の流れも、FirestoreとWatchConnectivityに分けて説明してください。
```

<div style="page-break-after: always;"></div>

## 第三章: 開発のための環境準備

<div style="page-break-after: always;"></div>

### 3-1. 必要なもの

サンプルアプリのようなWeb、iOS、Apple Watch対応アプリを作るには、次の環境が必要です。

| カテゴリ | ツール・環境 | 備考 |
|---|---|---|
| **OS** | macOS | iOS/Watch開発にはmacOS必須 |
| **IDE** | Cursor | メインの開発環境 |
| **AI** | Claude Sonnet/Opus | Cursor経由で利用 |
| **Apple** | Xcode | ビルド・デプロイ専用 |
| **JS環境** | Node.js / npm | Web開発 |
| **iOS依存** | CocoaPods | Firebaseなど |
| **Backend** | Firebase CLI | Firestore・Hosting |
| **バージョン管理** | Git / GitHub | 変更履歴管理 |
| **実機** | iPhone + Apple Watch | HealthKit・モーションの実機確認に必須 |

> **💡 実機を用意する理由**
>
> HealthKitやCore Motion、Apple Watch連携はシミュレータだけでは確認しにくいため、できれば実機を用意します。特に心拍数、HRV、Watchのモーション検知は**実機確認が必須**です。

<div style="page-break-after: always;"></div>

### 3-2. Cursorのセットアップ

Cursorは公式サイトからmacOS版をダウンロードしてインストールします。インストール後、アカウントでサインインし、`File > Open Folder` からプロジェクトフォルダを開きます。

サンプルアプリの場合は、次のフォルダを開きます。

[プロンプト例]: Cursorで開くプロジェクトフォルダのパス例
```text
~/Git/kfit
```

**Cursorを使う準備で確認すること：**

- プロジェクトルートを開いている
- CursorのチャットでClaude Sonnet/Opusを選べる
- ターミナルがCursor内で開ける
- Git差分がCursor上で確認できる
- ファイル検索が使える
- `.md`、`.swift`、`.tsx` を編集できる

[プロンプト例]: プロジェクト開封後の初回構成説明依頼
```text
このリポジトリを開きました。
まずREADME、CLAUDE.md、ios/README.md、web/README.mdを読み、初心者向けに開発手順を説明してください。
まだコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 3-3. CursorのGit連携

Cursorでは、Git差分を見ながらAIに変更を依頼できます。初心者にとって重要なのは、AIが変更したファイルをそのまま信じるのではなく、差分を読むことです。

**作業前に確認するコマンド：**

```bash
git status
git diff --stat
```

CursorのGitビューでは、変更ファイルを一覧し、どの行が追加・削除されたか確認できます。AIに依頼した後は、必ず差分を見て、意図しないファイルが変更されていないか確認します。

[プロンプト例]: Git状態の確認と既存変更の保護指示
```text
作業前にgit statusを確認し、未コミット変更を把握してください。
ユーザーが変更した可能性のあるファイルは戻さないでください。
今回の作業に関係するファイルだけを編集してください。
```

<div style="page-break-after: always;"></div>

### 3-4. Cursorで複数LLMを使う

Cursorでは、Claude Sonnet/Opus以外のモデルも選べる場合があります。重要なのは、作業内容に応じてモデルを使い分けることです。

| 用途 | おすすめモデル |
|---|---|
| 軽い修正・文言変更 | 速いモデルまたはSonnet |
| 複数ファイル調査 | Sonnet |
| 複雑な設計・レビュー | Opus |
| 長文ドキュメント作成 | Opus |
| 実装後の説明 | Sonnet |

[プロンプト例]: モデル使い分け: 小さな修正はSonnetで依頼する
```text
この変更は小さなUI調整なので、Sonnetで既存の実装に合わせて修正してください。
```

[プロンプト例]: モデル使い分け: 複雑な問題はOpusで調査させる
```text
この問題は複数プラットフォームにまたがるため、Opusで広く調査してください。
まず原因候補を整理し、私が確認するまでコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 3-5. Xcodeの役割

本書では、コード編集の中心はCursorです。Xcodeは主に次の用途で使います。

- iOSアプリを実機にインストールする
- Apple Watchアプリを実機にインストールする
- Signing & Capabilitiesを設定する
- HealthKit、Watch App、Push NotificationsなどのCapabilityを確認する
- Schemeを選んでビルドする
- ArchiveしてApp Store提出準備を行う
- 実機ログやクラッシュを確認する

> **📌 役割分担の原則**
>
> **Cursorでコードを書き、Xcodeでデプロイする**
>
> SwiftUIコードの編集・調査・デバッグ支援はCursorで行います。実機へのインストール、証明書・プロビジョニング設定、Capabilityの追加はXcodeで行います。

<div style="page-break-after: always;"></div>

### 3-6. XcodeにClaudeを直接連携する方法

基本はCursorからClaudeを使いますが、Xcodeで作業中にClaudeを使いたい場合もあります。代表的な方法は次の3つです。

1. **Cursorで同じリポジトリを開き、Xcodeと並べて使う** ← 最も安定
2. Xcodeのエラーや該当コードをコピーして、CursorのClaudeに貼って相談する
3. Claudeのデスクトップアプリやブラウザを横に開き、Xcodeのエラー内容を渡す

[プロンプト例]: XcodeのSwiftエラーをClaudeで解決させる
```text
Xcodeで次のSwiftエラーが出ています。
エラー内容と該当ファイルをもとに、原因と最小限の修正案を教えてください。
UIの見た目は変えないでください。
```

<div style="page-break-after: always;"></div>

### 3-7. Xcodeのセットアップ

XcodeはApp Storeからインストールします。初回起動時に追加コンポーネントのインストールを求められる場合があります。

```bash
xcode-select -p
xcodebuild -version
```

Command Line Toolsが未設定の場合は、次のコマンドを使います。

```bash
xcode-select --install
```

サンプルアプリでは、iOSプロジェクトを次のように開きます。

```bash
cd ios
pod install
open kfit.xcworkspace   # ← .xcworkspace を開くこと（.xcodeprojではない）
```

**Xcodeで確認する項目：**

- iOSアプリターゲットにHealthKit Capabilityがある
- Watch Appターゲットが正しく含まれている
- Signing & CapabilitiesでTeamが設定されている
- `GoogleService-Info.plist` がiOSターゲットに含まれている
- HealthKitやカメラなどの権限説明文が `Info.plist` に入っている
- 実機iPhoneとApple Watchでビルドできる

<div style="page-break-after: always;"></div>

### 3-8. iPhone実機の準備

**iPhoneにアプリをデプロイする手順：**

1. iPhoneをMacにUSB接続する
2. iPhone側で「このコンピュータを信頼」を選ぶ
3. Xcodeの上部デバイス選択で接続したiPhoneを選ぶ
4. XcodeのSigning & CapabilitiesでTeamを設定する
5. Bundle Identifierが一意であることを確認する
6. 必要なCapabilityを有効にする
7. Runボタンで実機へインストールする

**実機で確認する設定：**

- 設定アプリで開発者モードが有効か
- Healthアプリへのアクセス許可が出るか
- Firebaseログインができるか
- ネットワーク接続があるか
- 通知やヘルスケア権限の許可文言が自然か

[プロンプト例]: iPhoneへの実機デプロイ手順を整理させる
```text
iPhone実機にこのiOSアプリをデプロイする手順を初心者向けに整理してください。
XcodeのScheme選択、Team設定、Bundle Identifier、HealthKit Capability、実機側の信頼設定を含めてください。
```

<div style="page-break-after: always;"></div>

### 3-9. Apple Watch実機の準備

Apple Watchアプリを実機にデプロイするには、iPhoneとApple Watchがペアリングされている必要があります。

**準備手順：**

1. iPhoneとApple Watchをペアリングする
2. Apple Watchのロックを解除して腕に装着する
3. iPhoneとApple Watchが近くにある状態にする
4. XcodeでWatch Appを含むSchemeを選ぶ
5. 実行先として、ペアリング済みのApple Watchを選ぶ
6. RunしてWatchへインストールする

**Watchで確認する設定：**

- Watch側でアプリがインストールされているか
- HealthKit権限が許可されているか
- 心拍数、HRV、ワークアウト、マインドフルネスのデータが取得できるか
- WatchConnectivityでiPhoneと通信できるか
- 1分瞑想、3分ストレッチ、運動記録が実機で動くか

[プロンプト例]: Apple Watchへの実機デプロイ手順を整理させる
```text
Apple Watch実機にWatchアプリをデプロイする手順を初心者向けに説明してください。
iPhoneとのペアリング、Xcodeの実行先選択、Watch App Scheme、HealthKit権限、WatchConnectivity確認を含めてください。
```

<div style="page-break-after: always;"></div>

### 3-10. Web開発環境

Web側はNode.jsとnpmで動かします。

```bash
cd web
npm install
npm run dev
```

型チェックとビルドは次のように実行します。

```bash
npm --prefix web run type-check
npm --prefix web run build
```

<div style="page-break-after: always;"></div>

### 3-11. Firebaseの準備

Firebaseでは、Authentication、Firestore、Hostingを使います。Webでは `.env.local` にFirebase設定を入れます。iOSではFirebase Consoleから取得した `GoogleService-Info.plist` をXcodeプロジェクトに追加します。

[プロンプト例]: Firebaseのセットアップ手順を説明させる
```text
Firebaseのセットアップ手順を初心者向けに整理してください。
Webの.env.local、iOSのGoogleService-Info.plist、Googleログイン、Firestoreルール、Firebase Hostingを分けて説明してください。
```

<div style="page-break-after: always;"></div>

### 3-12. GitHub連携のセットアップ

GitHubを使うと、ローカルの作業をクラウドに保存し、履歴を管理し、Pull Requestで変更内容を確認できます。AIにコードを書かせるほど、GitHubで差分を管理することが重要になります。

```bash
# GitHub上でリポジトリを作成したあと
git remote add origin git@github.com:your-name/kfit.git
git branch -M main
git push -u origin main
```

**CursorでGitHub連携を使う流れ：**

1. GitHubからリポジトリをcloneする
2. Cursorでフォルダを開く
3. 作業用ブランチを作る
4. Claudeに実装を依頼する
5. CursorのGitビューで差分を見る
6. type-checkやXcode実機確認を行う
7. commitする
8. pushする
9. GitHubでPull Requestを作る

**ブランチ名の例：**

[プロンプト例]: Gitブランチ名の命名規則の例
```text
feature/watch-hrv-history
fix/ios-healthkit-refresh
docs/cursor-claude-book
```

[プロンプト例]: Pull Request本文案をClaudeに作成させる
```text
この変更をGitHubのPull Requestに出したいです。
git statusとgit diff --statを確認し、変更内容をSummaryとTest planに分けてPR本文案を作ってください。
まだcommitやpushはしないでください。
```

<div style="page-break-after: always;"></div>

### 3-13. GitHubで安全にcommit/pushする

AIに実装を頼んだあと、すぐにcommitするのは危険です。必ず差分を確認します。

```bash
git status
git diff --stat
git diff
```

コミットメッセージは、何をしたかだけでなく、なぜ必要だったかが分かるようにします。

[プロンプト例]: Conventional Commits形式のコミットメッセージ例
```text
Add Watch HRV impact history

Record heart rate and HRV before and after mindfulness sessions
so users can review stress changes over time.
```

[プロンプト例]: コミット前の変更内容をClaudeにレビューさせる
```text
コミット前レビューをしてください。
変更ファイル、変更理由、リスク、テスト状況、コミットメッセージ案を出してください。
.env、APIキー、個人情報が含まれていないかも確認してください。
```

<div style="page-break-after: always;"></div>

### 3-14. `CLAUDE.md` と `rules.md` を育てる

AI開発では、ルールファイルを一度書いて終わりにしません。プロジェクトが育つほど、よく起きるミス、よく使うコマンド、注意すべき設計判断が増えます。それらを `CLAUDE.md` や `rules.md` に追記します。

**サンプルアプリで書いておくとよいルール例：**

[プロンプト例]: CLAUDE.mdのルール例（サンプルアプリ向け）
```text
- HealthKitの値は権限未許可や未取得を正常系として扱う
- WatchConnectivityではiOS側のTimeSlotManagerを正とする
- Watch UIは小さい画面を前提に、文字量を増やしすぎない
- Webのアプリ名変更ではmanifest、index.html、package.json、localStorageキーも確認する
- iOS/Watchの実機確認が必要な変更は、最終報告で未確認事項を明記する
- SwiftUIの巨大なViewは独立したView構造体に分割してスタックオーバーフローを防ぐ
```

[プロンプト例]: 実装から得た知見をCLAUDE.mdのルールとして整理させる
```text
今回の実装で得られた注意点を、CLAUDE.mdまたはrules.mdに追記する案としてまとめてください。
特に、次回同じミスを防ぐための具体的なルールにしてください。
```

<div style="page-break-after: always;"></div>

## コラム1: LLM比較、どれが最もコスパがいい？

Cursorでは、Claudeだけでなく、OpenAIやGemini系のモデルを選べる場合があります。モデルは「一番賢いものを常に使う」のではなく、作業内容に合わせて選ぶとコスパが良くなります。

> **⚠️ 価格について**
>
> ここでの価格は、2026年6月時点で公開されているAPI価格を目安にしたものです。実際のCursor内の利用料金やプランは、Cursor側の料金体系、契約プラン、キャッシュ、バッチ、プロモーション、為替によって変わります。最新の正確な価格は各社の公式価格ページを確認してください。

### 比較の前提

LLMのコスパは、単純な1トークンあたりの価格だけでは決まりません。開発では、次の観点を合わせて見ます。

- 実装の正確さ
- 長いコードベースを読めるか
- SwiftやTypeScriptの修正が得意か
- 指示に従う安定性
- 出力の長さと品質
- 何回やり直しが必要か
- 入力価格と出力価格

> **💡 コスパの考え方**
>
> 安いモデルでも何度も修正が必要なら総コストは上がります。高いモデルでも一回で正しく設計できるなら結果的に安いことがあります。

<div style="page-break-after: always;"></div>

### Claude系: Cursorでの本命候補

Claudeは、長いコードの読解、既存設計に合わせた修正、文章化、レビューに強い傾向があります。

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 |
|---|---|---:|---|
| Claude Opus 4.8 | **最新（2026/5/28）** | 入力 $5 / 出力 $25 | 最高品質の推論・設計・コードレビュー |
| Claude Opus 4.7 | 高性能・安定 | 入力 $5 / 出力 $25 | 複雑な設計、長文ドキュメント、難しいバグ調査 |
| Claude Sonnet 4.6 | 普及・標準 | 入力 $3 / 出力 $15 | 日常的な実装、複数ファイル調査、レビュー |
| Claude Haiku 4.5 | 軽量・安価 | 入力 $1 / 出力 $5 | 要約、分類、単純な文言変更 |

**Claudeを使うと効率が良い場面：**

- SwiftUIの大きなViewを読み解く
- HealthKitやWatchConnectivityの影響範囲を調査する
- `CLAUDE.md` や技術書原稿を書く
- Pull Requestのレビュー観点を洗い出す
- 既存設計を壊さずに修正する

<div style="page-break-after: always;"></div>

### OpenAI系: コード生成と軽量モデルの選択肢

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 |
|---|---|---:|---|
| GPT-4.1 | 最新API系・コード強化 | 入力 $2 / 出力 $8 | コード生成、指示追従、長文コンテキスト |
| GPT-4.1 mini | 普及・低価格 | 入力 $0.40 / 出力 $1.60 | 軽い修正、要約、単純な変換 |
| GPT-4.1 nano | 超軽量 | 入力 $0.10 / 出力 $0.40 | 分類、短い文言生成、単純抽出 |
| GPT-4o | 普及・マルチモーダル | 入力 $2.50 / 出力 $10 | 画像を含む相談、一般的な開発補助 |
| o3 | reasoning | 入力 $2 / 出力 $8 | 複雑な推論、設計判断、分析 |

<div style="page-break-after: always;"></div>

### Gemini系: 低コスト・長文・Google連携が強い

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 |
|---|---|---:|---|
| Gemini 2.5 Pro | 高性能・長文 | 入力 $1.25 / 出力 $10 | 長い資料、設計比較、複雑な調査 |
| Gemini 2.5 Flash | 普及・高速・安価 | 入力 $0.30 / 出力 $2.50 | 要約、分類、軽いコード調査 |
| Gemini Flash-Lite | 超低価格 | 入力 $0.10前後 | 大量分類、抽出、単純変換 |

<div style="page-break-after: always;"></div>

### 用途別のおすすめ

| 作業 | 最もコスパが良い候補 | 理由 |
|---|---|---|
| 日常的なCursorでの実装 | Claude Sonnet / GPT-4.1 | 既存コード理解と実装品質のバランスが良い |
| 複雑な設計・バグ調査 | Claude Opus / o3 | 失敗時の手戻りが高いので高性能モデルが得 |
| SwiftUI/WatchConnectivityの横断調査 | Claude Sonnet or Opus | 長い文脈と既存設計の読解に強い |
| Webの軽い修正 | GPT-4.1 mini / Gemini Flash | 安く速い |
| 大量の要約・分類 | Gemini Flash / GPT-4.1 nano | 低単価で処理できる |
| 技術書原稿の長文生成 | Claude Opus / Gemini Pro | 長文構成と文脈維持が重要 |
| PRレビュー | Claude Sonnet / Opus | バグ、リスク、未テスト箇所の指摘が得意 |
| UIスクリーンショットを見て相談 | GPT-4o / Gemini Pro | マルチモーダル相談に向く |

### 結論: 最初はSonnet中心、重い判断だけOpus

この本のようにCursorを中心に開発する場合、最初のおすすめはClaude Sonnet中心です。普段の実装、調査、レビュー、説明のバランスが良く、既存コードに合わせる力もあります。

**コスパを最大化する基本方針：**

[プロンプト例]: コスパを最大化するモデル使い分け戦略の例
```text
1. まず安い/標準モデルで調査する
2. 難しければ高性能モデルに切り替える
3. 実装後は別モデルでレビューする
4. 長い共通文脈はCLAUDE.mdやrules.mdに移す
5. 同じ説明を毎回プロンプトに書かない
```

**参考価格ソース：**
- Anthropic: https://platform.claude.com/docs/en/about-claude/pricing
- OpenAI: https://developers.openai.com/api/docs/pricing
- Google: https://ai.google.dev/gemini-api/docs/pricing

<div style="page-break-after: always;"></div>

## 第四章: Webアプリ開発

<div style="page-break-after: always;"></div>

### 4-1. Webアプリの役割

サンプルアプリのWebアプリは、PCやスマホブラウザから記録を確認・編集できる入口です。iOSアプリほどHealthKitやモーションセンサーに深くは関わりませんが、ダッシュボード、手動記録、週間目標、90日チャレンジ、設定画面を提供します。

Web版は、React + TypeScript + Viteで作ります。Cursor上でTypeScriptファイルを編集し、Cursor内ターミナルで開発サーバーや型チェックを実行します。

<div style="page-break-after: always;"></div>

### 4-2. Webの構成

[プロンプト例]: Webアプリのソースディレクトリ構成
```text
web/src/
├── components/
│   ├── DashboardView.tsx
│   ├── LoginView.tsx
│   ├── SettingsView.tsx
│   └── ...
├── services/
│   └── firebase.ts
├── store/
├── types/
├── App.tsx
└── main.tsx
```

<div style="page-break-after: always;"></div>

### 4-3. ダッシュボード開発

Webダッシュボードでは、今日の運動状況、記録、DIET、SLEEP、週間セット目標、90日チャレンジを表示します。

[プロンプト例]: Webダッシュボードのカード表示レイアウト変更依頼
```text
Webのダッシュボード構成を変更してください。
MINDカードとFOODカードは非表示にし、DIETカードを横幅いっぱいにしてください。
DIETカードには現在体重、目標体重、体脂肪、摂取目標、消費目標、日次バランスを表示してください。
カードを押したらGOAL設定画面へ遷移するようにしてください。
既存のデザインシステムとTailwindのクラスに合わせてください。
```

<div style="page-break-after: always;"></div>

### 4-4. アプリ名の変更

Webアプリ名を変更する場合、画面表示だけでは不十分です。`index.html`、`manifest.json`、`package.json`、README、localStorageキーも確認します。

```ts
const SETTINGS_KEY = 'fitingo_settings'
const LEGACY_SETTINGS_KEY = 'duofit_settings'
```

[プロンプト例]: アプリ名の全面変更（UI・設定ファイル・localStorage互換対応）
```text
Webアプリ名をFitingoに全面変更してください。
画面表示、index.html、manifest.json、package.json、README、localStorageキーを確認してください。
localStorageキーは旧キーから新キーへ読み替える互換処理を入れてください。
変更後にtype-checkを実行できるようにしてください。
```

<div style="page-break-after: always;"></div>

### 4-5. Firestore同期

Webで記録した運動や目標は、Firestoreに保存します。iOS側も同じデータを読むことで、WebとiOSの同期ができます。

[プロンプト例]: FirestoreのデータモデルとドキュメントID体系の例
```text
users/{userId}/
├── profile
├── completed-exercises/
├── daily-goals/
├── time-slot-goals/
├── achievements/
└── statistics/
```

[プロンプト例]: Firestore共通データ基盤の設計案を生成させる
```text
FirestoreをWeb、iOS、Watchの共通データ基盤として使います。
ユーザーごとの運動履歴、日次目標、時間帯別進捗、プロフィールを保存する設計案を出してください。
セキュリティルールでは、ユーザー本人だけが自分のデータを読み書きできるようにしてください。
```

<div style="page-break-after: always;"></div>

### 4-6. Webのテスト

```bash
npm --prefix web run type-check
npm --prefix web run build
```

[プロンプト例]: TypeScriptの型エラーを原因から解決させる
```text
Webのtype-checkでエラーが出ています。
エラー全文を読んで、原因を説明し、最小限の修正をしてください。
修正後にもう一度type-checkを実行してください。
```

<div style="page-break-after: always;"></div>

## コラム2: iPhoneからClaude CodeとGitHubで開発を続ける

### モバイル開発は「完結」より「継続」を目指す

外出中にiPhoneだけで本格的なiOSアプリをビルドするのは現実的ではありません。Xcodeによる実機ビルドやWatchデプロイはMacが必要です。しかし、GitHubとClaude Code、あるいはGitHub Codespacesやリモート開発環境を組み合わせると、iPhoneからでも設計、Issue整理、レビュー、軽微な修正、ドキュメント更新を続けられます。

**モバイル上で向いている作業：**

- GitHub Issueを書く
- Pull Requestの差分を読む
- レビューコメントを書く
- Claudeに調査プロンプトを作る
- READMEやMarkdownを修正する
- 小さなWeb修正を行う
- 次にMacで実機確認するためのチェックリストを作る

### iPhoneからGitHubを使う流れ

1. GitHub Mobileまたはブラウザでリポジトリを開く
2. Issueにやりたいことを書く
3. ClaudeアプリやブラウザでIssue内容を整理する
4. 必要ならGitHub上でMarkdownや小さなファイルを編集する
5. Pull Requestを作る
6. Macに戻ったらCursorでpullし、Xcodeで実機確認する

### モバイルから使うプロンプト例

[プロンプト例]: iPhoneからCursorの作業準備のためのIssue作成依頼
```text
いまiPhoneからGitHub Issueを書いています。
次にMacでCursorを開いたときにすぐ作業できるように、要件、影響範囲、実装ステップ、テスト項目に分けてIssue本文を作ってください。
```

[プロンプト例]: 外出中の実機確認チェックリスト作成依頼
```text
外出中なので実機確認はできません。
この変更について、Macに戻ったあとXcodeで確認すべき項目をチェックリストにしてください。
iPhone実機、Apple Watch実機、HealthKit権限、WatchConnectivityを含めてください。
```

> **⚠️ モバイル開発の注意点**
>
> モバイル上では、差分を見落としやすく、テストも限定されます。特に、HealthKit、WatchConnectivity、Core Motion、Xcode SigningはiPhoneだけでは確認できません。スマホで作業した内容は、必ずMacのCursorとXcodeで確認してからマージします。

<div style="page-break-after: always;"></div>

## 第五章: iOSアプリ開発

<div style="page-break-after: always;"></div>

### 5-1. iOSアプリの役割

iOSアプリはサンプルアプリの中心です。HealthKit、Core Motion、写真ログ、Diet Goal、MIND、メイン、FITページなど、スマートフォンならではの機能を担当します。

本書ではSwiftUIコードの編集はCursorで行い、実機へのインストールやCapabilities設定はXcodeで行います。

[プロンプト例]: iOSプロジェクトのディレクトリ構成（Cursor開発用）
```text
ios/kfit/
├── Managers/
│   ├── AuthenticationManager.swift
│   ├── HealthKitManager.swift
│   ├── MotionDetectionManager.swift
│   ├── TimeSlotManager.swift
│   └── iOSWatchBridge.swift
├── Models/
└── Views/
    ├── DashboardView.swift    ← ROUTINページ（最大ファイル）
    ├── MindView.swift
    ├── GoalView.swift
    └── ...
```

<div style="page-break-after: always;"></div>

### 5-2. CursorでSwiftUIを編集し、Xcodeで実行する

**基本の流れ：**

1. CursorでSwiftファイルを編集する
2. Cursorで差分を確認する
3. Xcodeで `kfit.xcworkspace` を開く
4. 実行先にiPhoneを選ぶ
5. Runして実機で確認する
6. Xcodeエラーが出たら、エラー内容をCursorのClaudeへ渡す
7. Cursorで修正し、再度Xcodeでビルドする

[プロンプト例]: XcodeのSwiftコンパイルエラーを最小限の修正で解決させる
```text
Xcodeで次のSwiftエラーが出ています。
該当ファイルとエラー内容をもとに、原因と最小限の修正案を教えてください。
UIの見た目は変えないでください。
```

<div style="page-break-after: always;"></div>

### 5-3. SwiftUIでメインダッシュボードを作る

メインページは、サンプルアプリのメイン画面です。マンダラ形式の渦巻きタスク表示、時間帯別の進捗、フィットネスボタン、食事・水分ログなどを1ページに集約します。

---

**メインページ ─ メイン表示とアクションボタン**

![メインページ下部 FITINGOキャラクターとアクションボタン](screenshots/main/IMG_3499.jpg)

*▲ FITINGOキャラクターをタップするとトレーニング開始。その下にマインドフルネス・3分ストレッチ・20分スタンドタイマーのボタンが並ぶ*

---

**時間帯別の記録表示（朝の例）**

![朝の記録表示 食事・水分・トレーニング動画](screenshots/main/IMG_3500.jpg)

*▲ 朝スロットで記録された食事・水分ログと、FITINGOのトレーニング動画（アコーディオン展開）が表示される*

---

[プロンプト例]: iOSのメインページに更新ボタンを追加（HealthKit再取得）
```text
iOSのROUTINページに、右上の更新ボタンを追加してください。
押したらHealthKitの最新データを再取得し、ロード中はアイコンを回転させ、連打できないようにしてください。
既存のdailySetsCardの構成を崩さず、最小限の変更にしてください。
```

<div style="page-break-after: always;"></div>

### 5-4. Apple Health連携

HealthKitを使うと、Apple Healthに保存された健康データを取得できます。サンプルアプリでは、歩数、アクティブカロリー、安静時カロリー、心拍数、HRV、睡眠、食事、PFC栄養素などを扱います。

```swift
let healthStore = HKHealthStore()
let typesToRead: Set<HKObjectType> = [
    HKQuantityType.quantityType(forIdentifier: .heartRate)!,
    HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
]
```

**FITページ ─ アクティビティ・カロリー収支・体重推移**

![FITページ 今日のアクティビティとカロリー収支](screenshots/fit/IMG_3509.jpg)

*▲ Apple Watchのアクティビティリング、消費カロリー収支、歩数、体重が一画面で確認できるFITページ*

[プロンプト例]: HealthKitから今日の健康データを取得してFITページに表示させる
```text
iOSでHealthKitから今日の歩数、アクティブカロリー、安静時カロリー、心拍数、HRVを取得してください。
HealthKit権限がない場合は画面が壊れないようにし、0または未取得表示にしてください。
既存のHealthKitManagerに合わせて実装してください。
```

<div style="page-break-after: always;"></div>

### 5-5. FITページ ─ 目標プランと週間実績

**FITページ ─ 目標プランと体重推移グラフ**

![FITページ 目標プランと週間実績グラフ](screenshots/fit/IMG_3510.jpg)

*▲ スタート体重・現在体重・目標体重を一本線で表示し、週間の燃焼カロリー・食事カロリー・カロリー収支をグラフで確認できる*

![FITページ 燃やしたカロリーグラフと食事カロリーグラフ](screenshots/fit/IMG_3511.jpg)

*▲ 週単位の燃やしたカロリー（安静時/活動）と食事カロリー（朝/昼前/昼後/夕/夜）を色分けして視覚化*

<div style="page-break-after: always;"></div>

### 5-6. Diet Goalとカロリー目標

Apple Healthで摂取カロリー計測をONにした場合は、HealthKitの実測値を使います。OFFの場合は、1日の目標を時間帯別に配分し、その時間帯になったら自動的に取得済みとして扱います。

**時間帯別カロリー配分の例（1日2000kcal）：**

| 時間帯 | 配分 |
|---|---|
| 朝 (6〜10時) | 400 kcal |
| 昼 (10〜14時) | 600 kcal |
| 午後 (14〜18時) | 200 kcal |
| 夜 (18〜24時) | 800 kcal |

**FOODページ ─ クイック記録とフォトログ**

![FOODページ クイック記録とFITカード](screenshots/main/IMG_3502.jpg)

*▲ 朝食・昼食・夕食・スナック・ドリンク・アルコールをワンタップで記録できるクイック記録、フォトログ（AI食事分析）へのアクセスも同じ画面から*

[プロンプト例]: 食事カロリー入力欄の追加とApple Health連携の実装
```text
ダイエット目標の摂取カロリー目標に入力欄を設けて、2000kcalをデフォルトにしてください。
Apple Healthで計測をONにしたら、実際の摂取カロリーはApple Healthの登録を使ってください。
OFFの場合は、1日の摂取目標を時間帯別に配分し、その時間になったら自動的にそのカロリーを取得したようにしてください。
```

<div style="page-break-after: always;"></div>

### 5-7. フォトログ ─ AI食事分析

写真1枚でAIがカロリー・PFCを自動推定するフォトログ機能です。

**フォトログ選択と分析結果**

![フォトログ 過去の記録から選択](screenshots/main/IMG_3503.jpg)

*▲ カメラで撮影またはアルバムから選択。過去の記録をサムネイル一覧で素早く再選択できる*

![フォトログ AI分析結果画面](screenshots/main/IMG_3504.jpg)

*▲ AIが画像を解析し、カロリー・タンパク質・脂質・炭水化物・水分を自動推定。確度も表示され、HealthKitやFOODフィードへ保存できる*

**FOODフィード ─ フォトログの一覧**

![FOODフィード 過去の食事写真一覧](screenshots/main/IMG_3505.jpg)

*▲ お気に入りに登録したフォトログをグリッド表示。カロリーと撮影日が各カードに表示され、過去の食事記録をひとめで振り返れる*

<div style="page-break-after: always;"></div>

### 5-8. Motion Sensorで運動を数える

サンプルアプリでは、Core Motionの加速度センサーを使い、運動の回数を検出します。

```swift
let acceleration = sqrt(
    data.acceleration.x * data.acceleration.x +
    data.acceleration.y * data.acceleration.y +
    data.acceleration.z * data.acceleration.z
)
```

**トレーニング計測画面 ─ モーション検出中**

![トレーニング計測 腹筋でモーション検出中](screenshots/main/IMG_3501.jpg)

*▲ 選択した種目（ここでは腹筋）のGIF動画を見ながら実施。iPhoneのモーションセンサーがレップを自動カウントし、手動補正ボタンで調整も可能*

[プロンプト例]: Core Motionで腕立て・スクワット・腹筋の自動カウントを実装させる
```text
iOSでCore Motionを使い、腕立て、スクワット、腹筋の回数を自動カウントしたいです。
まず既存のMotionDetectionManagerとExerciseTrackerViewを調査し、
現在の検出ロジック、サンプリング周波数、閾値、フォームスコアの計算方法を説明してください。
```

<div style="page-break-after: always;"></div>

### 5-9. MINDページとHRV分析

MINDページは、現在のストレスレベル（心拍・HRV）、1分瞑想タイマー、3分ストレッチ、HRV推移グラフ、今日のまとめを1ページで提供します。

**MINDページ ─ ストレスレベルと瞑想タイマー**

![MINDページ ストレスレベル表示と1分瞑想タイマー](screenshots/mind/IMG_3516.jpg)

*▲ 心拍数・HRV・ストレスレベルをリアルタイム表示。「1分瞑想タイマー」ボタンから即座にセッション開始できる*

**MINDページ ─ HRV推移グラフと今日のまとめ**

![MINDページ HRV推移グラフ](screenshots/mind/IMG_3517.jpg)

*▲ 今日のHRV推移を折れ線グラフで表示。マインドフル履歴のアコーディオン、平均心拍・HRV・ストレス・睡眠時間のサマリーも確認できる*

![MINDページ 今日のまとめと3分ストレッチ](screenshots/mind/IMG_3518.jpg)

*▲ 睡眠時間・日光下時間・運動時間のサマリーと、睡眠状態に合わせたアドバイス。「3分ストレッチ」ボタンからセッションを開始できる*

[プロンプト例]: MINDページへのHRV7日平均グラフ追加
```text
iOSのMINDページで、3分ストレッチの下に過去7日のHRV平均グラフを表示して。
20msの赤い基準線を入れて。HealthKitManagerに7日平均取得メソッドを追加し、
既存のSwiftUIデザインに合わせて。
```

<div style="page-break-after: always;"></div>

### 5-10. メイン全体のサマリー表示

メインページの中段には、FIT・FOOD・MINDの3つのサマリーカードが並びます。

**メイン ─ FIT・FOOD・MINDのサマリーカード**

![メインページ FIT・FOOD・MINDサマリー](screenshots/main/IMG_3506.jpg)

*▲ FITカード（消費カロリー・体重・歩数）、FOODカード（摂取カロリー・水分スコア）、MINDカード（睡眠・心拍・HRV・ストレス）を一覧表示*

**ポイント・90日チャレンジ・ハビットスタック**

![ポイント・90日チャレンジ・ハビットスタック](screenshots/main/IMG_3507.jpg)

*▲ 今日/今週/累計XP、90日チャレンジの進捗バー、日課とトレーニングをリンクするハビットスタック機能*

**TOMOページ ─ 友達とのランキング**

![TOMOページ 友達招待とランキング](screenshots/main/IMG_3530.jpg)

*▲ Googleアカウントのメールアドレスで友達を招待し、今週のポイント・累計ポイント・連続日数でランキング比較*

<div style="page-break-after: always;"></div>

### 5-11. SETUPページ ─ 習慣・目標の設定

**SETUPページ ─ メニューカスタマイズとタブ設定**

![設定ページ テーマとメニューカスタマイズ](screenshots/setup/IMG_3522.jpg)

*▲ ライト/ダークテーマの切り替えと、各タブ（メイン・FIT・FOOD・MIND・TOMO）の表示/非表示・並び替えを設定できる*

**毎日の習慣・目標設定**

![毎日の習慣目標設定 食事・体重・睡眠・カスタム項目](screenshots/setup/IMG_3523.jpg)

*▲ 食事記録・摂取カロリー・水分量目標・体重計測・睡眠計測・目標睡眠時間をトグルとスライダーで設定。Duolingoのような「スクリーンショット完了」カスタム項目も追加できる*

**曜日毎の目標設定**

![曜日毎の目標 月〜日ごとに活動・勉強・禁酒などを設定](screenshots/setup/IMG_3524.jpg)

*▲ 曜日ごとに「活動」「勉強」「禁酒」「読書」「英語学習」などのバッジを設定。アクティブなバッジは緑・非アクティブはグレーで視覚的に管理*

**時間帯別の目標設定**

![時間帯別の目標 朝スロットのトレーニング・マインドフル・20分スタンド設定](screenshots/setup/IMG_3525.jpg)

*▲ 朝（6:00-10:00）・昼・午後・夜の時間帯別にトレーニング回数・マインドフル時間・20分スタンドのON/OFFを設定。リマインダー時刻もスロットごとに指定できる*

<div style="page-break-after: always;"></div>

### 5-12. iPhoneへのデプロイ手順

**iPhone実機で動かす手順：**

1. iPhoneをMacに接続する
2. iPhoneで「このコンピュータを信頼」を選ぶ
3. Xcodeで `ios/kfit.xcworkspace` を開く
4. SchemeにiOSアプリを選ぶ
5. 実行先に接続したiPhoneを選ぶ
6. Signing & CapabilitiesでTeamを設定する
7. HealthKitなど必要なCapabilityを確認する
8. RunしてiPhoneへインストールする
9. 初回起動時にHealthKitや通知の権限を許可する
10. Cursorで修正、Xcodeで再実行を繰り返す

[プロンプト例]: iPhoneへの実機デプロイ手順を整理させる
```text
iPhone実機にこのiOSアプリをデプロイする手順を初心者向けに整理してください。
XcodeのScheme選択、Team設定、Bundle Identifier、HealthKit Capability、実機側の信頼設定を含めてください。
```

<div style="page-break-after: always;"></div>

## 第六章: Apple Watchアプリ開発

<div style="page-break-after: always;"></div>

### 6-1. Apple Watchアプリの役割

Apple Watchアプリは、iPhoneアプリの小さい版ではありません。画面が小さく、操作時間が短く、通知やハプティクスとの相性が重要です。

**Watchダッシュボード ─ 心拍・HRV・マインドフルネス**

![Watchダッシュボード 心拍・HRV・ストレスとマインドフルネスボタン](screenshots/watch/incoming-ECA98EF7-4623-4B16-89D5-111B858B3DAE.PNG)

*▲ Watch画面上部に心拍数（bpm）・HRV（ms）・ストレスレベルをリアルタイム表示。下部のマインドフルネスカードからすぐにセッション開始できる*

**Watchダッシュボード ─ アクションカード**

![Watchダッシュボード マインドフルネス・3分ストレッチボタン](screenshots/watch/incoming-193610BE-1B19-4A70-B4AF-669362980D13.PNG)

*▲ スワイプで切り替えられるカードUI。マインドフルネス（紫）・3分ストレッチ（緑〜青）・20分スタンドタイマー（オレンジ〜赤）の各セッションをWatchから直接開始できる*

<div style="page-break-after: always;"></div>

### 6-2. WatchConnectivityで同期する

サンプルアプリでは、iOS側からWatchへ今日の進捗や目標を送り、Watch側からiOSへ運動完了やマインドフルネス完了を送ります。

**Watchで同期するタスクの種類：**

- `training` ─ トレーニングセット完了
- `meal` ─ 食事記録
- `drink` ─ 水分記録
- `mind-input` ─ メンタル入力
- `mindfulness` ─ 瞑想完了
- `stretch` ─ ストレッチ完了
- `stand` ─ 20分スタンド完了

[プロンプト例]: WatchとiOSのタスク達成状態の同期問題を修正させる
```text
Watchで、渦巻き表示の達成済みマークがiOSの達成済みとそろっていません。
iOSの達成状態を正として、Watchの達成済み表示が必ず同期するようにしてください。
meal、drink、mind-input、mindfulness、stretch、trainingは別々に扱ってください。
```

<div style="page-break-after: always;"></div>

### 6-3. Watchのモーション計測

Apple Watchは手首に装着されているため、iPhoneとは違うモーションデータが取れます。腕立て伏せ、スクワット、ランジ、バーピーのような動作は、Watchの加速度・ジャイロから特徴を拾えます。

**Watchトレーニング計測画面**

![Watch トレーニング計測 腕立て伏せのレップカウント](screenshots/watch/incoming-4B24B149-215E-4EB7-A5B2-EF5961218BDD.PNG)

*▲ Watch画面で腕立て伏せの目標回数と現在カウントを表示。モーション検出中はリアルタイムでカウントアップ。手動+1ボタンで補正も可能*

[プロンプト例]: WatchのモーションカウントロジックをiOSと比較・整合させる
```text
Watch側でモーション検知を行うWatchMotionDetectionManagerを調査してください。
iPhone側のMotionDetectionManagerとの違い、サンプリング頻度、検出対象、ハプティクスの使い方を説明してください。
```

<div style="page-break-after: always;"></div>

### 6-4. 水分記録とクイック記録

**Watch水分記録**

![Watch 水分・コーヒー・ビール・ワインのクイック記録](screenshots/watch/incoming-9881886A-CF4B-42A4-A1E5-626877A14F2D.PNG)

*▲ Watchから水・コーヒー・ビール・ワインをワンタップで記録。腕を動かさずにすぐ記録できるのがWatchならではの利点*

<div style="page-break-after: always;"></div>

### 6-5. 1分瞑想と3分ストレッチ

Watch画面では、タイトルを左上に表示し、閉じるボタンを時計に重ならないように配置します。また、呼吸アニメーションは、吸う/吐くの違いが分かるように大きくします。

[プロンプト例]: Watchの瞑想・ストレッチ画面UI改善依頼
```text
Watchの1分瞑想と3分ストレッチ画面を改善してください。
タイトルを左上に表示し、閉じるXボタンは右上の時計に重ならないよう少し下げてください。
呼吸アニメーションは吸う/吐くの違いが分かるように大きくしてください。
```

<div style="page-break-after: always;"></div>

### 6-6. 心拍数とHRVの前後変化を履歴表示する

履歴には、心拍数、HRV、ストレススコアを表示します。

| 指標 | 表示内容 |
|---|---|
| 心拍数 | `前 → 後` と差分（bpm） |
| HRV | `前 → 後` と差分（ms） |
| ストレス | `前 → 後`、差分、改善/上昇/維持 |

[プロンプト例]: 瞑想・ストレッチ完了時の心拍とHRV前後差分の記録と表示
```text
1分瞑想と3分ストレッチで、心拍数とHRVの前後の変化はデータを保持して、履歴に表示してください。
履歴には、心拍数、HRV、ストレススコアの前後、差分、改善/上昇/維持を表示してください。
HealthKitのマインドフルネス記録メタデータにも保存してください。
```

<div style="page-break-after: always;"></div>

### 6-7. Apple Watchへのデプロイ手順

Apple Watchアプリを実機にデプロイするには、iPhoneとApple Watchがペアリングされている必要があります。

**手順：**

1. iPhoneとApple Watchをペアリングする
2. Apple Watchのロックを解除して腕に装着する
3. iPhoneとApple Watchを近くに置く
4. MacにiPhoneを接続する
5. XcodeでWatch Appを含むworkspaceを開く
6. SchemeでWatch AppまたはiOS App with Watch Appを選ぶ
7. 実行先としてペアリング済みApple Watchを選ぶ
8. Signing & CapabilitiesのTeamを確認する
9. RunしてWatchへインストールする
10. Watch側でHealthKit権限や通知許可を確認する

**確認項目：**

- Watch側でアプリが起動する
- iPhoneアプリとWatchアプリが通信できる
- Watchで記録した運動がiOS側に反映される
- iOS側の達成状態がWatchの渦巻き表示に反映される
- 心拍数、HRV、マインドフルネス履歴が取得できる

[プロンプト例]: Apple Watchへの実機デプロイ手順を整理させる
```text
Apple Watch実機にWatchアプリをデプロイする手順を初心者向けに説明してください。
iPhoneとのペアリング、Xcodeの実行先選択、Watch App Scheme、HealthKit権限、WatchConnectivity確認を含めてください。
```

<div style="page-break-after: always;"></div>

## 第七章: テスト、デバッグ、リリース

<div style="page-break-after: always;"></div>

### 7-1. Webのテスト

```bash
npm --prefix web run type-check
npm --prefix web run build
```

[プロンプト例]: TypeScriptの型エラーを原因から解決させる
```text
Webのtype-checkでエラーが出ています。
エラー全文を読んで、原因を説明し、最小限の修正をしてください。
修正後にもう一度type-checkを実行してください。
```

<div style="page-break-after: always;"></div>

### 7-2. iOSとWatchのテスト

iOSでは、Xcodeビルド、実機でのHealthKit権限確認、モーション検知、Watch同期を確認します。

**確認項目：**

- Googleログインできる
- Firestoreに運動記録が保存される
- iOSのメイン画面でトレーニングが開始できる
- Apple Healthの歩数、心拍、HRV、睡眠が表示される
- HealthKitオフ時に摂取カロリーが時間帯別に自動反映される
- Watchの渦巻き達成マークがiOSと一致する
- 1分瞑想と3分ストレッチの履歴に心拍/HRV前後差分が表示される

[プロンプト例]: Watch実機でHRV履歴が表示されない問題のデバッグ依頼
```text
Watch実機で、瞑想完了後にHRV履歴が表示されません。
WatchHealthKitManager、WatchBreatheFlowView、WatchDashboardViewのデータの流れを調査してください。
HealthKitから値が取れていないのか、UserDefaults保存が失敗しているのか、UIに反映されていないのかを切り分けてください。
```

<div style="page-break-after: always;"></div>

### 7-3. Cursorでデバッグする流れ

1. Xcodeやnpmのエラーを確認する
2. エラー全文をCursorのClaudeへ渡す
3. Claudeに原因候補を出させる
4. 変更前に関連ファイルを読ませる
5. Cursor上で修正する
6. Git差分を確認する
7. Xcodeまたはnpmで再テストする

> **💡 EXC_BAD_ACCESS クラッシュへの対処**
>
> SwiftUIの`EXC_BAD_ACCESS (code=2)`は、多くの場合スタックオーバーフローが原因です。巨大な`@ViewBuilder`に複数の`let`宣言が入ると型チェックが深くなりすぎます。
>
> **対処法：** 重い部分を独立した`View`構造体（`struct`）に切り出すことで、SwiftUIのレンダリンググラフに評価の境界ができ、ピークスタック深度が大幅に下がります。

[プロンプト例]: SwiftUIのコンパイルエラーの原因と修正方針を説明させる
```text
このエラーを初心者向けに説明し、原因と修正方針を分けて教えてください。
修正は最小限にし、既存の動作を変えないでください。
```

<div style="page-break-after: always;"></div>

### 7-4. リリース前チェック

**App Store向けの確認項目：**

- HealthKit使用目的の説明が明確か
- 医療診断のような表現をしていないか
- Apple Watchなしでも主要機能が使えるか
- ログインできない場合の導線があるか
- ネットワーク不通時に致命的に壊れないか
- 個人情報やAPIキーをリポジトリに含めていないか

[プロンプト例]: App Store提出前のiOS/Watchアプリレビュー依頼
```text
App Store提出前の観点で、このiOS/Watchアプリをレビューしてください。
HealthKitの権限説明、医療的に誤解を招く表現、個人情報、ログ出力、APIキー混入、Watchなしユーザーの体験を重点的に確認してください。
```

[プロンプト例]: Firebase Hostingデプロイ前の確認項目をチェックリスト化させる
```text
WebアプリをFirebase Hostingへデプロイする前に確認すべき項目をチェックリスト化してください。
環境変数、manifest、アプリ名、アイコン、ビルド、Firestoreルール、認証設定を含めてください。
```

<div style="page-break-after: always;"></div>

### 7-5. GitHub Pull Requestでレビューする

Pull Requestは、変更をmainブランチへ入れる前の確認場所です。AIに実装を頼んだ場合でも、Pull Requestで人間が読み直すことで安全性が上がります。

**PR本文の基本構成：**

[プロンプト例]: PR本文の基本構成のテンプレート例
```text
## Summary
- 何を変更したか
- なぜ変更したか

## Test plan
- 実行したコマンド
- 実機で確認したこと
- 未確認のこと

## Notes
- レビューしてほしい箇所
- リスクや注意点
```

[プロンプト例]: git diffをもとにPull Request本文を自動生成させる
```text
git diffをもとにPull Request本文を作ってください。
Summary、Test plan、Notesに分けてください。
確認していないことは、確認済みのように書かないでください。
```

<div style="page-break-after: always;"></div>

### 7-6. GitHub ActionsとCI

GitHub Actionsを使うと、Pull RequestごとにWebのtype-checkやbuildを自動実行できます。

**Web用CIの例：**

```yaml
name: Web CI

on:
  pull_request:
    paths:
      - 'web/**'

jobs:
  web:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
        working-directory: web
      - run: npm run type-check
        working-directory: web
      - run: npm run build
        working-directory: web
```

[プロンプト例]: GitHub ActionsのCI設定（型チェックとビルド）を作成させる
```text
GitHub ActionsでWebのtype-checkとbuildをPull Request時に実行したいです。
このリポジトリのweb/package.jsonを確認し、適切なworkflow YAMLを提案してください。
secretsやFirebase環境変数が必要な場合は、その扱いも説明してください。
```

<div style="page-break-after: always;"></div>

## 第八章: まとめと開発ポイント

<div style="page-break-after: always;"></div>

### 8-1. Cursorを中心に据える

サンプルアプリ開発では、CursorをIDEとして中心に置きます。ファイル操作、Git差分確認、ターミナル、複数LLMの呼び出し、ドキュメント作成をCursorに集約すると、初心者でも変更内容を追いやすくなります。

<div style="page-break-after: always;"></div>

### 8-2. Claude Sonnet/Opusを使い分ける

Sonnetは日常的な実装、Opusは複雑な設計やレビューに向いています。モデルを使い分けることで、速度と品質のバランスを取りやすくなります。

<div style="page-break-after: always;"></div>

### 8-3. XcodeはデプロイとApple設定のために使う

Xcodeは、iOS/WatchアプリをAppleの実機へ届けるために必要です。Signing、Capabilities、Scheme、実機選択、Archive、WKBackgroundModesなどのCapabilityの設定はXcodeの担当です。コード編集はCursor、デプロイはXcodeという役割分担が分かりやすいです。

<div style="page-break-after: always;"></div>

### 8-4. 健康データは慎重に扱う

HealthKit、心拍数、HRV、睡眠、ストレス推定は便利ですが、医療診断ではありません。アプリ内では「傾向」「目安」「提案」として表示し、断定的な表現は避けます。

<div style="page-break-after: always;"></div>

### 8-5. 実際に使ったプロンプト集

ここでは、サンプルアプリ開発で実際に使った、またはそのまま応用できるプロンプトをまとめます。初心者は、対象画面やファイル名だけを自分のアプリに置き換えて使うとよいでしょう。

#### 全体調査

[プロンプト例]: リポジトリ全体の構成と主要機能を初心者向けに把握させる
```text
このリポジトリはWeb、iOS、Apple Watch対応のフィットネス習慣化アプリです。
まずREADME、CLAUDE.md、ios/README.md、web/README.mdを読み、構成と主要機能を把握してください。
その後、初心者にも分かるように、どのディレクトリに何があるか説明してください。
まだコード変更はしないでください。
```

[プロンプト例]: 実装前に影響ファイルと計画を整理させる（コード変更は後回し）
```text
この機能は複数ファイルに影響しそうです。
まず実装計画を出してください。
対象ファイル、データモデル、UI変更、同期処理、テスト観点を分けて整理してください。
私が確認するまでコード変更はしないでください。
```

#### Web

[プロンプト例]: Webダッシュボードのカード表示変更（MIND・FOOD非表示、DIET拡大）
```text
Webのダッシュボードで、MINDカードとFOODカードを非表示にしてください。
DIETカードは横幅いっぱいにし、なるべく多くの情報を出してください。
カードを押すとGOAL設定画面へ移動してください。
```

[プロンプト例]: アプリ名の全面変更（UI・設定ファイル・localStorage互換対応）
```text
Webのアプリ名をFitingoに全面的に変更してください。
UI文言、HTML title、manifest、package.json、README、localStorageキーを確認してください。
旧localStorageキーからの互換読み込みも入れてください。
```

#### iOS

[プロンプト例]: iOSのGOALページにトレーニング開始ボタンを追加させる
```text
iOSのGOALページで、今日のアクティビティカードの上にFitingoトレーニングボタンを追加してください。
ボタンはシンプルでよく、タップしたらトレーニング画面に遷移して開始できるようにしてください。
```

[プロンプト例]: ページ名とヘッダー表示のリブランディング依頼
```text
FITページの名称は全体的にROUTINにしてください。
ヘッダー表示はRoutingoにし、Routinまでを炎の赤色にしてください。
関連するヘルプ文言やタブ名も確認してください。
```

#### HealthKit

[プロンプト例]: 食事カロリー入力欄の追加とApple Health連携の実装
```text
ダイエット目標の摂取カロリー目標に入力欄を設けて、2000kcalをデフォルトにしてください。
Apple Healthで計測をONにしたら、実際の摂取カロリーはApple Healthの登録を使ってください。
OFFの場合は、1日の摂取目標を時間帯別に配分し、その時間になったら自動的にそのカロリーを取得したようにしてください。
```

[プロンプト例]: MINDページへのHRV7日平均グラフ追加
```text
iOSのMINDページで、3分ストレッチの下に過去7日のHRV平均グラフを表示して。
20msの赤い基準線を入れて。HealthKitManagerに7日平均取得メソッドを追加し、
既存のSwiftUIデザインに合わせて。
```

#### Watch

[プロンプト例]: WatchとiOSのタスク達成状態の同期問題を修正させる
```text
Watchで、渦巻き表示の達成済みマークがiOSの達成済みとそろっていません。
iOSの達成状態を正として、Watchの達成済み表示が必ず同期するようにしてください。
meal、drink、mind-input、mindfulness、stretch、trainingは別々に扱ってください。
```

[プロンプト例]: 瞑想・ストレッチ完了時の心拍とHRV記録と履歴表示
```text
Watchで、1分瞑想と3分ストレッチの完了時に心拍数とHRVの前後差分を保存して。
履歴には心拍、HRV、ストレススコアの前後と改善/上昇/維持を表示して。
```

#### GitHub

[プロンプト例]: Pull Request本文案をClaudeに作成させる
```text
この変更をGitHubのPull Requestに出したいです。
git statusとgit diff --statを確認し、変更内容をSummaryとTest planに分けてPR本文案を作ってください。
まだcommitやpushはしないでください。
```

[プロンプト例]: PRレビューコメントへの対応方針の分類
```text
Pull Requestのレビューコメントに対応します。
コメント内容を読み、対応が必要なもの、質問として返すもの、対応しない理由を書くものに分類してください。
その後、対応が明確なものだけ修正してください。
```

#### ドキュメント

[プロンプト例]: 実装内容を技術書の1章として初心者向けに説明させる
```text
今回の実装内容を、初心者向けの技術書の1章として説明してください。
何を作ったか、なぜ必要か、どのファイルが関係するか、Claudeへ渡したプロンプト例も含めてください。
```

<div style="page-break-after: always;"></div>

### 8-6. Kindle化のための素材準備

MarkdownからEPUBへ変換する例です。

```bash
pandoc docs/cursor-claude-code-ios-app-book.md \
  -o cursor-claude-ios-app-book.epub \
  --metadata title="CursorとClaudeで作るiOSアプリの作り方" \
  --metadata lang=ja-JP
```

**スクリーンショットのフォルダ構成（本書で使用）：**

[プロンプト例]: スクリーンショットのフォルダ構成（本書使用）
```text
docs/screenshots/
├── main/          # ROUTIN・ダッシュボード・FOOD・TOMO・ウィジェット
│   ├── IMG_3498.jpg   ← ROUTINマンダラメイン
│   ├── IMG_3499.jpg   ← ROUTINボタン群
│   ├── IMG_3500.jpg   ← 時間帯別記録（朝）
│   ├── IMG_3501.jpg   ← トレーニング計測
│   ├── IMG_3502.jpg   ← FOODページ
│   ├── IMG_3503.jpg   ← フォトログ選択
│   ├── IMG_3504.jpg   ← フォトログAI分析
│   ├── IMG_3505.jpg   ← FOODフィード
│   ├── IMG_3506.jpg   ← FIT・FOOD・MINDサマリー
│   ├── IMG_3507.jpg   ← ポイント・90日チャレンジ
│   ├── IMG_3530.jpg   ← TOMOページ
│   └── IMG_3535.PNG   ← ホームウィジェット
├── fit/           # FITページ詳細
│   ├── IMG_3508.jpg   ← FIT目標プラン・体重推移
│   ├── IMG_3509.jpg   ← FITアクティビティ・カロリー収支
│   ├── IMG_3510.jpg   ← FIT週間実績グラフ
│   └── IMG_3511.jpg   ← FITカロリーグラフ
├── mind/          # MINDページ
│   ├── IMG_3516.jpg   ← MINDストレスレベル・瞑想
│   ├── IMG_3517.jpg   ← MINDHRV推移グラフ
│   └── IMG_3518.jpg   ← MINDまとめ・ストレッチ
├── setup/         # 設定ページ
│   ├── IMG_3522.jpg   ← テーマ・メニュー設定
│   ├── IMG_3523.jpg   ← 毎日の目標設定
│   ├── IMG_3524.jpg   ← 曜日毎の目標
│   └── IMG_3525.jpg   ← 時間帯別の目標
└── watch/         # Apple Watch画面
    ├── incoming-ECA98EF7-*.PNG  ← Watch心拍・HRV・マインド
    ├── incoming-193610BE-*.PNG  ← Watchアクションカード
    ├── incoming-4B24B149-*.PNG  ← Watchトレーニング計測
    └── incoming-9881886A-*.PNG  ← Watch水分記録
```

<div style="page-break-after: always;"></div>

## 終わりに

サンプルアプリの開発を通じて見えてくるのは、AI開発の本質は「速くコードを書くこと」だけではないということです。CursorをIDEとして使い、Claude Sonnet/Opusをそこから呼び出し、XcodeでiPhoneとApple Watchへデプロイする。この役割分担を作ることで、Web、iOS、Watch、Firebase、Apple Health、Motion Sensorのように領域が広いアプリでも、一つずつ前に進められます。

良いアプリにするためには、人間の判断が必要です。どの健康データを見せるか。どのメッセージを一つだけ出すか。どのタイミングで通知するか。どこまで自動化し、どこに手動入力を残すか。これらはプロダクト設計の問題です。

CursorとClaudeを使えば、一人でもかなり大きなアプリを作れます。ただし、成功の鍵はAIに丸投げすることではありません。小さく依頼し、差分を確認し、実機で試し、また改善する。その繰り返しです。

最後に、AI時代の開発で最も大切な姿勢を一つ挙げるなら、**「作りながら学ぶ」** ことです。CursorとClaudeは、その学びの速度を大きく上げてくれる相棒になります。

---

*本書に登場するFitingo（kfit）は個人開発プロジェクトです。スクリーンショットはすべて実機での動作画面です。*
