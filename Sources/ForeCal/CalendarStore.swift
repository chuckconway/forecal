import AppKit
import EventKit
import OSLog
import SwiftUI

/// One occurrence of an event on a given day. Recurring events share an
/// identifier, and multi-day events appear under several days, so the id
/// combines both.
struct DayEvent: Identifiable {
    let event: EKEvent
    let day: Date
    var id: String { "\(event.occurrenceKey)-\(day.timeIntervalSince1970)" }
}

extension EKEvent {
    /// Recurring events share an identifier, so the start date tells occurrences apart.
    var occurrenceKey: String { "\(calendarItemIdentifier)-\(startDate.timeIntervalSince1970)" }
}

struct AgendaDay: Identifiable {
    let day: Date
    let events: [DayEvent]
    var id: Date { day }
}

@MainActor
final class CalendarStore: ObservableObject {
    enum Access { case unknown, granted, denied }

    /// How many days the scrolling agenda reaches either side of today.
    static let agendaReach = 365
    private static let hiddenKey = "hiddenCalendarIDs"
    private static let log = Logger(subsystem: "com.cconway.ForeCal", category: "calendar")

    let eventStore = EKEventStore()

    @Published private(set) var access: Access = .unknown
    @Published private(set) var now = Date()
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var eventsByDay: [Date: [EKEvent]] = [:]
    /// Every day in the loaded range, so the list scrolls continuously and any
    /// day picked in the grid has a row to scroll to.
    @Published private(set) var agenda: [AgendaDay] = []
    private var loadedRange: Range<Date>?
    /// Stand-in events for snapshots, used instead of EventKit when set.
    private var sampleEvents: [EKEvent]?

    @Published var displayedMonth: Date {
        didSet { if !loadedRangeCoversGrid { reload() } }
    }
    /// The day at the top of the agenda. Scrolling the list sets it, and setting
    /// it (from the grid) scrolls the list.
    @Published var selectedDate: Date {
        didSet {
            let month = monthStart(selectedDate)
            if month != displayedMonth { displayedMonth = month }
        }
    }
    @Published var hiddenCalendarIDs: Set<String> {
        didSet {
            // Sample calendars are made up; saving them would clobber the real choice.
            if sampleEvents == nil {
                UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenKey)
            }
            reload()
        }
    }

    private var cal: Calendar { Calendar.current }
    private var storeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?

    /// `requestsAccess: false` never touches EventKit permissions, for snapshots
    /// that show sample events and shouldn't trigger a calendar access prompt.
    init(requestsAccess: Bool = true) {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDate = today
        displayedMonth = Calendar.current.dateInterval(of: .month, for: today)!.start
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])

        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        // A tick on each minute boundary keeps the menu bar countdown and the now
        // line in step with the clock, and catches day rollovers.
        let nextMinute = Calendar.current.dateInterval(of: .minute, for: Date())!.end
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Timers stall during sleep, so catch up as soon as the Mac wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        if requestsAccess {
            Task { await requestAccess() }
        }
    }

    // MARK: - Access

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
        default:
            access = .denied
        }
        reload()
        // Under the hardened runtime a missing entitlement shows up only as denied
        // access, so record the outcome where `log show` can find it.
        Self.log.notice("Calendar access \(String(describing: self.access), privacy: .public): \(self.calendars.count) calendars, \(self.eventsByDay.count) days with events")
    }

    // MARK: - Navigation

    var today: Date { cal.startOfDay(for: now) }

    func goToToday() {
        selectedDate = today
    }

    func shiftMonth(by months: Int) {
        displayedMonth = cal.date(byAdding: .month, value: months, to: displayedMonth)!
    }

    private func tick() {
        guard sampleEvents == nil else { return }
        let previousToday = today
        now = Date()
        guard today != previousToday else { return }
        if selectedDate == previousToday { selectedDate = today }
        reload()
    }

    // MARK: - Derived data

    /// Six full weeks starting on the locale's first weekday.
    var gridDays: [Date] {
        let weekday = cal.component(.weekday, from: displayedMonth)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -offset, to: displayedMonth)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    var weekdaySymbols: [String] {
        let symbols = cal.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var loadedRangeCoversGrid: Bool {
        guard let range = loadedRange else { return false }
        let days = gridDays
        return range.contains(days.first!) && range.contains(days.last!)
    }

    func events(on day: Date) -> [EKEvent] {
        eventsByDay[day] ?? []
    }

    /// Timed events overlapping the window, soonest first, without ones you've
    /// declined. Multi-day events are bucketed under several days, so dedupe.
    func upcomingEvents(from start: Date, through end: Date) -> [EKEvent] {
        var seen: Set<String> = []
        var result: [EKEvent] = []
        var day = cal.startOfDay(for: start)
        while day < end {
            for event in events(on: day) where !event.isAllDay && event.endDate > start && event.startDate < end {
                guard !Self.isDeclined(event), event.status != .canceled else { continue }
                if seen.insert(event.occurrenceKey).inserted { result.append(event) }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result.sorted { $0.startDate < $1.startDate }
    }

    static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    func isInDisplayedMonth(_ day: Date) -> Bool {
        cal.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    /// Shows or hides several calendars with one reload.
    func setCalendars(_ calendars: [EKCalendar], visible: Bool) {
        let ids = Set(calendars.map(\.calendarIdentifier))
        hiddenCalendarIDs = visible ? hiddenCalendarIDs.subtracting(ids) : hiddenCalendarIDs.union(ids)
    }

    // MARK: - Loading

    /// `now` stays put for samples, so snapshots look the same whenever they're taken.
    func showSample(_ events: [EKEvent], now: Date) {
        sampleEvents = events
        self.now = now
        access = .granted
        reload()
    }

    func reload() {
        guard access == .granted else {
            calendars = []
            eventsByDay = [:]
            agenda = []
            loadedRange = nil
            return
        }
        calendars = (sampleEvents.map { Array(Set($0.map(\.calendar))) } ?? eventStore.calendars(for: .event))
            // Calendars without an account (sample ones) have a nil source despite the `!` type.
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        let visible = calendars.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }

        let days = gridDays
        let start = min(days.first!, cal.date(byAdding: .day, value: -Self.agendaReach, to: today)!)
        let end = max(
            cal.date(byAdding: .day, value: 1, to: days.last!)!,
            cal.date(byAdding: .day, value: Self.agendaReach + 1, to: today)!
        )
        loadedRange = start..<end

        var buckets: [Date: [EKEvent]] = [:]
        // An empty calendar list means "all calendars" to EventKit, so skip the fetch.
        let events = sampleEvents ?? (visible.isEmpty
            ? []
            : eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: visible)))
        for event in events {
            // An event ending exactly at midnight doesn't belong to the next day.
            let lastMoment: Date = event.endDate > event.startDate ? event.endDate.addingTimeInterval(-1) : event.startDate
            var day = cal.startOfDay(for: max(event.startDate, start))
            while day <= lastMoment && day < end {
                buckets[day, default: []].append(event)
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }
        for key in buckets.keys {
            buckets[key]!.sort(by: Self.displayOrder)
        }
        eventsByDay = buckets

        var agendaDays: [AgendaDay] = []
        var day = start
        while day < end {
            let events = (buckets[day] ?? []).map { DayEvent(event: $0, day: day) }
            agendaDays.append(AgendaDay(day: day, events: events))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        agenda = agendaDays
    }

    private static func displayOrder(_ a: EKEvent, _ b: EKEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.startDate != b.startDate { return a.startDate < b.startDate }
        return (a.title ?? "") < (b.title ?? "")
    }

    private func monthStart(_ date: Date) -> Date {
        cal.dateInterval(of: .month, for: date)!.start
    }
}
