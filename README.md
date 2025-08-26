# SwiftTestContainers

A Swift library for managing Docker containers in integration tests, inspired by the TestContainers project. SwiftTestContainers provides a programmatic, lightweight API for spinning up throwaway instances of Docker containers for your tests.

## Features

- 🚀 **Easy Docker Container Management**: Create, start, and manage Docker containers programmatically from Swift tests
- 🔧 **Automatic Cleanup**: Containers are automatically cleaned up after tests complete using the Ryuk sidecar container
- 🌐 **Network Support**: Create Docker networks and connect containers for inter-container communication
- 📝 **Log Monitoring**: Monitor container logs and wait for specific log patterns before proceeding
- 🔌 **Port Mapping**: Automatically discover mapped ports for container services
- 🎯 **Multiple Docker Locator Strategies**: Supports TestContainers standard discovery and environment-based Docker host configuration

## Installation

### Swift Package Manager

Add SwiftTestContainers to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/SwiftTestContainers", from: "1.0.0")
]
```

Then add it as a dependency to your test target:

```swift
.testTarget(
    name: "YourTests",
    dependencies: ["SwiftTestContainers"]
)
```

## Usage

### Basic Example

```swift
import Testing
import SwiftTestContainers

@Suite("Integration Tests")
final class MyIntegrationTests {
    private let containerManager: TestContainerManager
    
    init() async {
        containerManager = await TestContainerManager()
    }
    
    deinit {
        containerManager.close()
    }
    
    @Test("Test with PostgreSQL container")
    func testWithPostgres() async throws {
        // Create a PostgreSQL container
        let postgres = try await containerManager.createContainer(
            "postgres:15",
            CreateContainerSettings(
                exposedPorts: [ExposedPort(port: 5432)],
                environment: [
                    "POSTGRES_PASSWORD=test",
                    "POSTGRES_DB=testdb"
                ]
            )
        )
        
        // Wait for PostgreSQL to be ready
        try await postgres.waitForLogLineRegex("database system is ready to accept connections")
        
        // Get the mapped port
        let mappedPort = try await postgres.getMappedPort(5432)
        
        // Connect to PostgreSQL at localhost:mappedPort.port
        // ... your test code here ...
    }
}
```

### Container Networks

Create isolated networks for container-to-container communication:

```swift
@Test("Test container networking")
func testNetworking() async throws {
    // Create a network
    let network = try await containerManager.createNetwork("test-network")
    
    // Start a server container with network alias
    let server = try await containerManager.createContainer(
        "alpine/socat",
        CreateContainerSettings(
            exposedPorts: [ExposedPort(port: 8080)],
            aliases: ["test-network": ["my-server"]],
            cmd: ["-d", "-d", "-v", "tcp-l:8080,fork", "exec:echo \"Hello\""]
        )
    )
    
    // Start a client container on the same network
    let client = try await containerManager.createContainer(
        "busybox:latest",
        CreateContainerSettings(
            networks: ["test-network"],
            cmd: ["nc", "my-server", "8080"]
        )
    )
}
```

### Log Monitoring

Monitor container output and wait for specific patterns:

```swift
// Stream container logs
try await container.logOutput { logLine in
    print("Container log: \(logLine)")
}

// Wait for a specific log pattern
try await container.waitForLogLineRegex("Server started on port", timeout: 30)
```

### Volume Mounting

Mount host directories or Docker socket:

```swift
let container = try await containerManager.createContainer(
    "docker:dind",
    CreateContainerSettings(
        volumeBinds: [
            "/var/run/docker.sock:/var/run/docker.sock",
            "/path/to/host/dir:/container/dir"
        ],
        privileged: true
    )
)
```

## Architecture

### Core Components

- **TestContainerManager**: Main entry point for managing containers and networks
- **DockerClient**: Low-level Docker API client
- **Container**: Actor representing a running Docker container
- **DockerNetwork**: Represents a Docker network
- **Ryuk**: Automatic resource cleanup sidecar container

### Docker Host Discovery

SwiftTestContainers supports multiple strategies for discovering the Docker host:

1. **TestContainers Standard**: Uses the standard TestContainers discovery mechanism
2. **Environment-based**: Reads from environment variables like `DOCKER_HOST`

The library automatically tries these strategies in order until a working Docker connection is found.

## Testing

Run the test suite:

```bash
swift test
```

The test suite includes:
- Container connectivity tests
- Network isolation tests  
- Docker locator tests
- URL resolution tests

## License

SwiftTestContainers is licensed under the GNU General Public License v3.0. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. Contributors must submit an IRL AI LLC CLA.

## Acknowledgments

This project is inspired by the [Testcontainers](https://testcontainers.org/) project and brings similar functionality to the Swift ecosystem.