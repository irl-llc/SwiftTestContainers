//

import Foundation
import Logging

private let defaultURL: URL = {
  let host = "/var/run/docker.sock".addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
  let url = URL(string: "http+unix://\(host)")!
  logger.info("Default docker URL is \(url)")
  return url
}()

private let logger = Logger(label: "llc.irl.DockerTestContainers.EnvironmentBasedDockerLocator")

class EnvironmentBasedDockerLocator: DockerLocator {
  func locate() -> URL? {
    // Check for DOCKER_HOST environment variable
    if let dockerHost = ProcessInfo.processInfo.environment["DOCKER_HOST"] {
      return URL(string: dockerHost)
    }
    return defaultURL
  }
}

