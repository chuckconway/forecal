import Combine
import SwiftUI
import CoreLocation
import Foundation

struct DailyForecast {
    let code: Int
    let high: Double
    let low: Double
    let precipitationChance: Int?
    /// Nil when the sun doesn't rise or set that day (polar night or midnight sun).
    var sunrise: Date? = nil
    var sunset: Date? = nil

    var sunTimes: (sunrise: Date, sunset: Date)? {
        guard let sunrise, let sunset else { return nil }
        return (sunrise, sunset)
    }

    /// Palette colors for `symbolName`: the main shape (a cloud, or the sun on a
    /// clear day) and its accent (sun, rain, snow). Storm bolts are part of the
    /// cloud layer, so they take the base color.
    var colors: (base: Color, accent: Color) {
        switch code {
        case 0: (Theme.sun, Theme.sun)
        case 1, 2: (Theme.cloud, Theme.sun)
        case 51...67, 80...82, 95...99: (Theme.cloud, Theme.rain)
        case 71...77, 85, 86: (Theme.cloud, Theme.snow)
        default: (Theme.cloud, Theme.cloud)
        }
    }

    /// SF Symbol for a WMO weather code, as returned by Open-Meteo.
    var symbolName: String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

/// Gear-menu switches for the agenda's day headers. Both come from the same
/// Open-Meteo request, which is skipped when both are off.
enum WeatherSettings {
    static let showWeatherKey = "showWeather"
    static let showSunTimesKey = "showSunTimes"

    static var anyShown: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: showWeatherKey) as? Bool ?? true
            || defaults.object(forKey: showSunTimesKey) as? Bool ?? true
    }
}

/// Daily forecast for the Mac's location from Open-Meteo (free, no API key).
@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var forecastByDay: [Date: DailyForecast] = [:]

    private var coordinate: CLLocation?
    private var subscription: AnyCancellable?
    private var timer: Timer?

    init(location: LocationStore) {
        subscription = location.$location
            .compactMap { $0 }
            .sink { [weak self] in self?.update(location: $0) }

        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 300
    }

    func forecast(for day: Date) -> DailyForecast? {
        forecastByDay[day]
    }

    /// Stand-in forecasts for snapshots. With no location, live fetches never run.
    func showSample(_ forecasts: [Date: DailyForecast]) {
        forecastByDay = forecasts
    }

    private func update(location: CLLocation) {
        // Ignore small moves; the forecast won't change.
        if let coordinate, coordinate.distance(from: location) < 5_000 { return }
        coordinate = location
        Task { await refresh() }
    }

    /// Fetches now, unless nothing that needs the forecast is shown: then your
    /// location isn't sent at all.
    func refresh() async {
        guard let coordinate, WeatherSettings.anyShown else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.forecastURL(for: coordinate.coordinate))
            forecastByDay = try JSONDecoder().decode(Response.self, from: data).daily.byDay()
        } catch {
            NSLog("ForeCal: weather fetch failed: \(error)")
        }
    }

    /// The Open-Meteo request for a location: 16 days of daily highs, lows,
    /// weather codes, rain chances, sunrises, and sunsets.
    static func forecastURL(for coordinate: CLLocationCoordinate2D) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // About 1 km of precision: plenty for a daily forecast, and it keeps
        // your exact position off a third-party server.
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        return components.url!
    }

    struct Response: Decodable {
        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]
            let temperature2mMax: [Double?]
            let temperature2mMin: [Double?]
            let precipitationProbabilityMax: [Int?]?
            let sunrise: [String?]?
            let sunset: [String?]?

            // Explicit keys: .convertFromSnakeCase turns "temperature_2m_max"
            // into "temperature2MMax", which never matches.
            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case sunrise, sunset
            }

            /// Keys each forecast by local start of day. Open-Meteo dates are
            /// plain "yyyy-MM-dd" strings in the forecast location's time zone.
            func byDay() -> [Date: DailyForecast] {
                var result: [Date: DailyForecast] = [:]
                for (i, string) in time.enumerated() {
                    let parts = string.split(separator: "-").compactMap { Int($0) }
                    guard parts.count == 3,
                          let day = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                          let code = weatherCode[i], let high = temperature2mMax[i], let low = temperature2mMin[i]
                    else { continue }
                    var forecast = DailyForecast(code: code, high: high, low: low, precipitationChance: precipitationProbabilityMax?[i] ?? nil)
                    let rise = Self.localTime(sunrise?[i] ?? nil)
                    let set = Self.localTime(sunset?[i] ?? nil)
                    // With no sunrise or sunset, Open-Meteo reports both as midnight.
                    if let rise, let set, rise < set {
                        forecast.sunrise = rise
                        forecast.sunset = set
                    }
                    result[day] = forecast
                }
                return result
            }

            /// "2026-11-11T06:43", in the forecast location's time zone, read as
            /// this Mac's local time (the same zone, since the location is this Mac's).
            static func localTime(_ string: String?) -> Date? {
                guard let string else { return nil }
                let numbers = string.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                guard numbers.count == 5 else { return nil }
                return Calendar.current.date(from: DateComponents(
                    year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3], minute: numbers[4]))
            }
        }
        let daily: Daily
    }
}
