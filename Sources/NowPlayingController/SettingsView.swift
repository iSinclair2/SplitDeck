import AppKit
import ApplicationServices
import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("backgroundStyle") private var backgroundStyle = "album"
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentSource") private var accentSource = "system"
    @AppStorage("albumArtworkEnabled") private var albumArtworkEnabled = true
    @AppStorage("widgetBackgroundsEnabled") private var widgetBackgroundsEnabled = true
    @AppStorage("notificationBarEnabled") private var notificationBarEnabled = true
    @AppStorage("autoHideWindowControls") private var autoHideWindowControls = true
    @AppStorage("todaySectionEnabled") private var todaySectionEnabled = true
    @AppStorage("focusSectionEnabled") private var focusSectionEnabled = true
    @AppStorage("quickShelfEnabled") private var quickShelfEnabled = true
    @AppStorage("systemStatusEnabled") private var systemStatusEnabled = true
    @AppStorage("scratchpadEnabled") private var scratchpadEnabled = true
    @AppStorage("layoutOrder") private var layoutOrderString = "notifications,utilities,player"
    @AppStorage("infoBarEnabled") private var infoBarEnabled = true
    @AppStorage("temperatureUnit") private var temperatureUnit = "celsius"
    @AppStorage("utilityAutomaticColumns") private var utilityAutomaticColumns = true
    @AppStorage("utilityColumnCount") private var utilityColumnCount = 2
    @AppStorage("utilityRowCount") private var utilityRowCount = 1
    @AppStorage("clipboardHistoryEnabled") private var clipboardHistoryEnabled = true
    @AppStorage("utilityDeckEnabled") private var utilityDeckEnabled = true
    @AppStorage("mediaPlayerEnabled") private var mediaPlayerEnabled = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("meetingMode") private var meetingMode = false
    @AppStorage("worldClocksEnabled") private var worldClocksEnabled = true
    @AppStorage("monthCalendarEnabled") private var monthCalendarEnabled = true
    @AppStorage("networkWidgetEnabled") private var networkWidgetEnabled = true
    @AppStorage("audioWidgetEnabled") private var audioWidgetEnabled = true
    @AppStorage("performanceWidgetEnabled") private var performanceWidgetEnabled = true
    @AppStorage("recentFilesEnabled") private var recentFilesEnabled = true
    @AppStorage("launcherWidgetEnabled") private var launcherWidgetEnabled = true
    @AppStorage("notificationBadgeVisible") private var notificationBadgeVisible = true
    @AppStorage("weatherLocationMode") private var weatherLocationMode = "automatic"
    @AppStorage("weatherCustomLocation") private var weatherCustomLocation = ""
    @AppStorage("weatherCustomCoordinates") private var weatherCustomCoordinates = ""
    @State private var placeQuery = ""
    @State private var placeResults: [PlaceSuggestion] = []
    @State private var placeSearching = false
    @AppStorage("worldClockCities") private var worldClockCities = "Europe/London,America/New_York,Asia/Tokyo"
    @State private var newClockCity = ""
    @State private var clockCityError = false
    @State private var presetName = ""
    @State private var savedPresets = NamedLayoutPreset.load()
    @State private var draggedSection: String?
    @AppStorage("widgetOrder") private var widgetOrderString = "clock,media,notifications,calendar,focus,shelf,system,scratchpad,clipboard,clocks,month,network,audio,performance,recent,launcher"
    @State private var draggedWidget: String?
    @State private var layoutInstances = WidgetLayoutStore.load()
    @State private var draggedInstance: UUID?
    @State private var showsLayoutDesigner = false
    @State private var settingsSection = "layout"
    @State private var permissionsRefresh = 0
    @State private var automationStates: [String: MediaAutomationPermission.State] = [:]
    @State private var permissionBadges = DockBadgeModel()
    @AppStorage("placement_info") private var infoPlacement = "header"
    @AppStorage("placement_notifications") private var notificationsPlacement = "footer"
    @AppStorage("placement_utilities") private var utilitiesPlacement = "body"
    @AppStorage("placement_player") private var playerPlacement = "body"
    @AppStorage("size_info") private var infoSize = "medium"
    @AppStorage("size_notifications") private var notificationsSize = "medium"
    @AppStorage("size_utilities") private var utilitiesSize = "medium"
    @AppStorage("size_player") private var playerSize = "medium"

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $settingsSection) {
                Label("Widget Layout", systemImage: "rectangle.3.group").tag("layout")
                Label("Appearance", systemImage: "paintpalette").tag("appearance")
                Label("Widget Settings", systemImage: "slider.horizontal.3").tag("widgets")
                Label("Permissions", systemImage: "hand.raised").tag("permissions")
                Label("Modes & Data", systemImage: "slider.horizontal.3").tag("modes")
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            Group {
                if settingsSection == "layout" {
                    layoutPane
                } else {
                    Form {
                        if settingsSection == "appearance" {
                            Section("Appearance") {
                                Picker("Interface", selection: $appearanceMode) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                                Picker("Background", selection: $backgroundStyle) { Text("Album colours").tag("album"); Text("Solid").tag("solid"); Text("Full Liquid Glass").tag("glass") }
                                Picker("Widget accent", selection: $accentSource) {
                                    Text("System accent colour").tag("system")
                                    Text("Album contrast colour").tag("artwork")
                                }
                                Toggle("Album artwork", isOn: $albumArtworkEnabled)
                                Toggle("Widget backgrounds", isOn: $widgetBackgroundsEnabled)
                                Toggle("Auto-hide window controls", isOn: $autoHideWindowControls)
                                Toggle("Always keep on top", isOn: $alwaysOnTop)
                            }
                        } else if settingsSection == "widgets" {
                            weatherSection
                            Section("Per-widget settings") {
                                Text("Notification counts, World Clock cities and each weather widget's location are now set on the widget itself: choose Edit Layout (⇧⌘L) and click ⚙︎ on the widget. The location above is the default for weather widgets that don't have their own.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if settingsSection == "permissions" {
                            permissionsForm
                        } else {
                            Section("Modes & Presets") {
                                Text("Meeting Mode is available from the button beside Settings in the main window.").font(.caption).foregroundStyle(.secondary)
                                HStack { ForEach(SplitDeckPresetManager.builtIn, id: \.id) { preset in Button(preset.name) { applyPreset(preset.id) } } }
                                HStack { TextField("Preset name", text: $presetName); Button("Save Current Layout") { saveNamedPreset() }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                                ForEach(savedPresets) { preset in
                                    HStack {
                                        Button(preset.name) { applyNamedPreset(preset) }.buttonStyle(.plain)
                                        Spacer()
                                        Button { deleteNamedPreset(preset.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Global show/hide shortcut: ⇧⌘Space").font(.caption).foregroundStyle(.secondary)
                                HStack { Button("Export Settings…") { exportSettings() }; Button("Import Settings…") { importSettings() } }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
        .frame(minWidth: 1050, idealWidth: 1200, minHeight: 700, idealHeight: 820)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsWindowConfigurator())
        .navigationTitle("SplitDeck Settings")
        .onChange(of: autoHideWindowControls) { _, _ in
            NotificationCenter.default.post(name: .splitDeckAutoHideChanged, object: nil)
        }
        .onChange(of: alwaysOnTop) { _, _ in
            NotificationCenter.default.post(name: .splitDeckAlwaysOnTopChanged, object: nil)
        }
        .onChange(of: appearanceMode) { _, _ in applyApplicationAppearance() }
        .preferredColorScheme(AppAppearance.shared.scheme(for: appearanceMode))
        .onAppear { layoutInstances = WidgetLayoutStore.load(); applyApplicationAppearance() }
    }

    // MARK: Weather location

    private var weatherSection: some View {
        let weather = SplitDeckLiveData.shared.weather
        let locator = WeatherLocationProvider.shared
        return Section("Weather") {
            Picker("Location", selection: $weatherLocationMode) {
                Text("Approximate (from your network)").tag("automatic")
                Text("Precise (Location Services)").tag("precise")
                Text("Choose a place").tag("custom")
            }
            .onChange(of: weatherLocationMode) { _, mode in if mode == "precise" { locator.locate() } }

            if weatherLocationMode == "custom" {
                TextField("Search for a town, city or postcode", text: $placeQuery)
                if placeSearching {
                    HStack { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
                } else if !placeQuery.trimmingCharacters(in: .whitespaces).isEmpty && placeResults.isEmpty {
                    Text("No places found. Try a nearby town or a postcode.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(placeResults) { place in
                    Button { choosePlace(place) } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                if !place.detail.isEmpty { Text(place.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if weatherCustomCoordinates == WeatherLocation.coordinateString(latitude: place.latitude, longitude: place.longitude) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if weatherLocationMode == "precise" {
                if locator.authorization == .denied || locator.authorization == .restricted {
                    HStack {
                        Text("Location access is off, so weather uses your approximate location.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    }
                } else if locator.isLocating {
                    HStack { ProgressView().controlSize(.small); Text("Finding your location…").foregroundStyle(.secondary) }
                } else {
                    HStack {
                        Text(locator.lastError ?? "Updates when SplitDeck starts or you refresh.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh Location") { locator.locate() }
                    }
                }
            }

            LabeledContent("Showing weather for") {
                Text(weather.place.isEmpty ? "—" : [weather.place, weather.temperature.map { "\($0)°" }].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Picker("Temperature", selection: $temperatureUnit) { Text("Celsius").tag("celsius"); Text("Fahrenheit").tag("fahrenheit") }
        }
        // Search once typing pauses, rather than on every keystroke.
        .task(id: placeQuery) {
            let query = placeQuery
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { placeResults = []; placeSearching = false; return }
            placeSearching = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let results = await PlaceSuggestion.search(query)
            guard !Task.isCancelled else { return }
            placeResults = results
            placeSearching = false
        }
    }

    private func choosePlace(_ place: PlaceSuggestion) {
        weatherCustomLocation = place.fullName
        weatherCustomCoordinates = WeatherLocation.coordinateString(latitude: place.latitude, longitude: place.longitude)
        placeQuery = ""
        placeResults = []
    }

    /// Layout is edited directly on the deck now; this pane just opens the drawer.
    private var layoutPane: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.3.group").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Edit the layout on the deck").font(.title2.bold())
            Text("A drawer slides out beside your widgets. Drag new widgets straight onto the deck, and move, resize or remove widgets where they are.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            Button {
                LayoutEditSession.shared.begin()
                // Step out of the way and bring the deck forward.
                let settings = NSApplication.shared.keyWindow
                if let deck = NSApplication.shared.windows.first(where: { $0.title == "SplitDeck" }) { deck.makeKeyAndOrderFront(nil) }
                if settings?.title != "SplitDeck" { settings?.close() }
            } label: {
                Label("Edit Layout", systemImage: "slider.horizontal.below.rectangle").frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Text("Shortcut: ⇧⌘L, or the layout button beside Settings in the main window.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    @ViewBuilder private var permissionsForm: some View {
        let _ = permissionsRefresh
        Section("Why SplitDeck asks for access") {
            Text("Permissions are requested only when you enable a feature that needs them. You can also request them manually here. SplitDeck processes this information locally and does not upload calendar, reminder, notification badge or media data.")
                .foregroundStyle(.secondary)
        }
        Section("Calendar & Reminders") {
            permissionRow("Calendar", detail: "Shows events in Calendar widgets.", granted: calendarPermissionGranted) {
                requestCalendarPermissions()
            }
            permissionRow("Reminders", detail: "Shows incomplete reminders alongside upcoming events.", granted: remindersPermissionGranted) {
                requestCalendarPermissions()
            }
        }
        Section("Notification badges") {
            permissionRow("Accessibility", detail: "Reads unread badge values from app icons in the Dock. It does not read notification content.", granted: AXIsProcessTrusted()) {
                permissionBadges.requestPermissionIfNeeded()
                refreshPermissionsSoon()
            }
        }
        Section("Media artwork") {
            Text("Music doesn't share artwork through the system Now Playing data, and browsers rarely do, so SplitDeck asks the app instead: Music and Spotify for the exact cover, and browsers for the playing tab so it can show the video's thumbnail (YouTube, Vimeo, Twitch and more). Without access it falls back to an online search, which can pick the wrong cover.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(MediaAutomationPermission.installedPlayers) { player in
                automationRow(player)
            }
        }
        .task(id: permissionsRefresh) { await refreshAutomationStates() }
        Section("No permission required") {
            Text("Weather uses the selected place or an approximate network location. Quick Shelf and Recent Files only access files you explicitly drag into SplitDeck.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var calendarPermissionGranted: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess
    }

    private var remindersPermissionGranted: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .fullAccess
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(granted ? "Allowed" : "Not Allowed", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
            if !granted { Button("Request Access", action: request) }
        }
    }

    private func requestCalendarPermissions() {
        Task {
            let store = EKEventStore()
            _ = try? await store.requestFullAccessToEvents()
            _ = try? await store.requestFullAccessToReminders()
            permissionsRefresh += 1
        }
    }

    private func automationRow(_ player: MediaAutomationPermission.Player) -> some View {
        let state = automationStates[player.bundleIdentifier]
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Control \(player.name)")
                Text(state == .denied
                     ? "Access was denied. Turn on \(player.name) under SplitDeck in Privacy & Security → Automation."
                     : (BrowserArtwork.isBrowser(player.bundleIdentifier)
                        ? "Lets SplitDeck find the playing tab in \(player.name) to show its video thumbnail."
                        : "Lets SplitDeck read the current track's artwork from \(player.name)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .allowed:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .denied:
                Label("Not Allowed", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                Button("Open System Settings") { MediaAutomationPermission.openSystemSettings() }
            case .notDetermined, .notRunning:
                Label("Not Allowed", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                Button("Request Access") { requestMediaAutomation(player) }
            case nil:
                ProgressView().controlSize(.small)
            }
        }
    }

    private func refreshAutomationStates() async {
        for player in MediaAutomationPermission.installedPlayers {
            let id = player.bundleIdentifier
            automationStates[id] = await Task.detached { MediaAutomationPermission.state(for: id, askUser: false) }.value
        }
    }

    private func requestMediaAutomation(_ player: MediaAutomationPermission.Player) {
        Task {
            let id = player.bundleIdentifier
            // Permission can only be requested while the player is running, so start it
            // in the background first if needed.
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                try? await Task.sleep(for: .seconds(1))
            }
            // Shows the system prompt if the user hasn't decided yet; blocks until answered.
            automationStates[id] = await Task.detached { MediaAutomationPermission.state(for: id, askUser: true) }.value
        }
    }

    private func refreshPermissionsSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            permissionsRefresh += 1
        }
    }

    private var layoutOrder: [String] {
        var values = layoutOrderString.split(separator: ",").map(String.init)
        if !values.contains("info") { values.insert("info", at: 0) }
        return Set(values) == Set(["info", "notifications", "utilities", "player"]) ? values : ["info", "notifications", "utilities", "player"]
    }

    private var widgetOrder: [String] {
        let defaults = WidgetDropDelegate.defaults
        let stored = widgetOrderString.split(separator: ",").map(String.init)
        return Set(stored) == Set(defaults) ? stored : defaults
    }

    private func instanceBinding(_ id: UUID, _ keyPath: WritableKeyPath<WidgetInstance, String>) -> Binding<String> {
        Binding(get: { layoutInstances.first(where: { $0.id == id })?[keyPath: keyPath] ?? "body" }, set: { value in
            guard let index = layoutInstances.firstIndex(where: { $0.id == id }) else { return }
            if keyPath == \WidgetInstance.zone, value != "body" {
                for other in layoutInstances.indices where other != index && layoutInstances[other].zone == value { layoutInstances[other].zone = "body" }
            }
            layoutInstances[index][keyPath: keyPath] = value
            saveInstances()
        })
    }

    private func saveInstances() { WidgetLayoutStore.save(layoutInstances) }

    private func cityBinding(_ id: String) -> Binding<Bool> {
        Binding {
            Set(worldClockCities.split(separator: ",").map(String.init)).contains(id)
        } set: { enabled in
            var values = Set(worldClockCities.split(separator: ",").map(String.init))
            if enabled { values.insert(id) } else if values.count > 1 { values.remove(id) }
            worldClockCities = ClockCity.available.filter { values.contains($0.id) }.map(\.id).joined(separator: ",")
        }
    }

    private var selectedClockCities: [ClockCity] {
        worldClockCities.split(separator: ",").compactMap { ClockCity.city(for: String($0)) }
    }

    private var timeZoneChoices: [ClockCity] {
        TimeZone.knownTimeZoneIdentifiers.compactMap(ClockCity.city(for:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func applyApplicationAppearance() {
        let appearance = appearanceMode == "light" ? NSAppearance(named: .aqua) : (appearanceMode == "dark" ? NSAppearance(named: .darkAqua) : nil)
        NSApplication.shared.appearance = appearance
        NSApplication.shared.windows.forEach {
            $0.appearance = appearance
            $0.contentView?.needsDisplay = true
            $0.invalidateShadow()
        }
        NotificationCenter.default.post(name: .splitDeckAppearanceChanged, object: nil)
    }

    private func addClockCity() {
        guard let city = ClockCity.resolve(newClockCity) else { clockCityError = true; return }
        var ids = worldClockCities.split(separator: ",").map(String.init)
        if !ids.contains(city.id) { ids.append(city.id) }
        worldClockCities = ids.joined(separator: ",")
        newClockCity = ""
        clockCityError = false
    }

    private func removeClockCity(_ id: String) {
        let ids = worldClockCities.split(separator: ",").map(String.init).filter { $0 != id }
        if !ids.isEmpty { worldClockCities = ids.joined(separator: ",") }
    }

    private func widgetName(_ id: String) -> String {
        ["clock":"Time & Weather", "media":"Media", "notifications":"Notifications", "calendar":"Calendar", "focus":"Focus", "shelf":"Quick Shelf", "system":"System", "scratchpad":"Scratchpad", "clipboard":"Clipboard", "clocks":"World Clocks", "month":"Month", "network":"Network", "audio":"Audio", "performance":"Performance", "recent":"Recent Files", "launcher":"Launcher"][id] ?? id.capitalized
    }

    private func widgetIcon(_ id: String) -> String {
        ["clock":"clock", "media":"play.square", "notifications":"app.badge", "calendar":"calendar", "focus":"timer", "shelf":"tray", "system":"battery.75percent", "scratchpad":"square.and.pencil", "clipboard":"doc.on.clipboard", "clocks":"globe", "month":"calendar.circle", "network":"wifi", "audio":"speaker.wave.2", "performance":"waveform.path.ecg", "recent":"clock.arrow.circlepath", "launcher":"square.grid.2x2"][id] ?? "square"
    }

    private func widgetPlacementBinding(for id: String) -> Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "widgetPlacement_\(id)") ?? "body" }, set: { zone in
            if zone != "body" {
                for other in widgetOrder where other != id && (UserDefaults.standard.string(forKey: "widgetPlacement_\(other)") ?? "body") == zone {
                    UserDefaults.standard.set("body", forKey: "widgetPlacement_\(other)")
                }
            }
            UserDefaults.standard.set(zone, forKey: "widgetPlacement_\(id)")
            NotificationCenter.default.post(name: .splitDeckWidgetLayoutChanged, object: nil)
        })
    }

    private func widgetSizeBinding(for id: String) -> Binding<String> {
        Binding(get: { UserDefaults.standard.string(forKey: "widgetSize_\(id)") ?? "medium" }, set: { UserDefaults.standard.set($0, forKey: "widgetSize_\(id)"); NotificationCenter.default.post(name: .splitDeckWidgetLayoutChanged, object: nil) })
    }

    private func widgetVisibilityBinding(for id: String) -> Binding<Bool> {
        switch id {
        case "clock": return $infoBarEnabled; case "media": return $mediaPlayerEnabled; case "notifications": return $notificationBarEnabled
        case "calendar": return $todaySectionEnabled; case "focus": return $focusSectionEnabled; case "shelf": return $quickShelfEnabled
        case "system": return $systemStatusEnabled; case "scratchpad": return $scratchpadEnabled; case "clipboard": return $clipboardHistoryEnabled
        case "clocks": return $worldClocksEnabled; case "month": return $monthCalendarEnabled; case "network": return $networkWidgetEnabled
        case "audio": return $audioWidgetEnabled; case "performance": return $performanceWidgetEnabled; case "recent": return $recentFilesEnabled
        default: return $launcherWidgetEnabled
        }
    }

    private func sectionName(_ value: String) -> String {
        switch value { case "info": return "Clock, Date & Weather"; case "notifications": return "Unread Notifications"; case "utilities": return "Utility Grid"; default: return "Media Player" }
    }

    private func sectionIcon(_ value: String) -> String {
        switch value { case "info": return "clock"; case "notifications": return "app.badge"; case "utilities": return "square.grid.2x2"; default: return "play.square" }
    }

    private func visibilityBinding(for value: String) -> Binding<Bool> {
        switch value {
        case "info": return $infoBarEnabled
        case "notifications": return $notificationBarEnabled
        case "utilities": return $utilityDeckEnabled
        default: return $mediaPlayerEnabled
        }
    }

    private func placementBinding(for value: String) -> Binding<String> {
        Binding(get: { placementValue(for: value) }, set: { setPlacement($0, for: value) })
    }

    private func placementValue(for value: String) -> String {
        switch value { case "info": return infoPlacement; case "notifications": return notificationsPlacement; case "utilities": return utilitiesPlacement; default: return playerPlacement }
    }

    private func setPlacement(_ zone: String, for section: String) {
        if zone == "header" || zone == "footer" {
            for other in ["info", "notifications", "utilities", "player"] where other != section && placementValue(for: other) == zone {
                assignPlacement("body", to: other)
            }
        }
        assignPlacement(zone, to: section)
    }

    private func assignPlacement(_ zone: String, to section: String) {
        switch section { case "info": infoPlacement = zone; case "notifications": notificationsPlacement = zone; case "utilities": utilitiesPlacement = zone; default: playerPlacement = zone }
    }

    private func sizeBinding(for value: String) -> Binding<String> {
        switch value {
        case "info": return $infoSize
        case "notifications": return $notificationsSize
        case "utilities": return $utilitiesSize
        default: return $playerSize
        }
    }

    private func applyPreset(_ preset: String) {
        SplitDeckPresetManager.applyBuiltIn(preset)
        layoutInstances = WidgetLayoutStore.load()
    }

    private func setAllWidgetsEnabled(_ enabled: Bool) {
        infoBarEnabled = enabled; mediaPlayerEnabled = enabled; notificationBarEnabled = enabled; utilityDeckEnabled = enabled
        todaySectionEnabled = enabled; focusSectionEnabled = enabled; quickShelfEnabled = enabled; systemStatusEnabled = enabled
        scratchpadEnabled = enabled; clipboardHistoryEnabled = enabled; worldClocksEnabled = enabled; monthCalendarEnabled = enabled
        networkWidgetEnabled = enabled; audioWidgetEnabled = enabled; performanceWidgetEnabled = enabled; recentFilesEnabled = enabled; launcherWidgetEnabled = enabled
    }

    private func saveNamedPreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        savedPresets.append(NamedLayoutPreset(name: name, instances: WidgetLayoutStore.load(), columns: UserDefaults.standard.integer(forKey: "canvasColumnCount"), appearance: appearanceMode, background: backgroundStyle, accent: accentSource))
        NamedLayoutPreset.save(savedPresets)
        presetName = ""
    }

    private func applyNamedPreset(_ preset: NamedLayoutPreset) {
        SplitDeckPresetManager.apply(preset)
        appearanceMode = preset.appearance; backgroundStyle = preset.background; accentSource = preset.accent
        layoutInstances = WidgetLayoutStore.load()
    }

    private func deleteNamedPreset(_ id: UUID) {
        savedPresets.removeAll { $0.id == id }
        NamedLayoutPreset.save(savedPresets)
    }

    private func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "SplitDeck Settings.json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONSerialization.data(withJSONObject: UserDefaults.standard.dictionaryRepresentation(), options: [.prettyPrinted]) else { return }
        try? data.write(to: url)
    }

    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
    }
}

struct NamedLayoutPreset: Codable, Identifiable {
    static let storageKey = "namedLayoutPresets"
    var id = UUID()
    var name: String
    var instances: [WidgetInstance]
    var columns: Int
    var appearance: String
    var background: String
    var accent: String

    static func load() -> [NamedLayoutPreset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([NamedLayoutPreset].self, from: data)) ?? []
    }

    static func save(_ presets: [NamedLayoutPreset]) {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: storageKey) }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { DispatchQueue.main.async { configure(view.window) } }
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.resizable)
        window.tabbingMode = .disallowed
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        window.titleVisibility = .visible
        window.title = "SplitDeck Settings"
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 900, height: 620)
        window.maxSize = NSSize(width: 10000, height: 10000)
    }
}

private struct SectionDropDelegate: DropDelegate {
    let item: String
    @Binding var orderString: String
    @Binding var draggedItem: String?

    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item else { return }
        var values = normalizedOrder
        guard let from = values.firstIndex(of: draggedItem), let to = values.firstIndex(of: item) else { return }
        values.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        orderString = values.joined(separator: ",")
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    private var normalizedOrder: [String] {
        var values = orderString.split(separator: ",").map(String.init)
        if !values.contains("info") { values.insert("info", at: 0) }
        return Set(values) == Set(["info", "notifications", "utilities", "player"]) ? values : ["info", "notifications", "utilities", "player"]
    }
}

private struct WidgetDropDelegate: DropDelegate {
    static let defaults = ["clock", "media", "notifications", "calendar", "focus", "shelf", "system", "scratchpad", "clipboard", "clocks", "month", "network", "audio", "performance", "recent", "launcher"]
    let item: String
    @Binding var orderString: String
    @Binding var draggedItem: String?
    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item else { return }
        var values = order
        guard let from = values.firstIndex(of: draggedItem), let to = values.firstIndex(of: item) else { return }
        values.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        orderString = values.joined(separator: ",")
    }
    func performDrop(info: DropInfo) -> Bool { draggedItem = nil; return true }
    private var order: [String] {
        let stored = orderString.split(separator: ",").map(String.init)
        return Set(stored) == Set(Self.defaults) ? stored : Self.defaults
    }
}

private struct InstanceDropDelegate: DropDelegate {
    let item: UUID
    @Binding var instances: [WidgetInstance]
    @Binding var draggedItem: UUID?
    let save: () -> Void
    func dropEntered(info: DropInfo) {
        guard let draggedItem, draggedItem != item,
              let from = instances.firstIndex(where: { $0.id == draggedItem }),
              let to = instances.firstIndex(where: { $0.id == item }) else { return }
        instances.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
    func performDrop(info: DropInfo) -> Bool { draggedItem = nil; save(); return true }
}

extension Notification.Name {
    static let splitDeckAutoHideChanged = Notification.Name("SplitDeckAutoHideChanged")
    static let splitDeckAlwaysOnTopChanged = Notification.Name("SplitDeckAlwaysOnTopChanged")
    static let splitDeckWidgetLayoutChanged = Notification.Name("SplitDeckWidgetLayoutChanged")
    static let splitDeckWeatherLocationChanged = Notification.Name("SplitDeckWeatherLocationChanged")
    static let splitDeckAppearanceChanged = Notification.Name("SplitDeckAppearanceChanged")
}
