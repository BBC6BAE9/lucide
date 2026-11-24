// swift-tools-version: 6.2.1

import PackageDescription

let package = Package(
  name: "LucideRemote",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "LucideRemote", targets: ["LucideRemote"])
  ],
  targets: [
    .target(name: "LucideRemote"),
    .testTarget(name: "LucideRemoteTests", dependencies: ["LucideRemote"]),
  ]
)
