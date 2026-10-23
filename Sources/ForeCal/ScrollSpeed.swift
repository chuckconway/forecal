import AppKit

/// Speeds up scrolling in the panel. SwiftUI's ScrollView has no speed setting,
/// so this rescales scroll-wheel events before they reach it. A local monitor
/// only sees this app's events, which for a menu bar app means the panel.
enum ScrollSpeed {
    static let multiplier: Double = 1.6
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            scaled(event) ?? event
        }
    }

    private static func scaled(_ event: NSEvent) -> NSEvent? {
        guard let cg = event.cgEvent?.copy() else { return nil }
        // Trackpads report pixel deltas; mouse wheels report line deltas.
        // AppKit reads whichever applies, so scale all of them.
        for field: CGEventField in [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
                                    .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
            cg.setDoubleValueField(field, value: cg.getDoubleValueField(field) * multiplier)
        }
        for field: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2] {
            let value = Double(cg.getIntegerValueField(field)) * multiplier
            cg.setIntegerValueField(field, value: Int64(value.rounded(.awayFromZero)))
        }
        return NSEvent(cgEvent: cg)
    }
}
