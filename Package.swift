// swift-tools-version: 6.0

/*
 * SwiftTestContainers, a testing container manager for Swift and Docker.
 * Copyright (C) 2025, IRL AI LLC
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 */

import PackageDescription

let package = Package(
  name: "SwiftTestContainers",
  platforms: [
    .macOS(.v13),
    .iOS(.v13)
  ],
  products: [
    .library(
      name: "SwiftTestContainers",
      targets: ["SwiftTestContainers"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-nio", "2.73.0"..<"2.81.0"), // swift nio 2.81.0 seems to have a bug
    .package(url: "https://github.com/apple/swift-nio-extras", from: "1.24.0"),
    .package(url: "https://github.com/swift-server/async-http-client", from: "1.23.0")
  ],
  targets: [
    .target(
      name: "SwiftTestContainers",
      dependencies: [
        .product(name:"HTTPTypes", package:"swift-http-types"),
        .product(name:"NIOCore", package:"swift-nio"),
        .product(name:"NIOHTTP1", package:"swift-nio"),
        .product(name:"AsyncHTTPClient", package:"async-http-client")
      ]
    ),
    .testTarget(
      name: "SwiftTestContainersTests",
      dependencies: [
        "SwiftTestContainers",
        .product(name: "NIOExtras", package: "swift-nio-extras")
      ]
    )
  ]
)
