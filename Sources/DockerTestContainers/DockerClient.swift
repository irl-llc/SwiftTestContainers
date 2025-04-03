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

import AsyncHTTPClient
import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix

final class NIOMetricsLogger: NIOEventLoopMetricsDelegate {
  let logger = Logger(label: "llc.irl.SwiftTestContainers.NioMetricDelegate")
  func processedTick(info: NIOPosix.NIOEventLoopTickInfo) {
    logger.trace("Event loop tick statics \(info.eventLoopID): {startTime: \(info.startTime), numberOfTasks: \(info.numberOfTasks)}")
  }
}


public final class DockerClient: Sendable {
  static let logger = Logger(label: "llc.irl.SwiftTestContainers.DockerClient")
  private let httpClient: HTTPClient
  private let baseURL: URL
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let testContainersSessionId: UUID?
  private let eventLoopGroup: EventLoopGroup

  public init(baseURL: URL, testContainersSessionId: UUID? = nil) {
    self.baseURL = baseURL
    self.testContainersSessionId = testContainersSessionId
    let httpLogger = Logger(label: "llc.irl.SwiftTestContainers.DockerClient.HTTPClient")

    eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1, metricsDelegate: NIOMetricsLogger())
    httpClient = HTTPClient(
      eventLoopGroupProvider: .shared(eventLoopGroup),
      configuration: HTTPClient.Configuration(
        timeout: .init(connect: .seconds(30), read: .seconds(30))
      ),
      backgroundActivityLogger: httpLogger
    )
  }

  deinit {
    try? httpClient.syncShutdown()
    try? eventLoopGroup.syncShutdownGracefully()
  }

  private func makeRequest(_ path: String, method: HTTPMethod, query: [URLQueryItem] = [], body: (any Codable)? = nil, timeout: TimeAmount = .seconds(30)) async throws -> HTTPClientResponse {
    let requestUrlString = baseURL.appending(path: path).appending(queryItems: query).absoluteString
    Self.logger.trace("Request URL: \(requestUrlString)")
    var request = HTTPClientRequest(url: requestUrlString)
    request.addHostHeaderIfUnixDomainSocket(baseURL: baseURL)
    request.method = method
    var bodyBuffer: ByteBuffer? = nil
    if let body = body {
      let jsonData = try jsonEncoder.encode(body)
      bodyBuffer = ByteBuffer(data: jsonData)
      request.body = .bytes(bodyBuffer!)
      request.headers.add(name: "Content-Type", value: "application/json")
    }
    addStandardHeaders(request: &request)
    return try await withExponentialBackoff {
      Self.logger.trace(">>> \(request) \n    body: \(bodyBuffer != nil ? String(buffer: bodyBuffer!) : "nil")")
      return try await self.httpClient.execute(request, timeout: timeout, logger: Self.logger)
    }
  }

  private func decodeEmptyResponse(_ response: HTTPClientResponse, endpoint: String) async throws {
    let body = try await response.body.collect(upTo: 64 * 1024 * 1024) // 64 MB max
    Self.logger.trace("<<< response:\(response)\n    body: \(String(buffer: body))")
    if response.status.code >= 400 {
      let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: Data(buffer: body))
      throw DockerError(errorBody?.message ?? "Unknown error", endpoint: endpoint, statusCode: response.status)
    }
  }

  private func decodeResponse<T: Codable>(_ response: HTTPClientResponse, endpoint: String) async throws -> T {
    let body = try await response.body.collect(upTo: 64 * 1024 * 1024) // 64 MB max
    Self.logger.trace("<<< response:\(response)\n    body: \(String(buffer: body))")
    if response.status.code >= 400 {
      let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: Data(buffer: body))
      throw DockerError(errorBody?.message ?? "Unknown error", endpoint: endpoint, statusCode: response.status)
    }
    return try jsonDecoder.decode(T.self, from: Data(buffer: body))
  }

  // ContainerCreate
  func containerCreate(body: CreateContainerBody) async throws -> ContainerCreateResponse {
    let endpoint = "/containers/create"
    let response = try await makeRequest(endpoint, method: .POST, body: body)
    return try await decodeResponse(response, endpoint: endpoint)
  }

  // ContainerStart
  func containerStart(id: String) async throws {
    let endpoint = "/containers/\(id)/start"
    let response = try await makeRequest(endpoint, method: .POST)
    if response.status.code >= 400 {
      throw try await parseError(response, endpoint: endpoint)
    }
    if response.status != .noContent {
      Self.logger.warning("Start container returned a non-204 status (\(response.status)), which is unexpected.")
    }
  }

  // ContainerKill
  func containerKill(id: String) async throws {
    let endpoint = "/containers/\(id)/kill"
    let response = try await makeRequest(endpoint, method: .POST)
    switch response.status {
    case .notFound:
      Self.logger.warning("Container \(id) not found, cannot kill")
      return
    case .noContent:
      return
    default:
      throw try await parseError(response, endpoint: endpoint)
    }
  }

  // ContainerDelete
  func containerDelete(id: String, force: Bool = false) async throws {
    let query = force ? [URLQueryItem(name: "force", value: "true")] : []
    let endpoint = "/containers/\(id)"
    let response = try await makeRequest(endpoint, method: .DELETE, query: query)
    switch response.status {
    case .notFound:
      Self.logger.warning("Container \(id) not found, cannot delete")
      return
    case .noContent:
      return
    default:
      throw try await parseError(response, endpoint: endpoint)
    }
  }

  // ContainerInspect
  func containerInspect(id: String) async throws -> ContainerInspectResponse {
    let endpoint = "/containers/\(id)/json"
    Self.logger.debug("Inspecting container \(id)")
    let response = try await makeRequest(endpoint, method: .GET, timeout: .seconds(30))
    return try await decodeResponse(response, endpoint: endpoint)
  }

  // ContainerLogs
  func containerLogs(id: String, follow: Bool, stdout: Bool, stderr: Bool) async throws -> HTTPClientResponse.Body {
    let endpoint = "/containers/\(id)/logs"
    let query = [URLQueryItem(name: "follow", value: follow ? "true" : "false"),
                 URLQueryItem(name: "stdout", value: stdout ? "true" : "false"),
                 URLQueryItem(name: "stderr", value: stderr ? "true" : "false")]
    let response = try await makeRequest(endpoint, method: .GET, query: query, timeout: .nanoseconds(Int64.max))
    switch response.status {
    case .ok:
      break
    case .notFound:
      throw DockerError("Container \(id) not found, cannot follow logs", endpoint: endpoint, statusCode: response.status)
    case .internalServerError:
      throw DockerError("Failed to get logs for container \(id)", endpoint: endpoint, statusCode: response.status)
    default:
      throw DockerError("Failed to get logs for container \(id)", endpoint: endpoint, statusCode: response.status)
    }
    return response.body
  }

  func structuredContainerLogs(id: String, follow: Bool, stdout: Bool, stderr: Bool) async throws -> AsyncThrowingStream<DockerLogEvent, Error> {
    let body = try await containerLogs(id: id, follow: follow, stdout: stdout, stderr: stderr)
    let parser = DockerLogFrameParser()
    return AsyncThrowingStream { continuation in
      Task(priority: .medium) {
        var iterator = body.makeAsyncIterator()
        while let buffer = try await iterator.next() {
          try await parser.parseFrames(buffer)
          while let nextFrame = await parser.nextFrame() {
            continuation.yield(nextFrame)
          }
        }
        continuation.finish()
      }
    }
  }

  // NetworkCreate
  func networkCreate(name: String, labels: [String: String]) async throws -> NetworkCreateResponse {
    let body = NetworkCreateBody(Name: name, Labels: labels)
    let endpoint = "/networks/create"
    let response = try await makeRequest(endpoint, method: .POST, body: body)
    return try await decodeResponse(response, endpoint: endpoint)
  }

  // NetworkDelete
  func networkDelete(id: String) async throws {
    let endpoint = "/networks/\(id)"
    let response = try await makeRequest(endpoint, method: .DELETE)
    guard response.status == .noContent else {
      throw try await parseError(response, endpoint: endpoint)
    }
  }

  // ImageInspect
  func imageInspect(name: String) async throws -> ImageInspectResponse {
    let endpoint = "/images/\(name)/json"
    let response = try await makeRequest(endpoint, method: .GET)
    return try await decodeResponse(response, endpoint: endpoint)
  }

  // ImageCreate (Pull)
  func imagePull(fromImage: String) async throws {
    Self.logger.debug("Pulling image \(fromImage)")
    let query = [URLQueryItem(name: "fromImage", value: fromImage)]
    let response = try await makeRequest("/images/create", method: .POST, query: query)
    try await decodeEmptyResponse(response, endpoint: "/images/create")
    guard response.status == .ok else {
      throw DockerError("Failed to pull image: \(response.status)", statusCode: response.status)
    }
  }

  private func addStandardHeaders(request: inout HTTPClientRequest) {
    // Add the x-tc-sid header if testContainersSessionId is present
    if let sessionId = testContainersSessionId {
      request.headers.add(name: "x-tc-sid", value: sessionId.uuidString)
    }
    request.headers.add(name: "User-Agent", value: "tc-swift/0.0")
  }

  // ImageLoad
  func imageLoad(imagePath: String) async throws {
    let uploadTask = Task(priority: .medium) {
      let fileSize: Int64
      let fileManager = FileManager.default
      guard let type = try fileManager.attributesOfItem(atPath: imagePath)[.type] as? FileAttributeType else {
        throw DockerError("Unable to determine file type for \(imagePath)")
      }
      do {
        switch(type){
        case .typeSymbolicLink:
          fileSize = try fileManager.attributesOfItem(atPath: fileManager.destinationOfSymbolicLink(atPath: imagePath))[.size] as! Int64
        case .typeRegular:
          fileSize = try fileManager.attributesOfItem(atPath: imagePath)[.size] as! Int64
        default:
          throw DockerError("Unsupported file type \(type) for \(imagePath)")
        }
      } catch {
        throw DockerError("Failed to get file size for \(imagePath): \(error)")
      }
      let requestUrlString = baseURL.appending(path: "/images/load").absoluteString
      Self.logger.trace("Request URL: \(requestUrlString)")
      var request = HTTPClientRequest(url: requestUrlString)
      request.addHostHeaderIfUnixDomainSocket(baseURL: baseURL)
      request.method = .POST
      Self.logger.debug("Opening file handle to \(imagePath) for image import")
      let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: imagePath))
      defer {
        do {
          try fileHandle.close()
        } catch {
          Self.logger.warning("Failed to close file handle: \(error)")
        }
      }
      Self.logger.debug("Opened file handle to \(imagePath) for image import")
      let chunkSize = 32 * 1024 * 1024 // 32 mb chunks
      Self.logger.debug("Starting image import of \(fileSize) bytes from \(imagePath)")

      let imageStream = FileReadSequence(fileHandle: fileHandle, chunkSize: chunkSize, totalSize: fileSize)
      request.body = .stream(imageStream, length: .known(fileSize))
      request.headers.add(name: "Content-Type", value: "application/x-tar")
      addStandardHeaders(request: &request)

      let response: HTTPClientResponse
      do {
        response = try await withExponentialBackoff { try await self.httpClient.execute(request, timeout: .seconds(300)) }
      } catch {
        throw DockerError("Failed to load image: \(error)")
      }
      try await decodeEmptyResponse(response, endpoint: "/images/load")
      guard response.status == .ok else {
        throw DockerError("Failed to load image at path \(imagePath): \(response.status)", statusCode: response.status)
      }
    }
    try await uploadTask.value
  }

  // ImageDelete
  func imageDelete(name: String) async throws -> [ImageDeleteResponseItem] {
    let endpoint = "/images/\(name)"
    let response = try await makeRequest(endpoint, method: .DELETE)
    return try await decodeResponse(response, endpoint: endpoint)
  }

  private func parseError(_ response: HTTPClientResponse, endpoint: String) async throws -> DockerError {
    let body = try await response.body.collect(upTo: 64 * 1024 * 1024) // 64 MB max
    let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: Data(buffer: body))
    return DockerError(errorBody?.message ?? "Unknown error", endpoint: endpoint, statusCode: response.status)
  }
}

struct DockerLogEvent {
  public enum StreamType: UInt8 {
    case stdin = 0
    case stdout = 1
    case stderr = 2
  }

  public let streamType: StreamType
  public let message: String
}

private actor DockerLogFrameParser {
  static let logger = Logger(label: "llc.irl.SwiftTestContainers.DockerLogFrameParser")
  private var buffer = ByteBuffer()
  private var parsedFrames = [DockerLogEvent]()

  func parseFrames(_ newData: ByteBuffer) throws {
    buffer.writeImmutableBuffer(newData)
    var events: [DockerLogEvent] = []

    Self.logger.trace("Parser has \(buffer.readableBytes) bytes available")
    while buffer.readableBytes >= 8 {
      guard let typeByte = buffer.getBytes(at: buffer.readerIndex, length: 1)?[0] else {
        throw DockerError("Failed to read type despite having at least 8 bytes in buffer")
      }

      guard let streamType = DockerLogEvent.StreamType(rawValue: typeByte) else {
        throw DockerError("Unsupported stream type \(typeByte)")
      }
      Self.logger.trace("Found frame with type \(streamType)")
      guard let frameSize = buffer.getInteger(at: buffer.readerIndex + 4, as: UInt32.self) else {
        throw DockerError("Failed to read frame size despite having at least 8 bytes in buffer")
      }

      if buffer.readableBytes >= 8 + Int(frameSize) {
        buffer.moveReaderIndex(forwardBy: 8)
        guard var payload = buffer.readString(length: Int(frameSize)) else {
          throw DockerError("Unable to read string of size \(frameSize) despite having \(buffer.readableBytes) available in buffer")
        }
        payload.removeLast() // remove trailing newline
        events.append(DockerLogEvent(streamType: streamType, message: payload))
      } else {
        break
      }
    }
    parsedFrames.append(contentsOf: events)
  }

  var hasParsedFrames: Bool {
    !parsedFrames.isEmpty
  }

  func nextFrame() -> DockerLogEvent? {
    if parsedFrames.isEmpty {
      return nil
    }
    return parsedFrames.removeFirst()
  }
}

struct HostConfig: Codable {
  public let Binds: [String]?
  public let PortBindings: [String: [PortBinding]]?
  public let Privileged: Bool?
}

struct EmptyObject: Codable {}

struct CreateContainerBody: Codable {
  public let Image: String
  public let ExposedPorts: [String: EmptyObject]?
  public let Env: [String]?
  public let Labels: [String: String]?
  public let HostConfig: HostConfig?
  public let NetworkingConfig: NetworkingConfig?
  public let Cmd: [String]?
}

struct NetworkingConfig: Codable {
  public let EndpointsConfig: [String: EndpointConfig?]?
}

struct EndpointConfig: Codable {
  public let Aliases: [String]
}

struct ContainerCreateResponse: Codable {
  public let Id: String
  public let Warnings: [String]?
}

struct NetworkSettings: Codable {
  public let Ports: [String: [PortBinding]]?
}

struct PortBinding: Codable {
  public let HostIp: String
  public let HostPort: String
}

struct ContainerInspectResponse: Codable {
  public let NetworkSettings: NetworkSettings
}

struct NetworkCreateBody: Codable {
  public let Name: String
  public let Labels: [String: String]
}

struct NetworkCreateResponse: Codable {
  public let Id: String
  public let Warning: String?
}

struct ImageInspectResponse: Codable {}

struct ImageDeleteResponseItem: Codable {
  public let Untagged: String?
  public let Deleted: String?
}

private struct ErrorResponse: Codable {
  let message: String
}

private struct FileReadSequence: AsyncSequence {
  let logger = Logger(label: "llc.irl.SwiftTestContainers.FileReadSequence")
  typealias Element = ByteBuffer

  let fileHandle: FileHandle
  let chunkSize: Int
  let totalSize: Int64

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(fileHandle: fileHandle, chunkSize: chunkSize, totalSize: totalSize)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    let logger = Logger(label: "llc.irl.SwiftTestContainers.FileReadSequence.AsyncIterator")
    let fileHandle: FileHandle
    let chunkSize: Int
    let totalSize: Int64
    var readBytes: Int64 = 0

    mutating func next() async throws -> ByteBuffer? {
      if readBytes >= totalSize {
        return nil
      }

      let remainingBytes = totalSize - readBytes
      let bytesToRead = Swift.min(Int(remainingBytes), chunkSize)

      guard let data = try fileHandle.read(upToCount: bytesToRead) else {
        return nil
      }

      readBytes += Int64(data.count)
      logger.trace("Read \(readBytes) bytes of \(totalSize) for image import")

      return ByteBuffer(data: data)
    }
  }
}

extension HTTPClientRequest {
  mutating func addHostHeaderIfUnixDomainSocket(baseURL: URL) {
    if baseURL.scheme == "http+unix" {
      self.headers.add(name: "Host", value: baseURL.host() ?? "localhost")
    }
  }
}
