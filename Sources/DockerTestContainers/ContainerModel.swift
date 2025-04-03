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
import NIOCore
import NIOHTTP1
import NIOPosix

public enum ContainerSocketProtocol: Sendable {
  case tcp
  case udp

  public var name: String {
    switch self {
    case .tcp:
      return "tcp"
    case .udp:
      return "udp"
    }
  }
}

public struct ExposedPort: Sendable {
  public let port: Int
  public let `protocol`: ContainerSocketProtocol

  public init(port: Int, protocol: ContainerSocketProtocol = .tcp) {
    self.port = port
    self.protocol = `protocol`
  }
}

struct ManifestEntry: Codable, Sendable {
  var Config: String
  var RepoTags: [String]
  var Layers: [String]
}

public struct ContainerPortBinding: Sendable {
  let client: DockerClient
  public let port: Int
  public let host: String
  public let `protocol`: ContainerSocketProtocol
}

public struct CreateContainerSettings: Sendable {
  let exposedPorts: [ExposedPort]
  let volumeBinds: [String]
  let environment: [String]
  let aliases: [String: [String]]
  let privileged: Bool
  let networks: [String]
  let cmd: [String]?

  /**
    Create a new set of settings for creating a container.
    Parameters:
    - exposedPorts: A list of ports that the container will expose. These ports will be mapped to the host machine.
    - volumeBinds: A list of volume binds that will be mounted into the container. These follow the same format as the `--volume` flag in the `docker run` command.
    - environment: A list of environment variables that will be set in the container.
    - aliases: A dictionary of aliases that will be set for the container. The keys are the network name and the values are the aliases. Requires the network to have been created.
   */
  public init(
    exposedPorts: [ExposedPort] = [],
    volumeBinds: [String] = [],
    environment: [String] = [],
    aliases: [String: [String]] = [:],
    privileged: Bool = false,
    networks: [String] = [],
    cmd: [String]? = .none
  ) {
    self.exposedPorts = exposedPorts
    self.volumeBinds = volumeBinds
    self.environment = environment
    self.aliases = aliases
    self.privileged = privileged
    self.networks = networks
    self.cmd = cmd
  }
}

public struct DockerError: Error {
  let message: String
  let endpoint: String?
  let statusCode: HTTPResponseStatus?

  init(_ message: String, endpoint: String? = .none, statusCode: HTTPResponseStatus? = nil) {
    self.message = message
    self.endpoint = endpoint
    self.statusCode = statusCode
  }
}

public enum IoType {
  case stdin
  case stdout
  case stderr
}

public struct StdIOEntry {
  public let ioType: IoType
  public let data: ByteBufferView
  public var stringValue: String {
    return String(decoding: data, as: UTF8.self)
  }
}

public enum IOStreamEvent {
  case io(StdIOEntry)
  case start
  case end
}

public enum IOStreamNextAction {
  case keepGoing
  case stop
}
