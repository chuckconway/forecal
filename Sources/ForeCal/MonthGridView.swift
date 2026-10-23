import SwiftUI

struct MonthGridView: View {
    @EnvironmentObject private var store: CalendarStore

    private var weeks: [[Date]] {
        let days = store.gridDays
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.displayedMonth.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.text)
                Text(store.displayedMonth.formatted(.dateTime.year()))
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 2) {
                    Button { store.shiftMonth(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Previous month")
                    Button("Today") { store.goToToday() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button { store.shiftMonth(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 24, height: 24)
                    }
                    .accessibilityLabel("Next month")
                }
                .buttonStyle(.borderless)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            .padding(.bottom, 4)

            HStack(spacing: 0) {
                ForEach(Array(store.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(weeks, id: \.first) { week in
                let isSelectedWeek = week.contains(store.selectedDate)
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        DayCell(day: day)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelectedWeek ? Theme.band : .clear)
                )
            }
        }
    }
}

private struct DayCell: View {
    @EnvironmentObject private var store: CalendarStore
    @EnvironmentObject private var hover: HoverState
    let day: Date

    var body: some View {
        let isToday = day == store.today
        let isSelected = day == store.selectedDate
        let inMonth = store.isInDisplayedMonth(day)

        Button { store.selectedDate = day } label: {
            // Room below the number so the hover ring clears the event dots.
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : inMonth ? Theme.text : Theme.outOfMonth)
                    .frame(width: 24, height: 24)
                    .background {
                        if isToday {
                            Circle().fill(Theme.todayFill)
                        } else if isSelected {
                            Circle().fill(Theme.selectedDay)
                        }
                    }
                    // Ring the day the pointer is over in the agenda, with a gap so it
                    // shows even around a filled circle: in the hovered event's
                    // calendar color, or the today color over a header or gap.
                    .overlay {
                        if hover.day == day {
                            Circle()
                                .strokeBorder(hover.eventColor ?? Theme.todayFill, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                HStack(spacing: 2) {
                    ForEach(dotColors.indices, id: \.self) { i in
                        Circle().fill(dotColors[i]).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Up to three dots, one per distinct calendar with events that day.
    private var dotColors: [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for event in store.events(on: day) where seen.insert(event.calendar.calendarIdentifier).inserted {
            colors.append(Color(nsColor: event.calendar.color))
            if colors.count == 3 { break }
        }
        return colors
    }
}
