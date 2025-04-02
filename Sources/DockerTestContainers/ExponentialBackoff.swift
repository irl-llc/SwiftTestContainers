
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

