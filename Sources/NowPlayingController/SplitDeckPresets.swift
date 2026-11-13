import SwiftUI

enum SplitDeckPresetManager {
    /// Built-in presets, in menu order.
    static let builtIn: [(id: String, name: String)] = [
        ("work", "Work"), ("minimal", "Minimal"), ("dashboard", "Dashboard"), ("home", "Home"), ("markets", "News & Markets")
    ]

    /// Applies a built-in preset at the current column count (2–5). Presets list widgets in
    /// priority order without fixed positions; they're packed first-fit, so large widgets
    /// claim space first and small ones fill the gaps at any width.
    static func applyBuiltIn(_ name: String) {
        enableWidgets()
        let stored = UserDefaults.standard.object(forKey: "canvasColumnCount") == nil ? 4 : UserDefaults.standard.integer(forKey: "canvasColumnCount")
        let columns = min(5, max(2, stored))
        UserDefaults.standard.set(columns, forKey: "canvasColumnCount")
        let definition = definition(name)
        var items: [WidgetInstance] = []
        if let header = definition.header { items.append(WidgetInstance(kind: header, size: "medium", zone: "header")) }
        items += definition.body.map { WidgetInstance(kind: $0.kind, size: $0.size, zone: "body") }
        if let footer = definition.footer { items.append(WidgetInstance(kind: footer, size: "medium", zone: "footer")) }
        WidgetLayoutStore.save(WidgetLayoutStore.resolved(items, columns: columns))
        NotificationCenter.default.post(name: .splitDeckWidgetLayoutChanged, object: nil)
    }

    private static func definition(_ name: String) -> (header: String?, footer: String?, body: [(kind: String, size: String)]) {
        switch name {
        case "minimal":
            // The essentials, large: what's playing, what's next, and the day ahead.
            return ("clock", "notifications", [("media", "large"), ("calendar", "large"), ("meeting", "medium"), ("forecast", "medium")])
        case "dashboard":
            // Everything at a glance: media, weather and the health of the Mac.
            return ("clock", "notifications", [
                ("media", "large"), ("forecast", "large"), ("performance", "medium"), ("airquality", "medium"),
                ("network", "medium"), ("toggles", "medium"),
                ("sunmoon", "small"), ("disks", "small"), ("bluetooth", "small"), ("speedtest", "small")
            ])
        case "home":
            // Relaxed: photos and music, the weather outside, and things to look forward to.
            return ("clock", "news", [
                ("photos", "large"), ("media", "large"), ("forecast", "medium"), ("habits", "medium"),
                ("sunmoon", "small"), ("countdown", "small"), ("holidays", "small"), ("onthisday", "small")
            ])
        case "markets":
            return ("clock", "notifications", [
                ("news", "large"), ("hackernews", "large"), ("currency", "medium"), ("crypto", "medium"),
                ("onthisday", "medium"), ("clocks", "small"), ("publicip", "small")
            ])
        default:
            // Work: the day's schedule front and centre, with tools for getting through it.
            return ("clock", "notifications", [
                ("calendar", "large"), ("meeting", "medium"), ("reminders", "medium"), ("focus", "medium"),
                ("forecast", "medium"), ("toggles", "medium"), ("scratchpad", "small"), ("clipboard", "small")
            ])
        }
    }

    // MARK: Saved presets

    static func saveCurrent(as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var presets = NamedLayoutPreset.load()
        presets.append(snapshot(name: trimmed))
        NamedLayoutPreset.save(presets)
    }

    /// Replaces a saved preset's layout and look with the current ones, keeping its name.
    static func update(_ id: UUID) {
        var presets = NamedLayoutPreset.load()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        var replacement = snapshot(name: presets[index].name)
        replacement.id = id
        presets[index] = replacement
        NamedLayoutPreset.save(presets)
    }

    static func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var presets = NamedLayoutPreset.load()
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        NamedLayoutPreset.save(presets)
    }

    static func delete(_ id: UUID) {
        NamedLayoutPreset.save(NamedLayoutPreset.load().filter { $0.id != id })
    }

    private static func snapshot(name: String) -> NamedLayoutPreset {
        let defaults = UserDefaults.standard
        return NamedLayoutPreset(
            name: name, instances: WidgetLayoutStore.load(),
            columns: defaults.object(forKey: "canvasColumnCount") == nil ? 4 : defaults.integer(forKey: "canvasColumnCount"),
            appearance: defaults.string(forKey: "appearanceMode") ?? "system",
            background: defaults.string(forKey: "backgroundStyle") ?? "album",
            accent: defaults.string(forKey: "accentSource") ?? "system")
    }

    static func apply(_ preset: NamedLayoutPreset) {
        UserDefaults.standard.set(max(1, preset.columns), forKey: "canvasColumnCount")
        UserDefaults.standard.set(preset.appearance, forKey: "appearanceMode")
        UserDefaults.standard.set(preset.background, forKey: "backgroundStyle")
        UserDefaults.standard.set(preset.accent, forKey: "accentSource")
        WidgetLayoutStore.save(preset.instances)
        NotificationCenter.default.post(name: .splitDeckWidgetLayoutChanged, object: nil)
    }

    private static func enableWidgets() {
        ["infoBarEnabled", "mediaPlayerEnabled", "notificationBarEnabled", "utilityDeckEnabled", "todaySectionEnabled", "focusSectionEnabled", "quickShelfEnabled", "systemStatusEnabled", "scratchpadEnabled", "clipboardHistoryEnabled", "worldClocksEnabled", "monthCalendarEnabled", "networkWidgetEnabled", "audioWidgetEnabled", "performanceWidgetEnabled", "recentFilesEnabled", "launcherWidgetEnabled"].forEach {
            UserDefaults.standard.set(true, forKey: $0)
        }
    }
}

struct SplitDeckCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("meetingMode") private var meetingMode = false

    var body: some Commands {
        CommandMenu("SplitDeck Controls") {
            Toggle("Meeting Mode", isOn: $meetingMode)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Edit Layout") { LayoutEditSession.shared.isEditing ? LayoutEditSession.shared.end() : LayoutEditSession.shared.begin() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Menu("Apply Preset") {
                ForEach(SplitDeckPresetManager.builtIn, id: \.id) { preset in
                    Button(preset.name) { SplitDeckPresetManager.applyBuiltIn(preset.id) }
                }
                if !NamedLayoutPreset.load().isEmpty { Divider() }
                ForEach(NamedLayoutPreset.load()) { preset in
                    Button(preset.name) { SplitDeckPresetManager.apply(preset) }
                }
            }
        }
        CommandGroup(replacing: .help) {
            Button("SplitDeck Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}
