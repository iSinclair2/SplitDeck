import AppKit
import EventKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
}

@Observable
@MainActor
final class UtilityDeckModel {
    private let eventStore = EKEventStore()
    private var hasStarted = false
    var events: [CalendarEntry] = []
    var reminders: [String] = []
    var clipboardText = ""
    var clipboardHistory: [String] = []
    var pinnedFiles: [URL] = []
    var batteryPercent = 0
    var batteryState = "Checking…"
    var volumePercent = 0
    private var pasteboardChangeCount = NSPasteboard.general.changeCount

    var calendarAllowed: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess
    }

    var todayEvents: [CalendarEntry] { events.filter { Calendar.current.isDateInToday($0.startDate) } }
    var tomorrowEvents: [CalendarEntry] { events.filter { Calendar.current.isDateInTomorrow($0.startDate) } }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshLocalData()
        Task {
            await refreshSystemStatus()
            if calendarAllowed { await refreshToday() }
        }
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refreshSystemStatus()
                if calendarAllowed { await refreshToday() }
            }
        }
        // Pick up calendar edits immediately rather than on the next minute tick.
        Task {
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                if calendarAllowed { await refreshToday() }
            }
        }
        Task {
            while !Task.isCancelled {
                captureClipboardIfChanged()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func requestTodayAccess() {
        Task {
            let eventsGranted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            let remindersGranted = (try? await eventStore.requestFullAccessToReminders()) ?? false
            _ = eventsGranted || remindersGranted
            await refreshToday()
        }
    }

    func refreshToday() async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: 8, to: start) ?? tomorrow
        let candidates = eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay }
        var seen = Set<String>()
        events = candidates.filter { event in
            let key = "\(event.title ?? "")|\(Int(event.startDate.timeIntervalSince1970 / 60))|\(Int(event.endDate.timeIntervalSince1970 / 60))"
            return seen.insert(key).inserted
        }.prefix(8).map { event in
            let nativeColor = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemBlue
            return CalendarEntry(
                id: "\(event.title ?? "")|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)",
                title: event.title ?? "Event",
                startDate: event.startDate,
                red: nativeColor.redComponent,
                green: nativeColor.greenComponent,
                blue: nativeColor.blueComponent
            )
        }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        reminders = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { values in
                continuation.resume(returning: (values ?? []).prefix(3).map { $0.title ?? "Reminder" })
            }
        }
    }

    func refreshLocalData() {
        clipboardText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clipboardHistory = UserDefaults.standard.stringArray(forKey: "clipboardHistory") ?? []
        let paths = UserDefaults.standard.stringArray(forKey: "quickShelfPaths") ?? []
        pinnedFiles = paths.map(URL.init(fileURLWithPath:))
        // Checking files in protected folders can wait on a privacy prompt; do it off the main thread.
        Task {
            let existing = await Task.detached(priority: .utility) {
                paths.filter { FileManager.default.fileExists(atPath: $0) }
            }.value
            pinnedFiles = existing.map(URL.init(fileURLWithPath:))
        }
    }

    func captureClipboardIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        // Password managers mark secrets as concealed/transient; never keep those in history.
        let privateTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        if pasteboard.types?.contains(where: { privateTypes.contains($0.rawValue) }) == true { return }
        guard let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value != clipboardHistory.first else { return }
        clipboardHistory.insert(value, at: 0)
        clipboardHistory = Array(clipboardHistory.prefix(12))
        UserDefaults.standard.set(clipboardHistory, forKey: "clipboardHistory")
    }

    func copyHistoryItem(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        pasteboardChangeCount = NSPasteboard.general.changeCount
    }

    func removeHistoryItem(_ value: String) {
        clipboardHistory.removeAll { $0 == value }
        UserDefaults.standard.set(clipboardHistory, forKey: "clipboardHistory")
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where !pinnedFiles.contains(url) { pinnedFiles.append(url) }
        pinnedFiles = Array(pinnedFiles.prefix(8))
        savePinnedFiles()
    }

    func removeFile(_ url: URL) {
        pinnedFiles.removeAll { $0 == url }
        savePinnedFiles()
    }

    private func savePinnedFiles() {
        UserDefaults.standard.set(pinnedFiles.map(\.path), forKey: "quickShelfPaths")
    }

    func refreshSystemStatus() async {
        let values = await Task.detached(priority: .utility) { () -> (String, String) in
            (Self.run("/usr/bin/pmset", ["-g", "batt"]), Self.run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"]))
        }.value
        let rawBattery = values.0
        if let match = rawBattery.range(of: #"\d+%"#, options: .regularExpression) {
            batteryPercent = Int(rawBattery[match].dropLast()) ?? 0
        }
        if rawBattery.localizedCaseInsensitiveContains("charged") {
            batteryState = "Fully charged"
        } else if rawBattery.localizedCaseInsensitiveContains("; charging") {
            batteryState = "Charging"
        } else if let match = rawBattery.range(of: #"\d+:\d+ remaining"#, options: .regularExpression) {
            batteryState = String(rawBattery[match])
        } else {
            batteryState = "On battery"
        }
        volumePercent = Int(values.1.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

struct UtilityDeck: View {
    private enum Presentation { case compact, wide, expanded, banner }
    let player: PlayerModel
    let badges: DockBadgeModel
    /// When set, only this widget is rendered (used by the layout drawer's previews) instead of the whole deck.
    var preview: WidgetPreviewSpec? = nil
    @State private var model = SplitDeckLiveData.shared.utility
    @State private var extras = SplitDeckLiveData.shared.extras
    @State private var focusRemaining = 25 * 60
    @State private var focusRunning = false
    /// When the running focus session ends. Remaining time is derived from this so the
    /// timer stays accurate even if the app is busy or the Mac sleeps.
    @State private var focusEndDate: Date?
    @State private var copiedClipboardItem: String?
    @AppStorage("focusMinutes") private var focusMinutes = 25
    @AppStorage("scratchpadText") private var scratchpadText = ""
    @AppStorage("todaySectionEnabled") private var todayEnabled = true
    @AppStorage("focusSectionEnabled") private var focusEnabled = true
    @AppStorage("quickShelfEnabled") private var shelfEnabled = true
    @AppStorage("systemStatusEnabled") private var systemEnabled = true
    @AppStorage("scratchpadEnabled") private var scratchpadEnabled = true
    @AppStorage("utilityAutomaticColumns") private var automaticColumns = true
    @AppStorage("utilityColumnCount") private var columnCount = 2
    @AppStorage("utilityRowCount") private var rowCount = 1
    @AppStorage("clipboardHistoryEnabled") private var clipboardHistoryEnabled = true
    @AppStorage("worldClocksEnabled") private var worldClocksEnabled = true
    @AppStorage("monthCalendarEnabled") private var monthCalendarEnabled = true
    @AppStorage("networkWidgetEnabled") private var networkWidgetEnabled = true
    @AppStorage("audioWidgetEnabled") private var audioWidgetEnabled = true
    @AppStorage("performanceWidgetEnabled") private var performanceWidgetEnabled = true
    @AppStorage("recentFilesEnabled") private var recentFilesEnabled = true
    @AppStorage("launcherWidgetEnabled") private var launcherWidgetEnabled = true
    @State private var resolvedCardWidth: CGFloat = 230
    @AppStorage("meetingMode") private var meetingMode = false
    @AppStorage("quickShelfView") private var quickShelfView = "list"
    @AppStorage("worldClockStyle") private var worldClockStyle = "digital"
    @AppStorage("recentFilesView") private var recentFilesView = "list"
    @State private var weather = SplitDeckLiveData.shared.weather
    @AppStorage("headerLayoutStyle") private var headerLayoutStyle = "standard"
    @AppStorage("footerLayoutStyle") private var footerLayoutStyle = "standard"
    @AppStorage("weatherCustomCoordinates") private var weatherCustomCoordinates = ""
    @AppStorage("weatherPreciseCoordinates") private var weatherPreciseCoordinates = ""
    @AppStorage("temperatureUnit") private var temperatureUnit = "celsius"
    // Layout editing (see LayoutDrawer)
    @State private var resizePreview: [UUID: String] = [:]
    @State private var dropTarget: WidgetPosition?
    @State private var bannerTarget: String?
    @State private var settingsTarget: UUID?
    @State private var highlighted: UUID?
    private var editing: Bool { preview == nil && LayoutEditSession.shared.isEditing }
    @State private var layoutVersion = 0
    @State private var canvasWidth: CGFloat = 390
    @AppStorage("infoBarEnabled") private var infoEnabled = true
    @AppStorage("notificationBarEnabled") private var notificationsEnabled = true
    @AppStorage("mediaPlayerEnabled") private var mediaEnabled = true
    @State private var instances = WidgetLayoutStore.load()
    @AppStorage("canvasColumnCount") private var canvasColumnCount = 4
    @AppStorage("accentSource") private var accentSource = "system"
    @AppStorage("albumArtworkEnabled") private var albumArtworkEnabled = true
    @AppStorage("notificationBadgeVisible") private var notificationBadgeVisible = true
    @AppStorage("weatherLocationMode") private var weatherLocationMode = "automatic"
    @AppStorage("weatherCustomLocation") private var weatherCustomLocation = ""
    @AppStorage("worldClockCities") private var worldClockCities = "Europe/London,America/New_York,Asia/Tokyo"
    @AppStorage("widgetBackgroundsEnabled") private var widgetBackgroundsEnabled = true
    @State private var artworkAccent = Color.accentColor
    @State private var mediaHovering = false
    @State private var shelfHovering = false
    @State private var clocksHovering = false
    @State private var recentFilesHovering = false
    @State private var focusHovering = false

    private var activeAccent: Color { accentSource == "artwork" ? artworkAccent : .accentColor }

    private func dynamicGridColumns(count: Int, spacing: CGFloat = 10) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, Int(ceil(sqrt(Double(max(1, count)))))))
    }

    var hasCards: Bool { true }

    private var headerWidget: WidgetInstance? { instances.first { $0.zone == "header" && isEnabled($0.kind) } }
    private var footerWidget: WidgetInstance? { instances.first { $0.zone == "footer" && isEnabled($0.kind) } }
    private var bodyWidgets: [WidgetInstance] { instances.filter { $0.zone == "body" && isEnabled($0.kind) } }

    private func isEnabled(_ id: String) -> Bool {
        switch id {
        case "clock": return infoEnabled; case "media": return mediaEnabled; case "notifications": return notificationsEnabled && !meetingMode
        case "calendar": return todayEnabled; case "focus": return focusEnabled; case "shelf": return shelfEnabled && !meetingMode
        case "system": return systemEnabled; case "scratchpad": return scratchpadEnabled && !meetingMode; case "clipboard": return clipboardHistoryEnabled && !meetingMode
        case "clocks": return worldClocksEnabled; case "month": return monthCalendarEnabled; case "network": return networkWidgetEnabled
        case "audio": return audioWidgetEnabled; case "performance": return performanceWidgetEnabled; case "recent": return recentFilesEnabled
        case "launcher": return launcherWidgetEnabled
        // Newer widgets have no separate on/off setting: placing one in the layout shows it.
        default: return MoreWidgetCatalog.kinds.contains(id)
        }
    }

    var body: some View {
        if let preview {
            previewBody(preview)
        } else if hasCards {
            GeometryReader { geometry in
                let usableWidth = max(1, geometry.size.width - 56)
                let effectiveColumns = max(1, canvasColumnCount)
                // The grid cell and the rendered card must share the same cap.
                // A wider cell with a capped child creates invisible vertical
                // space between rows when the window grows.
                // Matches the 1×1 design size, so at full size a card fills its cell exactly
                // (and edit outlines line up with the card).
                let maximumCellWidth: CGFloat = 210
                let gridWidth = min(usableWidth, CGFloat(effectiveColumns) * maximumCellWidth + CGFloat(max(0, effectiveColumns - 1)) * 12)
                let cellWidth = max(1, (gridWidth - CGFloat(max(0, effectiveColumns - 1)) * 12) / CGFloat(effectiveColumns))
                let renderedWidgets = WidgetLayoutStore.resolved(instances, columns: effectiveColumns).filter { $0.zone == "body" && isEnabled($0.kind) }
                let bodyRows = renderedWidgets.map { ($0.row ?? 0) + span(for: $0.size).rows }.max() ?? 0
                // While editing, keep a spare empty row to drop new widgets into.
                let gridRows = editing ? bodyRows + 1 : bodyRows
                let bodyGridHeight = gridRows == 0 ? 0 : CGFloat(gridRows) * cellWidth + CGFloat(max(0, gridRows - 1)) * 12 + 16
                let showsHeader = headerWidget != nil || editing
                let showsFooter = footerWidget != nil || editing
                let headerHeight = showsHeader ? zoneHeight(headerLayoutStyle, cellWidth: cellWidth) : 0
                let footerMargin: CGFloat = showsFooter ? 18 : 0
                let footerHeight = showsFooter ? zoneHeight(footerLayoutStyle, cellWidth: cellWidth) : 0
                let availableBodyHeight = max(0, geometry.size.height - headerHeight - footerHeight - footerMargin - 20)
                let bodyViewportHeight = min(bodyGridHeight, availableBodyHeight)
                VStack(spacing: 10) {
                    if showsHeader { bannerSlot("header", widget: headerWidget).frame(maxWidth: 1100).frame(height: headerHeight).padding(.horizontal, 28) }
                    ScrollViewReader { scroller in
                    ScrollView(.vertical, showsIndicators: true) {
                        bodyGrid(renderedWidgets, columns: effectiveColumns, cellWidth: cellWidth, gridWidth: gridWidth, rows: gridRows)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                    }
                    // Bring a newly added widget into view and flash it, so an add is never invisible.
                    .onChange(of: LayoutEditSession.shared.lastAdded) { _, id in
                        guard let id, preview == nil else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(120))
                            withAnimation(.easeInOut(duration: 0.35)) { scroller.scrollTo(id, anchor: .center) }
                            withAnimation(.easeOut(duration: 0.2)) { highlighted = id }
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(.easeIn(duration: 0.4)) { if highlighted == id { highlighted = nil } }
                        }
                    }
                    }
                    .frame(height: bodyViewportHeight)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.025),
                            .init(color: .black, location: 0.975),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                    Spacer(minLength: 0)
                    if showsFooter { bannerSlot("footer", widget: footerWidget).frame(maxWidth: 1100).frame(height: footerHeight).padding(.horizontal, 28).padding(.bottom, footerMargin) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear { canvasWidth = geometry.size.width; updateCardWidth(for: geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in canvasWidth = width; updateCardWidth(for: width) }
            }
            .task { model.start() }
            .task { extras.start() }
            .task(id: "\(temperatureUnit)|\(weatherLocationMode)|\(weatherCustomLocation)|\(weatherCustomCoordinates)|\(weatherPreciseCoordinates)") {
                while !Task.isCancelled {
                    await weather.refresh(unit: temperatureUnit, location: WeatherLocation.query(), displayName: WeatherLocation.displayName())
                    try? await Task.sleep(for: .seconds(900))
                }
            }
            .task(id: player.artworkRevision) {
                withAnimation(.easeInOut(duration: 0.65)) {
                    artworkAccent = player.artworkImage?.splitDeckContrastAccent.map(Color.init(nsColor:)) ?? .accentColor
                }
            }
            .tint(activeAccent)
            .onReceive(NotificationCenter.default.publisher(for: .splitDeckWidgetLayoutChanged)) { _ in instances = WidgetLayoutStore.load(); layoutVersion += 1 }
            .onAppear { if !focusRunning { focusRemaining = focusMinutes * 60 } }
            .onChange(of: focusMinutes) { _, minutes in if !focusRunning { focusRemaining = minutes * 60 } }
            .task(id: focusRunning) {
                while focusRunning && focusRemaining > 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { syncFocusRemaining() }
                }
                // Only a session that was running when it hit zero counts as finished.
                if focusRunning && focusRemaining == 0 {
                    focusRunning = false
                    focusEndDate = nil
                    (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
                    NSApplication.shared.requestUserAttention(.criticalRequest)
                }
            }
        }
    }

    // MARK: Layout editing

    @ViewBuilder
    private func bodyGrid(_ widgets: [WidgetInstance], columns: Int, cellWidth: CGFloat, gridWidth: CGFloat, rows: Int) -> some View {
        let grid = WidgetGridLayout(spacing: 12, minimumCellWidth: 1, rowHeight: nil, fixedColumnCount: columns) {
            ForEach(widgets) { widget in
                let shownSize = resizePreview[widget.id] ?? widget.size
                deckWidget(widget, size: shownSize, columns: columns)
                    .overlay {
                        if highlighted == widget.id {
                            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(activeAccent, lineWidth: 4)
                                .shadow(color: activeAccent.opacity(0.8), radius: 12)
                                .allowsHitTesting(false)
                        }
                    }
                    .id(widget.id)
                    .layoutValue(key: WidgetSpanKey.self, value: span(for: shownSize))
                    .layoutValue(key: WidgetPositionKey.self, value: widget.column.flatMap { column in widget.row.map { WidgetPosition(column: column, row: $0) } })
            }
        }
        .frame(width: gridWidth, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: widgets)
        if editing {
            grid
                .frame(height: CGFloat(rows) * cellWidth + CGFloat(max(0, rows - 1)) * 12, alignment: .top)
                .background(alignment: .topLeading) { emptyCells(columns: columns, rows: rows, cell: cellWidth) }
                .overlay(alignment: .topLeading) { dropOutline(columns: columns, cell: cellWidth) }
                .onDrop(of: [.plainText], delegate: DeckDropDelegate(columns: columns, cell: cellWidth, spacing: 12, target: $dropTarget) { position in
                    applyDrop(zone: "body", at: position)
                })
        } else {
            grid
        }
    }

    @ViewBuilder
    private func deckWidget(_ widget: WidgetInstance, size: String, columns: Int) -> some View {
        let content = adaptiveWidget(widget.kind, instance: widget, forcedPresentation: presentation(for: size), maximumScale: bodyMaximumScale(for: columns))
        if editing { editable(content, widget: widget, banner: false) } else { content }
    }

    /// Header/footer slot. While editing it is a drop zone, with a placeholder when empty.
    @ViewBuilder
    private func bannerSlot(_ zone: String, widget: WidgetInstance?) -> some View {
        let slot = Group {
            if let widget {
                let content = adaptiveWidget(widget.kind, instance: widget, forcedPresentation: .banner)
                if editing { editable(content, widget: widget, banner: true) } else { content }
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    .overlay {
                        Label("Drop a widget here for the \(zone)", systemImage: zone == "header" ? "rectangle.topthird.inset.filled" : "rectangle.bottomthird.inset.filled")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    }
            }
        }
        if editing {
            slot
                .overlay {
                    if bannerTarget == zone {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(activeAccent.opacity(0.14))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(activeAccent, style: StrokeStyle(lineWidth: 3, dash: [8, 5])))
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.plainText], isTargeted: Binding(
                    get: { bannerTarget == zone },
                    set: { targeted in bannerTarget = targeted ? zone : (bannerTarget == zone ? nil : bannerTarget) }
                )) { _ in applyDrop(zone: zone, at: nil) }
        } else {
            slot
        }
    }

    /// Edit-mode chrome: the widget becomes inert and can be dragged, removed or resized.
    private func editable<Content: View>(_ content: Content, widget: WidgetInstance, banner: Bool) -> some View {
        let resizing = resizePreview[widget.id] != nil
        return content
            .allowsHitTesting(false)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(activeAccent.opacity(resizing ? 0.95 : 0.5), style: StrokeStyle(lineWidth: resizing ? 3 : 2, dash: [7, 5]))
            }
            .overlay { Color.clear.contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) }
            .onDrag {
                let payload = "move:\(widget.id.uuidString)"
                LayoutEditSession.shared.payload = payload
                return NSItemProvider(object: payload as NSString)
            }
            .overlay(alignment: .topTrailing) {
                Button { mutateLayout { $0.remove(widget.id) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                }
                .buttonStyle(.plain).padding(8).help("Remove \(WidgetLayoutStore.name(widget.kind))")
            }
            .overlay(alignment: .topLeading) {
                if WidgetSettingsCatalog.hasSettings(widget.kind) {
                    Button { settingsTarget = widget.id } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain).padding(8).help("\(WidgetLayoutStore.name(widget.kind)) settings")
                    .popover(isPresented: Binding(get: { settingsTarget == widget.id }, set: { if !$0 { settingsTarget = nil } }), arrowEdge: .bottom) {
                        WidgetSettingsPanel(kind: widget.kind, settings: widget.settings) { value in
                            mutateLayout { $0.setSettings(widget.id, value) }
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !banner {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24)
                        .background(resizing ? AnyShapeStyle(activeAccent) : AnyShapeStyle(.regularMaterial), in: Circle())
                        .foregroundStyle(resizing ? Color.white : Color.primary)
                        .padding(8)
                        .help("Drag to resize")
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in resizePreview[widget.id] = LayoutEditing.resizedSize(from: widget.size, translation: value.translation) }
                            .onEnded { value in
                                let size = LayoutEditing.resizedSize(from: widget.size, translation: value.translation)
                                resizePreview.removeValue(forKey: widget.id)
                                if size != widget.size { mutateLayout { $0.setSize(widget.id, size) } }
                            })
                }
            }
    }

    private func emptyCells(columns: Int, rows: Int, cell: CGFloat) -> some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dropOutline(columns: Int, cell: CGFloat) -> some View {
        if let target = dropTarget, let payload = LayoutEditSession.shared.payload {
            let footprint = LayoutEditing(instances, columns: columns).span(of: payload)
            let width = min(footprint.columns, columns)
            let column = min(target.column, columns - width)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(activeAccent.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(activeAccent, style: StrokeStyle(lineWidth: 3, dash: [8, 5])))
                .frame(width: CGFloat(width) * cell + CGFloat(max(0, width - 1)) * 12,
                       height: CGFloat(footprint.rows) * cell + CGFloat(max(0, footprint.rows - 1)) * 12)
                .offset(x: CGFloat(column) * (cell + 12), y: CGFloat(target.row) * (cell + 12))
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.12), value: target)
        }
    }

    private func applyDrop(zone: String, at position: WidgetPosition?) -> Bool {
        defer { LayoutEditSession.shared.payload = nil; dropTarget = nil; bannerTarget = nil }
        guard let payload = LayoutEditSession.shared.payload else { return false }
        let before = instances
        mutateLayout { $0.drop(payload, zone: zone, at: position) }
        LayoutEditSession.shared.noteAdded(before: before, after: instances)
        return true
    }

    /// Changes one widget's own settings and saves the layout.
    private func updateSettings(_ instance: WidgetInstance, _ change: (inout [String: String]) -> Void) {
        var settings = instances.first(where: { $0.id == instance.id })?.settings ?? [:]
        change(&settings)
        mutateLayout { $0.setSettings(instance.id, settings) }
    }

    private func mutateLayout(_ change: (inout LayoutEditing) -> Void) {
        var layout = LayoutEditing(instances, columns: max(1, canvasColumnCount))
        change(&layout)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { instances = layout.instances }
        WidgetLayoutStore.save(layout.instances)
    }

    /// One widget at its real design, scaled to fit the space it is given.
    private func previewBody(_ spec: WidgetPreviewSpec) -> some View {
        let presentation: Presentation = spec.size == "banner" ? .banner : presentation(for: spec.size)
        return adaptiveWidget(spec.kind, forcedPresentation: presentation, maximumScale: 1)
            .tint(activeAccent)
            .onAppear { if !focusRunning { focusRemaining = focusMinutes * 60 } }
            .task(id: player.artworkRevision) {
                artworkAccent = player.artworkImage?.splitDeckContrastAccent.map(Color.init(nsColor:)) ?? .accentColor
            }
    }

    private func layoutSize(for presentation: Presentation) -> String {
        switch presentation { case .compact: return "small"; case .wide: return "medium"; case .expanded: return "large"; case .banner: return "banner" }
    }

    private func span(for size: String) -> WidgetSpan {
        switch size { case "large": return WidgetSpan(columns: 2, rows: 2); case "medium": return WidgetSpan(columns: 2, rows: 1); default: return WidgetSpan(columns: 1, rows: 1) }
    }

    private func presentation(for size: String) -> Presentation {
        size == "large" ? .expanded : (size == "medium" ? .wide : .compact)
    }

    private func bodyMaximumScale(for columns: Int) -> CGFloat {
        if columns <= 4 { return 1.0 }
        return 0.90
    }

    @ViewBuilder private func widgetView(_ id: String) -> some View {
        switch id {
        case "clock": clockWeatherCard; case "media": mediaCard; case "notifications": notificationsCard
        case "calendar": todayCard; case "focus": focusCard; case "shelf": shelfCard; case "system": systemCard
        case "scratchpad": scratchpadCard; case "clipboard": clipboardCard; case "clocks": worldClocksCard
        case "month": monthCalendarCard; case "network": networkCard; case "audio": audioCard
        case "performance": performanceCard; case "recent": recentFilesCard; default: launcherCard
        }
    }

    private func zoneHeight(_ style: String, cellWidth: CGFloat) -> CGFloat {
        let factor: CGFloat = style == "slim" ? 0.52 : (style == "tall" ? 0.82 : 2.0 / 3.0)
        return min(220, max(88, cellWidth * factor))
    }

    private func adaptiveWidget(_ id: String, instance: WidgetInstance? = nil, forcedPresentation: Presentation? = nil, maximumScale: CGFloat? = nil) -> some View {
        GeometryReader { geometry in
            let presentation: Presentation = forcedPresentation ?? .compact
            let referenceSize = designReferenceSize(for: presentation)
            let fittingScale = min(geometry.size.width / referenceSize.width, geometry.size.height / referenceSize.height)
            // Keep the denser narrow-window card size as the visual maximum.
            // Cards may continue shrinking, but widening the window no longer inflates them.
            let scale = min(maximumScale ?? 0.82, fittingScale)
            ZStack {
                if presentation == .banner {
                    // Banners reflow at their real width, but are laid out at a fixed
                    // design height and scaled to the Slim/Standard/Tall zone height.
                    // Every banner layout therefore only has to fit 140pt vertically.
                    let bannerScale = max(0.01, geometry.size.height / Self.bannerDesignHeight)
                    adaptiveWidgetContent(id, presentation: presentation, instance: instance)
                        .frame(width: geometry.size.width / bannerScale, height: Self.bannerDesignHeight)
                        .background(widgetBackgroundsEnabled ? activeAccent.opacity(0.10) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: widgetBackgroundsEnabled ? 22 : 0, style: .continuous))
                        .scaleEffect(bannerScale, anchor: .center)
                } else {
                    adaptiveWidgetContent(id, presentation: presentation, instance: instance)
                        .frame(width: referenceSize.width, height: referenceSize.height)
                        .scaleEffect(max(0.01, scale), anchor: .center)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .clipped()
    }

    private static let bannerDesignHeight: CGFloat = 140

    private func designReferenceSize(for presentation: Presentation) -> CGSize {
        switch presentation {
        case .compact: return CGSize(width: 210, height: 210)
        case .wide: return CGSize(width: 432, height: 210) // two cells plus the 12pt gap
        case .expanded: return CGSize(width: 432, height: 432)
        case .banner: return CGSize(width: 880, height: 140)
        }
    }

    @ViewBuilder private func adaptiveWidgetContent(_ id: String, presentation: Presentation, instance: WidgetInstance?) -> some View {
        switch id {
        case "clock": clockWeatherCard(presentation, settings: instance?.settings)
        case "media": mediaCard(presentation)
        case "notifications": notificationsCard(presentation, settings: instance?.settings)
        case "calendar": todayCard(presentation)
        case "focus": focusCard(presentation)
        case "system": systemCard(presentation)
        case "clipboard": clipboardCard(presentation)
        case "month": monthCalendarCard(presentation)
        case "audio": audioCard(presentation)
        case "network": networkCard(presentation)
        case "launcher": launcherCard(presentation)
        case "clocks": worldClocksCard(presentation, instance: instance)
        case "performance": performanceCard(presentation)
        case "shelf": if presentation == .banner { shelfBannerCard } else { shelfCard }
        case "recent": if presentation == .banner { recentFilesBannerCard } else { recentFilesCard }
        default:
            if MoreWidgetCatalog.kinds.contains(id) {
                card(WidgetLayoutStore.name(id), icon: WidgetLayoutStore.icon(id), fullBleed: MoreWidgetCatalog.isFullBleed(id)) {
                    MoreWidgetContent(kind: id, size: layoutSize(for: presentation), accent: activeAccent, settings: instance?.settings)
                }
            } else {
                widgetView(id)
            }
        }
    }

    private var clockWeatherCard: some View { clockWeatherCard(.compact, settings: nil) }
    private func clockWeatherCard(_ presentation: Presentation, settings: [String: String]?) -> some View {
        // Each Time & Weather widget can have its own location; the rest share the default.
        let local = WeatherHub.weather(for: settings)
        let weather = local.weather
        let weatherSymbol = Self.weatherSymbol(for: weather.condition)
        return card("Time & Weather", icon: "clock") {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if presentation == .banner {
                    GeometryReader { banner in
                        let compact = banner.size.width < 650
                        let ultraCompact = banner.size.width < 430
                        let clockWidth = banner.size.width * (ultraCompact ? 0.50 : (compact ? 0.42 : 0.50))
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(context.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: ultraCompact ? 30 : (compact ? 38 : 46), weight: .semibold, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.82)
                                Text(ultraCompact ? context.date.formatted(.dateTime.day().month(.abbreviated)) : (compact ? context.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) : context.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                                    .font(ultraCompact ? .caption.weight(.semibold) : (compact ? .subheadline.weight(.semibold) : .headline)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                            }
                            .padding(.horizontal, ultraCompact ? 12 : (compact ? 16 : 22))
                            .frame(width: clockWidth, height: banner.size.height, alignment: .center)
                            Divider()
                            if compact {
                                HStack(spacing: 10) {
                                    Image(systemName: weatherSymbol).font(.system(size: ultraCompact ? 22 : 25, weight: .semibold))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(weather.temperature.map { "\($0)°" } ?? "—").font(.system(size: ultraCompact ? 25 : 30, weight: .bold))
                                        if !ultraCompact { Text(weather.condition).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
                                    }
                                }
                                .padding(.horizontal, ultraCompact ? 10 : 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            } else {
                                // Four equal, centred columns so the readings are evenly spaced.
                                HStack(spacing: 0) {
                                    VStack(spacing: 2) {
                                        Image(systemName: weatherSymbol).font(.system(size: 20, weight: .semibold))
                                        Text(weather.temperature.map { "\($0)°" } ?? "—").font(.system(size: 30, weight: .bold)).lineLimit(1)
                                        Text(weather.condition).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    weatherMetricCentered("wind", weather.wind, label: "Wind")
                                    weatherMetricCentered("drop.fill", weather.humidity, label: "Humidity")
                                    weatherMetricCentered("sunset.fill", weather.sunset, label: "Sunset")
                                }
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            }
                        }
                    }
                } else if presentation == .wide {
                    HStack(spacing: 0) {
                        liveAnalogClock(context.date).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 8) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: weatherSymbol).font(.system(size: 24, weight: .semibold))
                                Text(weather.temperature.map { "\($0)°" } ?? "—").font(.system(size: 30, weight: .bold))
                            }
                            Text(weather.condition).font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                            Divider()
                            HStack(spacing: 0) {
                                weatherMetricCentered("wind", weather.wind, label: "Wind")
                                weatherMetricCentered("drop.fill", weather.humidity, label: "Humidity")
                                weatherMetricCentered("sunset.fill", weather.sunset, label: "Sunset")
                            }
                        }
                        .padding(.trailing, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else if presentation == .expanded {
                    VStack(spacing: 14) {
                        liveAnalogClock(context.date).padding(.horizontal, 40).padding(.top, 8)
                        HStack(spacing: 0) {
                            weatherMetricCentered(weatherSymbol, weather.temperature.map { "\($0)°" } ?? "—", label: weather.condition)
                            weatherMetricCentered("wind", weather.wind, label: "Wind")
                            weatherMetricCentered("drop.fill", weather.humidity, label: "Humidity")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) {
                        liveAnalogClock(context.date).frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Temperature on the left, humidity on the right, under the clock.
                        HStack(alignment: .firstTextBaseline) {
                            Label(weather.temperature.map { "\($0)°" } ?? "—", systemImage: weatherSymbol)
                            Spacer(minLength: 4)
                            Label(weather.humidity, systemImage: "drop.fill")
                        }
                        .font(.system(size: 14, weight: .bold)).labelStyle(.titleAndIcon).lineLimit(1)
                    }
                }
            }
        }
        .task(id: settings?["location"] ?? "") { local.activate("current") }
    }

    private func liveAnalogClock(_ date: Date) -> some View {
        AnalogClockFace(date: date, timeZone: .current, showsTicks: true)
    }

    private func weatherMetricCentered(_ symbol: String, _ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func weatherMetricCompact(_ symbol: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            Text(value).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private static func weatherSymbol(for condition: String) -> String {
        let value = condition.lowercased()
        if value.contains("thunder") { return "cloud.bolt.rain.fill" }
        if value.contains("sleet") { return "cloud.sleet.fill" }
        if value.contains("snow") || value.contains("blizzard") { return "cloud.snow.fill" }
        if value.contains("rain") || value.contains("drizzle") || value.contains("shower") { return "cloud.rain.fill" }
        if value.contains("fog") || value.contains("mist") || value.contains("haze") { return "cloud.fog.fill" }
        if value.contains("partly") { return "cloud.sun.fill" }
        if value.contains("cloud") || value.contains("overcast") { return "cloud.fill" }
        return "sun.max.fill"
    }

    private var notificationsCard: some View { notificationsCard(.compact, settings: nil) }
    private func notificationsCard(_ presentation: Presentation, settings: [String: String]?) -> some View {
        let showsCounts = settings?["badges"].map { $0 == "on" } ?? notificationBadgeVisible
        return card("Notifications", icon: "app.badge", fullBleed: presentation == .banner) {
            Group {
            if !badges.hasAccessibilityPermission {
                Button { badges.requestPermissionIfNeeded() } label: {
                    Group {
                        if presentation == .banner {
                            HStack(spacing: 14) {
                                Image(systemName: "hand.raised.fill").font(.system(size: 28))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow Notification Badge Access").font(.system(size: 17, weight: .semibold))
                                    Text("Click to enable this widget").font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "hand.raised.fill").font(.title)
                                Text("Allow Notification Badge Access").font(.headline).multilineTextAlignment(.center)
                                Text("Click to enable this widget").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain)
            } else if badges.apps.isEmpty {
                Text("No unread notifications").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation == .banner {
                GeometryReader { geometry in
                    let visibleCount = max(1, Int((geometry.size.width - 16 + 24) / 106))
                    HStack(spacing: 24) {
                        ForEach(Array(badges.apps.prefix(visibleCount))) { app in notificationApp(app, size: 68, showsCount: showsCounts) }
                    }
                    .fixedSize()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: dynamicGridColumns(count: badges.apps.count), spacing: 10) { notificationApps(size: 48, showsCount: showsCounts) }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder private func notificationApps(size: CGFloat, showsCount: Bool) -> some View {
        ForEach(badges.apps) { app in
            notificationApp(app, size: size, showsCount: showsCount)
        }
    }

    private func notificationApp(_ app: BadgedApp, size: CGFloat, showsCount: Bool) -> some View {
        Button { badges.open(app) } label: {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: app.url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                    .resizable().frame(width: size, height: size)
                if showsCount { Text(app.badge).font(.caption2.bold()).foregroundStyle(.white).padding(4).background(.red, in: Capsule()).offset(x: 7, y: -6) }
            }.padding(7)
        }.buttonStyle(.plain)
    }

    private var mediaCard: some View { mediaCard(.compact) }
    private func mediaCard(_ presentation: Presentation) -> some View {
        card("Now Playing", icon: "play.square", fullBleed: true) {
            GeometryReader { geometry in
                if presentation == .banner || presentation == .wide {
                    // Banners show square artwork at the banner's height; 2×1 cards give it the left half.
                    let artworkInset: CGFloat = widgetBackgroundsEnabled && presentation == .banner ? 10 : 0
                    let artworkHeight = max(0, geometry.size.height - artworkInset * 2)
                    let artworkWidth = presentation == .banner ? artworkHeight : geometry.size.width / 2
                    HStack(spacing: 0) {
                        mediaArtwork.frame(width: artworkWidth, height: artworkHeight).clipShape(RoundedRectangle(cornerRadius: widgetBackgroundsEnabled && presentation == .banner ? 14 : 0)).padding(artworkInset)
                        VStack(alignment: .leading, spacing: presentation == .banner ? 5 : 8) {
                            if presentation != .banner || geometry.size.width >= 480 {
                                Text(player.item.title).font(presentation == .banner ? Font.system(size: 19, weight: .bold) : Font.title2.bold()).lineLimit(1)
                            }
                            if presentation != .banner || geometry.size.width >= 600 {
                                Text(player.item.artist).font(presentation == .banner ? Font.system(size: 14) : nil).foregroundStyle(.secondary).lineLimit(1)
                            }
                            progressSlider
                            mediaControls(compact: presentation == .banner)
                        }.padding(presentation == .banner ? 12 : 16).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background {
                        if widgetBackgroundsEnabled {
                            LinearGradient(colors: [activeAccent.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                } else {
                    ZStack {
                        if widgetBackgroundsEnabled {
                            LinearGradient(colors: [.black.opacity(0.96), activeAccent.opacity(0.92), activeAccent.opacity(0.48), .black.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                        ZStack {
                            if albumArtworkEnabled, let image = player.artworkImage { Image(nsImage: image).resizable().scaledToFill().clipped() }
                            else { Image(systemName: "waveform").font(.system(size: 54, weight: .medium)).foregroundStyle(.white.opacity(0.92)) }
                        }
                        .id(player.artworkRevision).transition(.opacity)
                        if widgetBackgroundsEnabled {
                            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                        }
                        VStack(spacing: 8) { Spacer(); if mediaHovering { VStack(alignment: .leading, spacing: 2) { Text(player.item.title).font(.headline).lineLimit(1); Text(player.item.artist).foregroundStyle(.white.opacity(0.72)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).transition(.opacity) }; progressSlider.tint(.white); mediaControls }.padding(14).foregroundStyle(.white)
                    }
                    .animation(.easeInOut(duration: 0.8), value: player.artworkRevision)
                }
            }
        }
        .onHover { mediaHovering = $0 }
    }

    /// Playback position. Drags only seek once released, and the thumb follows the drag.
    private var progressSlider: some View {
        Slider(
            value: Binding(get: { player.isScrubbing ? player.scrubValue : player.displayElapsed }, set: { player.updateScrubValue($0) }),
            in: 0...max(1, player.item.duration),
            onEditingChanged: { editing in if editing { player.beginScrubbing() } else { player.endScrubbing() } }
        )
    }

    private func openNowPlayingSource() {
        guard !player.item.sourceBundle.isEmpty else { return }
        openApp(player.item.sourceBundle)
    }

    private var mediaArtwork: some View {
                // Color.clear takes exactly the proposed size; the filled image is drawn as an
                // overlay so it can never grow the layout beyond the frame it is given.
                Color.clear
                .overlay {
                    ZStack {
                        Group {
                            if albumArtworkEnabled, let image = player.artworkImage { Image(nsImage: image).resizable().scaledToFill() }
                            else { Image(systemName: "music.note").font(.title) }
                        }
                        .id(player.artworkRevision).transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.8), value: player.artworkRevision)
                }
                .clipped().background(widgetBackgroundsEnabled ? Color.secondary.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { openNowPlayingSource() }
                .help("Open the playing app")
    }

    private var mediaDetails: some View {
                VStack(alignment: .leading, spacing: 6) {
                    Text(player.item.title).font(.headline).lineLimit(1)
                    Text(player.item.artist).foregroundStyle(.secondary).lineLimit(1)
                    progressSlider
                    HStack {
                        Button { player.send(.previous) } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { player.send(.playPause) } label: { Image(systemName: player.item.isPlaying ? "pause.fill" : "play.fill") }
                        Spacer()
                        Button { player.send(.next) } label: { Image(systemName: "forward.fill") }
                    }.buttonStyle(.plain)
                }
    }

    private var mediaControls: some View { mediaControls(compact: false) }

    private func mediaControls(compact: Bool) -> some View {
        HStack {
            Spacer()
            Button { player.send(.previous) } label: { Image(systemName: "backward.fill").font(.system(size: compact ? 16 : 20, weight: .semibold)) }
            Spacer()
            Button { player.send(.playPause) } label: { Image(systemName: player.item.isPlaying ? "pause.fill" : "play.fill").font(.system(size: compact ? 22 : 27, weight: .semibold)) }
            Spacer()
            Button { player.send(.next) } label: { Image(systemName: "forward.fill").font(.system(size: compact ? 16 : 20, weight: .semibold)) }
            Spacer()
        }.buttonStyle(.plain)
    }

    private var todayCard: some View { todayCard(.compact) }
    private func todayCard(_ presentation: Presentation) -> some View {
        card("Calendar", icon: "calendar") {
            if !model.calendarAllowed {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26))
                    Button("Allow Calendar & Reminders") { model.requestTodayAccess() }.buttonStyle(.borderedProminent).controlSize(.small)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.events.isEmpty && model.reminders.isEmpty {
                Text("Nothing scheduled today or tomorrow").foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !model.todayEvents.isEmpty || !model.reminders.isEmpty {
                            HStack { Text(Date().formatted(.dateTime.day())).font(.system(size: 28, weight: .bold)); VStack(alignment: .leading, spacing: 0) { Text("Today").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase); if presentation == .banner { Text(Date().formatted(.dateTime.month(.wide))).font(.headline) } } }
                            eventRows(model.todayEvents, compact: presentation == .banner, limit: presentation == .banner ? 2 : nil)
                            ForEach(presentation == .banner ? Array(model.reminders.prefix(model.todayEvents.isEmpty ? 2 : 0)) : model.reminders, id: \.self) { reminder in
                                Label(reminder, systemImage: "checkmark.circle").lineLimit(1)
                            }
                        }
                        if presentation == .expanded && !model.tomorrowEvents.isEmpty {
                            Text("Tomorrow").font(.caption2.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                                .padding(.top, 2)
                            eventRows(model.tomorrowEvents)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(presentation == .expanded ? 10 : 0)
                    .background(presentation == .expanded ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    if presentation == .wide || presentation == .banner { Divider(); VStack(alignment: .leading, spacing: 5) { Text("Tomorrow").font(.system(size: 13, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase); eventRows(model.tomorrowEvents, compact: presentation == .banner, limit: presentation == .banner ? 2 : nil) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
                    if presentation == .expanded { Divider(); VStack(alignment: .leading, spacing: 7) { Text("Coming up").font(.caption2.bold()).foregroundStyle(.secondary).textCase(.uppercase); eventRows(Array(model.events.dropFirst(model.todayEvents.count + model.tomorrowEvents.count))); Spacer(minLength: 0) }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func eventRows(_ events: [CalendarEntry], compact: Bool = false, limit: Int? = nil) -> some View {
        let shown = limit.map { Array(events.prefix($0)) } ?? events
        return ForEach(shown) { event in
            Button { openApp("com.apple.iCal") } label: {
                HStack(spacing: 7) {
                    Capsule().fill(event.color).frame(width: 5, height: compact ? 20 : 28)
                    Text("\(event.startDate.formatted(date: .omitted, time: .shortened))  \(event.title)").font(.system(size: compact ? 13 : 14, weight: .medium)).lineLimit(1)
                }
                .padding(compact ? 4 : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help("Open in Calendar")
        }
    }

    private var focusCard: some View { focusCard(.compact) }
    private func focusCard(_ presentation: Presentation) -> some View {
        return card("Focus", icon: "timer", tint: focusRunning ? activeAccent : nil) {
            Group {
            if presentation == .expanded {
                VStack(spacing: 18) {
                    focusRing(diameter: 190)
                    focusControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation == .wide || presentation == .banner {
                let diameter: CGFloat = presentation == .banner ? 100 : progressIndicatorDiameter
                HStack(spacing: 0) {
                    focusRing(diameter: diameter).frame(maxWidth: .infinity, maxHeight: .infinity)
                    focusControls.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // 1×1: the ring itself is the play/pause button; reset appears once a session has started.
                focusRingButton(diameter: progressIndicatorDiameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomTrailing) {
                        if focusSessionStarted {
                            Button(action: resetFocus) { Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22) }
                                .buttonStyle(SoftIconButtonStyle(accent: activeAccent, active: false)).help("Reset")
                                .transition(.opacity)
                        }
                    }
            }
            }
        }
        .onHover { focusHovering = $0 }
    }

    private var focusSessionStarted: Bool { focusRunning || focusRemaining != focusMinutes * 60 }

    /// `showsPlayState` adds a play/pause glyph, for the 1×1 card where the ring is the only control.
    private func focusRing(diameter: CGFloat, showsPlayState: Bool = false) -> some View {
        let total = max(1, focusMinutes * 60)
        let completed = Double(focusRemaining) / Double(total)
        let line = max(5, diameter * 0.06)
        return ZStack {
            Circle().stroke(activeAccent.opacity(0.16), lineWidth: line)
            Circle().trim(from: 0, to: max(0.002, completed)).stroke(activeAccent, style: StrokeStyle(lineWidth: line, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: focusRemaining)
            VStack(spacing: diameter * 0.03) {
                Text(String(format: "%02d:%02d", focusRemaining / 60, focusRemaining % 60)).font(.system(size: diameter * 0.22, weight: .bold, design: .rounded).monospacedDigit())
                if showsPlayState {
                    Image(systemName: focusRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: diameter * 0.11, weight: .semibold))
                        .foregroundStyle(focusRunning ? Color.secondary : activeAccent)
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func focusRingButton(diameter: CGFloat) -> some View {
        Button(action: toggleFocus) { focusRing(diameter: diameter, showsPlayState: true).contentShape(Circle()) }
            .buttonStyle(.plain)
            .help(focusRunning ? "Pause" : (focusSessionStarted ? "Resume" : "Start"))
    }

    private func syncFocusRemaining() {
        guard let focusEndDate else { return }
        focusRemaining = max(0, Int(ceil(focusEndDate.timeIntervalSinceNow)))
    }

    private func toggleFocus() {
        if focusRunning {
            syncFocusRemaining()
            focusEndDate = nil
            focusRunning = false
        } else {
            if focusRemaining <= 0 { focusRemaining = focusMinutes * 60 }
            focusEndDate = Date().addingTimeInterval(Double(focusRemaining))
            focusRunning = true
        }
    }

    private func resetFocus() {
        focusRunning = false
        focusEndDate = nil
        focusRemaining = focusMinutes * 60
    }

    private func setFocusMinutes(_ minutes: Int) {
        focusMinutes = minutes
        if !focusRunning { focusRemaining = minutes * 60 }
    }

    /// Common session lengths, plus the current one if it was set to something else.
    private var focusPresets: [Int] { Array(Set([15, 25, 45, 60, focusMinutes])).sorted() }

    private var progressIndicatorDiameter: CGFloat { 132 }

    private var focusControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                ForEach(focusPresets, id: \.self) { minutes in
                    Button("\(minutes)") { setFocusMinutes(minutes) }
                        .buttonStyle(FocusChipStyle(selected: focusMinutes == minutes, accent: activeAccent))
                        .help("\(minutes) minutes")
                }
                Text("min").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            .disabled(focusRunning)
            .opacity(focusRunning ? 0.5 : 1)
            HStack(spacing: 8) {
                Button(action: toggleFocus) {
                    Label(focusRunning ? "Pause" : (focusSessionStarted ? "Resume" : "Start"), systemImage: focusRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 84, minHeight: 26)
                }
                .buttonStyle(SoftIconButtonStyle(accent: activeAccent, active: true))
                Button(action: resetFocus) { Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26) }
                    .buttonStyle(SoftIconButtonStyle(accent: activeAccent, active: false))
                    .help("Reset")
                    .disabled(!focusSessionStarted)
            }
        }
    }

    private var shelfCard: some View {
        card("Quick Shelf", icon: "tray.full") {
            HStack { Spacer(); Button { quickShelfView = quickShelfView == "list" ? "icons" : "list" } label: { Image(systemName: quickShelfView == "list" ? "square.grid.2x2" : "list.bullet") }.buttonStyle(.plain).opacity(shelfHovering ? 1 : 0).allowsHitTesting(shelfHovering) }
            if model.pinnedFiles.isEmpty {
                Text("Drop files here").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if quickShelfView == "icons" {
                ScrollView(.vertical, showsIndicators: false) { LazyVGrid(columns: dynamicGridColumns(count: model.pinnedFiles.count)) { ForEach(model.pinnedFiles, id: \.self) { fileTile($0, removable: true) } }.frame(maxWidth: .infinity, alignment: .center) }
            } else {
                ScrollView(.vertical, showsIndicators: false) { VStack(alignment: .leading) { ForEach(model.pinnedFiles, id: \.self) { url in fileRow(url, removable: true) } } }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls.filter(\.isFileURL))
            return !urls.isEmpty
        }
        .onHover { shelfHovering = $0 }
    }

    private var systemCard: some View { systemCard(.compact) }
    private func systemCard(_ presentation: Presentation) -> some View {
        card("System", icon: "gauge.with.dots.needle.67percent") {
            if presentation == .compact {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 11)
                    Circle().trim(from: 0, to: Double(model.batteryPercent) / 100).stroke(batteryTint, style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 4) { Text("\(model.batteryPercent)%").font(.system(size: 29, weight: .bold, design: .rounded).monospacedDigit()); Image(systemName: batterySymbol).font(.title3).foregroundStyle(.secondary) }
                }
                .frame(width: progressIndicatorDiameter, height: progressIndicatorDiameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if presentation == .banner {
                HStack(spacing: 22) {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.12), lineWidth: 8)
                        Circle().trim(from: 0, to: Double(model.batteryPercent) / 100).stroke(batteryTint, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(model.batteryPercent)%").font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 5) {
                        Label(model.batteryState, systemImage: batterySymbol)
                        Label(extras.cpu, systemImage: "cpu")
                        Label(extras.memory, systemImage: "memorychip")
                        Label(extras.storage, systemImage: "internaldrive")
                    }
                    .font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: 320, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: 10) { Image(systemName: batterySymbol).font(.title2); VStack(alignment: .leading, spacing: 1) { Text("\(model.batteryPercent)%").font(.headline.monospacedDigit()); Text(model.batteryState).foregroundStyle(.secondary).lineLimit(1) } }
                ProgressView(value: Double(model.batteryPercent), total: 100).tint(batteryTint)
                if ProcessInfo.processInfo.isLowPowerModeEnabled { Label("Low Power", systemImage: "leaf.fill") }
                if presentation == .expanded { Divider(); Label(extras.cpu, systemImage: "cpu").lineLimit(1); Label(extras.memory, systemImage: "memorychip").lineLimit(1); Label(extras.storage, systemImage: "internaldrive").lineLimit(1) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openSettings(.battery) }
        .help("Open Battery settings")
    }

    private var batterySymbol: String {
        if model.batteryState == "Charging" { return "battery.100percent.bolt" }
        switch model.batteryPercent { case 76...: return "battery.100percent"; case 51...: return "battery.75percent"; case 26...: return "battery.50percent"; default: return "battery.25percent" }
    }

    private var batteryTint: Color { model.batteryPercent < 20 ? .red : (model.batteryState == "Charging" ? .green : .primary) }

    private var scratchpadCard: some View {
        card("Scratchpad", icon: "square.and.pencil") {
            ZStack(alignment: .topLeading) {
                if scratchpadText.isEmpty { Text("Write a quick note…").foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 12).allowsHitTesting(false) }
                TextEditor(text: $scratchpadText).scrollContentBackground(.hidden).font(.callout).padding(5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var clipboardCard: some View { clipboardCard(.compact) }
    private func clipboardCard(_ presentation: Presentation) -> some View {
        card("Clipboard", icon: "doc.on.clipboard") {
            if model.clipboardHistory.isEmpty {
                Text("Copied text will appear here").foregroundStyle(.secondary)
            } else {
                if presentation == .wide || presentation == .banner {
                    HStack(spacing: 12) {
                        clipboardItem(model.clipboardHistory[0], lines: presentation == .banner ? 3 : 2).frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        VStack { ForEach(model.clipboardHistory.dropFirst().prefix(presentation == .banner ? 2 : 3), id: \.self) { clipboardItem($0, lines: presentation == .banner ? 1 : 2) } }.frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    ForEach(model.clipboardHistory.prefix(presentation == .expanded ? 6 : 3), id: \.self) { clipboardItem($0) }
                }
            }
        }
    }

    private func clipboardItem(_ value: String, lines: Int = 2) -> some View {
        let copied = copiedClipboardItem == value
        return Button {
            model.copyHistoryItem(value)
            withAnimation(.easeOut(duration: 0.15)) { copiedClipboardItem = value }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedClipboardItem == value { withAnimation(.easeIn(duration: 0.25)) { copiedClipboardItem = nil } }
            }
        } label: {
            Text(value.replacingOccurrences(of: "\n", with: " ")).lineLimit(lines).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                .background(copied ? activeAccent.opacity(0.22) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if copied {
                        Label("Copied", systemImage: "checkmark").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule()).padding(4)
                            .transition(.opacity)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).help("Copy again")
        .contextMenu { Button("Remove", role: .destructive) { model.removeHistoryItem(value) } }
    }

    private var worldClocksCard: some View { worldClocksCard(.compact, instance: nil) }
    private func worldClocksCard(_ presentation: Presentation, instance: WidgetInstance?) -> some View {
        // Cities and style are per widget, falling back to the shared defaults.
        let selected = clockCities(instance?.settings?["cities"] ?? worldClockCities)
        let style = instance?.settings?["style"] ?? worldClockStyle
        return card("World Clocks", icon: "globe") {
            ZStack(alignment: .topTrailing) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    adaptiveGrid(banner: presentation == .banner, count: selected.count, spacing: 10) {
                        if style == "analog" {
                            ForEach(selected) { city in analogTile(city.shortName, zone: city.id, date: context.date, diameter: presentation == .compact || presentation == .banner ? 62 : 74) }
                        } else {
                            ForEach(selected) { city in digitalTile(city.shortName, zone: city.id, date: context.date) }
                        }
                    }
                    .padding(.top, presentation == .banner ? 8 : 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                Button {
                    let next = style == "digital" ? "analog" : "digital"
                    if let instance { updateSettings(instance) { $0["style"] = next } } else { worldClockStyle = next }
                } label: { Image(systemName: style == "digital" ? "clock" : "digitalcrown.horizontal.arrow.counterclockwise") }.buttonStyle(.plain).help("Switch clock style").opacity(clocksHovering ? 1 : 0).allowsHitTesting(clocksHovering)
            }
        }
        .onHover { clocksHovering = $0 }
    }

    @ViewBuilder private func adaptiveGrid<C: View>(banner: Bool, count: Int, spacing: CGFloat, @ViewBuilder content: () -> C) -> some View {
        if banner { HStack(spacing: spacing) { content() } }
        else { LazyVGrid(columns: dynamicGridColumns(count: count), spacing: spacing) { content() } }
    }

    private func clockCities(_ list: String) -> [ClockCity] {
        let ids = list.split(separator: ",").map(String.init)
        let result = ids.compactMap(ClockCity.city(for:))
        return result.isEmpty ? [ClockCity.available[0]] : result
    }

    private func digitalTile(_ city: String, zone: String, date: Date) -> some View {
        let formatter = DateFormatter(); formatter.timeStyle = .short; formatter.timeZone = TimeZone(identifier: zone)
        return VStack(spacing: 4) { Text(formatter.string(from: date)).font(.title3.bold().monospacedDigit()); clockLabel(city, zone: zone, date: date).font(.caption.bold()).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 72).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func clockRow(_ city: String, zone: String, date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: zone)
        return HStack { Text(city); Spacer(); Text(formatter.string(from: date)).monospacedDigit() }
    }

    private var monthCalendarCard: some View { monthCalendarCard(.compact) }
    private func monthCalendarCard(_ presentation: Presentation) -> some View {
        card("This Month", icon: "calendar") {
            // Re-render every minute so "today" moves on at midnight.
            TimelineView(.everyMinute) { context in
                if presentation == .wide || presentation == .banner {
                    HStack(spacing: 12) { liveMonthGrid(context.date, expanded: false, banner: presentation == .banner); Divider(); liveMonthGrid(Calendar.current.date(byAdding: .month, value: 1, to: context.date) ?? context.date, expanded: false, banner: presentation == .banner) }
                } else {
                    liveMonthGrid(context.date, expanded: presentation == .expanded)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openApp("com.apple.iCal") }
        .help("Open Calendar")
    }

    private func liveMonthGrid(_ date: Date, expanded: Bool, banner: Bool = false) -> some View {
        let calendar = Calendar.current
        let today = calendar.isDate(date, equalTo: Date(), toGranularity: .month) ? calendar.component(.day, from: Date()) : -1
        let cells = monthCells(date)
        return VStack(spacing: expanded ? 7 : (banner ? 2 : 3)) {
            Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size: banner ? 14 : 16, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: expanded ? 7 : (banner ? 0 : 3)) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, value in Text(value).font(.system(size: banner ? 10 : 11, weight: .semibold)).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: expanded ? 4 : (banner ? 0 : 2)) {
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] { Text("\(day)").font(.system(size: expanded ? 16 : (banner ? 10 : 12), weight: .medium)).frame(maxWidth: .infinity).frame(height: expanded ? 38 : (banner ? 13 : 18)).foregroundStyle(day == today ? Color.white : Color.primary.opacity(day < today ? 0.32 : 0.92)).fontWeight(day == today ? .bold : .medium).background(day == today ? activeAccent : .clear, in: Circle()) }
                    else { Color.clear.frame(height: expanded ? 38 : (banner ? 13 : 15)) }
                }
            }.frame(maxHeight: .infinity, alignment: .top)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func monthCells(_ date: Date) -> [Int?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date), let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let sundayBased = calendar.component(.weekday, from: interval.start)
        let leading = (sundayBased + 5) % 7
        var cells = Array(repeating: Optional<Int>.none, count: leading) + range.map(Optional.some)
        while !cells.count.isMultiple(of: 7) { cells.append(nil) }
        return cells
    }

    private var networkCard: some View { networkCard(.compact) }
    private func networkCard(_ presentation: Presentation) -> some View {
        card("Network", icon: "wifi") {
            if presentation == .banner {
                HStack(spacing: 16) {
                    VStack(spacing: 6) { networkConnection("Wi-Fi", symbol: "wifi", detail: extras.network.wifiDetail, connected: extras.network.wifiConnected, pane: .wifi, compact: true); networkConnection("Ethernet", symbol: "network", detail: extras.network.ethernetDetail, connected: extras.network.ethernetConnected, pane: .network, compact: true) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    Sparkline(values: extras.networkHistory).stroke(activeAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)).frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
                }
            } else {
                VStack(spacing: 8) { networkConnection("Wi-Fi", symbol: "wifi", detail: extras.network.wifiDetail, connected: extras.network.wifiConnected, pane: .wifi); networkConnection("Ethernet", symbol: "network", detail: extras.network.ethernetDetail, connected: extras.network.ethernetConnected, pane: .network) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func networkConnection(_ name: String, symbol: String, detail: String, connected: Bool, pane: SystemSettingsPane, compact: Bool = false) -> some View {
        Button { openSettings(pane) } label: {
            HStack { Image(systemName: symbol).font(compact ? Font.system(size: 15) : Font.title3).frame(width: compact ? 24 : 28); VStack(alignment: .leading, spacing: 0) { Text(name).font(compact ? Font.system(size: 13) : nil).bold(); Text(detail).font(compact ? Font.system(size: 11) : nil).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }; Spacer(); Circle().fill(connected ? .green : .secondary.opacity(0.4)).frame(width: 8, height: 8) }
                .padding(compact ? 6 : 8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Open \(name) settings")
    }

    private var audioCard: some View { audioCard(.compact) }
    private func audioCard(_ presentation: Presentation) -> some View {
        card("Audio", icon: "speaker.wave.2") {
            ZStack(alignment: .bottomTrailing) {
                HStack(spacing: 10) {
                    Button { openSettings(.sound) } label: { Image(systemName: extras.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                        .buttonStyle(.plain).help("Open Sound settings")
                    Slider(value: Binding(get: { extras.volume }, set: { extras.setVolume($0) }), in: 0...100)
                    Text(extras.isMuted ? "Muted" : "\(Int(extras.volume.rounded()))%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Button { extras.toggleMute() } label: {
                    Image(systemName: extras.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(SoftIconButtonStyle(accent: extras.isMuted ? .red : activeAccent, active: extras.isMuted))
                .help(extras.isMuted ? "Unmute" : "Mute")
            }
        }
    }

    private var performanceCard: some View { performanceCard(.compact) }
    private func performanceCard(_ presentation: Presentation) -> some View {
        card("Performance", icon: "waveform.path.ecg") {
            if presentation == .banner {
                HStack(spacing: 20) {
                    Sparkline(values: extras.cpuHistory).stroke(activeAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 14)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label(extras.cpu, systemImage: "cpu")
                        Label(extras.memory, systemImage: "memorychip")
                        Label(extras.storage, systemImage: "internaldrive")
                    }
                    .font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: 300, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Sparkline(values: extras.cpuHistory).stroke(activeAccent, lineWidth: 2).frame(height: 28)
                Label(extras.cpu, systemImage: "cpu").lineLimit(1)
                Label(extras.memory, systemImage: "memorychip").lineLimit(1)
                Label(extras.storage, systemImage: "internaldrive").lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openApp("com.apple.ActivityMonitor") }
        .help("Open Activity Monitor")
    }

    private var recentFilesCard: some View {
        card("Recent Files", icon: "clock.arrow.circlepath") {
            if extras.recentFilesAccess != .granted { recentFilesAccessPrompt } else {
            HStack { Spacer(); Button { recentFilesView = recentFilesView == "list" ? "icons" : "list" } label: { Image(systemName: recentFilesView == "list" ? "square.grid.2x2" : "list.bullet") }.buttonStyle(.plain).opacity(recentFilesHovering ? 1 : 0).allowsHitTesting(recentFilesHovering) }
            if recentFilesView == "icons" { ScrollView(.vertical, showsIndicators: false) { LazyVGrid(columns: dynamicGridColumns(count: extras.recentFiles.count)) { ForEach(extras.recentFiles, id: \.self) { fileTile($0, removable: false) } }.frame(maxWidth: .infinity, alignment: .center) } }
            else { ScrollView(.vertical, showsIndicators: false) { VStack(alignment: .leading) { ForEach(extras.recentFiles, id: \.self) { fileRow($0, removable: false) } } } }
            }
        }
        .onHover { recentFilesHovering = $0 }
    }

    private var launcherCard: some View { launcherCard(.compact) }
    private func launcherCard(_ presentation: Presentation) -> some View {
        card("Launch", icon: "square.grid.2x2") {
            if extras.launcherApps.isEmpty {
                VStack(spacing: 8) { launcherIcon(name: "Downloads", symbol: "arrow.down.circle") { openFolder(.downloadsDirectory) }; Text("Drop apps here to add shortcuts").foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(presentation == .banner ? .horizontal : .vertical, showsIndicators: false) {
                    Group {
                        if presentation == .banner {
                            HStack(spacing: 18) { launcherIcon(name: "Downloads", symbol: "arrow.down.circle", iconSize: 54) { openFolder(.downloadsDirectory) }; launcherApps(iconSize: 54) }
                        } else {
                            LazyVGrid(columns: dynamicGridColumns(count: min(4, extras.launcherApps.count + 1)), spacing: 8) { launcherIcon(name: "Downloads", symbol: "arrow.down.circle") { openFolder(.downloadsDirectory) }; launcherApps(iconSize: 36) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .center)
                }
                .help("Drop apps here to add shortcuts")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in extras.addLaunchers(urls); return !urls.isEmpty }
    }

    @ViewBuilder private func launcherApps(iconSize: CGFloat) -> some View {
        ForEach(extras.launcherApps.prefix(8), id: \.self) { url in
            Button { NSWorkspace.shared.open(url) } label: { VStack(spacing: 5) { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: iconSize, height: iconSize); Text(url.deletingPathExtension().lastPathComponent).font(.caption2).lineLimit(1) }.frame(width: max(70, iconSize + 22)).frame(minHeight: iconSize + 26, alignment: .center) }.buttonStyle(.plain).help(url.deletingPathExtension().lastPathComponent).contextMenu { Button("Remove Shortcut", role: .destructive) { extras.removeLauncher(url) } }
        }
    }

    private func launcherIcon(name: String, symbol: String, iconSize: CGFloat = 36, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 5) { Image(systemName: symbol).font(iconSize > 40 ? .largeTitle : .title2).frame(width: iconSize, height: iconSize); Text(name).font(.caption2).lineLimit(1) }.frame(width: max(70, iconSize + 22)).frame(minHeight: iconSize + 26, alignment: .center) }.buttonStyle(.plain)
    }


    private func openFolder(_ directory: FileManager.SearchPathDirectory) {
        if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
    }

    private func fileRow(_ url: URL, removable: Bool) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                Text(url.lastPathComponent).lineLimit(1)
            }
        }
        .buttonStyle(.plain).draggable(url)
        .contextMenu {
            if removable { Button("Remove from Shelf", role: .destructive) { model.removeFile(url) } }
        }
    }

    private func fileTile(_ url: URL, removable: Bool) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            VStack(spacing: 3) {
                FilePreview(url: url, size: 42)
                Text(url.deletingPathExtension().lastPathComponent).font(.caption2).lineLimit(1)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).draggable(url)
            .contextMenu { if removable { Button("Remove from Shelf", role: .destructive) { model.removeFile(url) } } }
    }

    private func analogTile(_ label: String, zone: String, date: Date, diameter: CGFloat = 42) -> some View {
        return VStack(spacing: 4) {
            AnalogClockFace(date: date, timeZone: TimeZone(identifier: zone) ?? .current, showsTicks: diameter >= 56)
                .frame(width: diameter, height: diameter)
            clockLabel(label, zone: zone, date: date).font(.caption2.bold())
        }.frame(maxWidth: .infinity)
    }

    /// City name, plus "+1" / "−1" when it's already tomorrow (or still yesterday) there.
    private func clockLabel(_ city: String, zone: String, date: Date) -> Text {
        let offset = dayOffset(zone: zone, date: date)
        guard offset != 0 else { return Text(city) }
        return Text(city) + Text(offset > 0 ? " +\(offset)" : " −\(-offset)").foregroundStyle(activeAccent)
    }

    private func dayOffset(zone: String, date: Date) -> Int {
        var remote = Calendar.current
        remote.timeZone = TimeZone(identifier: zone) ?? .current
        let local = Calendar.current
        guard let remoteDay = local.date(from: remote.dateComponents([.year, .month, .day], from: date)),
              let localDay = local.date(from: local.dateComponents([.year, .month, .day], from: date)) else { return 0 }
        return local.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
    }

    private var shelfBannerCard: some View {
        card("Quick Shelf", icon: "tray.full") {
            bannerFileStrip(model.pinnedFiles, removable: true, emptyText: "Drop files here")
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls.filter(\.isFileURL))
            return !urls.isEmpty
        }
    }

    private var recentFilesBannerCard: some View {
        card("Recent Files", icon: "clock.arrow.circlepath") {
            if extras.recentFilesAccess != .granted { recentFilesAccessPrompt }
            else { bannerFileStrip(extras.recentFiles, removable: false, emptyText: "No recent files") }
        }
    }

    /// Same pattern as the Calendar card: ask first, and only then touch the folders.
    private var recentFilesAccessPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 26))
            if extras.recentFilesAccess == .denied {
                Text("Folder access is off").font(.system(size: 13, weight: .semibold))
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("Allow Documents & Downloads") { extras.requestRecentFilesAccess() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bannerFileStrip(_ files: [URL], removable: Bool, emptyText: String) -> some View {
        Group {
            if files.isEmpty {
                Text(emptyText).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(files, id: \.self) { url in fileTile(url, removable: removable).frame(width: 84) }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func updateCardWidth(for availableWidth: CGFloat) {
        if automaticColumns {
            resolvedCardWidth = 230
        } else {
            let usable = max(150, availableWidth - 56 - CGFloat(max(0, columnCount - 1)) * 12)
            resolvedCardWidth = max(150, usable / CGFloat(max(1, columnCount)))
        }
    }

    private enum SystemSettingsPane: String {
        case wifi = "com.apple.wifi-settings-extension"
        case network = "com.apple.Network-Settings.extension"
        case sound = "com.apple.Sound-Settings.extension"
        case battery = "com.apple.Battery-Settings.extension"
    }

    private func openSettings(_ pane: SystemSettingsPane) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openApp(_ bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func card<Content: View>(_ title: String, icon: String, tint: Color? = nil, progress: Double? = nil, fullBleed: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        let _ = layoutVersion
        return VStack(alignment: .leading, spacing: 7) {
            content()
                // macOS desktop widgets use noticeably larger labels than the
                // standard app control size. Keep that hierarchy consistent
                // across every card, including captions and secondary values.
                .dynamicTypeSize(.accessibility1)
                .imageScale(.large)
            Spacer(minLength: 0)
        }
        .padding(fullBleed ? 0 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if widgetBackgroundsEnabled { ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.025), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                GeometryReader { geometry in
                    RadialGradient(
                        colors: [activeAccent.opacity(0.20), .clear],
                        center: .bottomLeading,
                        startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.92
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                if let tint {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.16))
                }
                if let progress {
                    GeometryReader { geometry in
                        Rectangle().fill(activeAccent.opacity(0.24)).frame(width: geometry.size.width * max(0, min(1, progress)))
                    }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } }
        }
        .overlay {
            if widgetBackgroundsEnabled { RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08), .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8) }
        }
        .shadow(color: .black.opacity(widgetBackgroundsEnabled ? 0.16 : 0), radius: widgetBackgroundsEnabled ? 10 : 0, x: 0, y: widgetBackgroundsEnabled ? 5 : 0)
        .clipShape(RoundedRectangle(cornerRadius: widgetBackgroundsEnabled ? 22 : 0, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: tint != nil)
    }
}

struct Sparkline: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = rect.height * (1 - CGFloat(max(0, min(100, value))) / 100)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct FocusChipStyle: ButtonStyle {
    let selected: Bool
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.82))
            .frame(minWidth: 30, minHeight: 24)
            .background(selected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftIconButtonStyle: ButtonStyle {
    let accent: Color
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.82))
            .padding(4)
            .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(.ultraThinMaterial)) }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(active ? 0.28 : 0.18), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.14), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Tracks which grid cell a drag is over and applies the drop there.
private struct DeckDropDelegate: DropDelegate {
    let columns: Int
    let cell: CGFloat
    let spacing: CGFloat
    @Binding var target: WidgetPosition?
    let perform: (WidgetPosition) -> Bool

    func dropEntered(info: DropInfo) { update(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? { update(info.location); return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { target = nil }
    func performDrop(info: DropInfo) -> Bool {
        guard let target else { return false }
        return perform(target)
    }

    private func update(_ location: CGPoint) {
        let column = max(0, min(columns - 1, Int(location.x / (cell + spacing))))
        let row = max(0, Int(location.y / (cell + spacing)))
        let position = WidgetPosition(column: column, row: row)
        if target != position { target = position }
    }
}

/// Analog clock whose face, ticks and hands all scale with the space it's given, so it
/// reads correctly from a 50pt World Clocks tile up to a 2×2 card.
struct AnalogClockFace: View {
    let date: Date
    let timeZone: TimeZone
    var showsTicks = true

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2
            let (hour, minute) = Self.time(date, in: timeZone)
            ZStack {
                Circle().fill(Color.primary.opacity(0.045))
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: max(0.8, diameter * 0.008)))
                    .shadow(color: .white.opacity(0.14), radius: diameter * 0.03, x: -diameter * 0.02, y: -diameter * 0.02)
                    .shadow(color: .black.opacity(0.18), radius: diameter * 0.045, x: diameter * 0.025, y: diameter * 0.025)
                if showsTicks {
                    ForEach(0..<12, id: \.self) { tick in
                        let major = tick.isMultiple(of: 3)
                        Capsule().fill(Color.primary.opacity(major ? 0.6 : 0.28))
                            .frame(width: max(1, diameter * (major ? 0.018 : 0.012)), height: diameter * (major ? 0.085 : 0.05))
                            .offset(y: -(radius - diameter * (major ? 0.085 : 0.06)))
                            .rotationEffect(.degrees(Double(tick) * 30))
                    }
                }
                // Hands pivot on the centre: each is offset by half its length.
                Capsule().fill(Color.primary)
                    .frame(width: max(1.5, diameter * 0.03), height: radius * 0.52)
                    .offset(y: -radius * 0.26)
                    .rotationEffect(.degrees(hour * 30 + minute * 0.5))
                Capsule().fill(Color.primary.opacity(0.85))
                    .frame(width: max(1, diameter * 0.018), height: radius * 0.78)
                    .offset(y: -radius * 0.39)
                    .rotationEffect(.degrees(minute * 6))
                Circle().fill(Color.primary).frame(width: max(3, diameter * 0.06), height: max(3, diameter * 0.06))
            }
            .frame(width: diameter, height: diameter)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private static func time(_ date: Date, in zone: TimeZone) -> (hour: Double, minute: Double) {
        var calendar = Calendar.current
        calendar.timeZone = zone
        return (Double(calendar.component(.hour, from: date) % 12), Double(calendar.component(.minute, from: date)))
    }
}
