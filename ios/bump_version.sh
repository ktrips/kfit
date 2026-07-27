#!/bin/bash
# kfit(Fitingo) / kfitWatch のバージョン・ビルド番号を一括更新するスクリプト。
#
# project.yml（XcodeGenのソース・オブ・トゥルース）と、実ファイルの
# kfit/Info.plist・kfitWatch/Info.plist を必ず同時に書き換える。
# ここを編集せずXcodeのUIだけでビルド番号を上げると、次の
# `xcodegen generate` で消えてしまうため、このスクリプト経由での
# 更新を徹底すること。
#
# 使い方（ios/ ディレクトリで実行）:
#   ./bump_version.sh                # Build番号だけ +1（Versionは維持）
#   ./bump_version.sh 0.3            # Versionを0.3に変更、Buildは1にリセット
#   ./bump_version.sh 0.3 4          # Version・Buildを明示的に指定
#
# 実行後は必ず:
#   xcodegen generate
#   pod install     ← xcodegen generate は .xcodeproj を丸ごと再生成し、
#                      CocoaPodsの統合（Pods xcconfig・Embed Frameworks）が
#                      消えてしまうため必ずセットで実行すること
#   open kfit.xcworkspace
# を行ってからアーカイブすること。

set -euo pipefail
cd "$(dirname "$0")"

PROJECT_YML="project.yml"
INFO_PLIST_KFIT="kfit/Info.plist"
INFO_PLIST_WATCH="kfitWatch/Info.plist"

CURRENT_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$PROJECT_YML" | sed -E 's/.*"([^"]+)".*/\1/')
CURRENT_BUILD=$(grep -m1 'CFBundleVersion:' "$PROJECT_YML" | sed -E 's/.*"([0-9]+)".*/\1/')

if [ $# -eq 0 ]; then
  NEW_VERSION="$CURRENT_VERSION"
  NEW_BUILD=$((CURRENT_BUILD + 1))
elif [ $# -eq 1 ]; then
  NEW_VERSION="$1"
  NEW_BUILD=1
else
  NEW_VERSION="$1"
  NEW_BUILD="$2"
fi

echo "Version: ${CURRENT_VERSION} (${CURRENT_BUILD})  →  ${NEW_VERSION} (${NEW_BUILD})"

# project.yml: kfit・kfitWatch 両ターゲットの記述を一括置換
sed -i.bak -E \
  -e "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"${NEW_VERSION}\"/g" \
  -e "s/(CFBundleVersion: )\"[0-9]+\"/\1\"${NEW_BUILD}\"/g" \
  "$PROJECT_YML"
rm -f "${PROJECT_YML}.bak"

# 実ファイルの Info.plist も同じ値に揃える（plutilはmacOS標準ツール）
if ! command -v plutil >/dev/null 2>&1; then
  echo "エラー: plutilが見つかりません。このスクリプトはmacOS上のXcode環境で実行してください。" >&2
  exit 1
fi
for PLIST in "$INFO_PLIST_KFIT" "$INFO_PLIST_WATCH"; do
  plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$PLIST"
  plutil -replace CFBundleVersion -string "$NEW_BUILD" "$PLIST"
done

echo ""
echo "✅ project.yml / Info.plist を更新しました"
echo "次のコマンドでXcodeプロジェクトへ反映してください:"
echo "   cd ios && xcodegen generate && pod install && open kfit.xcworkspace"
