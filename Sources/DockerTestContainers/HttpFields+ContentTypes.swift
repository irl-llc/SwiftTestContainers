import Foundation
import HTTPTypes

extension HTTPFields {
  func isApplicationJson() -> Bool {
    return contains(where: { header in
      header.name.rawName.lowercased() == "content-type" &&
        header.value.lowercased() == "application/json"
    })
  }
}
