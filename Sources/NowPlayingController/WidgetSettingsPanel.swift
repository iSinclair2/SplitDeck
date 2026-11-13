import SwiftUI

/// Widgets whose settings live on the widget itself (shown from the ⚙︎ button in Edit Layout).
enum WidgetSettingsCatalog {
    static let weatherKinds: Set<String> = ["clock", "forecast", "airquality", "sunmoon"]

    static func hasSettings(_ kind: String) -> Bool {
        weatherKinds.contains(kind) || kind == "notifications" || kind == "clocks"
    }
}

/// Settings for a single widget. Changes are applied as they're made.
struct WidgetSettingsPanel: View {
    let kind: String
    let onChange: ([String: String]) -> Void
    @State private var settings: [String: String]

    init(kind: String, settings: [String: String]?, onChange: @escaping ([String: String]) -> Void) {
        self.kind = kind
        self.onChange = onChange
        _settings = State(initialValue: settings ?? [:])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(WidgetLayoutStore.name(kind), systemImage: WidgetLayoutStore.icon(kind)).font(.headline)
            if WidgetSettingsCatalog.weatherKinds.contains(kind) { WeatherLocationSettings(settings: $settings) }
            if kind == "notifications" { notificationSettings }
            if kind == "clocks" { WorldClockSettings(settings: $settings) }
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: settings) { _, value in onChange(value) }
    }

    private var notificationSettings: some View {
        Toggle("Show unread counts on app icons", isOn: Binding(
            get: { settings["badges"].map { $0 == "on" } ?? (UserDefaults.standard.object(forKey: "notificationBadgeVisible") as? Bool ?? true) },
            set: { settings["badges"] = $0 ? "on" : "off" }
        ))
    }
}

// MARK: - Weather location

private struct WeatherLocationSettings: View {
    @Binding var settings: [String: String]
    @State private var choosingPlace = false
    @State private var query = ""
    @State private var results: [PlaceSuggestion] = []
    @State private var searching = false

    private var location: String { settings["location"] ?? "" }
    private var mode: String {
        if choosingPlace { return "place" }
        switch location {
        case "": return "default"
        case "automatic", "precise": return location
        default: return "place"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Location", selection: Binding(get: { mode }, set: { setMode($0) })) {
                Text("Default (from Settings)").tag("default")
                Text("Approximate (from your network)").tag("automatic")
                Text("Precise (Location Services)").tag("precise")
                Text("Choose a place").tag("place")
            }
            if mode == "place" {
                if let name = settings["locationName"], !location.isEmpty, !["automatic", "precise"].contains(location) {
                    Label(name, systemImage: "mappin.circle.fill").font(.callout).foregroundStyle(.secondary)
                }
                TextField("Search for a town, city or postcode", text: $query)
                    .textFieldStyle(.roundedBorder)
                if searching { HStack { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) } }
                ForEach(results.prefix(6)) { place in
                    Button { choose(place) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                            if !place.detail.isEmpty { Text(place.detail).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Each weather widget can follow its own place, so you can keep several cities on the deck.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: query) {
            let text = query
            guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; searching = false; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await PlaceSuggestion.search(text)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    private func setMode(_ value: String) {
        choosingPlace = value == "place"
        switch value {
        case "default": settings.removeValue(forKey: "location"); settings.removeValue(forKey: "locationName")
        case "automatic", "precise":
            settings["location"] = value
            settings.removeValue(forKey: "locationName")
            if value == "precise" { WeatherLocationProvider.shared.locate() }
        default: break // wait until a place is picked
        }
    }

    private func choose(_ place: PlaceSuggestion) {
        settings["location"] = WeatherLocation.coordinateString(latitude: place.latitude, longitude: place.longitude)
        settings["locationName"] = place.fullName
        query = ""
        results = []
    }
}

// MARK: - World clocks

private struct WorldClockSettings: View {
    @Binding var settings: [String: String]
    @State private var query = ""

    private var cities: [String] {
        let list = settings["cities"] ?? (UserDefaults.standard.string(forKey: "worldClockCities") ?? "Europe/London,America/New_York,Asia/Tokyo")
        return list.split(separator: ",").map(String.init)
    }

    /// Known cities first, then any matching time zone identifier.
    private var suggestions: [ClockCity] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return [] }
        let normalised = text.replacingOccurrences(of: " ", with: "_")
        let known = ClockCity.available.filter { $0.name.localizedCaseInsensitiveContains(text) }
        let zones = TimeZone.knownTimeZoneIdentifiers
            .filter { $0.localizedCaseInsensitiveContains(normalised) }
            .compactMap(ClockCity.city(for:))
        var seen = Set<String>()
        return (known + zones).filter { !cities.contains($0.id) && seen.insert($0.id).inserted }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: Binding(
                get: { settings["style"] ?? (UserDefaults.standard.string(forKey: "worldClockStyle") ?? "digital") },
                set: { settings["style"] = $0 }
            )) {
                Text("Digital").tag("digital")
                Text("Analog").tag("analog")
            }
            .pickerStyle(.segmented)
            Text("Cities").font(.subheadline.bold())
            ForEach(cities, id: \.self) { id in
                HStack {
                    Text(ClockCity.city(for: id)?.name ?? id)
                    Spacer()
                    Text(id).font(.caption).foregroundStyle(.secondary)
                    Button { remove(id) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(cities.count == 1)
                        .help("Remove")
                }
            }
            TextField("Add a city or time zone", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let first = suggestions.first ?? ClockCity.resolve(query) { add(first.id) } }
            ForEach(suggestions) { city in
                Button { add(city.id) } label: {
                    HStack { Text(city.name); Spacer(); Text(city.id).font(.caption).foregroundStyle(.secondary) }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func add(_ id: String) {
        guard !cities.contains(id) else { return }
        settings["cities"] = (cities + [id]).joined(separator: ",")
        query = ""
    }

    private func remove(_ id: String) {
        settings["cities"] = cities.filter { $0 != id }.joined(separator: ",")
    }
}
