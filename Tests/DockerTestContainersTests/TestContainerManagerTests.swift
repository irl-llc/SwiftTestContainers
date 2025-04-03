@testable import SwiftTestContainers
import Logging
import NIO
import NIOExtras
import Testing
import Foundation

@Suite("SwiftTestContainers")
final class SwiftTestContainersTest {
  private let logger: Logger = Logger(label: "llc.irl.SwiftTestContainersTest")
  private let dockerTestContainers: TestContainerManager
  
  init() async {
    dockerTestContainers = await TestContainerManager()
  }
  
  private func createSocatServerContainer(aliases: [String:[String]] = .init()) async throws -> Container {
    let createContainerSettings = CreateContainerSettings(
      exposedPorts: [.init(port: 8080)],
      aliases: aliases,
      cmd: ["-d", "-d", "-v", "tcp-l:8080,fork", "exec:echo \"Hello, World!\""]
    )
    let simpleContainer = try await dockerTestContainers.createContainer(
      "alpine/socat",
      createContainerSettings
    )
    try await simpleContainer.logOutput()
    try await simpleContainer.waitForLogLineRegex("listening on")
    return simpleContainer
  }
  
  deinit {
    dockerTestContainers.close()
  }
  
  @Test("Containers can be connected to from test host")
  func startAContainerAndWaitForLogLineAndPort() async throws {
    let simpleContainer = try await createSocatServerContainer()
    let mappedPort = try await simpleContainer.getMappedPort(8080)
    let response = try await connectAndReadResponse(host: mappedPort.host, port: mappedPort.port)
    #expect(response == "Hello, World!")
  }
  
  @Test("Containers can connect to each other via networks")
  func testNetworkConnectivity() async throws {
    let dockerTestContainers = await TestContainerManager()
    let testNetworkUUID = UUID()
    let testNetworkName = "test-network-\(testNetworkUUID.uuidString)"
    _ = try await dockerTestContainers.createNetwork(testNetworkName)
    _ = try await createSocatServerContainer(aliases: [testNetworkName: ["simple-server"]])
    let simpleContainerClient = try await dockerTestContainers.createContainer(
      // TODO: simply using "busybox" (which should work) fails with a 404
      "mirror.gcr.io/library/busybox:latest",
      .init(networks: [testNetworkName], cmd: ["sh", "-c", "echo \"Reading from simple server\" && nc simple-server 8080 && echo \"Assertions Passed!\""])
    )
    try await simpleContainerClient.logOutput()
    try await simpleContainerClient.waitForLogLineRegex("Assertions Passed!")
  }
  
  private func connectAndReadResponse(host: String, port: Int) async throws -> String {
    let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      Task {
        try? await eventLoopGroup.shutdownGracefully()
      }
    }
    
    let bootstrap = ClientBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
      .channelInitializer { channel in
        channel.eventLoop.makeCompletedFuture {
          try channel.pipeline.syncOperations.addHandlers(ByteToMessageHandler(LineBasedFrameDecoder()))
        }
      }
    
    let channel = try await bootstrap.connect(host: host, port: port).get()
    defer {
      Task {
        try? await channel.close().get()
      }
    }
    
    let promise = channel.eventLoop.makePromise(of: String.self)
    try await channel.pipeline.addHandler(SimpleHandler(promise: promise))
    
    return try await promise.futureResult.get()
  }
  
  private final class SimpleHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    
    private let promise: EventLoopPromise<String>
    
    init(promise: EventLoopPromise<String>) {
      self.promise = promise
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      let buffer = unwrapInboundIn(data)
      if let string = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) {
        promise.succeed(string)
      } else {
        promise.fail(Error.invalidResponse)
      }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
      promise.fail(error)
      context.close(promise: nil)
    }
    
    enum Error: Swift.Error {
      case invalidResponse
    }
  }
}
