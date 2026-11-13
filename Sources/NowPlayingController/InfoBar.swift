import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class WeatherModel {
    var temperature: Int?
    var condition = "Loading weather…"
    var place = ""
    var humidity = "—"
    var wind = "—"
    var sunset = "—"
    var sunrise = "—"
    var moonPhase = ""
    var moonIllumination: Int?
    /// Coordinates of the resolved weather location, shared with the forecast,
    /// air-quality and sun widgets so they follow the same automatic/custom place.
    var latitude: Double?
    var longitude: Double?
    func refresh(unit: String, location: String = "", displayName: String? = nil) async {
        let encodedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://wttr.in/\(encodedLocation)?format=j1"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(WeatherResponse.self, from: data),
              let current = response.current_condition.first else {
            condition = "Weather unavailable"
            return
        }
        temperature = Int(unit == "fahrenheit" ? current.temp_F : current.temp_C)
        condition = current.weatherDesc.first?.value ?? "Current conditions"
        place = displayName ?? response.nearest_area.first?.areaName.first?.value ?? ""
        humidity = current.humidity.map { "\($0)%" } ?? "—"
        wind = (unit == "fahrenheit" ? current.windspeedMiles.map { "\($0) mph" } : current.windspeedKmph.map { "\($0) km/h" }) ?? "—"
        sunset = response.weather.first?.astronomy.first?.sunset ?? "—"
        sunrise = response.weather.first?.astronomy.first?.sunrise ?? "—"
        moonPhase = response.weather.first?.astronomy.first?.moon_phase ?? ""
        moonIllumination = response.weather.first?.astronomy.first?.moon_illumination.flatMap(Int.init)
        let previous = (latitude, longitude)
        // A chosen place's own coordinates are more accurate than wttr's nearest weather station.
        let requested = location.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if requested.count == 2 {
            latitude = requested[0]
            longitude = requested[1]
        } else {
            latitude = response.nearest_area.first?.latitude.flatMap(Double.init)
            longitude = response.nearest_area.first?.longitude.flatMap(Double.init)
        }
        if previous.0 != latitude || previous.1 != longitude {
            NotificationCenter.default.post(name: .splitDeckWeatherLocationChanged, object: nil)
        }
    }
}

private struct WeatherResponse: Decodable {
    let current_condition: [Current]
    let nearest_area: [Area]
    let weather: [Day]
    struct Current: Decodable { let temp_C: String; let temp_F: String; let weatherDesc: [Value]; let humidity: String?; let windspeedKmph: String?; let windspeedMiles: String? }
    struct Area: Decodable { let areaName: [Value]; let latitude: String?; let longitude: String? }
    struct Day: Decodable { let astronomy: [Astronomy] }
    struct Astronomy: Decodable { let sunset: String; let sunrise: String?; let moon_phase: String?; let moon_illumination: String? }
    struct Value: Decodable { let value: String }
}

struct InfoBar: View {
    @State private var weather = WeatherModel()
    @AppStorage("temperatureUnit") private var temperatureUnit = "celsius"
    @AppStorage("weatherLocationMode") private var weatherLocationMode = "automatic"
    @AppStorage("weatherCustomLocation") private var weatherCustomLocation = ""
    @AppStorage("weatherCustomCoordinates") private var weatherCustomCoordinates = ""
    @AppStorage("weatherPreciseCoordinates") private var weatherPreciseCoordinates = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: weatherSymbol).font(.title2)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(weather.temperature.map { "\($0)°\(temperatureUnit == "fahrenheit" ? "F" : "C")" } ?? "—")
                            .font(.headline.monospacedDigit())
                        Text([weather.condition, weather.place].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10)))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .task(id: "\(temperatureUnit)|\(weatherLocationMode)|\(weatherCustomLocation)|\(weatherCustomCoordinates)|\(weatherPreciseCoordinates)") {
            while !Task.isCancelled {
                await weather.refresh(unit: temperatureUnit, location: WeatherLocation.query(), displayName: WeatherLocation.displayName())
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    private var weatherSymbol: String {
        let value = weather.condition.lowercased()
        if value.contains("rain") || value.contains("drizzle") { return "cloud.rain.fill" }
        if value.contains("snow") { return "cloud.snow.fill" }
        if value.contains("thunder") { return "cloud.bolt.rain.fill" }
        if value.contains("cloud") || value.contains("overcast") { return "cloud.fill" }
        if value.contains("fog") || value.contains("mist") { return "cloud.fog.fill" }
        return "sun.max.fill"
    }
}
