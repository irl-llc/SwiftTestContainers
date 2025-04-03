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

import Foundation
import Logging

private let nanosecondsInSecond: UInt64 = 1_000_000_000

private let logger = Logger(label: "llc.irl.SwiftTestContainers.Task")

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
