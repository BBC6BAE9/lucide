// swift-tools-version: 6.2.1

import PackageDescription

let package = Package(
  name: "Lucide",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "Lucide", targets: ["Lucide"])
  ],
  targets: [
    .target(name: "Lucide"),
    .testTarget(name: "LucideTests", dependencies: ["Lucide"]),
  ]
)
