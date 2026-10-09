// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
        .library(name: "FileWatch", targets: ["FileWatch"]),
    ],
    dependencies: [
        // Stejný parser jako GitHub (cmark-gfm). Pinováno přesně, Package.resolved je v gitu.
        .package(url: "https://github.com/swiftlang/swift-cmark.git", exact: "0.9.0"),
    ],
    targets: [
        // Syntax extension pro matiku ($…$, $$…$$, $`…`$) napsaná přímo nad inline parserem cmarku.
        .target(
            name: "CMarkMath",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
            ]
        ),
        .target(
            name: "MarkdownCore",
            dependencies: [
                "CMarkMath",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .target(name: "FileWatch"),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
        .testTarget(name: "FileWatchTests", dependencies: ["FileWatch"]),
    ]
)
