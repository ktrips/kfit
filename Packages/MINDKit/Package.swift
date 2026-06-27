// swift-tools-version: 5.9
// MINDKit: kfit と kmind で共有する MIND 機能パッケージ
// このファイルを変更したら両プロジェクトで「File → Packages → Update」を実行

import PackageDescription

let package = Package(
    name: "MINDKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "MINDKit",
            targets: ["MINDKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MINDKit",
            dependencies: [],
            path: "Sources/MINDKit",
            swiftSettings: [
                .define("MINDKIT")
            ]
        ),
    ]
)
