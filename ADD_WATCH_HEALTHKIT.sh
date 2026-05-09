#!/bin/bash

# WatchHealthKitManager.swift を Xcode プロジェクトに追加するスクリプト

echo "=========================================="
echo "WatchHealthKitManager.swift 追加スクリプト"
echo "=========================================="
echo ""

# ファイルの存在確認
MANAGER_FILE="/Users/kenichi.yoshida/Git/kfit/ios/kfitWatch/Managers/WatchHealthKitManager.swift"

if [ ! -f "$MANAGER_FILE" ]; then
    echo "❌ エラー: ファイルが見つかりません"
    echo "   $MANAGER_FILE"
    exit 1
fi

echo "✅ ファイルを確認しました: WatchHealthKitManager.swift"
echo ""

# Xcodeが開いているか確認
XCODE_RUNNING=$(osascript -e 'tell application "System Events" to (name of processes) contains "Xcode"' 2>/dev/null)

if [ "$XCODE_RUNNING" = "false" ]; then
    echo "⚠️  Xcodeが起動していません"
    echo ""
    echo "以下の手順で手動で追加してください:"
    echo ""
    echo "1. Xcodeでプロジェクトを開く:"
    echo "   open /Users/kenichi.yoshida/Git/kfit/ios/kfit.xcodeproj"
    echo ""
    echo "2. Finderでファイルを開く:"
    echo "   open -R $MANAGER_FILE"
    echo ""
    echo "3. WatchHealthKitManager.swift を Xcode の"
    echo "   kfitWatch > Managers フォルダにドラッグ＆ドロップ"
    echo ""
    echo "4. ダイアログで以下を確認:"
    echo "   [ ] Copy items if needed (チェック不要)"
    echo "   [✓] Add to targets: kfitWatch (必ずチェック)"
    echo ""
    exit 0
fi

echo "✅ Xcodeが起動しています"
echo ""

# Finderでファイルの場所を表示
echo "📁 Finderでファイルの場所を開きます..."
open -R "$MANAGER_FILE"

echo ""
echo "=========================================="
echo "次の手順:"
echo "=========================================="
echo ""
echo "1. Finderで選択されている WatchHealthKitManager.swift を"
echo "   Xcodeの kfitWatch > Managers フォルダにドラッグ"
echo ""
echo "2. ダイアログが表示されたら:"
echo "   [ ] Copy items if needed (チェック不要)"
echo "   [✓] Create groups (選択)"
echo "   [✓] Add to targets: kfitWatch (必ずチェック)"
echo ""
echo "3. 「Finish」をクリック"
echo ""
echo "4. Xcode で Cmd+B でビルド"
echo ""
echo "=========================================="
