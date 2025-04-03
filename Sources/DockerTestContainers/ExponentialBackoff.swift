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
 
import Logging
import Foundation

struct BackoffError: Error {
  let totalDuration: TimeInterval
  let attempts: Int
  let errors: [any Error]
}

private let backoffLogger = Logger(label: "llc.irl.SwiftTestContainers.Backoff")

func withExponentialBackoff<T: Sendable>(backoffStartingSeconds: TimeInterval = 1,
                               maxBackoffSeconds: TimeInterval = 60,
                               isolation: isolated (any Actor)? = #isolation,
                               _ body: @escaping () async throws -> T) async throws -> T
{
  var currentBackoff = backoffStartingSeconds
  var attempts = 0
  let start = Date()
  var errors = [any Error]()
  while currentBackoff < maxBackoffSeconds {
    do {
      attempts += 1
      return try await body()
    } catch {
      errors.append(error)
      backoffLogger.trace("Backing off due to error: \(error)\nat\n\(Thread.callStackSymbols.joined(separator: "\n"))")
      let backoff = min(currentBackoff, maxBackoffSeconds)
      // Ensure backoff is at least 1 nanosecond
      let safeBackoffNanos = max(1e-9, backoff * 1e9)
      try await Task.sleep(nanoseconds: UInt64(safeBackoffNanos))
      if currentBackoff == 1 {
        currentBackoff = 2
      } else if currentBackoff < 1 {
        currentBackoff = sqrt(currentBackoff)
      } else {
        currentBackoff = currentBackoff * currentBackoff
      }
    }
  }
  throw BackoffError(totalDuration: -start.timeIntervalSinceNow, attempts: attempts, errors: errors)
}

