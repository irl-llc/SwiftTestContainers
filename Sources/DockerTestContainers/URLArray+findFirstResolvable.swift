import Foundation
import NIO

extension Array where Element == URL {
  func findFirstResolvable() async -> URL? {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    defer {
      Task {
        try? await group.shutdownGracefully()
      }
    }

    for url in self {
      switch url.scheme {
      case "file", "http+unix", "unix":
        let socketLocation = url.host()?.removingPercentEncoding
        if let socketLocation, FileManager.default.fileExists(atPath: socketLocation) {
          return url
        }
      case "tcp", "http":
        if let host = url.host, let port = url.port {
          let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(5))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
          do {
            let channel = try await bootstrap.connect(host: host, port: port).get()
            try await channel.close()
            return url
          } catch {
            continue
          }
        }
      default:
        continue
      }
    }
    return nil
  }
}
