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

import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix

actor Ryuk {
  let logger = Logger(label: "llc.irl.SwiftTestContainers.Ryuk")
  let container: Container
  private let portBinding: ContainerPortBinding
  private var channel: Channel?
  private let eventLoopGroup: MultiThreadedEventLoopGroup = .init(numberOfThreads: 1)

  init(container: Container) async throws {
    self.container = container
    logger.debug("Waiting for Ryuk to become available")
    try await container.waitForLogLineRegex("Started!")
    logger.debug("Ryuk has started")
    let port = try await container.getMappedPort(8080)
    portBinding = port

    // Open a connection on TCP port 8080 and keep it open
    channel = try await ClientBootstrap(group: eventLoopGroup).connect(host: port.host, port: port.port).get()
    logger.debug("Connected to Ryuk at \(port.host):\(port.port)")
  }

  func addKillQuery(query: String) async throws {
    guard let channel = channel else {
      throw RyukError.connectionNotEstablished
    }

    // Write the query string to the connection
    let data = query.data(using: .utf8)! + "\n".data(using: .utf8)!
    let buffer = ByteBuffer(data: data)
    try await channel.writeAndFlush(buffer)
  }

  func close() async throws {
    try await channel?.close()
    channel = nil
  }
}

enum RyukError: Error {
  case connectionNotEstablished
}
