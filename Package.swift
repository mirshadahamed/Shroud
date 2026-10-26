
 // swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shroud",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Shroud",
            targets: ["Shroud"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Shroud",
            path: "Sources/Shroud"
        ),
        .testTarget(
            name: "ShroudTests",
            dependencies: ["Shroud"]
        )
    ]
)
