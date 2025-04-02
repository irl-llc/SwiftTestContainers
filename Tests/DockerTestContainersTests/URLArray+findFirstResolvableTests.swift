@testable import DockerTestContainers
import NIOCore
import NIOPosix
import Foundation
import Testing

@Suite("URL array resolution tests")
class URLArrayFindFirstResolvableTests {
  var tempFileURL: URL!
  var serverURL: URL!
  var server: NIOTCPServer!
    
  init() async throws {
    // Create a temporary file
    let tempFileActualURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: tempFileActualURL)
    tempFileURL = URL(string: "file://\(tempFileActualURL.path.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)")
        
    // Create a mock server
    server = try await NIOTCPServer()
    serverURL = URL(string: "tcp://localhost:\(server.port)")!
  }
    
  deinit {
    try? FileManager.default.removeItem(at: tempFileURL)
    try? server.close()
  }
  
  @Test("Only accept a file URL if it is valid")
  func validFileURLOnly() async throws {
    let urls = [tempFileURL!]
    let result = await urls.findFirstResolvable()
    #expect(result == tempFileURL, "The valid file URL should be chosen")
  }
    
  @Test("Reject an invalid file URL")
  func testInvalidFileURLOnly() async throws {
    let urls = [URL(string: "file:///nonexistent/file")!]
    let result = await urls.findFirstResolvable()
    #expect(result == nil, "An invalid file URL should not be chosen")
  }
    
  @Test("Accept a valid TCP URL")
  func testValidTCPURLOnly() async throws {
    let urls = [serverURL!]
    let result = await urls.findFirstResolvable()
    #expect(result == serverURL, "The valid TCP URL should be chosen")
  }
    
  @Test("Reject an invalid TCP URL")
  func testInvalidTCPURLOnly() async throws {
    let urls = [URL(string: "tcp://localhost:11111")!]
    let result = await urls.findFirstResolvable()
    #expect(result == nil, "An invalid TCP URL should not be chosen")
  }
    
  @Test("Resolution order prefers first valid URL")
  func resolutionOrder() async throws {
    let urls = [
      URL(string: "file:///nonexistent/file")!,
      tempFileURL!,
      serverURL!,
      URL(string: "https://example.com")!
    ]
    let result = await urls.findFirstResolvable()
    #expect(result == tempFileURL, "The first valid URL (file) should be chosen")
  }
}

// Custom error type
enum NIOTCPServerError: Error {
  case failedToGetAssignedPort
}

// Helper class to create a simple TCP server for testing
class NIOTCPServer {
  private let channel: Channel
  let port: Int
    
  init() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        
    // Bind to port 0 to let the OS assign a random available port
    self.channel = try await bootstrap.bind(host: "localhost", port: 0).get()
        
    // Get the assigned port
    guard let port = (channel.localAddress)?.port, port != 0 else {
      throw NIOTCPServerError.failedToGetAssignedPort
    }
    self.port = port
  }
    
  func close() throws {
    try channel.close().wait()
  }
}
