# CursorとClaudeで作るiOSアプリの作り方

Web・iOS・Apple Watch対応フィットネスアプリ「Fitingo」開発解説書  
Kindle原稿ドラフト v0.5

![Fitingo mascot](../web/public/mascot.png)

> 本書は、Cursorを開発環境の中心に置き、CursorからClaude Sonnet/OpusなどのLLMを呼び出しながら、Web・iOS・Apple Watch対応アプリを作る方法をまとめた初心者向け解説書です。  
> Xcodeは主にiOS/Watchアプリのビルド、署名、実機デプロイ、App Store提出準備に使う前提で説明します。

<div style="page-break-after: always;"></div>

## 目次

- はじめに
- 第一章: AI時代のアプリ開発
- 第二章: アプリの全体像
- 第三章: 開発のための環境準備
- コラム1: LLM比較、どれが最もコスパがいい？
- 第四章: Webアプリ開発
- コラム2: iPhoneからClaude CodeとGitHubで開発を続ける
- 第五章: iOSアプリ開発
- 第六章: Apple Watchアプリ開発
- 第七章: テスト、デバッグ、リリース
- 第八章: まとめと開発ポイント
- 終わりに

<div style="page-break-after: always;"></div>

## はじめに

個人でアプリを作るハードルは、以前より大きく下がりました。理由の一つは、CursorのようなAI統合IDEと、Claude Sonnet/Opusのような高性能LLMを組み合わせて使えるようになったことです。

本書では、Cursorを開発の中心に置きます。ファイル操作、コード編集、検索、ターミナル、Git連携、差分確認、複数LLMの切り替えをCursor上で行い、Claude Sonnet/OpusをCursorから呼び出して設計相談、実装、レビュー、ドキュメント作成を進めます。

Xcodeは、iOS/Watchアプリの開発で欠かせないツールですが、本書では「コードを書く中心」ではなく「Appleプラットフォームへビルド・署名・デプロイするための環境」として扱います。SwiftUIコードの編集や調査はCursorで行い、実機起動、Capabilities設定、Signing、Archive、App Store提出準備はXcodeで行う、という役割分担です。

題材にするのは、フィットネス習慣化アプリ「Fitingo」です。Fitingoは、Web、iOS、Apple Watchに対応し、運動記録、Apple Health連携、モーションセンサーによるレップ計測、HRVストレス分析、食事・水分管理、Watchの渦巻き目標表示、Firebase同期などを含みます。

![スクリーンショット: CursorでFitingoのコードを開いている画面](screenshots/01-cursor-project.png)

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

ただし、AIは万能ではありません。アプリの方向性、ユーザー体験、健康データの扱い、ストア審査に関わる表現などは、人間が判断する必要があります。AI時代の開発では、人間がプロダクトの意思決定を行い、AIが実装と調査を支援する役割分担が重要です。

<div style="page-break-after: always;"></div>

### 1-2. Cursorを開発環境の中心にする

Cursorは、AI機能を備えたIDEです。Visual Studio Codeに近い操作感で、プロジェクトフォルダを開き、ファイルを編集し、検索し、ターミナルを使い、Git差分を確認しながら、AIに相談できます。

本書では、Cursorを次の用途で使います。

- プロジェクト全体を開く
- ファイルを検索する
- Swift、TypeScript、Markdownを編集する
- ターミナルでnpmやgitコマンドを実行する
- Git差分を確認する
- Claude Sonnet/Opusなど複数LLMを切り替えて使う
- AIに実装、レビュー、説明、ドキュメント作成を依頼する

Cursorの強みは、プロジェクト全体を見ながらAIと会話できることです。開いているファイルだけでなく、関連ファイルを検索し、コードの流れを読んだうえで回答できます。Fitingoのように、Web、iOS、Watchが同じリポジトリにある場合、横断的な調査に向いています。

Cursorでよく使う依頼です。

```text
このファイルの役割を初心者向けに説明してください。
特に、@StateObject、@Published、Task、async/awaitがどう使われているか知りたいです。
```

```text
この機能はWeb、iOS、Watchに影響しそうです。
関連ファイルを調査し、どこを変更すべきか整理してください。
まだコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 1-3. Claude Sonnet/OpusをCursorから使う

本書では、Claudeを主にCursorから呼び出して使います。つまり、ターミナルで独立したClaude Codeを使うことを前提にするのではなく、Cursorのチャットやエージェント機能からClaude Sonnet/Opusを選び、開いているリポジトリの文脈を渡して作業します。

SonnetとOpusは、ざっくり次のように使い分けます。

- Sonnet: 日常的な実装、調査、軽いリファクタリング、エラー修正。
- Opus: 大きな設計判断、複雑なバグ調査、アーキテクチャ整理、長文ドキュメント作成。

たとえば、単純なUI文言変更やTypeScriptエラー修正はSonnetで十分です。一方、iOSとWatchの同期ずれ、HealthKitとUserDefaultsとWatchConnectivityをまたぐ問題などは、Opusに調査と設計を頼むと安定します。

Cursorでモデルを選ぶときの考え方です。

```text
この変更は小さなUI修正なので、Sonnetで実装してください。
既存のデザインに合わせ、不要なリファクタリングは避けてください。
```

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

- 対象画面または対象ファイル
- 実現したいユーザー体験
- データの取得元
- 保存先
- 表示条件
- やってほしくないこと
- 実装後に確認してほしいこと

良い例です。

```text
iOSのMINDページで、今日のまとめの3分ストレッチの下に、過去7日のHRV平均グラフを表示してください。
20msの赤い基準線を入れてください。
HealthKitManagerに7日平均を取得する処理を追加し、MindViewで表示してください。
既存のSwiftUIデザインに合わせ、不要なリファクタリングは避けてください。
```

作業前に入れる制約です。

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

初心者が最初に覚えるべきGitHub連携は、次の5つです。

- リポジトリをGitHubに作る。
- ローカルのCursorでそのリポジトリを開く。
- 変更をGitで確認する。
- Pull Requestで変更内容を説明する。
- CIやレビュー結果を見て修正する。

CursorではGit差分を見ながらClaudeに修正を依頼できます。たとえば、Pull Requestで指摘された内容をClaudeに読ませ、関連ファイルを修正させることができます。ただし、最終的にマージするかどうかは人間が判断します。

GitHub連携の調査をClaudeに依頼するプロンプトです。

```text
このプロジェクトをGitHubで管理します。
初心者向けに、clone、branch作成、commit、push、Pull Request作成、レビュー対応、mergeまでの流れを説明してください。
Cursor上でどの操作を確認できるかも含めてください。
```

```text
現在の変更をPull Requestに出す前提でレビューしてください。
PR本文に書くべきSummary、Test plan、注意点を作ってください。
変更内容を誇張せず、実際に確認したことと未確認のことを分けてください。
```

<div style="page-break-after: always;"></div>

### 1-7. `CLAUDE.md` と `rules.md` の役割

AI開発では、毎回同じ注意事項をチャットに書くのは大変です。そこで、プロジェクト内にAI向けのルールファイルを置きます。代表的なのが `CLAUDE.md` や `rules.md` です。

`CLAUDE.md` は、Claudeに読ませるプロジェクト説明書です。何のアプリか、技術スタックは何か、よく使うコマンドは何か、コミットやプッシュのルールは何か、触ってはいけないファイルは何かを書きます。

`rules.md` は、より一般的な開発ルールやコーディング規約を書くファイルとして使えます。CursorのRules機能やプロジェクト固有のAIルールと組み合わせると、AIが毎回同じ前提を理解しやすくなります。

`CLAUDE.md` に書くとよい項目です。

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

`rules.md` に書くとよい項目です。

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

Claudeにルール整備を依頼するプロンプトです。

```text
このプロジェクトのCLAUDE.mdを改善したいです。
README、ios/README.md、web/README.mdを読み、AIが開発時に参照すべきルールを整理してください。
コミット、プッシュ、HealthKit、WatchConnectivity、Firebase、Web type-checkの注意点を含めてください。
```

```text
Cursor Rulesまたはrules.mdに書くべき開発ルールを提案してください。
初心者がAIに安全に作業を頼めるように、禁止事項、確認事項、よく使うコマンド、レビュー観点を含めてください。
```


<div style="page-break-after: always;"></div>

## 第二章: アプリの全体像

<div style="page-break-after: always;"></div>

### 2-1. Fitingoとは

Fitingoは、「毎日の運動を習慣にする」ことを目的にしたフィットネスアプリです。Duolingoのように、短い達成感、連続記録、ポイント、キャラクター表示を使い、ユーザーが毎日少しずつ体を動かすきっかけを作ります。

主な構成は次の3つです。

- Webアプリ: React + TypeScript + Vite。手動記録、ダッシュボード、週間目標、90日チャレンジ、設定画面を担当します。
- iOSアプリ: SwiftUI。Apple Health、Core Motion、写真ログ、食事目標、MIND、ROUTIN、FITページを担当します。
- Apple Watchアプリ: SwiftUI for watchOS。運動のクイック記録、目標の渦巻き表示、心拍/HRV、瞑想/ストレッチを担当します。

![スクリーンショット: Webダッシュボード](screenshots/02-web-dashboard.png)

![スクリーンショット: iOSダッシュボード](screenshots/03-ios-dashboard.png)

![スクリーンショット: Watchダッシュボード](screenshots/04-watch-dashboard.png)

<div style="page-break-after: always;"></div>

### 2-2. 技術スタック

```text
Web:
- React 18
- TypeScript
- Vite
- Tailwind CSS
- Firebase Authentication
- Firestore

iOS:
- SwiftUI
- HealthKit
- Core Motion
- Firebase iOS SDK
- WidgetKit

Apple Watch:
- SwiftUI for watchOS
- HealthKit
- Core Motion
- WatchConnectivity
- Haptics

開発環境:
- Cursor
- Claude Sonnet/Opus
- Xcode
- Git
- Node.js / npm
- CocoaPods
- Firebase CLI
```

<div style="page-break-after: always;"></div>

### 2-3. データの流れ

```text
Webで記録
  -> Firestore
  -> iOSが読み込み
  -> DashboardやHistoryに表示

iOSで運動記録
  -> Firestoreへ保存
  -> Webに反映
  -> Watchへ今日の進捗を同期

Watchで運動完了
  -> WatchConnectivityでiOSへ送信
  -> iOSがFirestoreへ保存
  -> Webにも反映

Apple Health
  -> iOS/WatchがHealthKitから取得
  -> Dashboard、MIND、FIT、Watch履歴に表示
```

Firestoreはクラウド同期、HealthKitは健康データ、WatchConnectivityはiPhoneとWatchの近距離同期を担当します。

<div style="page-break-after: always;"></div>

### 2-4. 全体像をClaudeに説明させるプロンプト

```text
このプロジェクトは、Web、iOS、Apple Watch対応のフィットネス習慣化アプリです。
README、CLAUDE.md、ios/README.md、web/README.mdを読んで、全体像を初心者向けに説明してください。
まだコード変更はしないでください。
```

```text
このリポジトリの主要ディレクトリを調査し、Web、iOS、Watch、Firebaseがどのように分かれているか説明してください。
データ同期の流れも、FirestoreとWatchConnectivityに分けて説明してください。
```

<div style="page-break-after: always;"></div>

## 第三章: 開発のための環境準備

<div style="page-break-after: always;"></div>

### 3-1. 必要なもの

FitingoのようなWeb、iOS、Apple Watch対応アプリを作るには、次の環境が必要です。

- macOS
- Cursor
- Claude Sonnet/Opusを利用できるCursor設定
- Xcode
- Node.js
- npm
- CocoaPods
- Firebase CLI
- Git
- iPhone実機
- Apple Watch実機

HealthKitやCore Motion、Apple Watch連携はシミュレータだけでは確認しにくいため、できれば実機を用意します。特に心拍数、HRV、Watchのモーション検知は実機確認が重要です。

<div style="page-break-after: always;"></div>

### 3-2. Cursorのセットアップ

Cursorは公式サイトからmacOS版をダウンロードしてインストールします。インストール後、アカウントでサインインし、`File > Open Folder` からプロジェクトフォルダを開きます。

Fitingoの場合は、次のフォルダを開きます。

```text
~/Git/kfit
```

Cursorを使う準備では、次を確認します。

- プロジェクトルートを開いている。
- CursorのチャットでClaude Sonnet/Opusを選べる。
- ターミナルがCursor内で開ける。
- Git差分がCursor上で確認できる。
- ファイル検索が使える。
- `.md`、`.swift`、`.tsx` を編集できる。

Cursorを使い始めるときのプロンプトです。

```text
このリポジトリを開きました。
まずREADME、CLAUDE.md、ios/README.md、web/README.mdを読み、初心者向けに開発手順を説明してください。
まだコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 3-3. CursorのGit連携

Cursorでは、Git差分を見ながらAIに変更を依頼できます。初心者にとって重要なのは、AIが変更したファイルをそのまま信じるのではなく、差分を読むことです。

作業前に確認するコマンドです。

```bash
git status
git diff --stat
```

CursorのGitビューでは、変更ファイルを一覧し、どの行が追加・削除されたか確認できます。AIに依頼した後は、必ず差分を見て、意図しないファイルが変更されていないか確認します。

Claudeへ渡すプロンプトです。

```text
作業前にgit statusを確認し、未コミット変更を把握してください。
ユーザーが変更した可能性のあるファイルは戻さないでください。
今回の作業に関係するファイルだけを編集してください。
```

<div style="page-break-after: always;"></div>

### 3-4. Cursorで複数LLMを使う

Cursorでは、Claude Sonnet/Opus以外のモデルも選べる場合があります。重要なのは、作業内容に応じてモデルを使い分けることです。

- 軽い修正: 速いモデルまたはSonnet
- 複数ファイル調査: Sonnet
- 複雑な設計・レビュー: Opus
- 長文ドキュメント: Opus
- 実装後の説明: Sonnet

プロンプト例です。

```text
この変更は小さなUI調整なので、Sonnetで既存の実装に合わせて修正してください。
```

```text
この問題は複数プラットフォームにまたがるため、Opusで広く調査してください。
まず原因候補を整理し、私が確認するまでコード変更はしないでください。
```

<div style="page-break-after: always;"></div>

### 3-5. Xcodeの役割

本書では、コード編集の中心はCursorです。Xcodeは主に次の用途で使います。

- iOSアプリを実機にインストールする。
- Apple Watchアプリを実機にインストールする。
- Signing & Capabilitiesを設定する。
- HealthKit、Watch App、Push NotificationsなどのCapabilityを確認する。
- Schemeを選んでビルドする。
- ArchiveしてApp Store提出準備を行う。
- 実機ログやクラッシュを確認する。

つまり、Swiftコードを書く場所としてXcodeを使っても構いませんが、本書ではCursorで編集し、Xcodeでデプロイする役割分担を基本にします。

![スクリーンショット: Xcodeでkfit.xcworkspaceを開いた画面](screenshots/05-xcode-workspace.png)

<div style="page-break-after: always;"></div>

### 3-6. XcodeにClaudeを直接連携する方法

基本はCursorからClaudeを使いますが、Xcodeで作業中にClaudeを使いたい場合もあります。代表的な方法は次の3つです。

1. Cursorで同じリポジトリを開き、Xcodeと並べて使う。
2. Xcodeのエラーや該当コードをコピーして、CursorのClaudeに貼って相談する。
3. Claudeのデスクトップアプリやブラウザを横に開き、Xcodeのエラー内容を渡す。

実務上は、1つ目の「XcodeとCursorを同じリポジトリで並行利用する」方法が最も安定します。コード編集はCursor、ビルドと実機起動はXcode、という分担です。

XcodeエラーをClaudeに渡すプロンプトです。

```text
Xcodeで次のSwiftエラーが出ています。
エラー内容と該当ファイルをもとに、原因と最小限の修正案を教えてください。
UIの見た目は変えないでください。
```

<div style="page-break-after: always;"></div>

### 3-7. Xcodeのセットアップ

XcodeはApp Storeからインストールします。初回起動時に追加コンポーネントのインストールを求められる場合があります。

確認コマンドです。

```bash
xcode-select -p
xcodebuild -version
```

Command Line Toolsが未設定の場合は、次のコマンドを使います。

```bash
xcode-select --install
```

Fitingoでは、iOSプロジェクトを次のように開きます。

```bash
cd ios
pod install
open kfit.xcworkspace
```

Xcodeで確認する項目です。

- iOSアプリターゲットにHealthKit Capabilityがある。
- Watch Appターゲットが正しく含まれている。
- Signing & CapabilitiesでTeamが設定されている。
- `GoogleService-Info.plist` がiOSターゲットに含まれている。
- HealthKitやカメラなどの権限説明文が `Info.plist` に入っている。
- 実機iPhoneとApple Watchでビルドできる。

<div style="page-break-after: always;"></div>

### 3-8. iPhone実機の準備

iPhoneにアプリをデプロイするには、次の準備をします。

1. iPhoneをMacにUSB接続する。
2. iPhone側で「このコンピュータを信頼」を選ぶ。
3. Xcodeの上部デバイス選択で接続したiPhoneを選ぶ。
4. XcodeのSigning & CapabilitiesでTeamを設定する。
5. Bundle Identifierが一意であることを確認する。
6. 必要なCapabilityを有効にする。
7. Runボタンで実機へインストールする。

実機で確認する設定です。

- 設定アプリで開発者モードが有効か。
- Healthアプリへのアクセス許可が出るか。
- Firebaseログインができるか。
- ネットワーク接続があるか。
- 通知やヘルスケア権限の許可文言が自然か。

Claudeへのプロンプトです。

```text
iPhone実機にこのiOSアプリをデプロイする手順を初心者向けに整理してください。
XcodeのScheme選択、Team設定、Bundle Identifier、HealthKit Capability、実機側の信頼設定を含めてください。
```

<div style="page-break-after: always;"></div>

### 3-9. Apple Watch実機の準備

Apple Watchアプリを実機にデプロイするには、iPhoneとApple Watchがペアリングされている必要があります。

準備手順です。

1. iPhoneとApple Watchをペアリングする。
2. Apple Watchのロックを解除して腕に装着する。
3. iPhoneとApple Watchが近くにある状態にする。
4. XcodeでWatch Appを含むSchemeを選ぶ。
5. 実行先として、ペアリング済みのApple Watchを選ぶ。
6. RunしてWatchへインストールする。

Watchで確認する設定です。

- Watch側でアプリがインストールされているか。
- HealthKit権限が許可されているか。
- 心拍数、HRV、ワークアウト、マインドフルネスのデータが取得できるか。
- WatchConnectivityでiPhoneと通信できるか。
- 1分瞑想、3分ストレッチ、運動記録が実機で動くか。

Claudeへのプロンプトです。

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

```text
Firebaseのセットアップ手順を初心者向けに整理してください。
Webの.env.local、iOSのGoogleService-Info.plist、Googleログイン、Firestoreルール、Firebase Hostingを分けて説明してください。
```


<div style="page-break-after: always;"></div>

### 3-12. GitHub連携のセットアップ

GitHubを使うと、ローカルの作業をクラウドに保存し、履歴を管理し、Pull Requestで変更内容を確認できます。AIにコードを書かせるほど、GitHubで差分を管理することが重要になります。

基本手順です。

```bash
# GitHub上でリポジトリを作成したあと
git remote add origin git@github.com:your-name/kfit.git
git branch -M main
git push -u origin main
```

既存リポジトリを取得する場合です。

```bash
git clone git@github.com:your-name/kfit.git
cd kfit
```

CursorでGitHub連携を使う流れです。

1. GitHubからリポジトリをcloneする。
2. Cursorでフォルダを開く。
3. 作業用ブランチを作る。
4. Claudeに実装を依頼する。
5. CursorのGitビューで差分を見る。
6. type-checkやXcode実機確認を行う。
7. commitする。
8. pushする。
9. GitHubでPull Requestを作る。

ブランチ名の例です。

```text
feature/watch-hrv-history
fix/ios-healthkit-refresh
docs/cursor-claude-book
```

ClaudeにGitHub連携を依頼するプロンプトです。

```text
この変更をGitHubのPull Requestに出したいです。
git statusとgit diff --statを確認し、変更内容をSummaryとTest planに分けてPR本文案を作ってください。
まだcommitやpushはしないでください。
```

```text
GitHubのIssueから作業を始めます。
Issue本文を読み、要件、影響範囲、実装ステップ、テスト観点を整理してください。
実装前に関連ファイルを調査してください。
```

```text
Pull Requestのレビューコメントに対応します。
コメント内容を読み、対応が必要なもの、質問として返すもの、対応しない理由を書くものに分類してください。
その後、対応が明確なものだけ修正してください。
```

<div style="page-break-after: always;"></div>

### 3-13. GitHubで安全にcommit/pushする

AIに実装を頼んだあと、すぐにcommitするのは危険です。必ず差分を確認します。

確認コマンドです。

```bash
git status
git diff --stat
git diff
```

コミットメッセージは、何をしたかだけでなく、なぜ必要だったかが分かるようにします。

```text
Add Watch HRV impact history

Record heart rate and HRV before and after mindfulness sessions so users can review stress changes over time.
```

Claudeにコミット前確認を依頼するプロンプトです。

```text
コミット前レビューをしてください。
変更ファイル、変更理由、リスク、テスト状況、コミットメッセージ案を出してください。
.env、APIキー、個人情報が含まれていないかも確認してください。
```

```text
この差分から適切なコミットメッセージを3案出してください。
短く、命令形で、なぜ必要な変更かが分かるものにしてください。
```

<div style="page-break-after: always;"></div>

### 3-14. `CLAUDE.md` と `rules.md` を育てる

AI開発では、ルールファイルを一度書いて終わりにしません。プロジェクトが育つほど、よく起きるミス、よく使うコマンド、注意すべき設計判断が増えます。それらを `CLAUDE.md` や `rules.md` に追記します。

Fitingoで書いておくとよいルール例です。

```text
- HealthKitの値は権限未許可や未取得を正常系として扱う。
- WatchConnectivityではiOS側のTimeSlotManagerを正とする。
- Watch UIは小さい画面を前提に、文字量を増やしすぎない。
- Webのアプリ名変更ではmanifest、index.html、package.json、localStorageキーも確認する。
- iOS/Watchの実機確認が必要な変更は、最終報告で「Xcodeビルド未実行」など未確認事項を書く。
```

ルール更新をClaudeに頼むプロンプトです。

```text
今回の実装で得られた注意点を、CLAUDE.mdまたはrules.mdに追記する案としてまとめてください。
特に、次回同じミスを防ぐための具体的なルールにしてください。
```



<div style="page-break-after: always;"></div>

## コラム1: LLM比較、どれが最もコスパがいい？

Cursorでは、Claudeだけでなく、OpenAIやGemini系のモデルを選べる場合があります。モデルは「一番賢いものを常に使う」のではなく、作業内容に合わせて選ぶとコスパが良くなります。

ここでの価格は、2026年5月時点で公開されているAPI価格を目安にしたものです。実際のCursor内の利用料金やプランは、Cursor側の料金体系、契約プラン、キャッシュ、バッチ、プロモーション、為替によって変わります。最新の正確な価格は、各社の公式価格ページを確認してください。

### 比較の前提

LLMのコスパは、単純な1トークンあたりの価格だけでは決まりません。開発では、次の観点を合わせて見ます。

- 実装の正確さ
- 長いコードベースを読めるか
- SwiftやTypeScriptの修正が得意か
- 指示に従う安定性
- 出力の長さと品質
- 何回やり直しが必要か
- 入力価格と出力価格
- キャッシュやバッチ割引の有無

安いモデルでも、何度も修正が必要なら総コストは上がります。高いモデルでも、一回で正しく設計できるなら結果的に安いことがあります。

<div style="page-break-after: always;"></div>

### Claude系: Cursorでの本命候補

Claudeは、長いコードの読解、既存設計に合わせた修正、文章化、レビューに強い傾向があります。FitingoのようにSwiftUI、WatchConnectivity、HealthKit、Reactが混ざるプロジェクトでは、Claude Sonnetを普段使い、Opusを難しい設計やレビューに使うのが扱いやすいです。

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 | コスパ判断 |
|---|---|---:|---|---|
| Claude Opus 4.7 | 最新・高性能 | 入力 $5 / 出力 $25 | 複雑な設計、長文ドキュメント、難しいバグ調査 | 高いが失敗コストを下げたい場面で有効 |
| Claude Sonnet 4.6 | 普及・標準 | 入力 $3 / 出力 $15 | 日常的な実装、複数ファイル調査、レビュー | Cursor開発の主力。品質と速度のバランスが良い |
| Claude Haiku 4.5 | 軽量・安価 | 入力 $1 / 出力 $5 | 要約、分類、単純な文言変更 | 大量処理や軽作業向き |

Claudeを使うと効率が良い場面です。

- SwiftUIの大きなViewを読み解く。
- HealthKitやWatchConnectivityの影響範囲を調査する。
- `CLAUDE.md` や技術書原稿を書く。
- Pull Requestのレビュー観点を洗い出す。
- 既存設計を壊さずに修正する。

Claudeを使うプロンプト例です。

```text
この問題はiOS、Watch、HealthKit、WatchConnectivityをまたぎます。
Opusで関連ファイルを広く調査し、原因候補と修正方針を出してください。
まだコード変更はしないでください。
```

```text
この変更は通常のSwiftUI UI修正なので、Sonnetで既存実装に合わせて最小限に実装してください。
変更後に関連ファイルの診断も確認してください。
```

<div style="page-break-after: always;"></div>

### OpenAI系: コード生成と軽量モデルの選択肢

OpenAI系は、APIではGPT-4.1ファミリーやGPT-4o、reasoning系のo3などが使われます。Cursorで選べるモデルはプランや時期によって変わりますが、一般的には「高速な軽量モデル」「標準モデル」「reasoningモデル」を使い分けます。

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 | コスパ判断 |
|---|---|---:|---|---|
| GPT-4.1 | 最新API系・コード強化 | 入力 $2 / 出力 $8 | コード生成、指示追従、長文コンテキスト | Claude Sonnetより安く、コード作業の候補 |
| GPT-4.1 mini | 普及・低価格 | 入力 $0.40 / 出力 $1.60 | 軽い修正、要約、単純な変換 | かなり安い。大量の軽作業向き |
| GPT-4.1 nano | 超軽量 | 入力 $0.10 / 出力 $0.40 | 分類、短い文言生成、単純抽出 | 最安級。難しい実装には不向き |
| GPT-4o | 普及・マルチモーダル | 入力 $2.50 / 出力 $10 | 画像を含む相談、一般的な開発補助 | 汎用性が高いが、コード専用なら4.1も候補 |
| o3 | reasoning | 入力 $2 / 出力 $8 | 複雑な推論、設計判断、分析 | 難問向き。速度や出力量に注意 |

OpenAI系を使うと効率が良い場面です。

- 軽量モデルで大量の文言修正を行う。
- WebのTypeScriptエラーを素早く見る。
- 画像やUIスクリーンショットを含めて相談する。
- コード生成を安く大量に試す。

OpenAI系に向いたプロンプト例です。

```text
このReactコンポーネントの文言だけを変更してください。
ロジックは変えず、差分を最小限にしてください。
```

```text
このスクリーンショットのUIを見て、ユーザーが迷いそうな箇所を指摘してください。
実装変更ではなく、改善案だけ出してください。
```

<div style="page-break-after: always;"></div>

### Gemini系: 低コスト・長文・Google連携が強い

Gemini系は、価格面で強い選択肢です。特にGemini 2.5 Flashは、入力 $0.30 / 出力 $2.50 程度の低価格で、軽い調査や大量処理に向いています。Gemini 2.5 Proは、長いコンテキストや複雑な推論を比較的安く扱える候補です。

| モデル | 位置づけ | 目安価格/100万token | 向いている作業 | コスパ判断 |
|---|---|---:|---|---|
| Gemini 2.5 Pro | 高性能・長文 | 入力 $1.25 / 出力 $10（<=200K） | 長い資料、設計比較、複雑な調査 | 入力が安く、長文読解で強い候補 |
| Gemini 2.5 Flash | 普及・高速・安価 | 入力 $0.30 / 出力 $2.50 | 要約、分類、軽いコード調査 | コスパが非常に良い。日常の軽作業向き |
| Gemini Flash-Lite系 | 超低価格 | 入力 $0.10前後 / 出力 $0.40前後の系統 | 大量分類、抽出、単純変換 | 大規模な定型処理向き |

Geminiを使うと効率が良い場面です。

- 長いドキュメントを安く要約する。
- 多数のIssueやレビューコメントを分類する。
- 仕様比較や市場調査を行う。
- コード以外の文章処理を大量に行う。

Gemini系に向いたプロンプト例です。

```text
この長い仕様メモを、要件、未決事項、実装タスク、テスト観点に分類してください。
コード変更は不要です。
```

```text
複数のレビューコメントを、すぐ対応、仕様確認、対応不要、質問に分類してください。
それぞれ理由も短く書いてください。
```

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
| スクリーンショットを見たUI相談 | GPT-4o / Gemini Pro | マルチモーダル相談に向く |

### 結論: 最初はSonnet中心、重い判断だけOpus

この本のようにCursorを中心に開発する場合、最初のおすすめはClaude Sonnet中心です。普段の実装、調査、レビュー、説明のバランスが良く、既存コードに合わせる力もあります。

複雑な設計、失敗すると手戻りが大きい変更、長いドキュメント作成ではOpusを使います。大量の軽作業や要約は、Gemini FlashやGPT-4.1 mini/nanoのような安価なモデルを使うとコストを抑えられます。

コスパを最大化する基本方針です。

```text
1. まず安い/標準モデルで調査する。
2. 難しければ高性能モデルに切り替える。
3. 実装後は別モデルでレビューする。
4. 長い共通文脈はCLAUDE.mdやrules.mdに移す。
5. 同じ説明を毎回プロンプトに書かない。
```

### 参考価格ソース

価格は変わるため、最終的には公式ページを確認してください。

- Anthropic Claude pricing: https://platform.claude.com/docs/en/about-claude/pricing
- OpenAI API pricing: https://developers.openai.com/api/docs/pricing
- Google Gemini API pricing: https://ai.google.dev/gemini-api/docs/pricing


<div style="page-break-after: always;"></div>

## 第四章: Webアプリ開発

<div style="page-break-after: always;"></div>

### 4-1. Webアプリの役割

FitingoのWebアプリは、PCやスマホブラウザから記録を確認・編集できる入口です。iOSアプリほどHealthKitやモーションセンサーに深くは関わりませんが、ダッシュボード、手動記録、週間目標、90日チャレンジ、設定画面を提供します。

Web版は、React + TypeScript + Viteで作ります。Cursor上でTypeScriptファイルを編集し、Cursor内ターミナルで開発サーバーや型チェックを実行します。

<div style="page-break-after: always;"></div>

### 4-2. Webの構成

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

![スクリーンショット: Fitingo WebのDIETカード](screenshots/06-web-diet-card.png)

Claudeへのプロンプトです。

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

Claudeへのプロンプトです。

```text
Webアプリ名をFitingoに全面変更してください。
画面表示、index.html、manifest.json、package.json、README、localStorageキーを確認してください。
localStorageキーは旧キーから新キーへ読み替える互換処理を入れてください。
変更後にtype-checkを実行できるようにしてください。
```

<div style="page-break-after: always;"></div>

### 4-5. Firestore同期

Webで記録した運動や目標は、Firestoreに保存します。iOS側も同じデータを読むことで、WebとiOSの同期ができます。

```text
users/{userId}/
├── profile
├── completed-exercises/
├── daily-goals/
├── time-slot-goals/
├── achievements/
└── statistics/
```

Claudeへのプロンプトです。

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

```text
Webのtype-checkでエラーが出ています。
エラー全文を読んで、原因を説明し、最小限の修正をしてください。
修正後にもう一度type-checkを実行してください。
```

<div style="page-break-after: always;"></div>

## コラム2: iPhoneからClaude CodeとGitHubで開発を続ける

### モバイル開発は「完結」より「継続」を目指す

外出中にiPhoneだけで本格的なiOSアプリをビルドするのは現実的ではありません。Xcodeによる実機ビルドやWatchデプロイはMacが必要です。しかし、GitHubとClaude Code、あるいはGitHub Codespacesやリモート開発環境を組み合わせると、iPhoneからでも設計、Issue整理、レビュー、軽微な修正、ドキュメント更新を続けられます。

モバイル上で向いている作業です。

- GitHub Issueを書く。
- Pull Requestの差分を読む。
- レビューコメントを書く。
- Claudeに調査プロンプトを作る。
- READMEやMarkdownを修正する。
- 小さなWeb修正を行う。
- 次にMacで実機確認するためのチェックリストを作る。

### iPhoneからGitHubを使う流れ

1. GitHub Mobileまたはブラウザでリポジトリを開く。
2. Issueにやりたいことを書く。
3. ClaudeアプリやブラウザでIssue内容を整理する。
4. 必要ならGitHub上でMarkdownや小さなファイルを編集する。
5. Pull Requestを作る。
6. Macに戻ったらCursorでpullし、Xcodeで実機確認する。

### iPhoneからClaude Codeを使う考え方

Claude Codeそのものは通常ターミナルで使うため、iPhone単体よりも、リモートのMacやクラウド開発環境へ接続して使う形が現実的です。たとえば、SSHアプリで自宅MacやクラウドVMに入り、そこでClaude Codeを起動します。

ただし、iOS/WatchのビルドにはXcodeが必要です。したがって、iPhoneから行う作業は「コードを完成させる」よりも、「次の開発を止めない」ことを目的にします。

### モバイルから使うプロンプト例

```text
いまiPhoneからGitHub Issueを書いています。
次にMacでCursorを開いたときにすぐ作業できるように、要件、影響範囲、実装ステップ、テスト項目に分けてIssue本文を作ってください。
```

```text
このPull Requestの差分をスマホで確認しています。
レビュー観点を、バグ、仕様漏れ、テスト不足、リリース前確認に分けてチェックリスト化してください。
```

```text
外出中なので実機確認はできません。
この変更について、Macに戻ったあとXcodeで確認すべき項目をチェックリストにしてください。
iPhone実機、Apple Watch実機、HealthKit権限、WatchConnectivityを含めてください。
```

### モバイル開発の注意点

モバイル上では、差分を見落としやすく、テストも限定されます。特に、HealthKit、WatchConnectivity、Core Motion、Xcode SigningはiPhoneだけでは確認できません。スマホで作業した内容は、必ずMacのCursorとXcodeで確認してからマージします。

このコラムの結論は、iPhoneだけで開発を完結させることではありません。GitHubとClaudeを使い、移動中でも考えを止めず、Issue、レビュー、ドキュメント、次の実装準備を進めることです。

<div style="page-break-after: always;"></div>

## 第五章: iOSアプリ開発

<div style="page-break-after: always;"></div>

### 5-1. iOSアプリの役割

iOSアプリはFitingoの中心です。HealthKit、Core Motion、写真ログ、Diet Goal、MIND、ROUTIN、FITページなど、スマートフォンならではの機能を担当します。

本書ではSwiftUIコードの編集はCursorで行い、実機へのインストールやCapabilities設定はXcodeで行います。

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
```

<div style="page-break-after: always;"></div>

### 5-2. CursorでSwiftUIを編集し、Xcodeで実行する

基本の流れです。

1. CursorでSwiftファイルを編集する。
2. Cursorで差分を確認する。
3. Xcodeで `kfit.xcworkspace` を開く。
4. 実行先にiPhoneを選ぶ。
5. Runして実機で確認する。
6. Xcodeエラーが出たら、エラー内容をCursorのClaudeへ渡す。
7. Cursorで修正し、再度Xcodeでビルドする。

XcodeエラーをClaudeに渡すプロンプトです。

```text
Xcodeで次のSwiftエラーが出ています。
該当ファイルとエラー内容をもとに、原因と最小限の修正案を教えてください。
UIの見た目は変えないでください。
```

<div style="page-break-after: always;"></div>

### 5-3. SwiftUIでダッシュボードを作る

![スクリーンショット: iOS 今日の状況カード](screenshots/07-ios-today-status.png)

Claudeへのプロンプトです。

```text
iOSの今日の状況カードに、右上の更新ボタンを追加してください。
押したらHealthKitの最新データを再取得し、ロード中はアイコンを回転させ、連打できないようにしてください。
既存のdailySetsCardの構成を崩さず、最小限の変更にしてください。
```

<div style="page-break-after: always;"></div>

### 5-4. Apple Health連携

HealthKitを使うと、Apple Healthに保存された健康データを取得できます。Fitingoでは、歩数、アクティブカロリー、安静時カロリー、心拍数、HRV、睡眠、食事、PFC栄養素などを扱います。

```swift
let healthStore = HKHealthStore()
let typesToRead: Set<HKObjectType> = [
    HKQuantityType.quantityType(forIdentifier: .heartRate)!,
    HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
]
```

Claudeへのプロンプトです。

```text
iOSでHealthKitから今日の歩数、アクティブカロリー、安静時カロリー、心拍数、HRVを取得してください。
HealthKit権限がない場合は画面が壊れないようにし、0または未取得表示にしてください。
既存のHealthKitManagerに合わせて実装してください。
```

<div style="page-break-after: always;"></div>

### 5-5. Diet Goalとカロリー目標

Apple Healthで摂取カロリー計測をONにした場合は、HealthKitの実測値を使います。OFFの場合は、1日の目標を時間帯別に配分し、その時間帯になったら自動的に取得済みとして扱います。

例として、1日2000kcalなら次のようになります。

- 朝: 400kcal
- 昼: 600kcal
- 午後: 200kcal
- 夜: 800kcal

![スクリーンショット: Diet Goal設定の摂取カロリー入力欄](screenshots/09-ios-diet-goal-settings.png)

```text
ダイエット目標の摂取カロリー目標に入力欄を設けて、2000kcalをデフォルトにしてください。
Apple Healthで計測をONにしたら、実際の摂取カロリーはApple Healthの登録を使ってください。
OFFの場合は、1日の摂取目標を時間帯別に配分し、その時間になったら自動的にそのカロリーを取得したようにしてください。
```

<div style="page-break-after: always;"></div>

### 5-6. Motion Sensorで運動を数える

Fitingoでは、Core Motionの加速度センサーを使い、運動の回数を検出します。

```swift
let acceleration = sqrt(
    data.acceleration.x * data.acceleration.x +
    data.acceleration.y * data.acceleration.y +
    data.acceleration.z * data.acceleration.z
)
```

![スクリーンショット: iOSトレーニング計測画面](screenshots/08-ios-motion-tracking.png)

```text
iOSでCore Motionを使い、腕立て、スクワット、腹筋の回数を自動カウントしたいです。
まず既存のMotionDetectionManagerとExerciseTrackerViewを調査し、
現在の検出ロジック、サンプリング周波数、閾値、フォームスコアの計算方法を説明してください。
```

<div style="page-break-after: always;"></div>

### 5-7. MINDページとHRV分析

![スクリーンショット: MINDページの7日HRV平均グラフ](screenshots/10-ios-mind-hrv-chart.png)

```text
iOSのMINDページで、3分ストレッチの下に過去7日のHRV平均グラフを表示して。
20msの赤い基準線を入れて。HealthKitManagerに7日平均取得メソッドを追加し、
既存のSwiftUIデザインに合わせて。
```

<div style="page-break-after: always;"></div>

### 5-8. iPhoneへのデプロイ手順

iPhone実機で動かす手順です。

1. iPhoneをMacに接続する。
2. iPhoneで「このコンピュータを信頼」を選ぶ。
3. Xcodeで `ios/kfit.xcworkspace` を開く。
4. SchemeにiOSアプリを選ぶ。
5. 実行先に接続したiPhoneを選ぶ。
6. Signing & CapabilitiesでTeamを設定する。
7. HealthKitなど必要なCapabilityを確認する。
8. RunしてiPhoneへインストールする。
9. 初回起動時にHealthKitや通知の権限を許可する。
10. Cursorで修正、Xcodeで再実行を繰り返す。

デプロイ手順をClaudeに確認させるプロンプトです。

```text
iPhone実機にこのiOSアプリをデプロイする手順を初心者向けに整理してください。
XcodeのScheme選択、Team設定、Bundle Identifier、HealthKit Capability、実機側の信頼設定を含めてください。
```

<div style="page-break-after: always;"></div>

## 第六章: Apple Watchアプリ開発

<div style="page-break-after: always;"></div>

### 6-1. Apple Watchアプリの役割

Apple Watchアプリは、iPhoneアプリの小さい版ではありません。画面が小さく、操作時間が短く、通知やハプティクスとの相性が重要です。

![スクリーンショット: Watchの渦巻き目標表示](screenshots/11-watch-swirl.png)

<div style="page-break-after: always;"></div>

### 6-2. WatchConnectivityで同期する

Fitingoでは、iOS側からWatchへ今日の進捗や目標を送り、Watch側からiOSへ運動完了やマインドフルネス完了を送ります。

Watchへ送るタスクは細かく分けます。

- training
- meal
- drink
- mind-input
- mindfulness
- stretch

```text
Watchで、渦巻き表示の達成済みマークがiOSの達成済みとそろっていません。
iOSの達成状態を正として、Watchの達成済み表示が必ず同期するようにしてください。
meal、drink、mind-input、mindfulness、stretch、trainingは別々に扱ってください。
```

<div style="page-break-after: always;"></div>

### 6-3. Watchのモーション計測

Apple Watchは手首に装着されているため、iPhoneとは違うモーションデータが取れます。腕立て伏せ、スクワット、ランジ、バーピーのような動作は、Watchの加速度・ジャイロから特徴を拾えます。

![スクリーンショット: Watchワークアウトフロー](screenshots/12-watch-workout-flow.png)

```text
Watch側でモーション検知を行うWatchMotionDetectionManagerを調査してください。
iPhone側のMotionDetectionManagerとの違い、サンプリング頻度、検出対象、ハプティクスの使い方を説明してください。
```

<div style="page-break-after: always;"></div>

### 6-4. 1分瞑想と3分ストレッチ

Watch画面では、タイトルを左上に表示し、閉じるボタンを右上の時計に重ならないように配置します。また、呼吸アニメーションは、吸う/吐くの違いが分かるように大きくします。

```text
Watchの1分瞑想と3分ストレッチ画面を改善してください。
タイトルを左上に表示し、閉じるXボタンは右上の時計に重ならないよう少し下げてください。
呼吸アニメーションは吸う/吐くの違いが分かるように大きくしてください。
```

<div style="page-break-after: always;"></div>

### 6-5. 心拍数とHRVの前後変化を履歴表示する

![スクリーンショット: Watchの心拍・HRV前後変化履歴](screenshots/13-watch-hrv-history.png)

履歴には、心拍数、HRV、ストレススコアを表示します。

- 心拍数: `前→後` と差分
- HRV: `前→後` と差分
- ストレス: `前→後`、差分、改善/上昇/維持

```text
1分瞑想と3分ストレッチで、心拍数とHRVの前後の変化はデータを保持して、履歴に表示してください。
履歴には、心拍数、HRV、ストレススコアの前後、差分、改善/上昇/維持を表示してください。
HealthKitのマインドフルネス記録メタデータにも保存してください。
```

<div style="page-break-after: always;"></div>

### 6-6. Apple Watchへのデプロイ手順

Apple Watchアプリを実機にデプロイするには、iPhoneとApple Watchがペアリングされている必要があります。

手順です。

1. iPhoneとApple Watchをペアリングする。
2. Apple Watchのロックを解除して腕に装着する。
3. iPhoneとApple Watchを近くに置く。
4. MacにiPhoneを接続する。
5. XcodeでWatch Appを含むworkspaceを開く。
6. SchemeでWatch AppまたはiOS App with Watch Appを選ぶ。
7. 実行先としてペアリング済みApple Watchを選ぶ。
8. Signing & CapabilitiesのTeamを確認する。
9. RunしてWatchへインストールする。
10. Watch側でHealthKit権限や通知許可を確認する。

確認項目です。

- Watch側でアプリが起動する。
- iPhoneアプリとWatchアプリが通信できる。
- Watchで記録した運動がiOS側に反映される。
- iOS側の達成状態がWatchの渦巻き表示に反映される。
- 心拍数、HRV、マインドフルネス履歴が取得できる。

Claudeへのプロンプトです。

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

```text
Webのtype-checkでエラーが出ています。
エラー全文を読んで、原因を説明し、最小限の修正をしてください。
修正後にもう一度type-checkを実行してください。
```

<div style="page-break-after: always;"></div>

### 7-2. iOSとWatchのテスト

iOSでは、Xcodeビルド、実機でのHealthKit権限確認、モーション検知、Watch同期を確認します。

確認項目です。

- Googleログインできる。
- Firestoreに運動記録が保存される。
- iOSのROUTIN画面でトレーニングが開始できる。
- Apple Healthの歩数、心拍、HRV、睡眠が表示される。
- HealthKitオフ時に摂取カロリーが時間帯別に自動反映される。
- Watchの渦巻き達成マークがiOSと一致する。
- 1分瞑想と3分ストレッチの履歴に心拍/HRV前後差分が表示される。

```text
Watch実機で、瞑想完了後にHRV履歴が表示されません。
WatchHealthKitManager、WatchBreatheFlowView、WatchDashboardViewのデータの流れを調査してください。
HealthKitから値が取れていないのか、UserDefaults保存が失敗しているのか、UIに反映されていないのかを切り分けてください。
```

<div style="page-break-after: always;"></div>

### 7-3. Cursorでデバッグする流れ

1. Xcodeやnpmのエラーを確認する。
2. エラー全文をCursorのClaudeへ渡す。
3. Claudeに原因候補を出させる。
4. 変更前に関連ファイルを読ませる。
5. Cursor上で修正する。
6. Git差分を確認する。
7. Xcodeまたはnpmで再テストする。

```text
このエラーを初心者向けに説明し、原因と修正方針を分けて教えてください。
修正は最小限にし、既存の動作を変えないでください。
```

<div style="page-break-after: always;"></div>

### 7-4. リリース前チェック

App Store向けの確認項目です。

- HealthKit使用目的の説明が明確か。
- 医療診断のような表現をしていないか。
- Apple Watchなしでも主要機能が使えるか。
- ログインできない場合の導線があるか。
- ネットワーク不通時に致命的に壊れないか。
- 個人情報やAPIキーをリポジトリに含めていないか。

```text
App Store提出前の観点で、このiOS/Watchアプリをレビューしてください。
HealthKitの権限説明、医療的に誤解を招く表現、個人情報、ログ出力、APIキー混入、Watchなしユーザーの体験を重点的に確認してください。
```

Webリリース前のプロンプトです。

```text
WebアプリをFirebase Hostingへデプロイする前に確認すべき項目をチェックリスト化してください。
環境変数、manifest、アプリ名、アイコン、ビルド、Firestoreルール、認証設定を含めてください。
```


<div style="page-break-after: always;"></div>

### 7-5. GitHub Pull Requestでレビューする

Pull Requestは、変更をmainブランチへ入れる前の確認場所です。AIに実装を頼んだ場合でも、Pull Requestで人間が読み直すことで安全性が上がります。

PR本文には、最低限次の項目を書きます。

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

ClaudeにPR本文を作らせるプロンプトです。

```text
git diffをもとにPull Request本文を作ってください。
Summary、Test plan、Notesに分けてください。
確認していないことは、確認済みのように書かないでください。
```

レビューコメント対応のプロンプトです。

```text
このPull Requestのレビューコメントに対応してください。
まずコメントを分類してください。
- すぐ修正するもの
- 仕様確認が必要なもの
- 対応しない理由を書くもの
分類後、すぐ修正できるものだけ実装してください。
```

<div style="page-break-after: always;"></div>

### 7-6. GitHub ActionsとCI

GitHub Actionsを使うと、Pull RequestごとにWebのtype-checkやbuildを自動実行できます。iOSのビルドも可能ですが、署名やXcodeバージョンの管理が必要になるため、最初はWebのチェックから始めるとよいでしょう。

Web用CIの例です。

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

ClaudeにCI設定を依頼するプロンプトです。

```text
GitHub ActionsでWebのtype-checkとbuildをPull Request時に実行したいです。
このリポジトリのweb/package.jsonを確認し、適切なworkflow YAMLを提案してください。
secretsやFirebase環境変数が必要な場合は、その扱いも説明してください。
```


<div style="page-break-after: always;"></div>

## 第八章: まとめと開発ポイント

<div style="page-break-after: always;"></div>

### 8-1. Cursorを中心に据える

Fitingo開発では、CursorをIDEとして中心に置きます。ファイル操作、Git差分確認、ターミナル、複数LLMの呼び出し、ドキュメント作成をCursorに集約すると、初心者でも変更内容を追いやすくなります。

<div style="page-break-after: always;"></div>

### 8-2. Claude Sonnet/Opusを使い分ける

Sonnetは日常的な実装、Opusは複雑な設計やレビューに向いています。モデルを使い分けることで、速度と品質のバランスを取りやすくなります。

<div style="page-break-after: always;"></div>

### 8-3. XcodeはデプロイとApple設定のために使う

Xcodeは、iOS/WatchアプリをAppleの実機へ届けるために必要です。Signing、Capabilities、Scheme、実機選択、ArchiveはXcodeの担当です。コード編集はCursor、デプロイはXcodeという役割分担が分かりやすいです。

<div style="page-break-after: always;"></div>

### 8-4. 健康データは慎重に扱う

HealthKit、心拍数、HRV、睡眠、ストレス推定は便利ですが、医療診断ではありません。アプリ内では「傾向」「目安」「提案」として表示し、断定的な表現は避けます。


<div style="page-break-after: always;"></div>

### 8-5. 実際に使ったプロンプト集

ここでは、Fitingo開発で実際に使った、またはそのまま応用できるプロンプトをまとめます。初心者は、対象画面やファイル名だけを自分のアプリに置き換えて使うとよいでしょう。

#### 全体調査

```text
このリポジトリはWeb、iOS、Apple Watch対応のフィットネス習慣化アプリです。
まずREADME、CLAUDE.md、ios/README.md、web/README.mdを読み、構成と主要機能を把握してください。
その後、初心者にも分かるように、どのディレクトリに何があるか説明してください。
まだコード変更はしないでください。
```

```text
この機能は複数ファイルに影響しそうです。
まず実装計画を出してください。
対象ファイル、データモデル、UI変更、同期処理、テスト観点を分けて整理してください。
私が確認するまでコード変更はしないでください。
```

#### Web

```text
Webのダッシュボードで、MINDカードとFOODカードを非表示にしてください。
DIETカードは横幅いっぱいにし、なるべく多くの情報を出してください。
カードを押すとGOAL設定画面へ移動してください。
```

```text
Webのアプリ名をFitingoに全面的に変更してください。
UI文言、HTML title、manifest、package.json、README、localStorageキーを確認してください。
旧localStorageキーからの互換読み込みも入れてください。
```

#### iOS

```text
iOSのGOALページで、今日のアクティビティカードの上にFitingoトレーニングボタンを追加してください。
ボタンはシンプルでよく、タップしたらトレーニング画面に遷移して開始できるようにしてください。
```

```text
GOALページの目標到達までのメッセージは、一番適切で効果がある優先順位が高いメッセージを一つだけ表示してください。
安静時カロリーや基礎代謝が低い場合は「筋トレをしよう！」を出し、タップでトレーニング開始にしてください。
```

```text
FITページの名称は全体的にROUTINにしてください。
ヘッダー表示はRoutingoにし、Routinまでを炎の赤色にしてください。
関連するヘルプ文言やタブ名も確認してください。
```

#### HealthKit

```text
ダイエット目標の摂取カロリー目標に入力欄を設けて、2000kcalをデフォルトにしてください。
Apple Healthで計測をONにしたら、実際の摂取カロリーはApple Healthの登録を使ってください。
OFFの場合は、1日の摂取目標を時間帯別に配分し、その時間になったら自動的にそのカロリーを取得したようにしてください。
```

```text
iOSのMINDページで、3分ストレッチの下に過去7日のHRV平均グラフを表示して。
20msの赤い基準線を入れて。HealthKitManagerに7日平均取得メソッドを追加し、
既存のSwiftUIデザインに合わせて。
```

#### Watch

```text
Watchで、渦巻き表示の達成済みマークがiOSの達成済みとそろっていません。
iOSの達成状態を正として、Watchの達成済み表示が必ず同期するようにしてください。
meal、drink、mind-input、mindfulness、stretch、trainingは別々に扱ってください。
```

```text
Watchで、1分瞑想と3分ストレッチの画面を調整してください。
閉じるXボタンは右上の時計の下に配置し、タイトルは左上に表示してください。
吸う/吐くのアニメーションは違いが分かるようにしてください。
```

```text
Watchで、1分瞑想と3分ストレッチの完了時に心拍数とHRVの前後差分を保存して。
履歴には心拍、HRV、ストレススコアの前後と改善/上昇/維持を表示して。
```

#### GitHub

```text
この変更をGitHubのPull Requestに出したいです。
git statusとgit diff --statを確認し、変更内容をSummaryとTest planに分けてPR本文案を作ってください。
まだcommitやpushはしないでください。
```

```text
Pull Requestのレビューコメントに対応します。
コメント内容を読み、対応が必要なもの、質問として返すもの、対応しない理由を書くものに分類してください。
その後、対応が明確なものだけ修正してください。
```

#### ドキュメント

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

画面ショットは、`docs/screenshots/` に配置します。

```text
docs/screenshots/
├── 01-cursor-project.png
├── 02-web-dashboard.png
├── 03-ios-dashboard.png
├── 04-watch-dashboard.png
├── 05-xcode-workspace.png
├── 06-web-diet-card.png
├── 07-ios-today-status.png
├── 08-ios-motion-tracking.png
├── 09-ios-diet-goal-settings.png
├── 10-ios-mind-hrv-chart.png
├── 11-watch-swirl.png
├── 12-watch-workout-flow.png
└── 13-watch-hrv-history.png
```


<div style="page-break-after: always;"></div>


<div style="page-break-after: always;"></div>

## 終わりに

Fitingoの開発を通じて見えてくるのは、AI開発の本質は「速くコードを書くこと」だけではないということです。CursorをIDEとして使い、Claude Sonnet/Opusをそこから呼び出し、XcodeでiPhoneとApple Watchへデプロイする。この役割分担を作ることで、Web、iOS、Watch、Firebase、Apple Health、Motion Sensorのように領域が広いアプリでも、一つずつ前に進められます。

良いアプリにするためには、人間の判断が必要です。どの健康データを見せるか。どのメッセージを一つだけ出すか。どのタイミングで通知するか。どこまで自動化し、どこに手動入力を残すか。これらはプロダクト設計の問題です。

CursorとClaudeを使えば、一人でもかなり大きなアプリを作れます。ただし、成功の鍵はAIに丸投げすることではありません。小さく依頼し、差分を確認し、実機で試し、また改善する。その繰り返しです。

最後に、AI時代の開発で最も大切な姿勢を一つ挙げるなら、「作りながら学ぶ」ことです。CursorとClaudeは、その学びの速度を大きく上げてくれる相棒になります。
