import SwiftUI

@main
struct ForeCalApp: App {
    @StateObject private var store: CalendarStore
    @StateObject private var location: LocationStore
    @StateObject private var weather: WeatherStore
    @StateObject private var travel: TravelStore
    @StateObject private var hover = HoverState()

    init() {
        let calendar = CalendarStore(requestsAccess: Snapshot.outputDirectory == nil && Snapshot.hoverTestOutput == nil)
        let location = LocationStore()
        _store = StateObject(wrappedValue: calendar)
        _location = StateObject(wrappedValue: location)
        let weather = WeatherStore(location: location)
        let travel = TravelStore(calendar: calendar, location: location)
        _weather = StateObject(wrappedValue: weather)
        _travel = StateObject(wrappedValue: travel)
        ScrollSpeed.install()
        if let file = Snapshot.hoverTestOutput {
            Snapshot.runHoverTest(to: file, store: calendar, weather: weather, travel: travel)
        }
        if let directory = Snapshot.outputDirectory {
            Snapshot.capture(to: directory, store: calendar, weather: weather, travel: travel)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
                .environmentObject(weather)
                .environmentObject(travel)
                .hoverState(hover)
        } label: {
            Image(nsImage: StatusIcon.image(
                date: store.now,
                status: NextUp.status(now: store.now, calendar: store, travel: travel)
            ))
        }
        .menuBarExtraStyle(.window)
    }
}
