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

@Suite("Test Containers file docker locator tests")
class TestContainersDockerLocatorTests {
  
  @Test("Can locate docker host from .testcontainers.properties")
  func locateDockerHost() throws {
    // Create a temporary directory for the test
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
    // Create a mock .testcontainers.properties file
    let propertiesContent = """
    testcontainers.reuse.enable = true
    tc.host = tcp://127.0.0.1:63613
    docker.host = tcp://127.0.0.1:2375
    """
    let propertiesFile = tempDir.appendingPathComponent(".testcontainers.properties")
    try propertiesContent.write(to: propertiesFile, atomically: true, encoding: .utf8)
        
    // Initialize TestContainersDockerLocator with the temp directory
    let locator = TestContainersDockerLocator(baseDirectory: tempDir)
        
    // Test the locate() method
    let dockerURL = locator.locate()
    #expect(dockerURL?.absoluteString == "http://127.0.0.1:2375", "Docker URL should match the one in the properties file")
        
    // Clean up
    try? FileManager.default.removeItem(at: tempDir)
  }
    
  @Test("Returns nil when no .testcontainers.properties file is found")
  func locateDockerHostFileNotFound() {
    // Use a non-existent directory
    let nonExistentDir = URL(fileURLWithPath: "/non/existent/directory")
    let locator = TestContainersDockerLocator(baseDirectory: nonExistentDir)
        
    let dockerURL = locator.locate()
        
    #expect(dockerURL == nil, "Docker URL should be nil when .testcontainers.properties file doesn't exist")
  }
}
