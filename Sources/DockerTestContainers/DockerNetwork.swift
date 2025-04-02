
import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOPosix

public actor DockerNetwork {
  let logger = Logger(label: "llc.irl.SwiftTestContainers.DockerNetwork")
  private let client: DockerClient
  public let name: String
  init(_ name: String, client: DockerClient) {
    self.client = client
    self.name = name
  }

  public func delete() async throws {
    do {
      try await client.networkDelete(id: name)
    } catch let error as DockerError {
      if error.message.contains("not found") {
        logger.warning("Network \(name) not found for deletion")
      } else {
        throw error
      }
    }
  }
}
