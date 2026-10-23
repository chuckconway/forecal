import Combine
import CoreLocation
import EventKit
import MapKit
import OSLog

/// Drive time from the Mac's location to an upcoming event.
struct Trip {
    let destination: MKMapItem
    let travelTime: TimeInterval
    let eventStart: Date

    /// Rounded down to the minute, so "Leave by 2:41" is never late.
    var leaveBy: Date {
        let raw = eventStart.addingTimeInterval(-travelTime)
        return Calendar.current.dateInterval(of: .minute, for: raw)!.start
    }

    var minutes: Int { Int((travelTime / 60).rounded(.up)) }

    func openDirections() {
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// Looks up drive times for upcoming in-person events with MapKit.
@MainActor
final class TravelStore: ObservableObject {
    /// How far ahead to look up drive times.
    static let horizon: TimeInterval = 48 * 3600
    /// Shorter trips aren't worth a badge (you're probably already there).
    private static let minimumTravel: TimeInterval = 5 * 60
    /// Longer trips are probably a wrong match or a flight.
    private static let maximumTravel: TimeInterval = 4 * 3600

    private static let log = Logger(subsystem: "com.cconway.ForeCal", category: "travel")

    @Published private(set) var trips: [String: Trip] = [:]

    private struct Lookup {
        let travelTime: TimeInterval?
        let origin: CLLocation
        let checkedAt: Date
    }

    private let calendar: CalendarStore
    private let location: LocationStore
    /// Search results by location text; nil means nothing was found, so don't search again.
    private var destinations: [String: MKMapItem?] = [:]
    private var lookups: [String: Lookup] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var updating = false

    init(calendar: CalendarStore, location: LocationStore) {
        self.calendar = calendar
        self.location = location
        // The calendar ticks every minute, which is also when stale drive times get refreshed.
        calendar.$now.combineLatest(calendar.$eventsByDay, location.$location)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { await self?.update() } }
            .store(in: &subscriptions)
    }

    func trip(for event: EKEvent) -> Trip? {
        trips[event.occurrenceKey]
    }

    private func update() async {
        guard !updating, let origin = location.location else { return }
        updating = true
        defer { updating = false }

        let now = Date()
        let upcoming = calendar.upcomingEvents(from: now, through: now.addingTimeInterval(Self.horizon))
            .filter { $0.startDate > now && Self.physicalLocation(of: $0) != nil }

        var next: [String: Trip] = [:]
        for event in upcoming {
            let key = event.occurrenceKey
            if needsLookup(lookups[key], origin: origin, start: event.startDate, now: now) {
                lookups[key] = Lookup(
                    travelTime: await travelTime(to: event, from: origin),
                    origin: origin,
                    checkedAt: now
                )
            }
            guard let travelTime = lookups[key]?.travelTime,
                  let destination = destinations[Self.physicalLocation(of: event)!] ?? nil
            else { continue }
            next[key] = Trip(destination: destination, travelTime: travelTime, eventStart: event.startDate)
        }
        let upcomingKeys = Set(upcoming.map(\.occurrenceKey))
        lookups = lookups.filter { upcomingKeys.contains($0.key) }
        trips = next
        Self.log.debug("\(upcoming.count) in-person events, \(next.count) with drive times: \(next.values.map { "leave \($0.leaveBy.formatted(date: .omitted, time: .shortened)), \($0.minutes)m" }.joined(separator: "; "), privacy: .public)")
    }

    /// Traffic matters more as the event gets close, so refresh sooner then.
    private func needsLookup(_ lookup: Lookup?, origin: CLLocation, start: Date, now: Date) -> Bool {
        guard let lookup else { return true }
        if lookup.origin.distance(from: origin) > 1_000 { return true }
        let maxAge: TimeInterval = start.timeIntervalSince(now) < 2 * 3600 ? 10 * 60 : 60 * 60
        return now.timeIntervalSince(lookup.checkedAt) > maxAge
    }

    private func travelTime(to event: EKEvent, from origin: CLLocation) async -> TimeInterval? {
        guard let destination = await destination(for: event, near: origin) else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
        request.destination = destination
        request.transportType = .automobile
        request.departureDate = max(Date(), event.startDate.addingTimeInterval(-30 * 60))
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            guard (Self.minimumTravel...Self.maximumTravel).contains(eta.expectedTravelTime) else {
                Self.log.debug("Skipping drive time of \(Int(eta.expectedTravelTime / 60)) min for \(event.location ?? "", privacy: .public): outside the useful range")
                return nil
            }
            return eta.expectedTravelTime
        } catch {
            NSLog("ForeCal: drive time failed for \(event.title ?? "event"): \(error)")
            return nil
        }
    }

    private func destination(for event: EKEvent, near origin: CLLocation) async -> MKMapItem? {
        guard let text = Self.physicalLocation(of: event) else { return nil }
        if let cached = destinations[text] { return cached }

        var item: MKMapItem?
        // Calendar often stores the exact coordinate when the location was picked from Maps.
        if let geo = event.structuredLocation?.geoLocation {
            item = MKMapItem(placemark: MKPlacemark(coordinate: geo.coordinate))
            item?.name = event.structuredLocation?.title ?? text
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
            item = try? await MKLocalSearch(request: request).start().mapItems.first
            if item == nil { Self.log.debug("No map match for \(text, privacy: .public)") }
        }
        destinations[text] = .some(item)
        return item
    }

    private static let virtualPattern = try! NSRegularExpression(
        pattern: #"\b(zoom|teams|google meet|webex|facetime|online|virtual|phone|conference call|room|tbd|tba)\b"#,
        options: .caseInsensitive
    )
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The event's location if it names a place, rather than a call link.
    static func physicalLocation(of event: EKEvent) -> String? {
        guard let text = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if virtualPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return nil }
        if linkDetector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url?.scheme?.hasPrefix("http") == true {
            return nil
        }
        return text
    }
}
