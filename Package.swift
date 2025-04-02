// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "DockerTestContainers",
  platforms: [
    .macOS(.v13),
    .iOS(.v13)
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "DockerTestContainers",
      targets: ["DockerTestContainers"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-nio", "2.73.0"..<"2.81.0"), // swift nio 2.81.0 seems to have a bug
    .package(url: "https://github.com/apple/swift-nio-extras", from: "1.24.0"),
    .package(url: "https://github.com/apple/swift-protobuf", from: "1.28.1"),
    .package(url: "https://github.com/swift-server/async-http-client", from: "1.23.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "DockerTestContainers",
      dependencies: [
        .product(name:"HTTPTypes", package:"swift-http-types"),
        .product(name:"NIOCore", package:"swift-nio"),
        .product(name:"NIOHTTP1", package:"swift-nio"),
        .product(name:"AsyncHTTPClient", package:"async-http-client"),
      ]
    ),
    .testTarget(
      name: "DockerTestContainersTests",
      dependencies: [
        "DockerTestContainers",
        .product(name:"NIOExtras", package: "swift-nio-extras"),
      ]
    ),
  ],
)
