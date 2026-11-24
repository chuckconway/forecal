import Foundation
import ServiceManagement

/// Whether macOS starts ForeCal at login.
enum LoginItem {
    private static let registeredPathKey = "login.registeredPath"

    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool, defaults: UserDefaults = .standard) throws {
        if on {
            try SMAppService.mainApp.register()
            defaults.set(Bundle.main.bundlePath, forKey: registeredPathKey)
        } else {
            try SMAppService.mainApp.unregister()
            defaults.removeObject(forKey: registeredPathKey)
        }
    }

    /// macOS remembers a login item by the path it was registered from. When the app has moved since
    /// (the install into /Applications), the entry points at nothing and ForeCal doesn't start at login.
    /// So at launch, a login item registered from somewhere else is registered again from here.
    static func followMove(defaults: UserDefaults = .standard) {
        guard isOn, defaults.string(forKey: registeredPathKey) != Bundle.main.bundlePath else { return }
        try? SMAppService.mainApp.unregister()
        try? set(true, defaults: defaults)
    }
}
