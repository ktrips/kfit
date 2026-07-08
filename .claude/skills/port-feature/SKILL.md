---
name: port-feature
description: kfit の View/機能を kedu・kmind へ移植し、スタブ(KeduStubViews)のシグネチャずれ・pbxproj 未登録を検出して修正する。kfit の共有ファイル（TomoView 等）を変更した後にも実行する。
---

# port-feature: kfit → kedu/kmind 機能ポートとスタブ同期

kedu・kmind は kfit のソースを**相対パス参照で共有**している。kfit 側の変更が
kedu/kmind のビルドを静かに壊す構造のため、共有ファイル変更後は必ず同期チェックを行う。

## 構造の前提

- kedu は `kedu/kedu.xcodeproj/project.pbxproj` に `../ios/kfit/...` への参照を持つ
  （登録済みファイル一覧は `grep -o '[A-Za-z0-9_+]*\.swift' kedu/kedu.xcodeproj/project.pbxproj | sort -u`）
- kfit 専用の型（FoodView・DashboardView 内の型など）を共有ファイルが参照する場合、
  kedu 側は `kedu/kedu/KeduStubViews.swift` のスタブで解決する
- kmind は独立性が高い（fileSystemSynchronizedGroups 使用）。共有は最小限

## 手順

### 1. 共有ファイルの特定

```bash
# kedu が参照している kfit ファイル一覧
grep -o 'path = ../ios/kfit[^;]*' kedu/kedu.xcodeproj/project.pbxproj | sort -u
```

ポート対象・変更対象がこの一覧にあるかを最初に確認する。

### 2. 移植 / 変更の実施

新しい View・型を共有ファイルから切り出す場合の判断基準:

| 状況 | 置き場所 |
|---|---|
| kfit / kedu 両方で使う型・View | `ios/kfit/Views/Components/SharedEduViews.swift` など Components 配下（両プロジェクトに登録） |
| kfit 専用型に依存する extension | 依存先と同じ kfit 専用ファイルに置く（例: DayCarouselEntry の extension は DashboardView.swift） |
| kedu では UI 不要（型だけ必要） | KeduStubViews.swift にスタブを追加 |

### 3. pbxproj 登録（新ファイルを kedu と共有する場合）

kedu の pbxproj は CCDD… の連番擬似 UUID を使う。未使用 ID を確認して 4 箇所に追加:

```bash
grep -oE "CCDD[0-9A-F]{20}" kedu/kedu.xcodeproj/project.pbxproj | sort -u | tail -3
```

1. PBXBuildFile セクション
2. PBXFileReference セクション（`path = ../ios/kfit/...; sourceTree = SOURCE_ROOT;`）
3. グループ children
4. Sources ビルドフェーズ

既存の SharedAppComponents.swift のエントリをテンプレートにする。

### 4. スタブ同期チェック（最重要）

kfit 側の本実装とスタブのシグネチャずれが典型的な破壊原因:

```bash
# スタブが提供する型の一覧
grep -n "^struct \|^class \|^extension " kedu/kedu/KeduStubViews.swift
# それぞれの本実装（kfit 側）と引数を比較する
```

- 共有ファイル内の呼び出しで使われる**全ラベル付き引数**がスタブの init に存在するか
- 例: 過去の破損 — kfit の `SocialShareSheet(item:shareURL:overrideImage:)` に対し
  スタブが `item` のみ → `extra arguments in call` で kedu ビルド失敗

### 5. 典型コンパイルエラーの対処

| 症状 | 修正 |
|---|---|
| `cannot find 'X' in scope`（kedu） | X の定義ファイルを pbxproj 登録 or スタブ追加 |
| `extra arguments in call`（スタブ型） | スタブに引数を追加して本実装と同期 |
| `type '(_, Self)' cannot conform to 'Equatable'` | `.onChange` のクロージャ引数に明示型 `{ (_: T, v: T) in }` |
| `unable to type-check ... reasonable time` | body 内の複雑な式を `private func xxx(_:) -> 具体型` に切り出す |
| `missing import of defining module 'Combine'` | `import Combine` を追加 |

### 6. 検証

/release-check の手順で kedu → kfit の順にビルド（kmind は共有ファイルに触れた場合のみ）。
共有ファイルを 1 行でも変更したら kedu のビルド確認を省略しない。

## 恒久対策（中期）

このスタブ運用は Swift Package（KFitCore）化で構造的に解消する予定
（docs/SamBezThieMuskJobs_plan.md の Sam A3 参照）。Package 化までは本スキルで同期を守る。
