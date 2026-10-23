import AppKit
import EventKit

/// What the menu bar shows beside the date icon. Notifications are off, so this
/// is the only heads-up for what's next.
struct MenuBarStatus: Equatable {
    let text: String
    /// Shows a car: it's time to leave for an in-person event.
    let isLeaveAlert: Bool
}

@MainActor
enum NextUp {
    /// How soon an event (or its leave-by time) has to be before the menu bar mentions it.
    static let window: TimeInterval = 30 * 60
    /// Long blocks ("Work", "Vacation") aren't worth announcing while in progress.
    private static let longestInProgress: TimeInterval = 8 * 3600
    private static let maxTitleLength = 22

    static func status(now: Date, calendar: CalendarStore, travel: TravelStore) -> MenuBarStatus? {
        status(
            now: now,
            events: calendar.upcomingEvents(from: now, through: now.addingTimeInterval(TravelStore.horizon)),
            trip: travel.trip(for:)
        )
    }

    /// In priority order: time to leave, starting soon, in progress.
    /// `events` are timed events overlapping now onward, soonest first.
    static func status(now: Date, events: [EKEvent], trip: (EKEvent) -> Trip?) -> MenuBarStatus? {
        let leaving = events
            .compactMap { event in trip(event).map { (event, $0) } }
            .filter { event, trip in event.startDate > now && trip.leaveBy.timeIntervalSince(now) <= window }
            .min { $0.1.leaveBy < $1.1.leaveBy }
        if let (_, trip) = leaving {
            let wait = trip.leaveBy.timeIntervalSince(now)
            return MenuBarStatus(text: wait < 60 ? "Leave now" : "Leave in \(minutes(wait))", isLeaveAlert: true)
        }

        if let next = events.first(where: { $0.startDate > now && $0.startDate.timeIntervalSince(now) <= window }) {
            let wait = next.startDate.timeIntervalSince(now)
            return MenuBarStatus(text: "\(title(next)) · \(wait < 60 ? "now" : minutes(wait))", isLeaveAlert: false)
        }

        let current = events
            .filter { $0.startDate <= now && $0.endDate > now && $0.endDate.timeIntervalSince($0.startDate) <= longestInProgress }
            .max { $0.startDate < $1.startDate }
        if let current {
            return MenuBarStatus(
                text: "\(title(current)) · ends \(current.endDate.formatted(date: .omitted, time: .shortened))",
                isLeaveAlert: false
            )
        }
        return nil
    }

    /// "25m", "1h", "1h 20m". Rounded up so "starts in 1m" never means it already started.
    nonisolated static func minutes(_ interval: TimeInterval) -> String {
        let total = Int((interval / 60).rounded(.up))
        if total < 60 { return "\(total)m" }
        return total % 60 == 0 ? "\(total / 60)h" : "\(total / 60)h \(total % 60)m"
    }

    private static func title(_ event: EKEvent) -> String {
        let title = (event.title ?? "Untitled").trimmingCharacters(in: .whitespaces)
        guard title.count > maxTitleLength else { return title }
        return title.prefix(maxTitleLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// The whole menu bar item as one template image: optional status text, then
/// the date icon. MenuBarExtra labels drop all but the first view of an HStack,
/// so drawing it as one image is the reliable way to show both.
enum StatusIcon {
    static func image(date: Date, status: MenuBarStatus?) -> NSImage {
        let icon = DateIcon.image(for: date)
        guard let status else { return icon }

        let font = NSFont.menuBarFont(ofSize: 0)
        let text = NSAttributedString(string: status.text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        let car = status.isLeaveAlert
            ? NSImage(systemSymbolName: "car.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: font.pointSize - 1, weight: .medium))
            : nil
        let carWidth = car.map { $0.size.width + 4 } ?? 0
        let gap: CGFloat = 5
        let size = NSSize(
            width: ceil(carWidth + textSize.width + gap + icon.size.width),
            height: max(icon.size.height, ceil(textSize.height))
        )

        let image = NSImage(size: size, flipped: false) { rect in
            var x: CGFloat = 0
            if let car {
                car.draw(in: NSRect(x: x, y: (rect.height - car.size.height) / 2, width: car.size.width, height: car.size.height))
                x += carWidth
            }
            text.draw(at: NSPoint(x: x, y: (rect.height - textSize.height) / 2))
            x += textSize.width + gap
            icon.draw(in: NSRect(x: x, y: (rect.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "\(status.text), \(icon.accessibilityDescription ?? "")"
        return image
    }
}
