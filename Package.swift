// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacbookSibal",
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "MacbookSibal"
        ),
        .testTarget(
            name: "MacbookSibalTests",
            dependencies: ["MacbookSibal"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
