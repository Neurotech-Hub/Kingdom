// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AprilTagKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "AprilTagKit", targets: ["AprilTagKit"]),
    ],
    targets: [
        // Vendored from https://github.com/AprilRobotics/apriltag (BSD-2-Clause),
        // commit b7c0ebe9aa20f82ec7a828579004f9e706bfecd9. Only tag36h11 is included.
        .target(
            name: "CAprilTag",
            exclude: ["LICENSE.md"],
            cSettings: [
                .define("NDEBUG"),
                .headerSearchPath("include/common"),
                // Detection is unusably slow at -O0, so optimize even in Debug.
                .unsafeFlags(["-O3", "-w"]),
            ]
        ),
        .target(
            name: "AprilTagKit",
            dependencies: ["CAprilTag"]
        ),
        .testTarget(
            name: "AprilTagKitTests",
            dependencies: ["AprilTagKit", "CAprilTag"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
