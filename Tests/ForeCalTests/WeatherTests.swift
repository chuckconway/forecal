import CoreLocation
import Foundation
import Testing
@testable import ForeCal

@Suite("Weather")
@MainActor
struct WeatherTests {
    @Test func sendsLocationRoundedToAboutAKilometer() throws {
        let url = WeatherStore.forecastURL(for: .init(latitude: 37.774929, longitude: -122.419416))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "latitude" }?.value == "37.77")
        #expect(items.first { $0.name == "longitude" }?.value == "-122.42")
    }

    @Test func decodesOpenMeteoAndSkipsIncompleteDays() throws {
        let json = """
        {"daily": {
            "time": ["2026-10-23", "2026-10-24", "2026-10-25"],
            "weather_code": [61, null, 0],
            "temperature_2m_max": [68.4, 70.0, 72.6],
            "temperature_2m_min": [50.1, 51.0, 49.5],
            "precipitation_probability_max": [80, 10, null]
        }}
        """
        let forecast = try JSONDecoder().decode(WeatherStore.Response.self, from: Data(json.utf8)).daily.byDay()
        let day = { (d: Int) in Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d))! }

        #expect(forecast.count == 2)
        let rainy = try #require(forecast[day(23)])
        #expect(rainy.code == 61 && rainy.high == 68.4 && rainy.precipitationChance == 80)
        #expect(rainy.symbolName == "cloud.rain.fill")
        #expect(forecast[day(24)] == nil)
        #expect(forecast[day(25)]?.precipitationChance == nil)
    }

    @Test("Weather codes map to symbols", arguments: [
        (0, "sun.max.fill"), (2, "cloud.sun.fill"), (3, "cloud.fill"), (45, "cloud.fog.fill"),
        (53, "cloud.drizzle.fill"), (63, "cloud.rain.fill"), (73, "cloud.snow.fill"),
        (81, "cloud.heavyrain.fill"), (95, "cloud.bolt.rain.fill"), (999, "cloud.fill"),
    ] as [(Int, String)])
    func symbols(code: Int, symbol: String) {
        #expect(DailyForecast(code: code, high: 0, low: 0, precipitationChance: nil).symbolName == symbol)
    }
}
