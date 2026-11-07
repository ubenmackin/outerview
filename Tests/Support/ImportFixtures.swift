//
//  ImportFixtures.swift
//  OuterView
//

import Foundation

private final class FixtureAnchor: NSObject {}

enum ImportFixtures {
    enum FixtureError: Error {
        case missingResource(String)
    }

    static func safariExport() throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: "safari_export_sample", withExtension: "html") else {
            throw FixtureError.missingResource("safari_export_sample.html")
        }
        return try Data(contentsOf: url)
    }

    static func userSafariExport() throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: "user_safari_bookmarks", withExtension: "html") else {
            throw FixtureError.missingResource("user_safari_bookmarks.html")
        }
        return try Data(contentsOf: url)
    }
}
