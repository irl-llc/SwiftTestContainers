@testable import SwiftTestContainers
import Testing
import Foundation

@Suite("TCP Docker Locator Tests", .serialized)
class TcpDockerLocatorTests {
  var locator: EnvironmentBasedDockerLocator
    
  init() {
    locator = EnvironmentBasedDockerLocator()
  }
    
  @Test("Locate with DOCKER_HOST set")
  func locateWithDockerHostSet() {
    setenv("DOCKER_HOST", "tcp://192.168.1.100:2376", 1)
    let result = locator.locate()
    #expect(result?.absoluteString == "tcp://192.168.1.100:2376")
    unsetenv("DOCKER_HOST")
  }
    
  @Test("Locate using default")
  func testLocateWithoutDockerHostSet() {
    unsetenv("DOCKER_HOST")
    let result = locator.locate()
    #expect(result?.absoluteString == "http+unix://%2Fvar%2Frun%2Fdocker.sock")
  }
}
