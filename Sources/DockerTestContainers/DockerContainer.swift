
import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix

public actor Container {
  private let logger = Logger(label: "llc.irl.SwiftTestContainers.Container")
  private let client: DockerClient
  private let containerId: String
  private var backgroundTasks: [Task<Void, any Error>] = []
  init(client: DockerClient, containerId: String) {
    self.client = client
    self.containerId = containerId
  }

  private func inspect() async throws -> ContainerInspectResponse {
    return try await client.containerInspect(id: containerId)
  }

  public func start() async throws {
    try await client.containerStart(id: containerId)
  }

  public func delete() async throws {
    try await client.containerDelete(id: containerId, force: true)
  }

  public func getMappedPort(_ containerPort: Int, _ protocol: ContainerSocketProtocol = .tcp) async throws -> ContainerPortBinding {
    return try await withExponentialBackoff(backoffStartingSeconds: 1, maxBackoffSeconds: 10) {
      let protocolName = `protocol`.name
      guard let portMappings = try await self.inspect().NetworkSettings.Ports else {
        throw DockerError("No port mappings for container \(self.containerId)")
      }
      self.logger.debug("Received container port mappings \(portMappings)")
      let portId = "\(containerPort)/\(protocolName)"
      guard let portInfo = portMappings[portId] else {
        throw DockerError("No port mappings found for port id \(portId) in container \(self.containerId)")
      }
      if portInfo.count > 1, portInfo.contains(where: { $0.HostIp != "0.0.0.0" && $0.HostIp != "::" }) {
        throw DockerError("Multiple port mappings for container \(self.containerId) port \(portId): \(portInfo)")
      }
      if portInfo.count == 0 {
        throw DockerError("No port mapping for container \(self.containerId) port \(portId): \(portInfo)")
      }
      let onlyPortBinding = portInfo[0]
      
      let portHost = onlyPortBinding.HostIp
      guard let intPort = Int(onlyPortBinding.HostPort) else {
        throw DockerError("Port string \(onlyPortBinding.HostPort) is not an unsigned integer")
      }
      return ContainerPortBinding(client: self.client, port: intPort,
                                  host: portHost == "0.0.0.0" || portHost == "::" ? "localhost" : onlyPortBinding.HostIp,
                                  protocol: `protocol`)
    }
    
  }

  public func logOutput(_ processor: @escaping @Sendable (String) -> Void = { print($0) }) throws {
    logger.debug("Logging output for container \(containerId)")
    let logtask = Task {
      self.logger.debug("Logging task started")
      let logs = try await self.client.structuredContainerLogs(id: self.containerId, follow: true, stdout: true, stderr: true)
      for try await entry in logs {
        processor(entry.message)
      }
    }
    backgroundTasks.append(logtask)
  }

  public func waitForLogLineRegex(_ regexExpression: String, timeout: TimeInterval = 30) async throws {
    let logTask = Task(timeout: timeout) {
      let lineRegex = try Regex(regexExpression)
      let logs = try await self.client.structuredContainerLogs(id: self.containerId, follow: true, stdout: true, stderr: true)
      self.logger.trace("Looking for line matching regex \"\(regexExpression)\"")
      for try await entry in logs {
        self.logger.trace("Checking log entry \(entry.message)")
        if try lineRegex.firstMatch(in: entry.message) != nil {
          self.logger.trace("Found entry for regex: \(entry.message)")
          return
        }
      }
      throw DockerError("Container logs ended before entry was found for \(regexExpression)")
    }
    let logResult = await logTask.result
    switch logResult {
      case .success:
        break
      case .failure(let error):
        throw error
    }
  }

  private enum ReadState {
    case readingHeader
    case readingMessage
    case needMoreBytesForHeader
    case needMoreBytesForMessage
  }

  public func kill() async throws {
    for task in backgroundTasks {
      task.cancel()
    }
    backgroundTasks.removeAll()
    try await client.containerKill(id: containerId)
  }
}
