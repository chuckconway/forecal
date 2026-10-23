import EventKit
import SwiftUI

/// Chooses which calendars appear, grouped by account. Lives in the panel rather
/// than a menu, because a menu closes after every click.
struct CalendarPickerView: View {
    @EnvironmentObject private var store: CalendarStore
    let done: () -> Void

    private var groups: [(account: String, calendars: [EKCalendar])] {
        Dictionary(grouping: store.calendars) { $0.source?.title ?? "Other" }
            .map { (account: $0.key, calendars: $0.value) }
            .sorted { $0.account < $1.account }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Calendars")
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups, id: \.account) { group in
                        Section {
                            ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                                CalendarRow(calendar: calendar)
                            }
                        } header: {
                            AccountHeader(account: group.account, calendars: group.calendars)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .frame(height: 640)
    }
}

private struct AccountHeader: View {
    @EnvironmentObject private var store: CalendarStore
    let account: String
    let calendars: [EKCalendar]

    var body: some View {
        let shown = calendars.filter { !store.hiddenCalendarIDs.contains($0.calendarIdentifier) }.count
        HStack {
            Text(account.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.3)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button("Show All") { store.setCalendars(calendars, visible: true) }
                .disabled(shown == calendars.count)
            Button("Hide All") { store.setCalendars(calendars, visible: false) }
                .disabled(shown == 0)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.band)
    }
}

private struct CalendarRow: View {
    @EnvironmentObject private var store: CalendarStore
    let calendar: EKCalendar

    var body: some View {
        // The whole row toggles, not just the checkbox, so it's an easy target.
        Toggle(isOn: Binding(
            get: { !store.hiddenCalendarIDs.contains(calendar.calendarIdentifier) },
            set: { store.setCalendars([calendar], visible: $0) }
        )) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: calendar.color))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}
