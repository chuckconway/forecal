import SwiftUI

/// The agenda day under the pointer, ringed in the month grid. Kept apart from
/// CalendarStore so pointer moves redraw only the grid cells that observe it.
@MainActor
final class HoverState: ObservableObject {
    @Published var day: Date?
    /// The event under the pointer, if any: its calendar color tints the ring.
    @Published private(set) var eventID: String?
    @Published private(set) var eventColor: Color?

    func enterEvent(_ item: DayEvent) {
        day = item.day
        eventID = item.id
        eventColor = Color(nsColor: item.event.calendar.color)
    }

    /// Only clears if this event still owns the hover: moving between two rows
    /// can report entering the next before leaving the last. The day stays,
    /// since the pointer is still within that day's section.
    func exitEvent(_ item: DayEvent) {
        guard eventID == item.id else { return }
        eventID = nil
        eventColor = nil
    }
}

/// The agenda writes the hovered day through this key rather than observing
/// HoverState, so its rows don't redraw on every pointer move.
private struct HoverStateKey: EnvironmentKey {
    static let defaultValue: HoverState? = nil
}

extension EnvironmentValues {
    var hoverState: HoverState? {
        get { self[HoverStateKey.self] }
        set { self[HoverStateKey.self] = newValue }
    }
}

extension View {
    /// Supplies the hover state to the grid (observing) and the agenda (writing).
    func hoverState(_ hover: HoverState) -> some View {
        environmentObject(hover).environment(\.hoverState, hover)
    }

    /// Marks this agenda row as `item` for hover highlighting in its calendar color.
    func hoverEvent(_ item: DayEvent) -> some View {
        modifier(HoverEventModifier(item: item))
    }

    /// Marks this agenda view as belonging to `day` for hover highlighting.
    func hoverDay(_ day: Date) -> some View {
        modifier(HoverDayModifier(day: day))
    }
}

private struct HoverDayModifier: ViewModifier {
    @Environment(\.hoverState) private var hover
    let day: Date

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                hover?.day = day
            } else if hover?.day == day {
                // Moving between a day's header and its rows exits one and enters
                // the other; only clear if nothing else has claimed the hover.
                hover?.day = nil
            }
        }
    }
}

private struct HoverEventModifier: ViewModifier {
    @Environment(\.hoverState) private var hover
    let item: DayEvent

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { hover?.enterEvent(item) } else { hover?.exitEvent(item) }
        }
    }
}
