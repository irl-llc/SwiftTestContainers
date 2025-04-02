//

import Foundation

protocol DockerLocator {
  func locate() -> URL?
}
