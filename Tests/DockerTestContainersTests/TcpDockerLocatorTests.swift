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
