//

import Foundation
import Logging

class TestContainersDockerLocator: DockerLocator {
  let baseDirectory: URL?
  static let logger = Logger(label: "llc.irl.DockerTestContainers.TestContainersDockerLocator")
  
  private static let homeDir = getHomeDir()
  
  init(baseDirectory: URL? = homeDir) {
    self.baseDirectory = baseDirectory
  }
  
  private static func getHomeDir() -> URL? {
    // In an iOS test, XCTestRunner sets HOME to a directory that looks like
    // /Users/username/Library/Developer/CoreSimulator/Devices/49FEA876-C9F3-478B-B562-C463B8F0356B/data.
    // If the environment variable matches this format, then remove the part after the user's home directory
    if let homeFromHomeEnv = homeFromHomeEnvVar() {
      return URL(string: "file://\(homeFromHomeEnv)")!
    }
    if let homeFromUserEnv = homeFromUserEnvVar() {
      return URL(string: "file://\(homeFromUserEnv)")!
    }
    logger.warning("Could not find a home directory to search for TestContainers config file. TestContainers-based Docker will not be available.")
    return .none
  }
  
  private static func homeFromUserEnvVar() -> String? {
    guard let userEnv = ProcessInfo.processInfo.environment["USER"] else {
      logger.debug("USER environment variable not set")
      return .none
    }
    let fileManager = FileManager.default
    let usersRootHomeDirectory = "/Users/\(userEnv)"
    if fileManager.fileExists(atPath: usersRootHomeDirectory) {
      return usersRootHomeDirectory
    }
    let homeRootHomeDirectory = "/home/\(userEnv)"
    if fileManager.fileExists(atPath: homeRootHomeDirectory) {
      return homeRootHomeDirectory
    }
    logger.warning("USER environment variable set to \(userEnv), but \(usersRootHomeDirectory) and \(homeRootHomeDirectory) do not exist")
    return .none
  }
                    
  private static func homeFromHomeEnvVar() -> String? {
    if let simulatorHostHomeEnv = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
      return simulatorHostHomeEnv
    } else {
      logger.debug("SIMULATOR_HOST_HOME environment variable not set")
    }
    guard let homeEnv = ProcessInfo.processInfo.environment["HOME"] else {
      logger.debug("HOME environment variable not set")
      return .none
    }
    logger.debug("HOME environment variable set to \(homeEnv)")
    let dataPathRegex = /(\/Users\/[^\/]+)\/.*\/data/
    guard let match = try? dataPathRegex.wholeMatch(in: homeEnv) else {
      logger.debug("HOME is not in a simulator data path, using HOME as is")
      return homeEnv
    }
    logger.debug("HOME is in a simulator data path, using \(match.output.1) as HOME")
    return String(match.output.1)
  }
  
  func locate() -> URL? {
    guard let baseDirectory = baseDirectory else {
      return .none
    }
    let fileManager = FileManager.default
    let propertiesFilePath = baseDirectory.appendingPathComponent(".testcontainers.properties")
    
    guard fileManager.fileExists(atPath: propertiesFilePath.path) else {
      return nil
    }
    
    do {
      let contents = try String(contentsOf: propertiesFilePath, encoding: .utf8)
      let lines = contents.components(separatedBy: .newlines)
      
      for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmedLine.components(separatedBy: "=")
        if parts[0].trimmingCharacters(in: .whitespaces) == "docker.host", parts.count == 2 {
          let dockerHost = parts[1].trimmingCharacters(in: .whitespaces)
          return URL(string: dockerHost.replacingOccurrences(of: "tcp://", with: "http://"))
        }
      }
    } catch {
      print("Error reading .testcontainers.properties file: \(error)")
    }
    
    return nil
  }
}
