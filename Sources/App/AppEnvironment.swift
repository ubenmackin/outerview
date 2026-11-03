// App — Shared process-environment probes for tests and screenshot runs.
import Foundation

/// Single owner for environment probes; call sites never read env directly.
enum AppEnvironment {
    /// True under XCTest; daemon sessions and modal presentation stay inert there.
    nonisolated static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
