// Security — Biometric gate for private tabs.

import Foundation
import LocalAuthentication
import os

/// Protocol abstracting biometric verification for test isolation and production use.
@MainActor
protocol BiometricAuthenticating: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func authenticate(reason: String) async -> Bool
}

/// System Face ID / Touch ID / Passcode evaluator for guarding private tabs.
@MainActor
final class BiometricAuthService: BiometricAuthenticating {
    static let shared = BiometricAuthService()

    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Fail closed when no passcode or biometrics are enrolled.
            Logger(subsystem: "com.volcrypt.OuterView", category: "Security")
                .error("Biometrics unavailable: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Security")
                .notice("Biometric authentication failed or cancelled: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
