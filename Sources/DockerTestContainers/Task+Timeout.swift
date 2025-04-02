//

import Foundation
import Logging

private let nanosecondsInSecond: UInt64 = 1_000_000_000

private let logger = Logger(label: "llc.irl.DockerTestContainers.Task")

public extension Task where Failure == Error {
  init(priority: TaskPriority? = nil, timeout: TimeInterval, operation: @escaping @Sendable () async throws -> Success) {
    self = Task(priority: priority) {
      try await withThrowingTaskGroup(of: Success.self) { group -> Success in
        group.addTask(operation: operation)
        group.addTask {
          try await _Concurrency.Task.sleep(nanoseconds: UInt64(timeout * Double(nanosecondsInSecond)))
          logger.debug("Task timed out after \(timeout) seconds")
          throw TimeoutError()
        }
        guard let success = try await group.next() else {
          logger.debug("group.next() failed.")
          throw _Concurrency.CancellationError()
        }
        group.cancelAll()
        return success
      }
    }
  }
}

struct TimeoutError: LocalizedError {
  var errorDescription: String? = "Task timed out before completion"
}
