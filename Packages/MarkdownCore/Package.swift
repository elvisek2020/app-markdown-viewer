// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
        .library(name: "FileWatch", targets: ["FileWatch"]),
        .library(name: "WebAssets", targets: ["WebAssets"]),
        .library(name: "Updates", targets: ["Updates"]),
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
            ],
            // Emoji zkratky z gemoji (generuje web-vendor/update.sh).
            resources: [.copy("Resources/emoji.json"), .copy("Resources/gemoji-LICENSE")]
        ),
        .target(name: "FileWatch"),
        // Šablona, CSS, app.js a vendorované knihovny náhledu (aktualizace: web-vendor/update.sh).
        .target(name: "WebAssets", resources: [.copy("Resources/web")]),
        // Aktualizace aplikace z GitHub Releases: verze a odpověď API (stahování a instalace jsou v App/Update).
        .target(name: "Updates"),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore", "WebAssets"],
            // Golden fixtures + referenční výstupy GitHubu (scripts/gh-golden.sh).
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "FileWatchTests", dependencies: ["FileWatch"]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
    ]
)
