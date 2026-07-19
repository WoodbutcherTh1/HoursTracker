// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoursTrackerKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "HoursTrackerKit", targets: ["HoursTrackerKit"])
    ],
    targets: [
        .target(
            name: "HoursTrackerKit",
            path: "Sources/HoursTrackerKit"
        ),
        .testTarget(
            name: "HoursTrackerKitTests",
            dependencies: ["HoursTrackerKit"],
            path: "Tests/HoursTrackerKitTests"
        )
    ]
)
