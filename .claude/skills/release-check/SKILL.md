---
name: release-check
description: kfit/kedu/kmind 全6ターゲット（iOS + Watch）をビルド検証し、エラーを自動修正してコミット可能な状態にする。リリース前・大きな変更後に実行する。
---

# release-check: 全ターゲットビルド検証

kfit リポジトリの 3 アプリ × 6 ターゲットを順にビルドし、エラーがあれば修正して、コミット可能な状態にする。

## 手順

### 0. 事前チェック（必須）

ディスク空き容量を確認する。**5GB 未満なら先にキャッシュを削除**（ビルド途中の ENOSPC は全ターゲット巻き添えで失敗する）:

```bash
df -h /System/Volumes/Data | tail -1
```

空きが足りない場合、安全に削除できるのは以下のみ（ユーザーデータには触れない）:

```bash
# ModuleCache は純粋なキャッシュ（自動再生成、~4GB）
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
# 使われていない古い DerivedData（現行は kfit-gycep…, kedu-bcrur…, kmind-gqydu… の3つ）
du -sh ~/Library/Developer/Xcode/DerivedData/* | sort -rh
```

### 1. ビルド（この順で。並列実行はディスクを食い合うので禁止）

小さい順に実行し、早くエラーを検出する:

```bash
# 1) kmind（最小・数分）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project kmind/kmind.xcodeproj -scheme kmind -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | sort -u

# 2) kmind Watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project kmind/kmind.xcodeproj -scheme "kmindWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | sort -u

# 3) kedu（kfit のソースを共有参照している）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project kedu/kedu.xcodeproj -scheme kedu -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | sort -u

# 4) kedu Watch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project kedu/kedu.xcodeproj -scheme "keduWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD" | sort -u

# 5) kfit（最大・Pods込みで10分超。workspace 必須。watch/widget/share 拡張も同スキームでビルドされる）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace ios/kfit.xcworkspace -scheme kfit -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | sort -u
```

kfit のビルドはバックグラウンド実行し、待ち時間に他の作業をしてよい。

### 2. 典型エラーの対処（実績ある修正パターン）

| 症状 | 原因 | 修正 |
|---|---|---|
| kedu で `cannot find 'X' in scope`（X は kfit の View/型） | kfit 側で型を新ファイルへ切り出した際、kedu の pbxproj 未登録 or KeduStubViews 未同期 | 新ファイルが両ターゲット共有可能なら kedu/kedu.xcodeproj/project.pbxproj に登録（既存の CCDD… 連番 ID を踏襲し、PBXBuildFile / PBXFileReference / group / Sources の4箇所に追加）。kfit 専用型に依存するなら kedu/kedu/KeduStubViews.swift にスタブを追加 |
| kedu で `extra arguments in call`（スタブ型） | kfit 側の本実装とスタブのシグネチャずれ | KeduStubViews.swift のスタブに引数を追加して本実装に同期 |
| `type '(_, Self)' cannot conform to 'Equatable'`（.onChange） | 2引数 onChange のオーバーロード解決失敗 | クロージャ引数に明示型を付ける: `{ (_: T, newVal: T) in ... }` |
| `unable to type-check this expression in reasonable time` | body 内の複雑なイニシャライザ式（複数クロージャ引数のシート等） | 式を `private func xxxSheet(_:) -> 具体型` に切り出す（TomoView の swipeDetailSheet / socialShareSheet / categoryGroupSheet が前例） |
| `missing import of defining module 'Combine'`（ObservableObject） | import Combine 漏れ | ファイル先頭に `import Combine` 追加 |
| `out of space` / `.priors because the volume … is out of space` | ディスク枯渇 | 手順 0 のキャッシュ削除 → 再ビルド（コードは壊れていないので修正不要） |

共有ソースの構造: kedu/kmind は `../ios/kfit/` 配下のファイルを相対パス参照で共有する。**kfit の共有ファイル（TomoView.swift 等）を変更したら、kedu/kmind のビルドまで必ず確認する。**

### 3. 完了処理

全 6 ターゲット `BUILD SUCCEEDED` を確認したら:

1. `git status` と `git diff --stat` を表示
2. 提案コミットメッセージを提示
3. CLAUDE.md のワークフローに従いユーザーの承認を待つ（ユーザーのメッセージが「commit」「push」で終わっていた場合は承認済みとして自動実行）

## 成功条件

- 6 ターゲットすべて BUILD SUCCEEDED
- 修正を入れた場合は、修正内容の要約（何を・なぜ）を報告に含める
- ディスク空きが 3GB を切っていたら報告に警告を含める
