import EventKit
import MapKit
@testable import ForeCal

/// Builds unsaved events for tests. EventKit lets you create these without
/// calendar access, the same way snapshot mode builds its sample events.
enum Fixtures {
    static let store = EKEventStore()
    static let calendar = EKCalendar(for: .event, eventStore: store)

    /// A fixed reference time, so tests don't depend on when they run.
    static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 10))!

    static func event(
        _ title: String = "Event",
        start minutesFromNow: Double,
        length minutes: Double = 60,
        location: String? = nil,
        notes: String? = nil,
        url: String? = nil,
        allDay: Bool = false
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.startDate = now.addingTimeInterval(minutesFromNow * 60)
        event.endDate = event.startDate.addingTimeInterval(minutes * 60)
        event.isAllDay = allDay
        event.location = location
        event.notes = notes
        event.url = url.flatMap(URL.init(string:))
        return event
    }

    static func trip(to event: EKEvent, minutes: Double) -> Trip {
        Trip(
            destination: MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 37.77, longitude: -122.42))),
            travelTime: minutes * 60,
            eventStart: event.startDate
        )
    }
}
