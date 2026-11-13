import Foundation

struct ClockCity: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String

    static let available: [ClockCity] = [
        .init(id: "Europe/London", name: "London", shortName: "LDN"),
        .init(id: "America/New_York", name: "New York", shortName: "NYC"),
        .init(id: "America/Los_Angeles", name: "Los Angeles", shortName: "LAX"),
        .init(id: "Europe/Paris", name: "Paris", shortName: "PAR"),
        .init(id: "Europe/Berlin", name: "Berlin", shortName: "BER"),
        .init(id: "Asia/Dubai", name: "Dubai", shortName: "DXB"),
        .init(id: "Asia/Tokyo", name: "Tokyo", shortName: "TYO"),
        .init(id: "Asia/Singapore", name: "Singapore", shortName: "SIN"),
        .init(id: "Australia/Sydney", name: "Sydney", shortName: "SYD")
    ]

    static func city(for identifier: String) -> ClockCity? {
        guard TimeZone(identifier: identifier) != nil else { return nil }
        if let known = available.first(where: { $0.id == identifier }) { return known }
        let raw = identifier.split(separator: "/").last.map(String.init) ?? identifier
        let name = raw.replacingOccurrences(of: "_", with: " ")
        let short = String(name.filter(\.isLetter).prefix(3)).uppercased()
        return ClockCity(id: identifier, name: name, shortName: short)
    }

    static func resolve(_ query: String) -> ClockCity? {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let exact = city(for: cleaned) { return exact }
        let normalized = cleaned.replacingOccurrences(of: " ", with: "_")
        let matches = TimeZone.knownTimeZoneIdentifiers.filter {
            $0.localizedCaseInsensitiveContains(normalized) ||
            ($0.split(separator: "/").last.map(String.init) ?? "").localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }
        return matches.first.flatMap(city(for:))
    }
}
