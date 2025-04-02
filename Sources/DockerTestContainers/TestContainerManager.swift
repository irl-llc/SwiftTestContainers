//

import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOPosix

public actor TestContainerManager {
  private let logger = Logger(label: "llc.irl.DockerTestContainers.TestContainerManager")
  private let client: DockerClient
  private var ryuk: Ryuk?
  private let testId: UUID
  private static let testIdLabel = "llc.irl.ryukTestId"
  private var startedContainers: [Container] = []
  private var addedNetworks: [DockerNetwork] = []
  private var addedImageTags: [String] = []
  private var ryukIsStarting = false

  public init() async {
    let serverUrl = await [
      TestContainersDockerLocator().locate(),
      EnvironmentBasedDockerLocator().locate()
    ].compactMap { $0 }.findFirstResolvable()
    guard let serverUrl = serverUrl else {
      fatalError("Unable to locate docker server")
    }
    testId = UUID()
    client = DockerClient(baseURL: serverUrl, testContainersSessionId: testId)
  }

  public func logRyuk() async throws {
    try await ensureRyukIsStarted()
    try await ryuk!.container.logOutput()
  }

  public nonisolated func close() {
    Task {
      let startedContainers = await self.startedContainers
      logger.debug("There are \(startedContainers.count) containers to clean up")
      for container in startedContainers {
        try await container.kill()
        try await container.delete()
      }
      try await removeAddedImages()
      let addedNetworks = await self.addedNetworks
      for network in addedNetworks {
        try await network.delete()
      }
    }
  }

  private func removeAddedImages() async throws {
    for tag in addedImageTags {
      do {
        _ = try await client.imageDelete(name: tag)
        logger.debug("Cleaned up image \(tag)")
      } catch let error as DockerError {
        if error.message.contains("not found") {
          logger.debug("Image \(tag) not found for cleanup")
        } else if error.message.contains("conflict") {
          logger.warning("Conflict while deleting image \(tag): \(error.message). This may be due to the image being in use by a container that was created outside this test.")
        } else {
          throw error
        }
      }
    }
  }

  public func loadTarball(_ tarballPath: String) async throws {
    try await client.imageLoad(imagePath: tarballPath)
    logger.debug("Container image uploaded")
  }

  public func createNetwork(_ name: String) async throws -> DockerNetwork {
    try await ensureRyukIsStarted()
    let _ = try await client.networkCreate(name: name, labels: [TestContainerManager.testIdLabel: testId.uuidString])
    let network = DockerNetwork(name, client: client)
    addedNetworks.append(network)
    return network
  }

  public func createContainer(
    _ image: String, _ createContainerSettings: CreateContainerSettings
  ) async throws -> Container {
    try await ensureRyukIsStarted()
    let container = try await internalCreateContainer(image, createContainerSettings)
    startedContainers.append(container)
    return container
  }

  private func imageIsCached(_ image: String) async throws -> Bool {
    logger.debug("Checking for image \(image)")
    do {
      _ = try await client.imageInspect(name: image)
      return true
    } catch let error as DockerError {
      if error.statusCode?.code == 404 {
        return false
      } else {
        throw error
      }
    }
  }

  private func pullImageIfNeeded(_ image: String) async throws {
    if try await !imageIsCached(image) {
      logger.debug("Pulling image \(image)")
      try await client.imagePull(fromImage: image)
      logger.debug("Pulled image \(image)")
    }
  }

  private func createContainerBodyFromSettings(_ image: String, _ createContainerSettings: CreateContainerSettings) -> CreateContainerBody {
    logger.debug("Creating container from image \(image)")
    let exposedPorts = createContainerSettings.exposedPorts.reduce(into: [String: EmptyObject]()) { result, port in
      result["\(port.port)/\(port.protocol.name)"] = EmptyObject()
    }
    let portBindings = createContainerSettings.exposedPorts.reduce(into: [String: [PortBinding]]()) { result, port in
      result["\(port.port)/\(port.protocol.name)"] = [PortBinding(HostIp: "", HostPort: "")]
    }
    struct EndpointConfigPair {
      let network: String
      let aliases: [String]
    }
    let networkOnlyEndpointsConfig: [EndpointConfigPair] = createContainerSettings.networks.map { .init(network: $0, aliases: []) }
    let networkAliasConfig: [EndpointConfigPair] = createContainerSettings.aliases.map { .init(network: $0.key, aliases: $0.value) }
    let endpointsConfig: [String: EndpointConfig] = (networkOnlyEndpointsConfig + networkAliasConfig)
      .reduce(into: [String: EndpointConfig]()) { result, pair in
        result[pair.network] = EndpointConfig(Aliases: pair.aliases)
      }
    let config = CreateContainerBody(
      Image: image,
      ExposedPorts: exposedPorts,
      Env: createContainerSettings.environment,
      Labels: [TestContainerManager.testIdLabel: testId.uuidString],
      HostConfig: HostConfig(
        Binds: createContainerSettings.volumeBinds,
        PortBindings: portBindings,
        Privileged: createContainerSettings.privileged
      ),
      NetworkingConfig: NetworkingConfig(EndpointsConfig: endpointsConfig),
      Cmd: createContainerSettings.cmd
    )
    logger.debug("Creating container request \(config)")
    return config
  }

  private func internalCreateContainer(
    _ image: String, _ createContainerSettings: CreateContainerSettings
  ) async throws -> Container {
    try await pullImageIfNeeded(image)
    let config = createContainerBodyFromSettings(image, createContainerSettings)
    let response = try await client.containerCreate(body: config)
    let container = Container(
      client: client,
      containerId: response.Id
    )
    try await container.start()
    return container
  }

  private func ensureRyukIsStarted() async throws {
    if ryuk != nil || ryukIsStarting {
      return
    }
    ryukIsStarting = true
    logger.debug("Ryuk has not yet been started, starting a new Ryuk container to reap zombie containers")
    let container = try await internalCreateContainer(
      "docker.io/testcontainers/ryuk:0.9.0",
      .init(
        exposedPorts: [ExposedPort(port: 8080, protocol: .tcp)],
        volumeBinds: ["/var/run/docker.sock:/var/run/docker.sock"],
        privileged: true
      )
    )
    // Ryuk should not be added to the list of running containers, it will auto
    // terminate after it has been unsupervised for 10 s and has killed any
    // zombie containers
    logger.debug("Ryuk container was created and start invoked")
    let ryuk = try await Ryuk(container: container)
    let killQuery = "label=\(TestContainerManager.testIdLabel)=\(testId)\n"
    try await ryuk.addKillQuery(query: killQuery)
    logger.debug("Kill query added to ryuk: \(killQuery)")
    self.ryuk = ryuk
  }
}
