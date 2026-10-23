import EventKit
import SwiftUI

struct AgendaView: View {
    @EnvironmentObject private var store: CalendarStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Pinned headers: a day's header stays at the top, under the grid,
                // until the next day's header pushes it off.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(store.agenda) { day in
                        Section {
                            DayEvents(day: day)
                                .hoverDay(day.day)
                        } header: {
                            DayHeader(day: day)
                                .hoverDay(day.day)
                        }
                        .id(day.day)
                    }
                }
                .scrollTargetLayout()
            }
            // The top visible day drives the grid selection, and picking a day
            // in the grid scrolls the list to it.
            .scrollPosition(id: Binding(
                get: { store.selectedDate },
                set: { if let day = $0 { store.selectedDate = day } }
            ), anchor: .top)
            .scrollIndicators(.never)
            .onAppear {
                // The first jump lands on estimated row heights (the rows above
                // haven't been laid out yet); the second one corrects it.
                proxy.scrollTo(store.selectedDate, anchor: .top)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(store.selectedDate, anchor: .top)
                }
            }
        }
        .frame(height: 380)
    }
}

private struct DayEvents: View {
    @EnvironmentObject private var store: CalendarStore
    let day: AgendaDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if day.events.isEmpty {
                Text("No events")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(Array(day.events.enumerated()), id: \.element.id) { index, item in
                if index == nowLineIndex {
                    NowLine(next: item.event)
                }
                Group {
                    if item.event.isAllDay {
                        AllDayPill(event: item.event)
                    } else {
                        EventRow(item: item)
                    }
                }
                .hoverEvent(item)
            }
            if nowLineIndex == day.events.count {
                NowLine(next: nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where today's now line goes: before the first timed event that hasn't
    /// started, or after the last event once they all have.
    private var nowLineIndex: Int? {
        guard Calendar.current.isDateInToday(day.day), !day.events.isEmpty else { return nil }
        return day.events.firstIndex { !$0.event.isAllDay && $0.event.startDate > store.now } ?? day.events.count
    }
}

private struct DayHeader: View {
    @EnvironmentObject private var weather: WeatherStore
    let day: AgendaDay

    private var isToday: Bool { Calendar.current.isDateInToday(day.day) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name)
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.3)
                .foregroundStyle(isToday ? Theme.today : Theme.text)
            Text(dateText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            if let forecast = weather.forecast(for: day.day) {
                ForecastLabel(forecast: forecast)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque, so rows scrolling under the pinned header don't show through.
        .background(isToday ? Theme.todayBand : Theme.band)
    }

    private var name: String {
        let cal = Calendar.current
        if cal.isDateInToday(day.day) { return "TODAY" }
        if cal.isDateInTomorrow(day.day) { return "TOMORROW" }
        if cal.isDateInYesterday(day.day) { return "YESTERDAY" }
        return day.day.formatted(.dateTime.weekday(.wide)).uppercased()
    }

    /// "Fri 10/23" beside Today/Tomorrow/Yesterday, which don't name the
    /// weekday; plain "10/25" otherwise, with the year outside this one.
    private var dateText: String {
        let cal = Calendar.current
        var style = Date.FormatStyle().month(.defaultDigits).day()
        if !cal.isDate(day.day, equalTo: Date(), toGranularity: .year) {
            style = style.year(.twoDigits)
        }
        let date = day.day.formatted(style)
        if cal.isDateInToday(day.day) || cal.isDateInTomorrow(day.day) || cal.isDateInYesterday(day.day) {
            return "\(day.day.formatted(.dateTime.weekday(.abbreviated))) \(date)"
        }
        return date
    }
}

private struct AllDayPill: View {
    let event: EKEvent

    var body: some View {
        Text(event.title ?? "Untitled")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color(nsColor: event.calendar.color).opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ForecastLabel: View {
    let forecast: DailyForecast

    var body: some View {
        HStack(spacing: 4) {
            // Multicolor symbols draw clouds white, which vanish on a light
            // background, so color the cloud and its accent (sun, rain) explicitly.
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(forecast.colors.base, forecast.colors.accent)
            if let chance = forecast.precipitationChance, chance >= 30 {
                Text("\(chance)%")
                    .foregroundStyle(Theme.rain)
            }
            Text("\(Int(forecast.high.rounded()))°")
            Text("\(Int(forecast.low.rounded()))°")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text)
        .monospacedDigit()
    }
}

/// Red marker for the current time in today's list.
private struct NowLine: View {
    @EnvironmentObject private var store: CalendarStore
    let next: EKEvent?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.today)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.today)
                .monospacedDigit()
            Rectangle()
                .fill(Theme.today.opacity(0.7))
                .frame(height: 1)
        }
        .padding(.vertical, 1)
    }

    private var label: String {
        let time = store.now.formatted(date: .omitted, time: .shortened)
        guard let next else { return time }
        return "\(time) · next in \(NextUp.minutes(next.startDate.timeIntervalSince(store.now)))"
    }
}

private struct EventRow: View {
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var travel: TravelStore
    @State private var expanded = false
    let item: DayEvent

    private var event: EKEvent { item.event }

    var body: some View {
        let isPast = !event.isAllDay && event.endDate < store.now
        let meetingURL = MeetingLink.find(in: event)
        let trip = travel.trip(for: event)

        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.calendar.color))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(timeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(event.title ?? "Untitled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(expanded ? nil : 1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(expanded ? nil : 1)
                }
                if let trip, event.startDate > store.now {
                    LeaveByBadge(trip: trip)
                }
                if expanded {
                    details
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                if let meetingURL, !isPast {
                    Button("Join") { NSWorkspace.shared.open(meetingURL) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
                if let trip, !isPast {
                    Button("Directions") { trip.openDirections() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(isPast ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
    }

    @ViewBuilder
    private var details: some View {
        Text(event.calendar.title)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
        if let attendees = event.attendees, !attendees.isEmpty {
            Text(attendees.compactMap(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            Text(notes)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(8)
                .textSelection(.enabled)
        }
        if let url = event.url {
            Link(url.absoluteString, destination: url)
                .font(.system(size: 12))
                .lineLimit(1)
        }
    }

    /// Time range relative to the day this row sits under, so a multi-day
    /// event reads "Until 3 PM" on its last day rather than repeating its start.
    private var timeText: String {
        if event.isAllDay { return "All day" }
        let cal = Calendar.current
        let nextDay = cal.date(byAdding: .day, value: 1, to: item.day)!
        let startsBefore = event.startDate < item.day
        let endsAfter = event.endDate > nextDay
        switch (startsBefore, endsAfter) {
        case (true, true): return "All day"
        case (true, false): return "Until \(event.endDate.formatted(date: .omitted, time: .shortened))"
        case (false, true): return "\(event.startDate.formatted(date: .omitted, time: .shortened)) →"
        case (false, false): return (event.startDate..<event.endDate).formatted(date: .omitted, time: .shortened)
        }
    }
}

/// "Leave by 2:41 · 19 min drive", highlighted once it's within the hour.
private struct LeaveByBadge: View {
    @EnvironmentObject private var store: CalendarStore
    let trip: Trip

    var body: some View {
        let soon = trip.leaveBy.timeIntervalSince(store.now) <= 3600
        HStack(spacing: 5) {
            Image(systemName: "car.fill")
                .font(.system(size: 10))
            Text("Leave by \(trip.leaveBy.formatted(date: .omitted, time: .shortened))")
                .fontWeight(soon ? .bold : .regular)
            Text("· \(trip.minutes) min")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(soon ? Theme.leave : Theme.textSecondary)
        .padding(.horizontal, soon ? 7 : 0)
        .padding(.vertical, soon ? 2 : 0)
        .background(soon ? Theme.leaveBand : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.top, 3)
    }
}
