import Foundation

struct WidgetInstance: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: String
    var size: String = "small"
    var zone: String = "body"
    var column: Int? = nil
    var row: Int? = nil
    /// Settings for this widget only, e.g. ["location": "51.5,-0.12"] or ["cities": "..."].
    /// Optional so layouts saved before per-widget settings still decode.
    var settings: [String: String]? = nil
}

enum WidgetLayoutStore {
    static let key = "widgetLayoutInstancesV2"
    /// The original widgets, which make up the default layout.
    static let coreKinds = ["clock", "media", "notifications", "calendar", "focus", "shelf", "system", "scratchpad", "clipboard", "clocks", "month", "network", "audio", "performance", "recent", "launcher"]
    /// Everything available in the gallery.
    static let kinds = coreKinds + MoreWidgetCatalog.kinds

    static var defaults: [WidgetInstance] {
        coreKinds.map { kind in
            WidgetInstance(kind: kind, size: ["media", "calendar", "focus"].contains(kind) ? "medium" : "small", zone: kind == "clock" ? "header" : (kind == "notifications" ? "footer" : "body"))
        }
    }

    static func load() -> [WidgetInstance] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode([WidgetInstance].self, from: data) else { return defaults }
        let storedColumns = UserDefaults.standard.object(forKey: "canvasColumnCount") == nil ? 4 : UserDefaults.standard.integer(forKey: "canvasColumnCount")
        return resolved(value, columns: max(1, storedColumns))
    }

    static func save(_ instances: [WidgetInstance]) {
        let storedColumns = UserDefaults.standard.object(forKey: "canvasColumnCount") == nil ? 4 : UserDefaults.standard.integer(forKey: "canvasColumnCount")
        let value = resolved(instances, columns: max(1, storedColumns))
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .splitDeckWidgetLayoutChanged, object: nil)
    }

    static func resolved(_ source: [WidgetInstance], columns: Int) -> [WidgetInstance] {
        var result = source
        var occupied = Set<String>()
        func footprint(_ item: WidgetInstance) -> (Int, Int) {
            item.size == "large" ? (2, 2) : (item.size == "medium" ? (2, 1) : (1, 1))
        }
        func fits(_ column: Int, _ row: Int, _ width: Int, _ height: Int) -> Bool {
            guard column >= 0, row >= 0, column + width <= columns else { return false }
            for r in row..<(row + height) { for c in column..<(column + width) where occupied.contains("\(c):\(r)") { return false } }
            return true
        }
        for index in result.indices where result[index].zone == "body" {
            if result[index].kind == "audio" && result[index].size == "large" { result[index].size = "medium" }
            let (rawWidth, height) = footprint(result[index])
            let width = min(rawWidth, columns)
            var column = min(max(0, result[index].column ?? 0), columns - width)
            var row = max(0, result[index].row ?? 0)
            while !fits(column, row, width, height) {
                column += 1
                if column + width > columns { column = 0; row += 1 }
            }
            result[index].column = column
            result[index].row = row
            for r in row..<(row + height) { for c in column..<(column + width) { occupied.insert("\(c):\(r)") } }
        }
        return result
    }

    static func name(_ kind: String) -> String {
        ["clock":"Time & Weather", "media":"Media", "notifications":"Notifications", "calendar":"Calendar", "focus":"Focus", "shelf":"Quick Shelf", "system":"System", "scratchpad":"Scratchpad", "clipboard":"Clipboard", "clocks":"World Clocks", "month":"Month", "network":"Network", "audio":"Audio", "performance":"Performance", "recent":"Recent Files", "launcher":"Launcher"][kind] ?? MoreWidgetCatalog.names[kind] ?? kind.capitalized
    }

    static func icon(_ kind: String) -> String {
        ["clock":"clock", "media":"play.square", "notifications":"app.badge", "calendar":"calendar", "focus":"timer", "shelf":"tray", "system":"battery.75percent", "scratchpad":"square.and.pencil", "clipboard":"doc.on.clipboard", "clocks":"globe", "month":"calendar.circle", "network":"wifi", "audio":"speaker.wave.2", "performance":"waveform.path.ecg", "recent":"clock.arrow.circlepath", "launcher":"square.grid.2x2"][kind] ?? MoreWidgetCatalog.icons[kind] ?? "square"
    }
}
