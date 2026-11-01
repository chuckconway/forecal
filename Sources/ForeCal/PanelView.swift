import AppKit
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var store: CalendarStore
    /// Theme colors are static, so rebuild the panel when the today color changes.
    @AppStorage(Accent.storageKey) private var todayColor = Accent.red.rawValue
    @State private var screen = Screen.calendar

    var body: some View {
        VStack(spacing: 0) {
            switch store.access {
            case _ where screen == .about:
                AboutView { screen = .calendar }
            case .granted where screen == .calendars:
                CalendarPickerView { screen = .calendar }
            case .granted:
                MonthGridView()
                    .padding(12)
                Theme.gridEdge.frame(height: 1)
                // The grid is a fixed header the list scrolls under: a firm edge and
                // a drawn shadow keep them apart even when a gray day band is on top.
                AgendaView()
                    .overlay(alignment: .top) {
                        // Eased stops so the shadow fades out softly instead of ending in a hard band.
                        LinearGradient(stops: [
                            .init(color: Theme.gridShadow, location: 0),
                            .init(color: Theme.gridShadow.opacity(0.4), location: 0.35),
                            .init(color: Theme.gridShadow.opacity(0), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                            .frame(height: 5)
                            .allowsHitTesting(false)
                    }
            case .denied:
                AccessDeniedView()
            case .unknown:
                ProgressView()
                    .padding(40)
            }
            Theme.separator.frame(height: 1)
            FooterView(screen: $screen)
        }
        .id(todayColor)
        .frame(width: 340)
        // The panel's views live on between opens, so put it back on today each
        // time. Doing it on close too keeps the jump out of sight.
        .background(PanelWindowObserver { resetToToday() })
        // Opaque, so light mode doesn't pick up grey from the translucent menu bar window.
        .background(Theme.background)
    }
}

extension PanelView {
    private func resetToToday() {
        screen = .calendar
        store.goToToday()
    }
}

/// Calls `onOpenOrClose` when the window hosting this view becomes or stops
/// being key, which for a menu bar panel means it opened or closed.
private struct PanelWindowObserver: NSViewRepresentable {
    let onOpenOrClose: () -> Void

    func makeNSView(context: Context) -> NSView { WindowView(onOpenOrClose: onOpenOrClose) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowView)?.onOpenOrClose = onOpenOrClose
    }

    private final class WindowView: NSView {
        var onOpenOrClose: () -> Void
        private var observers: [NSObjectProtocol] = []

        init(onOpenOrClose: @escaping () -> Void) {
            self.onOpenOrClose = onOpenOrClose
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            observers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in
                    self?.onOpenOrClose()
                }
            }
        }
    }
}

/// What the panel shows above the footer.
enum Screen { case calendar, calendars, about }

private struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("ForeCal needs calendar access.")
                .font(.headline)
            Text("Turn on Full Access for ForeCal in System Settings › Privacy & Security › Calendars.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
        }
        .padding(24)
    }
}

private struct FooterView: View {
    @EnvironmentObject private var store: CalendarStore
    @AppStorage(Accent.storageKey) private var todayColor = Accent.red.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Binding var screen: Screen

    var body: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            } label: {
                Label("Open Calendar", systemImage: "calendar")
                    .foregroundStyle(Theme.text)
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button("Choose Calendars…") { screen = .calendars }
                    .disabled(store.calendars.isEmpty)
                Picker("Today Color", selection: $todayColor) {
                    ForEach(Accent.allCases) { accent in
                        Text(accent.name).tag(accent.rawValue)
                    }
                }
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: setLaunchAtLogin
                ))
                Divider()
                Button("About ForeCal") { screen = .about }
                Button("Quit ForeCal") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ForeCal: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
