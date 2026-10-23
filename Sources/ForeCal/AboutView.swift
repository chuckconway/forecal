import AppKit
import SwiftUI

/// Version, credits, and what leaves the Mac. In the panel, like the calendar
/// chooser, because a separate About window would open behind other apps once
/// the panel closes.
struct AboutView: View {
    static let repository = URL(string: "https://github.com/chuckconway/forecal")!

    let done: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("About")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Theme.separator.frame(height: 1)

            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("ForeCal")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)
                Text(version)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                Text("A menu bar calendar that looks ahead: your events, the weather, and when to leave.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Theme.separator.frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                AboutRow(symbol: "lock", text: "Read-only. ForeCal never changes your calendars, and has no server of its own.")
                AboutRow(symbol: "cloud.sun", text: "Weather from Open-Meteo, sent your location rounded to about 1 km.") {
                    Link("open-meteo.com", destination: URL(string: "https://open-meteo.com")!)
                }
                AboutRow(symbol: "car", text: "Drive times from Apple Maps, which receives your location and the address of in-person events.")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Theme.separator.frame(height: 1)

            HStack {
                Text("Free and open source · MIT License")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Link(destination: Self.repository) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct AboutRow<Accessory: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
                    .font(.system(size: 12))
            }
        }
    }
}

extension AboutRow where Accessory == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}
