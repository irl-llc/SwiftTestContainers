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
