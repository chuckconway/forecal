import EventKit
import Testing
@testable import ForeCal

@Suite("Menu bar countdown text")
struct MinutesTests {
    @Test("Rounds up, so a countdown never says 0m before the start", arguments: [
        (1, "1m"), (59, "1m"), (60, "1m"), (61, "2m"), (1500, "25m"),
        (3541, "1h"), (3600, "1h"), (4800, "1h 20m"), (7200, "2h"),
    ] as [(Double, String)])
    func formats(seconds: Double, expected: String) {
        #expect(NextUp.minutes(seconds) == expected)
    }
}

@Suite("Menu bar status")
@MainActor
struct NextUpStatusTests {
    let now = Fixtures.now

    private func status(_ events: [EKEvent], trips: [EKEvent: Double] = [:]) -> MenuBarStatus? {
        NextUp.status(now: now, events: events) { event in
            trips[event].map { Fixtures.trip(to: event, minutes: $0) }
        }
    }

    @Test func nothingSoonShowsNothing() {
        #expect(status([Fixtures.event(start: 45)]) == nil)
        #expect(status([]) == nil)
    }

    @Test func startingWithinHalfAnHour() {
        let result = status([Fixtures.event("Design review", start: 25)])
        #expect(result == MenuBarStatus(text: "Design review · 25m", isLeaveAlert: false))
    }

    @Test func startingWithinAMinuteSaysNow() {
        let result = status([Fixtures.event("Standup", start: 0.5)])
        #expect(result?.text == "Standup · now")
    }

    @Test func leaveAlertBeatsAnEventStartingSooner() {
        let call = Fixtures.event("Call", start: 10)
        let drive = Fixtures.event("Dentist", start: 50)
        let result = status([call, drive], trips: [drive: 30])
        #expect(result == MenuBarStatus(text: "Leave in 20m", isLeaveAlert: true))
    }

    @Test func leaveNowOnceLeaveByArrives() {
        let drive = Fixtures.event("Dentist", start: 30)
        #expect(status([drive], trips: [drive: 30])?.text == "Leave now")
    }

    @Test func noLeaveAlertWhileLeaveByIsFarOff() {
        let drive = Fixtures.event("Dentist", start: 120, location: "100 Main St")
        #expect(status([drive], trips: [drive: 20]) == nil)
    }

    @Test func inProgressShowsEndTime() {
        let meeting = Fixtures.event("Planning", start: -15, length: 60)
        let end = meeting.endDate.formatted(date: .omitted, time: .shortened)
        #expect(status([meeting])?.text == "Planning · ends \(end)")
    }

    @Test func longBlocksArentAnnounced() {
        #expect(status([Fixtures.event("Work", start: -60, length: 9 * 60)]) == nil)
    }

    @Test func longTitlesAreTruncated() {
        let result = status([Fixtures.event("Quarterly business review with finance", start: 10)])
        #expect(result?.text == "Quarterly business re… · 10m")
    }
}
