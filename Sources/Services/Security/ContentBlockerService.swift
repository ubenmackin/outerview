// Security — Content blocker compilation plus live rule install.

import Foundation
import os
import WebKit

/// Manages native WebKit content rule compilation and installation for blocking trackers and ads.
@MainActor
final class ContentBlockerService {
    static let shared = ContentBlockerService()
    static let ruleListIdentifier = "OuterViewContentBlockerRules"

    static let defaultRulesJSON = """
    [
      {
        "trigger": {
          "url-filter": ".*doubleclick\\\\.net.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*google-analytics\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*googletagmanager\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*adnxs\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*scorecardresearch\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*quantserve\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*criteo\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*advertising\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*taboola\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*outbrain\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*hotjar\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*analytics\\\\.twitter\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*adservice\\\\.google\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*pagead2\\\\.googlesyndication\\\\.com.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*popunder.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*popup.*",
          "load-type": ["third-party"]
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """

    private(set) var compiledRuleList: WKContentRuleList?
    private struct WeakController {
        weak var value: WKUserContentController?
    }

    private var trackedControllers: [WeakController] = []
    private var isCompiling = false
    private var compileWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastToggle: Task<Void, Never>?

    /// Remembers a live controller so later toggles apply with no restart.
    func track(_ controller: WKUserContentController) {
        trackedControllers.removeAll { $0.value == nil || $0.value === controller }
        trackedControllers.append(WeakController(value: controller))
    }

    /// Single toggle owner: fans the flag out to every live controller.
    /// Toggles serialize through a chain so rapid flips apply in order.
    func setEnabled(_ enabled: Bool, controllers: [WKUserContentController]) async {
        let previous = lastToggle
        let current = Task { @MainActor in
            await previous?.value
            for controller in controllers {
                await applyRules(to: controller, enabled: enabled)
            }
        }
        lastToggle = current
        await current.value
    }

    /// Single toggle owner: fans the flag out to every tracked controller.
    /// Toggles serialize through a chain so rapid flips apply in order.
    func setEnabled(_ enabled: Bool) async {
        let previous = lastToggle
        let current = Task { @MainActor in
            await previous?.value
            trackedControllers.removeAll { $0.value == nil }
            for entry in trackedControllers {
                if let controller = entry.value {
                    await applyRules(to: controller, enabled: enabled)
                }
            }
        }
        lastToggle = current
        await current.value
    }

    /// Compiles or looks up cached content rules asynchronously.
    func loadOrCompileRules() async -> WKContentRuleList? {
        if let compiled = compiledRuleList {
            return compiled
        }
        // Second caller parks on the in-flight compile for the same
        // identifier instead of compiling concurrently.
        if isCompiling {
            await withCheckedContinuation { continuation in
                compileWaiters.append(continuation)
            }
            if let compiled = compiledRuleList {
                return compiled
            }
        }
        guard let store = WKContentRuleListStore.default() else {
            return nil
        }
        isCompiling = true
        defer {
            isCompiling = false
            let waiters = compileWaiters
            compileWaiters = []
            for waiter in waiters {
                waiter.resume()
            }
        }
        // Check if already compiled
        let existing: WKContentRuleList? = await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: Self.ruleListIdentifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
        if let existing {
            compiledRuleList = existing
            return existing
        }
        do {
            let compiled: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                store.compileContentRuleList(
                    forIdentifier: Self.ruleListIdentifier,
                    encodedContentRuleList: Self.defaultRulesJSON
                ) { list, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let list {
                        continuation.resume(returning: list)
                    } else {
                        continuation.resume(throwing: NSError(domain: "ContentBlockerService", code: -1))
                    }
                }
            }
            compiledRuleList = compiled
            return compiled
        } catch {
            // Concurrent compile for the same identifier can fail even when
            // serialized elsewhere; re-check the store before giving up.
            let retry: WKContentRuleList? = await withCheckedContinuation { continuation in
                store.lookUpContentRuleList(forIdentifier: Self.ruleListIdentifier) { list, _ in
                    continuation.resume(returning: list)
                }
            }
            if let retry {
                compiledRuleList = retry
                return retry
            }
            Logger(subsystem: "com.volcrypt.OuterView", category: "Security")
                .error("Content rule compilation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Applies or removes the compiled content blocker rules from a user content controller.
    func applyRules(to controller: WKUserContentController, enabled: Bool) async {
        if !enabled {
            if let compiled = compiledRuleList {
                controller.remove(compiled)
            }
            return
        }
        if let list = await loadOrCompileRules() {
            controller.remove(list)
            controller.add(list)
        }
    }
}
