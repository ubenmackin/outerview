//
//  HistorySegmenterTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

@MainActor
final class HistorySegmenterTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }

    private func makeEntry(title: String, date: Date) -> HistoryEntry {
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return HistoryEntry(
            id: UUID(),
            title: title,
            url: URL(string: "https://example.com/\(slug)")!,
            visitedAt: date
        )
    }

    func testEmptyEntriesReturnsEmptySections() {
        let sections = HistorySegmenter.segment(entries: [], calendar: calendar)
        XCTAssertTrue(sections.isEmpty)
    }

    func testTodaySegments() {
        // "Now" is 2026-10-27 20:00 (Evening)
        let now = makeDate(year: 2026, month: 10, day: 27, hour: 20)

        let morning = makeEntry(title: "Morning Visit", date: makeDate(year: 2026, month: 10, day: 27, hour: 9))
        let afternoon = makeEntry(title: "Afternoon Visit", date: makeDate(year: 2026, month: 10, day: 27, hour: 14))
        let evening = makeEntry(title: "Evening Visit", date: makeDate(year: 2026, month: 10, day: 27, hour: 19))

        let sections = HistorySegmenter.segment(entries: [morning, afternoon, evening], calendar: calendar, relativeTo: now)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].title, "This Evening")
        XCTAssertEqual(sections[0].entries.first?.title, "Evening Visit")
        XCTAssertEqual(sections[1].title, "This Afternoon")
        XCTAssertEqual(sections[1].entries.first?.title, "Afternoon Visit")
        XCTAssertEqual(sections[2].title, "This Morning")
        XCTAssertEqual(sections[2].entries.first?.title, "Morning Visit")
    }

    func testYesterdaySegments() {
        let now = makeDate(year: 2026, month: 10, day: 27, hour: 12)

        let yEvening = makeEntry(title: "Yesterday Eve", date: makeDate(year: 2026, month: 10, day: 26, hour: 21))
        let yMorning = makeEntry(title: "Yesterday Morn", date: makeDate(year: 2026, month: 10, day: 26, hour: 8))

        let sections = HistorySegmenter.segment(entries: [yEvening, yMorning], calendar: calendar, relativeTo: now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Yesterday Evening")
        XCTAssertEqual(sections[1].title, "Yesterday Morning")
    }

    func testPreviousWeekGroupsIntoSingleBucket() {
        let now = makeDate(year: 2026, month: 10, day: 27, hour: 12)
        let twoDaysAgo = makeEntry(title: "Two Days Ago", date: makeDate(year: 2026, month: 10, day: 25, hour: 10))
        let fiveDaysAgo = makeEntry(title: "Five Days Ago", date: makeDate(year: 2026, month: 10, day: 22, hour: 15))
        let sevenDaysAgo = makeEntry(title: "Seven Days Ago", date: makeDate(year: 2026, month: 10, day: 20, hour: 10))

        let sections = HistorySegmenter.segment(
            entries: [sevenDaysAgo, twoDaysAgo, fiveDaysAgo],
            calendar: calendar,
            relativeTo: now
        )
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Previous 7 Days")
        XCTAssertEqual(sections[0].entries.map(\.title), ["Two Days Ago", "Five Days Ago", "Seven Days Ago"])
    }

    func testOlderEntriesGroupIntoOlderBucket() {
        let now = makeDate(year: 2026, month: 10, day: 27, hour: 12)
        let eightDaysAgo = makeEntry(title: "Eight Days Ago", date: makeDate(year: 2026, month: 10, day: 19, hour: 10))
        let oldVisit = makeEntry(title: "Old Visit", date: makeDate(year: 2026, month: 10, day: 5, hour: 10))

        let sections = HistorySegmenter.segment(entries: [oldVisit, eightDaysAgo], calendar: calendar, relativeTo: now)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Older")
        XCTAssertEqual(sections[0].entries.map(\.title), ["Eight Days Ago", "Old Visit"])
    }

    func testPreviousWeekBoundary() {
        let now = makeDate(year: 2026, month: 10, day: 27, hour: 12)
        let sevenDaysAgo = makeEntry(title: "Seven Days Ago", date: makeDate(year: 2026, month: 10, day: 20, hour: 12))
        let eightDaysAgo = makeEntry(title: "Eight Days Ago", date: makeDate(year: 2026, month: 10, day: 19, hour: 12))

        let sections = HistorySegmenter.segment(entries: [eightDaysAgo, sevenDaysAgo], calendar: calendar, relativeTo: now)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Previous 7 Days")
        XCTAssertEqual(sections[0].entries.map(\.title), ["Seven Days Ago"])
        XCTAssertEqual(sections[1].title, "Older")
        XCTAssertEqual(sections[1].entries.map(\.title), ["Eight Days Ago"])
    }
}
