#!/bin/bash
# TestFlight配布用: Watchアプリを含まないIPAを作成するスクリプト。
#
# 背景: App Store Connectの検証が、watchOS向けの旧式アイコンロール
# （notificationCenter/appLauncher/quickLook）不足エラー（90394/90741）で
# 通らない状態が続いている（DTS問い合わせ中）。Watchアプリを同梱しなければ
# この検証自体が走らないため、iOS本体だけを先にTestFlightへ配布して
# 動作確認を進められる。
#
# 使い方: ios/ ディレクトリで `./build_testflight_no_watch.sh` を実行。
# 生成された build/kfit-no-watch.ipa を Transporter アプリ（App Store から
# 入手可能）にドラッグ&ドロップしてアップロードする。
#
# 注意: このスクリプトで作るIPAには Apple Watch アプリが含まれないため、
# 本番のApp Store提出には使わないこと（あくまでTestFlightでの動作確認用）。

set -euo pipefail
cd "$(dirname "$0")"

ARCHIVE_PATH="build/kfit-no-watch.xcarchive"
EXPORT_PATH="build/kfit-no-watch-export"
EXPORT_OPTIONS="build/ExportOptions-no-watch.plist"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p build

echo "0/5: DerivedData をクリア中..."
# kfit関連の全DerivedDataを削除
find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -type d -name "kfit-*" -exec rm -rf {} + 2>/dev/null || true
# モジュールキャッシュもクリア
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex
# ビルドキャッシュもクリア
rm -rf ~/Library/Caches/com.apple.dt.Xcode 2>/dev/null || true
echo "   → DerivedData をクリアしました"

echo "1/5: アーカイブを作成中（Watchアプリも含めて通常通りビルド）..."
xcodebuild archive \
  -workspace kfit.xcworkspace -scheme kfit \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS'

echo "2/5: 生成されたアーカイブからWatchアプリを削除中..."
WATCH_DIR="$ARCHIVE_PATH/Products/Applications/kfit.app/Watch"
if [ -d "$WATCH_DIR" ]; then
  rm -rf "$WATCH_DIR"
  echo "   -> 削除しました: $WATCH_DIR"
else
  echo "   -> 警告: Watchディレクトリが見つかりませんでした（想定と違う構成の可能性）"
fi

echo "3/5: ExportOptions.plistを生成中..."
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:Team" "$ARCHIVE_PATH/Info.plist")
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
EOF

echo "4/5: IPAをエクスポート中..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo ""
echo "完了: $EXPORT_PATH/kfit.ipa"
echo "Transporterアプリでこのipaをアップロードしてください。"
