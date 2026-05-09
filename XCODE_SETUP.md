# Xcode プロジェクトセットアップ手順

## 問題の修正完了

pbxprojファイルのエラーを修正しました。プロジェクトは正常に開けるようになっています。

## WatchHealthKitManager.swift を手動で追加する手順

WatchHealthKitManager.swiftファイルは作成済みですが、Xcodeプロジェクトに登録する必要があります。

### 手順

1. **Xcodeでプロジェクトを開く**
   ```bash
   open /Users/kenichi.yoshida/Git/kfit/ios/kfit.xcodeproj
   ```

2. **kfitWatchターゲットを選択**
   - 左サイドバーのプロジェクトナビゲータで`kfitWatch`フォルダを右クリック
   - 「Add Files to "kfit"...」を選択

3. **WatchHealthKitManager.swiftを追加**
   - ファイル選択ダイアログで以下のパスに移動:
     ```
     /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/Managers/WatchHealthKitManager.swift
     ```
   - 「Options」セクションで:
     - ✅ "Copy items if needed" をチェック（既に正しい場所にあるのでチェック不要）
     - ✅ "Add to targets" で `kfitWatch` をチェック
   - 「Add」をクリック

4. **kfitWatch.entitlementsを追加**
   - 同様に`kfitWatch`フォルダを右クリック
   - 「Add Files to "kfit"...」を選択
   - ファイル選択ダイアログで:
     ```
     /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/kfitWatch.entitlements
     ```
   - ✅ "Add to targets" で `kfitWatch` をチェック
   - 「Add」をクリック

5. **Build Settingsでentitlementsを設定**
   - プロジェクトナビゲータで`kfit`プロジェクトをクリック
   - TARGETSから`kfitWatch`を選択
   - 「Build Settings」タブをクリック
   - 検索フィールドに "CODE_SIGN_ENTITLEMENTS" と入力
   - `Code Signing Entitlements` の値を設定:
     ```
     kfitWatch/kfitWatch.entitlements
     ```
   - DebugとReleaseの両方に設定されていることを確認

6. **ビルドして確認**
   - Cmd+B でビルド
   - エラーがないことを確認

## 代替方法: Finderからドラッグ＆ドロップ

1. Finderで以下のフォルダを開く:
   ```
   /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/Managers/
   ```

2. `WatchHealthKitManager.swift` をドラッグして、Xcodeの `kfitWatch/Managers` フォルダにドロップ

3. ダイアログが表示されたら:
   - ✅ "Copy items if needed" をチェック（または既に正しい場所にあるのでチェック不要）
   - ✅ "Create groups" を選択
   - ✅ "Add to targets" で `kfitWatch` をチェック
   - 「Finish」をクリック

4. 同様に `kfitWatch.entitlements` も追加

## トラブルシューティング

### エラー: "Cannot find 'WatchHealthKitManager' in scope"

**原因**: WatchHealthKitManager.swiftがkfitWatchターゲットに追加されていない

**解決方法**:
1. プロジェクトナビゲータで `WatchHealthKitManager.swift` を選択
2. 右サイドバーの「File Inspector」(ファイルアイコン)をクリック
3. 「Target Membership」セクションで `kfitWatch` にチェックが入っているか確認
4. チェックが入っていなければ、チェックを入れる

### エラー: "Code signing entitlements file not found"

**原因**: CODE_SIGN_ENTITLEMENTSのパスが間違っている

**解決方法**:
1. kfitWatchターゲットの「Build Settings」を開く
2. "CODE_SIGN_ENTITLEMENTS" を検索
3. 正しいパスを設定:
   ```
   kfitWatch/kfitWatch.entitlements
   ```
4. ファイルが実際に存在するか確認:
   ```bash
   ls -la /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/kfitWatch.entitlements
   ```

## HealthKit Capability の追加

1. kfitWatchターゲットを選択
2. 「Signing & Capabilities」タブをクリック
3. 左上の「+ Capability」ボタンをクリック
4. "HealthKit" を検索して追加
5. entitlementsファイルが自動的に更新される

## 確認コマンド

```bash
# ファイルが存在するか確認
ls -la /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/Managers/WatchHealthKitManager.swift
ls -la /Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/kfitWatch.entitlements

# プロジェクトファイルが正常か確認
plutil -lint /Users/kenichi.yoshida/Git/kfit/ios/kfit.xcodeproj/project.pbxproj
```

## 完了後の状態

すべて正しく設定されると:
- ✅ WatchHealthKitManager.swiftがkfitWatchターゲットに含まれる
- ✅ kfitWatch.entitlementsがプロジェクトに含まれる
- ✅ CODE_SIGN_ENTITLEMENTSが正しく設定される
- ✅ HealthKit capabilityが有効になる
- ✅ ビルドエラーがない

## 補足

自動スクリプトでのpbxproj編集は複雑でエラーが発生しやすいため、手動でXcodeから追加する方が安全です。Xcodeが自動的に正しい構文でproject.pbxprojを更新します。
