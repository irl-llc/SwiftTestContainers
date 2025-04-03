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
