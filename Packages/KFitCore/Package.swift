// swift-tools-version: 5.9
// KFitCore: kfit / kedu / kmind 全アプリで共有する基盤パッケージ
//
// ── 追加方法 ──────────────────────────────────────────────────
// Xcode でプロジェクトを開き、
//   File → Add Package Dependencies... → Add Local...
//   /Users/kenichi.yoshida/Git/kfit/Packages/KFitCore を選択
//
// ── 含まれる機能 ──────────────────────────────────────────────
// - KFitColors   : duoGreen/duoRed/... カラー定数、UIScale、hex 変換
// - KFitHRV      : HRVThreshold、MindStressInfo、stressInfoFromHRV
// - KFitMoomin   : MoominQuote、moominQuoteForStress
// - KFitLanguage : BCP-47変換、国旗、言語名、バッジ色
// - KFitFirestore: Firestore コレクションパス定数
// - KFitUI       : RoundedCorner、cornerRadius(corners:)
// - CoachingContent: 100メソッド JSON DB ローダー
// ──────────────────────────────────────────────────────────────

import PackageDescription

let package = Package(
    name: "KFitCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "KFitCore",
            targets: ["KFitCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "KFitCore",
            dependencies: [],
            path: "Sources/KFitCore",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("KFITCORE")
            ]
        ),
    ]
)
