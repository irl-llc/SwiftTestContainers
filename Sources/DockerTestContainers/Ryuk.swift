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
