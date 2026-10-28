//
//  HistorySegmenter.swift
//  OuterView
//

import Foundation

/// Represents a chronological group of history entries with a display title.
@MainActor
struct HistorySection: Identifiable {
    let title: String
    let entries: [HistoryEntry]

    nonisolated var id: String {
        title
    }
}

/// Segments a list of history entries into time buckets:
/// - Today: "This Evening", "This Afternoon", "This Morning"
/// - Yesterday: "Yesterday Evening", "Yesterday Afternoon", "Yesterday Morning"
/// - "Previous 7 Days"
/// - "Older"
@MainActor
enum HistorySegmenter {
    static func segment(
        entries: [HistoryEntry],
        calendar: Calendar = .current,
        relativeTo now: Date = Date()
    ) -> [HistorySection] {
        guard !entries.isEmpty else { return [] }

        let sorted = entries.sorted { $0.visitedAt > $1.visitedAt }
        var sections: [HistorySection] = []
        var currentSectionTitle: String?
        var currentEntries: [HistoryEntry] = []

        for entry in sorted {
            let title = sectionTitle(for: entry.visitedAt, calendar: calendar, relativeTo: now)
            if title == currentSectionTitle {
                currentEntries.append(entry)
            } else {
                if let currentSectionTitle, !currentEntries.isEmpty {
                    sections.append(HistorySection(title: currentSectionTitle, entries: currentEntries))
                }
                currentSectionTitle = title
                currentEntries = [entry]
            }
        }

        if let currentSectionTitle, !currentEntries.isEmpty {
            sections.append(HistorySection(title: currentSectionTitle, entries: currentEntries))
        }

        return sections
    }

    // MARK: - Private

    private static func sectionTitle(
        for date: Date,
        calendar: Calendar,
        relativeTo now: Date
    ) -> String {
        let hour = calendar.component(.hour, from: date)
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? Int.max

        // Future-dated visits cluster with today so they never land in Older.
        if dayDiff <= 0 {
            return timeOfDayTitle(prefix: "This", hour: hour)
        }

        if dayDiff == 1 {
            return timeOfDayTitle(prefix: "Yesterday", hour: hour)
        }

        if (2 ... 7).contains(dayDiff) {
            return "Previous 7 Days"
        }

        return "Older"
    }

    private static func timeOfDayTitle(prefix: String, hour: Int) -> String {
        switch hour {
        case 0 ..< 12:
            "\(prefix) Morning"
        case 12 ..< 17:
            "\(prefix) Afternoon"
        default:
            "\(prefix) Evening"
        }
    }
}
