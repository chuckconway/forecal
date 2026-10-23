import Combine
import SwiftUI
import CoreLocation
import Foundation

struct DailyForecast {
    let code: Int
    let high: Double
    let low: Double
    let precipitationChance: Int?

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

    private func refresh() async {
        guard let coordinate else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.forecastURL(for: coordinate.coordinate))
            forecastByDay = try JSONDecoder().decode(Response.self, from: data).daily.byDay()
        } catch {
            NSLog("ForeCal: weather fetch failed: \(error)")
        }
    }

    /// The Open-Meteo request for a location: 16 days of daily highs, lows,
    /// weather codes, and rain chances.
    static func forecastURL(for coordinate: CLLocationCoordinate2D) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // About 1 km of precision: plenty for a daily forecast, and it keeps
        // your exact position off a third-party server.
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
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

            // Explicit keys: .convertFromSnakeCase turns "temperature_2m_max"
            // into "temperature2MMax", which never matches.
            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
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
                    result[day] = DailyForecast(code: code, high: high, low: low, precipitationChance: precipitationProbabilityMax?[i] ?? nil)
                }
                return result
            }
        }
        let daily: Daily
    }
}
