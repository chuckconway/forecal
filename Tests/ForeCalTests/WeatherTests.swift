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
        #expect(items.first { $0.name == "daily" }?.value?.contains("sunrise,sunset") == true)
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

    @Test func decodesSunriseAndSunsetAndSkipsPolarDays() throws {
        let json = """
        {"daily": {
            "time": ["2026-11-11", "2026-11-12", "2026-11-13"],
            "weather_code": [0, 0, 0],
            "temperature_2m_max": [60, 60, 60],
            "temperature_2m_min": [40, 40, 40],
            "sunrise": ["2026-11-11T06:43", "2026-11-12T00:00", null],
            "sunset": ["2026-11-11T16:55", "2026-11-12T00:00", "2026-11-13T16:54"]
        }}
        """
        let forecast = try JSONDecoder().decode(WeatherStore.Response.self, from: Data(json.utf8)).daily.byDay()
        let at = { (d: Int, h: Int, m: Int) in
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
        }

        let sunny = try #require(forecast[at(11, 0, 0)])
        #expect(sunny.sunrise == at(11, 6, 43) && sunny.sunset == at(11, 16, 55))
        // Polar night: both midnight. Missing sunrise: neither shown.
        #expect(forecast[at(12, 0, 0)]?.sunrise == nil && forecast[at(12, 0, 0)]?.sunset == nil)
        #expect(forecast[at(13, 0, 0)]?.sunrise == nil && forecast[at(13, 0, 0)]?.sunset == nil)
    }

    @Test func forecastIsFetchedOnlyWhileSomethingUsesIt() {
        let defaults = UserDefaults.standard
        let keys = [WeatherSettings.showWeatherKey, WeatherSettings.showSunTimesKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }

        keys.forEach { defaults.removeObject(forKey: $0) }
        #expect(WeatherSettings.anyShown, "both default to on")
        defaults.set(false, forKey: WeatherSettings.showWeatherKey)
        #expect(WeatherSettings.anyShown, "sun times alone still need the forecast")
        defaults.set(false, forKey: WeatherSettings.showSunTimesKey)
        #expect(!WeatherSettings.anyShown, "both off: location isn't sent")
    }

    @Test func oldResponsesWithoutSunTimesStillDecode() throws {
        let json = """
        {"daily": {"time": ["2026-11-11"], "weather_code": [0],
                   "temperature_2m_max": [60], "temperature_2m_min": [40]}}
        """
        let forecast = try JSONDecoder().decode(WeatherStore.Response.self, from: Data(json.utf8)).daily.byDay()
        #expect(forecast.count == 1 && forecast.values.first?.sunrise == nil)
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
