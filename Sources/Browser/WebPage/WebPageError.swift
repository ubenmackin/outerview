//
//  WebPageError.swift
//  OuterView
//

import Foundation

/// User-facing classification of a failed page load.
struct WebPageError: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable, CaseIterable {
        case offline
        case serverTrust
        case other

        var systemImageName: String {
            switch self {
            case .offline:
                "wifi.exclamationmark"
            case .serverTrust:
                "exclamationmark.shield"
            case .other:
                "xmark"
            }
        }
    }

    var code: Int
    var kind: Kind
    var title: String
    var detail: String

    var hint: String? {
        kind == .offline ? "Check your connection and try again." : nil
    }

    var copySummary: String {
        "\(title) (Code \(code))\n\(detail)"
    }

    nonisolated static func make(
        code: Int?,
        hasFailedServerTrustChallenge: Bool,
        detail: String?,
        url: URL? = nil
    ) -> WebPageError {
        let kind: Kind = if code == NSURLErrorNotConnectedToInternet {
            .offline
        } else if hasFailedServerTrustChallenge {
            .serverTrust
        } else {
            .other
        }
        let host = HostFormatter.host(of: url)
        let title: String = switch kind {
        case .offline:
            host.isEmpty ? "Can't Connect" : "Can't Connect to \(host)"
        case .serverTrust:
            "Can't Verify Server"
        case .other:
            "Something Went Wrong"
        }
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedDetail: String = if !trimmed.isEmpty {
            trimmed
        } else if kind == .offline {
            "This page couldn't be loaded."
        } else if kind == .serverTrust {
            "The server's certificate isn't trusted."
        } else {
            "The page couldn't be loaded."
        }
        return WebPageError(code: code ?? 0, kind: kind, title: title, detail: resolvedDetail)
    }
}
