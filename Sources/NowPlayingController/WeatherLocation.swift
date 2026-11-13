import CoreLocation
import Foundation
import Observation

/// Where weather is fetched for. Modes (stored in "weatherLocationMode"):
/// - "automatic": approximate, from the network's IP address (no permission needed)
/// - "precise": Location Services, falling back to approximate until a fix arrives
/// - "custom": a place picked from search, stored as coordinates
enum WeatherLocation {
    /// The location string for wttr.in: "lat,lon", a place name, or "" for IP-based.
    static func query() -> String {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "weatherLocationMode") ?? "automatic" {
        case "custom":
            let coordinates = defaults.string(forKey: "weatherCustomCoordinates") ?? ""
            // Older settings stored only typed text; still honour it.
            return coordinates.isEmpty ? (defaults.string(forKey: "weatherCustomLocation") ?? "") : coordinates
        case "precise":
            return defaults.string(forKey: "weatherPreciseCoordinates") ?? ""
        default:
            return ""
        }
    }

    /// The name to show, when the user chose a place (wttr's nearest-area name for a
    /// coordinate can be a tiny neighbouring village).
    static func displayName() -> String? {
        guard UserDefaults.standard.string(forKey: "weatherLocationMode") == "custom",
              let name = UserDefaults.standard.string(forKey: "weatherCustomLocation"), !name.isEmpty else { return nil }
        return name.components(separatedBy: ",").first
    }

    static func coordinateString(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

/// A place-search result from Open-Meteo's free geocoding service.
struct PlaceSuggestion: Identifiable, Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?

    var detail: String { [admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }
    var fullName: String { [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    static func search(_ query: String) async -> [PlaceSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: trimmed), .init(name: "count", value: "8"),
            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")
        ]
        struct Response: Decodable { let results: [PlaceSuggestion]? }
        guard let url = components.url, let response: Response = await Web.json(url) else { return [] }
        return response.results ?? []
    }
}

/// Precise location via Location Services, saved as "weatherPreciseCoordinates".
@Observable
@MainActor
final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherLocationProvider()

    var authorization: CLAuthorizationStatus
    var isLocating = false
    var lastError: String?

    private let manager = CLLocationManager()

    private override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool { authorization == .authorized || authorization == .authorizedAlways }

    /// Asks for permission if needed, then fetches a single location fix.
    func locate() {
        lastError = nil
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard isAuthorized else {
            lastError = "Location access is off for SplitDeck."
            return
        }
        isLocating = true
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorization = status
            if isAuthorized, UserDefaults.standard.string(forKey: "weatherLocationMode") == "precise" { locate() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let value = WeatherLocation.coordinateString(latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task { @MainActor in
            isLocating = false
            UserDefaults.standard.set(value, forKey: "weatherPreciseCoordinates")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            isLocating = false
            lastError = message
        }
    }
}

/// Weather for one location: current conditions plus, on demand, the forecast, sun times
/// and air quality. Widgets with their own location each get one; the rest share the
/// default, which follows the location set in Settings.
@Observable
@MainActor
final class LocalWeather {
    let weather: WeatherModel
    var hourly: [ForecastHour] = []
    var daily: [ForecastDay] = []
    var currentUV: Double?
    var sun: SunTimes?
    var airQuality: AirQuality?
    var forecastFailed = false
    var airQualityFailed = false

    /// nil for the default location (refreshed by the deck, which tracks Settings).
    private let query: String?
    private let displayName: String?
    private var started: Set<String> = []

    init(weather: WeatherModel, query: String?, displayName: String?) {
        self.weather = weather
        self.query = query
        self.displayName = displayName
    }

    /// Starts current conditions (for custom locations) and the requested extra data.
    func activate(_ part: String) {
        if let query, started.insert("current").inserted {
            loop(every: 900) { await $0.weather.refresh(unit: UserDefaults.standard.string(forKey: "temperatureUnit") ?? "celsius", location: query, displayName: $0.displayName) }
        }
        guard started.insert(part).inserted else { return }
        switch part {
        case "forecast": loop(every: 1800) { await $0.refreshForecast() }
        case "airquality": loop(every: 1800) { await $0.refreshAirQuality() }
        default: return
        }
        // Follow location changes immediately instead of on the next half-hour refresh.
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .splitDeckWeatherLocationChanged) {
                guard let self else { return }
                if part == "forecast" { await self.refreshForecast() } else { await self.refreshAirQuality() }
            }
        }
    }

    private func loop(every seconds: Double, _ work: @escaping @MainActor (LocalWeather) async -> Void) {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await work(self)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }


    private var coordinates: (Double, Double)? {
        guard let latitude = weather.latitude, let longitude = weather.longitude else { return nil }
        return (latitude, longitude)
    }

    /// The weather widget resolves the location (automatic or custom); wait briefly for it.
    private func waitForCoordinates() async -> (Double, Double)? {
        for _ in 0..<12 {
            if let coordinates { return coordinates }
            try? await Task.sleep(for: .seconds(5))
        }
        return coordinates
    }

    func refreshForecast() async {
        guard let (latitude, longitude) = await waitForCoordinates() else { forecastFailed = true; return }
        let fahrenheit = UserDefaults.standard.string(forKey: "temperatureUnit") == "fahrenheit"
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "uv_index"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "7"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius")
        ]
        guard let url = components.url, let response: OpenMeteoForecast = await Web.json(url) else { forecastFailed = true; return }
        forecastFailed = false
        let zone = TimeZone(identifier: response.timezone) ?? .current
        let parse = Web.localDateParser(zone)
        let now = Date()
        hourly = zip(response.hourly.time.indices, response.hourly.time).compactMap { index, value -> ForecastHour? in
            guard let time = parse(value), time > now.addingTimeInterval(-3600),
                  let temperature = response.hourly.temperature_2m[safe: index] ?? nil else { return nil }
            return ForecastHour(time: time, temperature: temperature, code: Int(response.hourly.weather_code[safe: index].flatMap { $0 } ?? 0),
                                precipitation: response.hourly.precipitation_probability[safe: index].flatMap { $0 }.map { Int($0) })
        }.prefix(24).map { $0 }
        daily = zip(response.daily.time.indices, response.daily.time).compactMap { index, value -> ForecastDay? in
            guard let date = Web.dayParser(zone)(value),
                  let high = response.daily.temperature_2m_max[safe: index] ?? nil,
                  let low = response.daily.temperature_2m_min[safe: index] ?? nil else { return nil }
            return ForecastDay(date: date, code: Int(response.daily.weather_code[safe: index].flatMap { $0 } ?? 0), high: high, low: low,
                               precipitation: response.daily.precipitation_probability_max[safe: index].flatMap { $0 }.map { Int($0) },
                               uvMax: response.daily.uv_index_max[safe: index] ?? nil)
        }
        currentUV = response.current?.uv_index
        if let rise = response.daily.sunrise.first.flatMap(parse), let set = response.daily.sunset.first.flatMap(parse) {
            sun = SunTimes(sunrise: rise, sunset: set, tomorrowSunrise: response.daily.sunrise[safe: 1].flatMap(parse), timeZone: zone)
        }
    }

    func refreshAirQuality() async {
        guard let (latitude, longitude) = await waitForCoordinates() else { airQualityFailed = true; return }
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "european_aqi,us_aqi,pm2_5,pm10,uv_index,grass_pollen,birch_pollen,alder_pollen,ragweed_pollen"),
            .init(name: "timezone", value: "auto")
        ]
        guard let url = components.url, let response: OpenMeteoAirQuality = await Web.json(url) else { airQualityFailed = true; return }
        airQualityFailed = false
        let current = response.current
        let pollen = [("Grass", current.grass_pollen), ("Birch", current.birch_pollen), ("Alder", current.alder_pollen), ("Ragweed", current.ragweed_pollen)]
            .compactMap { name, value in value.map { (name: name, value: $0) } }
        airQuality = AirQuality(europeanAQI: current.european_aqi, usAQI: current.us_aqi, pm25: current.pm2_5, pm10: current.pm10, uv: current.uv_index, pollen: pollen)
    }

}

/// Hands out one `LocalWeather` per location.
@MainActor
enum WeatherHub {
    private static var stores: [String: LocalWeather] = [:]

    /// Per-widget settings: "location" is "" (default), "automatic", "precise" or "lat,lon";
    /// "locationName" is the chosen place's name.
    static func weather(for settings: [String: String]?) -> LocalWeather {
        let location = settings?["location"] ?? ""
        let key = location.isEmpty ? "default" : location
        if let existing = stores[key] { return existing }
        let store: LocalWeather
        if location.isEmpty {
            store = LocalWeather(weather: SplitDeckLiveData.shared.weather, query: nil, displayName: nil)
        } else {
            let query: String
            switch location {
            case "automatic": query = ""
            case "precise": query = UserDefaults.standard.string(forKey: "weatherPreciseCoordinates") ?? ""
            default: query = location
            }
            store = LocalWeather(weather: WeatherModel(), query: query, displayName: settings?["locationName"]?.components(separatedBy: ",").first)
        }
        stores[key] = store
        return store
    }
}
