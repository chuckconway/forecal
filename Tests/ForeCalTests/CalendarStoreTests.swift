import EventKit
import Testing
@testable import ForeCal

@Suite("Calendar loading")
@MainActor
struct CalendarStoreTests {
    private func store(with events: [EKEvent]) -> CalendarStore {
        let store = CalendarStore(requestsAccess: false)
        store.showSample(events, now: Fixtures.now)
        return store
    }

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Fixtures.now))!
    }

    @Test func multiDayEventsAppearOnEachDay() {
        let trip = Fixtures.event("Trip", start: 0, length: 2 * 24 * 60)
        let store = store(with: [trip])
        for offset in 0...2 {
            #expect(store.events(on: day(offset)).map(\.title) == ["Trip"], "day \(offset)")
        }
        #expect(store.events(on: day(3)).isEmpty)
    }

    @Test func eventEndingAtMidnightStaysOnItsDay() {
        // 10 PM to midnight.
        let late = Fixtures.event("Late", start: 12 * 60, length: 2 * 60)
        let store = store(with: [late])
        #expect(store.events(on: day(0)).count == 1)
        #expect(store.events(on: day(1)).isEmpty)
    }

    @Test func allDayEventsListFirst() {
        let morning = Fixtures.event("Morning", start: -60)
        let allDay = Fixtures.event("Holiday", start: -10 * 60, length: 24 * 60, allDay: true)
        #expect(store(with: [morning, allDay]).events(on: day(0)).map(\.title) == ["Holiday", "Morning"])
    }

    @Test func upcomingCountsAMultiDayEventOnce() {
        let conference = Fixtures.event("Conference", start: 60, length: 2 * 24 * 60)
        let lunch = Fixtures.event("Lunch", start: 120)
        let upcoming = store(with: [lunch, conference]).upcomingEvents(from: Fixtures.now, through: day(3))
        #expect(upcoming.map(\.title) == ["Conference", "Lunch"])
    }

    @Test func upcomingSkipsAllDayAndPastEvents() {
        let allDay = Fixtures.event("Holiday", start: -10 * 60, length: 24 * 60, allDay: true)
        let earlier = Fixtures.event("Earlier", start: -120, length: 60)
        let later = Fixtures.event("Later", start: 60)
        let upcoming = store(with: [allDay, earlier, later]).upcomingEvents(from: Fixtures.now, through: day(1))
        #expect(upcoming.map(\.title) == ["Later"])
    }
}
