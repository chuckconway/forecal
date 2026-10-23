import AppKit
import EventKit
import SwiftUI

/// `ForeCal --snapshot <dir>` renders the panel offscreen in light and dark
/// appearance to PNGs, then quits. It shows sample events rather than real ones,
/// so it never needs calendar access (ad hoc builds re-prompt on every rebuild)
/// and nobody has to open the menu bar.
@MainActor
enum Snapshot {
    static var outputDirectory: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `ForeCal --hover-test <file>`: shows the panel with sample events on screen
    /// for about a second, moves the real pointer over the agenda while the app is
    /// inactive (as it is with the menu bar panel open), writes which day the grid
    /// picked up for each spot, puts the pointer back, and quits.
    static var hoverTestOutput: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--hover-test"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func runHoverTest(to file: String, store: CalendarStore, weather: WeatherStore, travel: TravelStore) {
        showSample(store: store, weather: weather, travel: travel)
        Task {
            let screen = NSScreen.main!.frame
            let saved = CGEvent(source: nil)?.location ?? .zero
            // The real panel: point at the agenda and see whether the grid's hover state picks a day.
            let hover = HoverState()
            let panel = NSWindow(contentRect: NSRect(x: screen.minX + 20, y: screen.maxY - 800, width: 340, height: 760),
                                 styleMask: .borderless, backing: .buffered, defer: false)
            panel.level = .floating
            panel.contentView = NSHostingView(rootView: PanelView()
                .environmentObject(store).environmentObject(weather).environmentObject(travel).hoverState(hover))
            panel.setContentSize(panel.contentView!.fittingSize)
            panel.setFrameTopLeftPoint(NSPoint(x: screen.minX + 20, y: screen.maxY - 40))
            panel.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))
            var panelResults: [String] = []
            for fromTop in [440.0, 520.0, 640.0] {
                let point = CGPoint(x: panel.frame.minX + 170, y: screen.maxY - panel.frame.maxY + fromTop)
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(300))
                let event = store.agenda.flatMap(\.events).first { $0.id == hover.eventID }
                panelResults.append("\(Int(fromTop))pt from top: \(hover.day?.formatted(date: .abbreviated, time: .omitted) ?? "none")"
                    + ", event: \(event.map { "\($0.event.title ?? "") (\($0.event.calendar.title))" } ?? "none")")
            }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left)?.post(tap: .cghidEventTap)
            panel.orderOut(nil)

            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left)?.post(tap: .cghidEventTap)

            // The calendar chooser's toggles, one after another, as clicking each row does.
            var toggles: [String] = []
            for calendar in store.calendars {
                store.setCalendars([calendar], visible: false)
                let hidden = store.calendars.filter { store.hiddenCalendarIDs.contains($0.calendarIdentifier) }.map(\.title)
                toggles.append("hid \(calendar.title) → hidden [\(hidden.joined(separator: ", "))]")
            }
            store.setCalendars(store.calendars, visible: true)
            toggles.append("Show All → \(store.calendars.filter { store.hiddenCalendarIDs.contains($0.calendarIdentifier) }.count) of them hidden")

            let report = "app active: \(NSApp.isActive)\npanel hover: \(panelResults.joined(separator: "; "))\n"
                + "chooser: \(toggles.joined(separator: "; "))\n"
            try? report.write(toFile: file, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    static func capture(to directory: String, store: CalendarStore, weather: WeatherStore, travel: TravelStore) {
        let hover = HoverState()
        showSample(store: store, weather: weather, travel: travel)
        Task {
            // Give the forecast and drive times a moment to load.
            try? await Task.sleep(for: .seconds(5))
            // Also with tomorrow at the top of the list, where its gray header band
            // meets the grid instead of today's red one.
            let shots: [(String, NSAppearance.Name, Int)] = [
                ("light", .aqua, 0), ("dark", .darkAqua, 0), ("light-tomorrow", .aqua, 1), ("dark-tomorrow", .darkAqua, 1),
            ]
            for (name, appearance, dayOffset) in shots {
                store.selectedDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: store.today)!
                // Hover the selected day: the ring has to show around an existing
                // highlight. The tomorrow shots hover its last event, for the
                // calendar-colored ring.
                hover.day = store.selectedDate
                if dayOffset == 1, let first = store.agenda.first(where: { $0.day == store.selectedDate })?.events.last {
                    hover.enterEvent(first)
                }
                let root = PanelView()
                    .environmentObject(store)
                    .environmentObject(weather)
                    .environmentObject(travel)
                    .hoverState(hover)
                let host = NSHostingView(rootView: root)
                let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.setContentSize(host.fittingSize)
                // Let onAppear scroll the agenda to today before drawing.
                try? await Task.sleep(for: .milliseconds(500))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                await captureScreen(CalendarPickerView {}, store: store, appearance: appearance, to: directory + "/calendars-\(name).png")
                await captureScreen(AboutView {}, store: store, appearance: appearance, to: directory + "/about-\(name).png")
            }
            await captureScrolled(to: directory, store: store, weather: weather, travel: travel)
            await captureAccents(to: directory, store: store, weather: weather, travel: travel)
            exit(0)
        }
    }

    /// A panel screen other than the calendar, at the panel's width.
    private static func captureScreen(_ view: some View, store: CalendarStore, appearance: NSAppearance.Name, to path: String) async {
        let host = NSHostingView(rootView: view.environmentObject(store).frame(width: 340).background(Theme.background))
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        try? await Task.sleep(for: .milliseconds(300))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// One sheet comparing each candidate today color, light above dark: the
    /// grid and the top of the agenda, where today's color shows.
    private static func captureAccents(to directory: String, store: CalendarStore, weather: WeatherStore, travel: TravelStore) async {
        store.selectedDate = store.today
        defer { Theme.accentOverride = nil }

        let crop: CGFloat = 520, label: CGFloat = 30, gap: CGFloat = 16
        var shots: [(String, NSBitmapImageRep)] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for accent in Accent.allCases {
                Theme.accentOverride = accent
                let host = NSHostingView(rootView: PanelView()
                    .environmentObject(store)
                    .environmentObject(weather)
                    .environmentObject(travel)
                    .hoverState(HoverState()))
                let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.setContentSize(host.fittingSize)
                try? await Task.sleep(for: .milliseconds(400))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                shots.append((accent.name, rep))
            }
        }
        guard let first = shots.first?.1 else { return }
        let width = first.size.width, columns = CGFloat(Accent.allCases.count)
        let sheet = NSImage(size: NSSize(width: columns * width + (columns + 1) * gap, height: 2 * (crop + label) + 3 * gap), flipped: true) { rect in
            NSColor(white: 0.5, alpha: 1).setFill()
            rect.fill()
            for (i, (name, rep)) in shots.enumerated() {
                let column = CGFloat(i % Accent.allCases.count), row = CGFloat(i / Accent.allCases.count)
                let x = gap + column * (width + gap), y = gap + row * (crop + label + gap)
                (name as NSString).draw(at: NSPoint(x: x, y: y + 4), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .bold), .foregroundColor: NSColor.white,
                ])
                let image = NSImage(size: rep.size)
                image.addRepresentation(rep)
                // The top `crop` points of the panel: the grid and the first agenda rows.
                image.draw(in: NSRect(x: x, y: y + label, width: width, height: crop),
                           from: NSRect(x: 0, y: rep.size.height - crop, width: width, height: crop),
                           operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            }
            return true
        }
        guard let tiff = sheet.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) else { return }
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory + "/today-colors.png"))
    }

    /// Scrolls the list the way a person would, to check that the day header
    /// stays pinned and that the grid's selected day follows the list.
    private static func captureScrolled(to directory: String, store: CalendarStore, weather: WeatherStore, travel: TravelStore) async {
        store.selectedDate = store.today
        let hover = HoverState()
        let host = NSHostingView(rootView: PanelView()
            .environmentObject(store)
            .environmentObject(weather)
            .environmentObject(travel)
            .hoverState(hover))
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        try? await Task.sleep(for: .milliseconds(500))
        guard let scrollView = host.firstDescendant(of: NSScrollView.self) else { return }

        var report = ""
        report += "start: \(store.selectedDate.formatted(date: .abbreviated, time: .omitted))\n"
        // Scroll-wheel events, not clip view moves: SwiftUI's scroll position
        // tracking only follows scrolling that comes through the event path.
        func wheel(_ points: Int32) async {
            for _ in 0..<abs(points / 20) {
                let delta: Int32 = points > 0 ? -20 : 20
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: cg) else { return }
                scrollView.scrollWheel(with: event)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        for distance in [120.0, 300.0, 520.0] {
            await wheel(Int32(distance))
            try? await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            report += "+\(Int(distance))pt: \(store.selectedDate.formatted(date: .abbreviated, time: .omitted))\n"
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("panel-scrolled-\(Int(distance)).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            // Each step starts from the original position.
            await wheel(-Int32(distance))
            try? await Task.sleep(for: .milliseconds(300))
        }
        try? report.write(toFile: directory + "/scroll.txt", atomically: true, encoding: .utf8)
    }

    /// Sample events, forecasts, and drive times: the same on every Mac, and
    /// nothing from this one.
    private static func showSample(store: CalendarStore, weather: WeatherStore, travel: TravelStore) {
        let events = sampleEvents(in: store.eventStore, now: store.now)
        store.showSample(events)

        let minutes: [String: Double] = ["Pick up Grandma": 35, "Soccer practice": 18, "Gymnastics": 12]
        travel.showSample(Dictionary(uniqueKeysWithValues: events.compactMap { event in
            minutes[event.title ?? ""].map { (event, $0 * 60) }
        }))

        // A plausible fortnight: a few clear days, some cloud, one rainy spell.
        let pattern: [(code: Int, high: Double, low: Double, rain: Int?)] = [
            (2, 71, 56, nil), (0, 73, 55, nil), (3, 68, 54, 10), (61, 62, 51, 80),
            (80, 60, 50, 60), (2, 66, 52, 20), (0, 70, 53, nil),
        ]
        let today = Calendar.current.startOfDay(for: store.now)
        weather.showSample(Dictionary(uniqueKeysWithValues: (0..<16).map { offset in
            let day = pattern[offset % pattern.count]
            return (
                Calendar.current.date(byAdding: .day, value: offset, to: today)!,
                DailyForecast(code: day.code, high: day.high, low: day.low, precipitationChance: day.rain)
            )
        }))
    }

    /// A day that exercises every row style: past, all-day, a call, a drive, tomorrow.
    private static func sampleEvents(in eventStore: EKEventStore, now: Date) -> [EKEvent] {
        func calendar(_ title: String, _ color: NSColor) -> EKCalendar {
            let calendar = EKCalendar(for: .event, eventStore: eventStore)
            calendar.title = title
            calendar.color = color
            return calendar
        }
        let family = calendar("Family", .systemRed)
        let work = calendar("Work", .systemBlue)
        let kids = calendar("Kids", .systemGreen)

        let today = Calendar.current.startOfDay(for: now)
        func event(_ title: String, _ calendar: EKCalendar, minutesFromNow: Double, length: Double,
                   location: String? = nil, url: String? = nil, allDayOffset: Int? = nil) -> EKEvent {
            let event = EKEvent(eventStore: eventStore)
            event.title = title
            event.calendar = calendar
            event.location = location
            event.url = url.flatMap(URL.init(string:))
            if let allDayOffset {
                event.isAllDay = true
                event.startDate = Calendar.current.date(byAdding: .day, value: allDayOffset, to: today)!
                // EventKit's all-day end date is inclusive: same day for a one-day event.
                event.endDate = event.startDate
            } else {
                // Whole quarter hours, like real events.
                let start = now.addingTimeInterval(minutesFromNow * 60)
                let rounded = (start.timeIntervalSinceReferenceDate / 900).rounded() * 900
                event.startDate = Date(timeIntervalSinceReferenceDate: rounded)
                event.endDate = event.startDate.addingTimeInterval(length * 60)
            }
            return event
        }
        return [
            event("Halloween costumes", kids, minutesFromNow: 0, length: 0, allDayOffset: 0),
            event("Morning run", family, minutesFromNow: -120, length: 45),
            event("Design review", work, minutesFromNow: 30, length: 30, url: "https://zoom.us/j/123456789"),
            event("Pick up Grandma", family, minutesFromNow: 100, length: 60, location: "San Francisco International Airport"),
            event("Soccer practice", kids, minutesFromNow: 360, length: 90, location: "Golden Gate Park"),
            event("1:1 with Dana", work, minutesFromNow: 24 * 60 + 60, length: 30, url: "https://meet.google.com/abc-defg-hij"),
            event("Gymnastics", kids, minutesFromNow: 24 * 60 + 600, length: 60, location: "City Gym, 100 Main St"),
        ]
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(of: type) { return match }
        }
        return nil
    }
}
