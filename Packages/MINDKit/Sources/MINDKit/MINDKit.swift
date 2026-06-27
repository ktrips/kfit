// MINDKit - MIND機能共有ライブラリ
//
// 【使い方】
// kfit.xcodeproj と kmind.xcodeproj の両方から
// このローカルパッケージを参照して使います。
//
// Xcode でのパッケージ追加手順:
//   File → Add Package Dependencies → Add Local... →
//   /Users/kenichi.yoshida/Git/kfit/Packages/MINDKit を選択
//
// 【MIND機能の更新方法】
// Packages/MINDKit/Sources/MINDKit/ 内のファイルを編集するだけで
// kfit・kmind 両アプリに自動的に反映されます。

import SwiftUI
import HealthKit

// MARK: - Public API
// MINDKit から export するモデル・ビュー・マネージャーはここで re-export します

public struct MINDKitInfo {
    public static let version = "1.0.0"
}
