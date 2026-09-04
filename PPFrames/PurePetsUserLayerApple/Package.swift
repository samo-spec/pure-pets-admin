// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PurePetsUserKit",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "PurePetsUserKit", targets: ["PurePetsUserKit"])
  ],
  targets: [
    .target(
      name: "PurePetsUserKit",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "PurePetsUserKitTests",
      dependencies: ["PurePetsUserKit"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
