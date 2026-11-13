import AppKit
import EventKit
import Foundation
import ImageIO
import Observation
import Photos

// MARK: - Catalog

/// The widgets that need no account: local tools, data SplitDeck already has permission
/// for, and free public services that don't require a key.
enum MoreWidgetCatalog {
    static let kinds = [
        "meeting", "reminders", "toggles", "forecast", "airquality", "sunmoon",
        "countdown", "habits", "shortcuts", "converter", "disks", "bluetooth",
        "speedtest", "photos", "news", "hackernews", "onthisday", "currency",
        "crypto", "holidays", "publicip"
    ]

    static let names: [String: String] = [
        "meeting": "Next Meeting", "reminders": "Reminders", "toggles": "Quick Toggles",
        "forecast": "Forecast", "airquality": "Air Quality & UV", "sunmoon": "Sun & Moon",
        "countdown": "Countdown", "habits": "Habits", "shortcuts": "Shortcuts",
        "converter": "Converter", "disks": "Disks", "bluetooth": "Bluetooth Devices",
        "speedtest": "Internet Speed", "photos": "Photo Frame", "news": "News",
        "hackernews": "Hacker News", "onthisday": "On This Day", "currency": "Currency",
        "crypto": "Crypto", "holidays": "Public Holidays", "publicip": "Public IP"
    ]

    static let icons: [String: String] = [
        "meeting": "video", "reminders": "checklist", "toggles": "switch.2",
        "forecast": "cloud.sun", "airquality": "aqi.medium", "sunmoon": "sun.horizon",
        "countdown": "hourglass", "habits": "flame", "shortcuts": "square.stack.3d.up",
        "converter": "arrow.left.arrow.right", "disks": "externaldrive", "bluetooth": "headphones",
        "speedtest": "speedometer", "photos": "photo.on.rectangle", "news": "newspaper",
        "hackernews": "y.square", "onthisday": "book.closed", "currency": "sterlingsign.circle",
        "crypto": "bitcoinsign.circle", "holidays": "gift", "publicip": "network.badge.shield.half.filled"
    ]

    /// Widgets whose content runs edge to edge instead of inside the card's padding.
    static func isFullBleed(_ kind: String) -> Bool { kind == "photos" }
}

// MARK: - Value types

struct ReminderItem: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let red: Double, green: Double, blue: Double
}

struct MeetingItem: Sendable, Equatable {
    let title: String
    let start: Date
    let end: Date
    let location: String
    let joinURL: URL?
    let red: Double, green: Double, blue: Double
}

struct DiskItem: Identifiable, Sendable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let ejectable: Bool
    let isInternal: Bool
}

struct BluetoothDevice: Identifiable, Sendable, Equatable {
    var id: String { name }
    let name: String
    let kind: String
    /// Battery levels by part, e.g. ["Left": 80, "Right": 75, "Case": 40] or ["Battery": 62].
    let batteries: [(label: String, percent: Int)]

    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.batteries.map(\.percent) == rhs.batteries.map(\.percent)
    }
}

struct SpeedResult: Codable, Sendable, Equatable {
    let download: Double   // megabits per second
    let upload: Double
    let responsiveness: Int?
    let date: Date
}

struct CountdownItem: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var title: String
    var date: Date
}

struct Habit: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var name: String
    /// Days completed, as "yyyy-MM-dd" in the user's calendar.
    var completed: Set<String> = []
}

struct ForecastHour: Identifiable, Sendable, Equatable {
    var id: Date { time }
    let time: Date
    let temperature: Double
    let code: Int
    let precipitation: Int?
}

struct ForecastDay: Identifiable, Sendable, Equatable {
    var id: Date { date }
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let precipitation: Int?
    let uvMax: Double?
}

struct SunTimes: Sendable, Equatable {
    let sunrise: Date
    let sunset: Date
    let tomorrowSunrise: Date?
    let timeZone: TimeZone
}

struct AirQuality: Sendable, Equatable {
    let europeanAQI: Double?
    let usAQI: Double?
    let pm25: Double?
    let pm10: Double?
    let uv: Double?
    let pollen: [(name: String, value: Double)]

    static func == (lhs: AirQuality, rhs: AirQuality) -> Bool {
        lhs.europeanAQI == rhs.europeanAQI && lhs.usAQI == rhs.usAQI && lhs.pm25 == rhs.pm25 && lhs.uv == rhs.uv
    }
}

struct NewsItem: Identifiable, Sendable, Equatable {
    var id: String { link.absoluteString + title }
    let title: String
    let link: URL
    let source: String
    let date: Date?
}

struct HackerNewsStory: Identifiable, Sendable, Equatable {
    let id: Int
    let title: String
    let url: URL?
    let score: Int
    let comments: Int
    var discussionURL: URL { URL(string: "https://news.ycombinator.com/item?id=\(id)")! }
}

struct HistoryEvent: Identifiable, Sendable, Equatable {
    var id: String { "\(year)-\(text.prefix(40))" }
    let year: Int
    let text: String
    let url: URL?
}

struct CurrencyRate: Identifiable, Sendable, Equatable {
    var id: String { code }
    let code: String
    let rate: Double
    let history: [Double]
    var change: Double? {
        guard let first = history.first, first != 0 else { return nil }
        return (rate - first) / first * 100
    }
}

struct CryptoCoin: Identifiable, Sendable, Equatable {
    let id: String
    let symbol: String
    let name: String
    let price: Double
    let change24h: Double?
    let sparkline: [Double]
}

struct PublicHoliday: Identifiable, Sendable, Equatable {
    var id: String { "\(date.timeIntervalSince1970)-\(name)" }
    let date: Date
    let name: String
    let localName: String
}

struct PublicIPInfo: Sendable, Equatable {
    let ip: String
    let city: String
    let region: String
    let country: String
    let organisation: String
}

/// Downsampled photo handed from a background thread to the main actor.
struct FramePhoto: @unchecked Sendable {
    let image: CGImage
    let caption: String
}

// MARK: - Model

@Observable
@MainActor
final class MoreWidgetsModel {
    // Calendar
    var meeting: MeetingItem?
    var meetingAfter: MeetingItem?
    var reminders: [ReminderItem] = []
    var remindersAllowed = false
    var calendarAllowed = false

    // Toggles
    var darkMode = false
    var keepAwake = false
    var desktopIconsHidden = false

    // Local
    var countdowns: [CountdownItem] = [] { didSet { save(countdowns, key: "countdownItems") } }
    var habits: [Habit] = [] { didSet { save(habits, key: "habitItems") } }
    var availableShortcuts: [String] = []
    var pinnedShortcuts: [String] = [] { didSet { UserDefaults.standard.set(pinnedShortcuts, forKey: "pinnedShortcuts") } }
    var runningShortcut: String?
    var disks: [DiskItem] = []
    var ejecting: Set<URL> = []
    var bluetooth: [BluetoothDevice] = []
    var bluetoothLoaded = false
    var speed: SpeedResult?
    var speedTestRunning = false
    var speedTestFailed = false

    // Photos
    var photo: FramePhoto?
    var photoSource: String = UserDefaults.standard.string(forKey: "photoFrameSource") ?? "folder" {
        didSet { UserDefaults.standard.set(photoSource, forKey: "photoFrameSource"); photoRevision += 1; Task { await nextPhoto() } }
    }
    var photoFolder: URL? = UserDefaults.standard.string(forKey: "photoFrameFolder").map(URL.init(fileURLWithPath:)) {
        didSet { UserDefaults.standard.set(photoFolder?.path, forKey: "photoFrameFolder"); photoFiles = []; Task { await nextPhoto() } }
    }
    var photosAuthorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var photoRevision = 0

    // Online
    var news: [NewsItem] = []
    var feeds: [String] = UserDefaults.standard.stringArray(forKey: "newsFeeds") ?? ["https://feeds.bbci.co.uk/news/rss.xml"] {
        didSet { UserDefaults.standard.set(feeds, forKey: "newsFeeds"); Task { await refreshNews() } }
    }
    var stories: [HackerNewsStory] = []
    var history: [HistoryEvent] = []
    var currencyBase: String = UserDefaults.standard.string(forKey: "currencyBase") ?? (Locale.current.currency?.identifier ?? "USD") {
        didSet { UserDefaults.standard.set(currencyBase, forKey: "currencyBase"); Task { await refreshCurrency() } }
    }
    var currencyTargets: [String] = UserDefaults.standard.stringArray(forKey: "currencyTargets") ?? ["USD", "EUR", "JPY", "GBP"] {
        didSet { UserDefaults.standard.set(currencyTargets, forKey: "currencyTargets"); Task { await refreshCurrency() } }
    }
    var rates: [CurrencyRate] = []
    var coins: [CryptoCoin] = []
    var cryptoIDs: [String] = UserDefaults.standard.stringArray(forKey: "cryptoIDs") ?? ["bitcoin", "ethereum", "solana"] {
        didSet { UserDefaults.standard.set(cryptoIDs, forKey: "cryptoIDs"); Task { await refreshCrypto() } }
    }
    var holidays: [PublicHoliday] = []
    var holidayCountry: String = Locale.current.region?.identifier ?? "GB"
    var publicIP: PublicIPInfo?
    /// Per-widget "couldn't load" flags, so cards can say so instead of spinning forever.
    var failed: Set<String> = []

    private let eventStore = EKEventStore()
    private var activated: Set<String> = []
    private var caffeinate: Process?
    private var photoFiles: [URL] = []
    private var photoIndex = 0

    init() {
        countdowns = load([CountdownItem].self, key: "countdownItems") ?? []
        habits = load([Habit].self, key: "habitItems") ?? []
        pinnedShortcuts = UserDefaults.standard.stringArray(forKey: "pinnedShortcuts") ?? []
        speed = load(SpeedResult.self, key: "lastSpeedTest")
    }

    /// Starts the data source for a widget the first time it's shown. Widgets that aren't
    /// in the layout (or the gallery) never fetch anything.
    func activate(_ kind: String) {
        let source = Self.dataSource(for: kind)
        guard activated.insert(source).inserted else { return }
        switch source {
        case "calendar":
            refreshAuthorization()
            loop(every: 60) { await $0.refreshCalendar() }
            Task {
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) { await refreshCalendar() }
            }
        case "toggles": loop(every: 10) { await $0.refreshToggles() }
        case "shortcuts": Task { await refreshShortcuts() }
        case "disks":
            refreshDisks()
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
                Task {
                    for await _ in NSWorkspace.shared.notificationCenter.notifications(named: name) { refreshDisks() }
                }
            }
            loop(every: 60) { $0.refreshDisks() }
        case "bluetooth": loop(every: 60) { await $0.refreshBluetooth() }
        case "photos": loop(every: 30) { await $0.nextPhoto() }
        case "news": loop(every: 900) { await $0.refreshNews() }
        case "hackernews": loop(every: 600) { await $0.refreshHackerNews() }
        case "onthisday": loop(every: 3600) { await $0.refreshHistory() }
        case "currency": loop(every: 3600) { await $0.refreshCurrency() }
        case "crypto": loop(every: 300) { await $0.refreshCrypto() }
        case "holidays": loop(every: 21600) { await $0.refreshHolidays() }
        case "publicip": loop(every: 600) { await $0.refreshPublicIP() }
        default: break
        }
    }

    /// Several widgets share one data source (e.g. Sun & Moon uses the forecast).
    private static func dataSource(for kind: String) -> String {
        switch kind {
        case "meeting", "reminders": return "calendar"
        default: return kind
        }
    }

    private func loop(every seconds: Double, _ work: @escaping @MainActor (MoreWidgetsModel) async -> Void) {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await work(self)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    // MARK: Calendar & reminders

    func refreshAuthorization() {
        calendarAllowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAllowed = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestCalendarAccess() {
        Task {
            _ = try? await eventStore.requestFullAccessToEvents()
            refreshAuthorization()
            await refreshCalendar()
        }
    }

    func requestRemindersAccess() {
        Task {
            _ = try? await eventStore.requestFullAccessToReminders()
            refreshAuthorization()
            await refreshCalendar()
        }
    }

    func refreshCalendar() async {
        refreshAuthorization()
        if calendarAllowed {
            let now = Date()
            let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            let upcoming = eventStore.events(matching: eventStore.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: end, calendars: nil))
                .filter { !$0.isAllDay && $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(2)
                .map { event -> MeetingItem in
                    let color = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemBlue
                    return MeetingItem(
                        title: event.title ?? "Event", start: event.startDate, end: event.endDate,
                        location: event.location ?? "",
                        joinURL: Self.meetingLink(url: event.url, location: event.location, notes: event.notes),
                        red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
                }
            meeting = upcoming.first
            meetingAfter = upcoming.count > 1 ? upcoming[1] : nil
        }
        if remindersAllowed {
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            let items: [ReminderItem] = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { values in
                    let mapped = (values ?? []).map { reminder -> ReminderItem in
                        let color = NSColor(cgColor: reminder.calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemOrange
                        return ReminderItem(
                            id: reminder.calendarItemIdentifier, title: reminder.title ?? "Reminder",
                            dueDate: reminder.dueDateComponents?.date,
                            red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
                    }
                    continuation.resume(returning: mapped)
                }
            }
            // Overdue and dated first, then undated, matching the Reminders app's "Today" feel.
            reminders = items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
    }

    func completeReminder(_ item: ReminderItem) {
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        withAnimationIfPossible { reminders.removeAll { $0.id == item.id } }
        try? eventStore.save(reminder, commit: true)
    }

    func addReminder(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let calendar = eventStore.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = trimmed
        reminder.calendar = calendar
        try? eventStore.save(reminder, commit: true)
        Task { await refreshCalendar() }
    }

    /// Finds a video-call link in an event's URL, location or notes.
    nonisolated static func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
        let hosts = ["zoom.us", "teams.microsoft.com", "teams.live.com", "meet.google.com", "webex.com", "whereby.com", "gotomeeting.com", "facetime.apple.com", "chime.aws", "slack.com/huddle"]
        func isMeeting(_ url: URL) -> Bool { hosts.contains { url.absoluteString.localizedCaseInsensitiveContains($0) } }
        if let url, isMeeting(url) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: "\n")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first(where: isMeeting)
    }

    // MARK: Quick toggles

    func refreshToggles() async {
        let values = await Task.detached(priority: .utility) {
            (
                Shell.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]),
                Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
            )
        }.value
        darkMode = values.0.output.trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
        let createDesktop = values.1.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        desktopIconsHidden = createDesktop == "0" || createDesktop == "false"
        keepAwake = caffeinate?.isRunning == true
    }

    /// Switching the system appearance needs Automation access to System Events; macOS
    /// asks the first time.
    func toggleDarkMode() {
        darkMode.toggle()
        Task {
            _ = await Task.detached {
                Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
            }.value
            await refreshToggles()
        }
    }

    /// Keeps the Mac and display awake until turned off. `-w` ties it to SplitDeck, so it
    /// also stops if SplitDeck quits.
    func toggleKeepAwake() {
        if let caffeinate, caffeinate.isRunning {
            caffeinate.terminate()
            self.caffeinate = nil
            keepAwake = false
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-di", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        do {
            try process.run()
            caffeinate = process
            keepAwake = true
        } catch {
            keepAwake = false
        }
    }

    func toggleDesktopIcons() {
        desktopIconsHidden.toggle()
        let show = desktopIconsHidden ? "false" : "true"
        Task.detached {
            _ = Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", show])
            _ = Shell.run("/usr/bin/killall", ["Finder"])
        }
    }

    func sleepDisplay() {
        Task.detached { _ = Shell.run("/usr/bin/pmset", ["displaysleepnow"]) }
    }

    // MARK: Countdown & habits

    func addCountdown(title: String, date: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        countdowns.append(CountdownItem(title: trimmed, date: Calendar.current.startOfDay(for: date)))
        countdowns.sort { $0.date < $1.date }
    }

    func removeCountdown(_ item: CountdownItem) { countdowns.removeAll { $0.id == item.id } }

    func addHabit(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        habits.append(Habit(name: trimmed))
    }

    func removeHabit(_ habit: Habit) { habits.removeAll { $0.id == habit.id } }

    func toggleHabit(_ habit: Habit, on day: Date = Date()) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = Self.dayKey(day)
        if habits[index].completed.contains(key) { habits[index].completed.remove(key) } else { habits[index].completed.insert(key) }
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Consecutive days completed, counting back from today (or yesterday, so an
    /// unfinished today doesn't reset the streak).
    func streak(_ habit: Habit) -> Int {
        let calendar = Calendar.current
        var day = Date()
        if !habit.completed.contains(Self.dayKey(day)) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while habit.completed.contains(Self.dayKey(day)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    // MARK: Shortcuts

    func refreshShortcuts() async {
        let output = await Task.detached(priority: .utility) { Shell.run("/usr/bin/shortcuts", ["list"]).output }.value
        availableShortcuts = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
    }

    func togglePinnedShortcut(_ name: String) {
        if pinnedShortcuts.contains(name) { pinnedShortcuts.removeAll { $0 == name } } else { pinnedShortcuts.append(name) }
    }

    func runShortcut(_ name: String) {
        runningShortcut = name
        Task {
            _ = await Task.detached { Shell.run("/usr/bin/shortcuts", ["run", name]) }.value
            if runningShortcut == name { runningShortcut = nil }
        }
    }

    // MARK: Disks

    func refreshDisks() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        disks = urls.compactMap { url -> DiskItem? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false,
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            return DiskItem(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, total: Int64(total), available: available,
                            ejectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true,
                            isInternal: values.volumeIsInternal == true)
        }
        .sorted { ($0.isInternal ? 0 : 1, $0.name) < ($1.isInternal ? 0 : 1, $1.name) }
    }

    func eject(_ disk: DiskItem) {
        ejecting.insert(disk.url)
        Task {
            try? await FileManager.default.unmountVolume(at: disk.url, options: [.allPartitionsAndEjectDisk])
            ejecting.remove(disk.url)
            refreshDisks()
        }
    }

    // MARK: Bluetooth

    func refreshBluetooth() async {
        let devices = await Task.detached(priority: .utility) { Self.bluetoothDevices() }.value
        bluetooth = devices
        bluetoothLoaded = true
    }

    /// Reads connected devices and their battery levels from System Information.
    nonisolated private static func bluetoothDevices() -> [BluetoothDevice] {
        let result = Shell.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        guard let data = result.output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothDevice] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let parts: [(String, String)] = [("Battery", "device_batteryLevelMain"), ("Left", "device_batteryLevelLeft"),
                                                     ("Right", "device_batteryLevelRight"), ("Case", "device_batteryLevelCase")]
                    let batteries = parts.compactMap { label, key -> (label: String, percent: Int)? in
                        guard let text = info[key] as? String, let percent = Int(text.filter(\.isNumber)) else { return nil }
                        return (label: label, percent: percent)
                    }
                    devices.append(BluetoothDevice(name: name, kind: info["device_minorType"] as? String ?? "", batteries: batteries))
                }
            }
        }
        return devices.sorted { ($0.batteries.isEmpty ? 1 : 0, $0.name) < ($1.batteries.isEmpty ? 1 : 0, $1.name) }
    }

    // MARK: Speed test

    /// Runs Apple's built-in `networkQuality` tool (about 20 seconds).
    func runSpeedTest() {
        guard !speedTestRunning else { return }
        speedTestRunning = true
        speedTestFailed = false
        Task {
            let output = await Task.detached(priority: .userInitiated) { Shell.run("/usr/bin/networkQuality", ["-c"]).output }.value
            speedTestRunning = false
            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let download = (json["dl_throughput"] as? NSNumber)?.doubleValue,
                  let upload = (json["ul_throughput"] as? NSNumber)?.doubleValue else { speedTestFailed = true; return }
            let rpm = (json["responsiveness"] as? NSNumber) ?? (json["dl_responsiveness"] as? NSNumber)
            let result = SpeedResult(download: download / 1_000_000, upload: upload / 1_000_000, responsiveness: rpm?.intValue, date: Date())
            speed = result
            save(result, key: "lastSpeedTest")
        }
    }

    // MARK: Photo frame

    func choosePhotoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of photos for the Photo Frame."
        if panel.runModal() == .OK, let url = panel.url {
            photoSource = "folder"
            photoFolder = url
        }
    }

    func usePhotosLibrary() {
        Task {
            photosAuthorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            photoSource = "photos"
        }
    }

    func nextPhoto() async {
        if photoSource == "photos" {
            photosAuthorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard photosAuthorization == .authorized || photosAuthorization == .limited else { photo = nil; return }
            if let next = await Self.randomFavouritePhoto() { photo = next }
            return
        }
        guard let folder = photoFolder else { photo = nil; return }
        if photoFiles.isEmpty {
            photoFiles = await Task.detached(priority: .utility) { Self.imageFiles(in: folder) }.value.shuffled()
            photoIndex = 0
        }
        guard !photoFiles.isEmpty else { photo = nil; return }
        let url = photoFiles[photoIndex % photoFiles.count]
        photoIndex += 1
        if let next = await Task.detached(priority: .utility, operation: { Self.thumbnail(url) }).value { photo = next }
    }

    nonisolated private static func imageFiles(in folder: URL) -> [URL] {
        let types = Set(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp"])
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL, files.count < 2000 {
            if types.contains(url.pathExtension.lowercased()) { files.append(url) }
        }
        return files
    }

    nonisolated private static func thumbnail(_ url: URL) -> FramePhoto? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1400]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return FramePhoto(image: image, caption: url.deletingPathExtension().lastPathComponent)
    }

    nonisolated private static func randomFavouritePhoto() async -> FramePhoto? {
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        var assets = collections.firstObject.map { PHAsset.fetchAssets(in: $0, options: nil) }
        if assets?.count ?? 0 == 0 {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 200
            assets = PHAsset.fetchAssets(with: .image, options: options)
        }
        guard let assets, assets.count > 0 else { return nil }
        let asset = assets.object(at: Int.random(in: 0..<assets.count))
        let caption = asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let thumbOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 1400]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return FramePhoto(image: image, caption: caption)
    }

    // MARK: News

    func addFeed(_ value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        guard URL(string: text) != nil, !feeds.contains(text) else { return }
        feeds.append(text)
    }

    func removeFeed(_ value: String) { feeds.removeAll { $0 == value } }

    func refreshNews() async {
        let urls = feeds.compactMap(URL.init(string:))
        let items = await withTaskGroup(of: [NewsItem].self) { group in
            for url in urls { group.addTask { await Self.feedItems(url) } }
            var all: [NewsItem] = []
            for await batch in group { all.append(contentsOf: batch) }
            return all
        }
        if items.isEmpty && !urls.isEmpty { failed.insert("news") } else { failed.remove("news") }
        news = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(30).map { $0 }
    }

    nonisolated private static func feedItems(_ url: URL) async -> [NewsItem] {
        guard let data = await Web.data(url) else { return [] }
        return FeedParser.parse(data, fallbackSource: url.host() ?? "")
    }

    // MARK: Hacker News

    func refreshHackerNews() async {
        guard let ids: [Int] = await Web.json(URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!) else { failed.insert("hackernews"); return }
        let top = Array(ids.prefix(12))
        let fetched = await withTaskGroup(of: (Int, HackerNewsStory?).self) { group in
            for (index, id) in top.enumerated() {
                group.addTask {
                    let item: HNItem? = await Web.json(URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")!)
                    return (index, item.map { HackerNewsStory(id: $0.id, title: $0.title ?? "", url: $0.url.flatMap(URL.init(string:)), score: $0.score ?? 0, comments: $0.descendants ?? 0) })
                }
            }
            var results: [(Int, HackerNewsStory?)] = []
            for await result in group { results.append(result) }
            return results
        }
        failed.remove("hackernews")
        stories = fetched.sorted { $0.0 < $1.0 }.compactMap(\.1).filter { !$0.title.isEmpty }
    }

    // MARK: On this day

    func refreshHistory() async {
        let components = Calendar.current.dateComponents([.month, .day], from: Date())
        let path = String(format: "https://en.wikipedia.org/api/rest_v1/feed/onthisday/selected/%02d/%02d", components.month ?? 1, components.day ?? 1)
        guard let response: WikiOnThisDay = await Web.json(URL(string: path)!) else { failed.insert("onthisday"); return }
        failed.remove("onthisday")
        history = response.selected.map {
            HistoryEvent(year: $0.year, text: $0.text, url: $0.pages.first?.content_urls?.desktop?.page.flatMap(URL.init(string:)))
        }.sorted { $0.year > $1.year }
    }

    // MARK: Currency

    func refreshCurrency() async {
        let targets = currencyTargets.filter { $0 != currencyBase }
        guard !targets.isEmpty else { rates = []; return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let start = formatter.string(from: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        let url = URL(string: "https://api.frankfurter.dev/v1/\(start)..?base=\(currencyBase)&symbols=\(targets.joined(separator: ","))")!
        guard let response: FrankfurterSeries = await Web.json(url) else { failed.insert("currency"); return }
        failed.remove("currency")
        let days = response.rates.keys.sorted()
        rates = targets.compactMap { code in
            let series = days.compactMap { response.rates[$0]?[code] }
            guard let latest = series.last else { return nil }
            return CurrencyRate(code: code, rate: latest, history: series)
        }
    }

    // MARK: Crypto

    func refreshCrypto() async {
        let currency = (Locale.current.currency?.identifier ?? "USD").lowercased()
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=\(currency)&ids=\(cryptoIDs.joined(separator: ","))&sparkline=true&price_change_percentage=24h")!
        guard let response: [CoinGeckoMarket] = await Web.json(url) else { failed.insert("crypto"); return }
        failed.remove("crypto")
        let order = Dictionary(uniqueKeysWithValues: cryptoIDs.enumerated().map { ($1, $0) })
        coins = response.map {
            CryptoCoin(id: $0.id, symbol: $0.symbol.uppercased(), name: $0.name, price: $0.current_price ?? 0,
                       change24h: $0.price_change_percentage_24h, sparkline: $0.sparkline_in_7d?.price ?? [])
        }.sorted { (order[$0.id] ?? 99) < (order[$1.id] ?? 99) }
    }

    // MARK: Holidays

    func refreshHolidays() async {
        let url = URL(string: "https://date.nager.at/api/v3/NextPublicHolidays/\(holidayCountry)")!
        guard let response: [NagerHoliday] = await Web.json(url) else { failed.insert("holidays"); return }
        failed.remove("holidays")
        let parse = Web.dayParser(.current)
        var seen = Set<String>()
        // Nationwide holidays only; regional ones (e.g. Scotland-only) are marked non-global.
        holidays = response.filter { $0.global != false }.compactMap { item -> PublicHoliday? in
            guard let date = parse(item.date), seen.insert("\(item.date)|\(item.name)").inserted else { return nil }
            return PublicHoliday(date: date, name: item.name, localName: item.localName)
        }
    }

    // MARK: Public IP

    func refreshPublicIP() async {
        guard let response: IPInfoResponse = await Web.json(URL(string: "https://ipinfo.io/json")!) else { failed.insert("publicip"); return }
        failed.remove("publicip")
        publicIP = PublicIPInfo(ip: response.ip, city: response.city ?? "", region: response.region ?? "",
                                country: response.country.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? (response.country ?? ""),
                                organisation: response.org ?? "")
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func withAnimationIfPossible(_ change: () -> Void) { change() }
}

// MARK: - Helpers

enum Shell {
    struct Result: Sendable { let output: String; let status: Int32 }

    nonisolated static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Result(output: "", status: -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(output: String(data: data, encoding: .utf8) ?? "", status: process.terminationStatus)
    }
}

enum Web {
    nonisolated static func data(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // Wikipedia and some feeds reject requests without an identifying user agent.
        request.setValue("SplitDeck/0.1 (macOS widget panel)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return data
    }

    nonisolated static func json<T: Decodable>(_ url: URL) async -> T? {
        guard let data = await data(url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Parses Open-Meteo's local "yyyy-MM-dd'T'HH:mm" times in the location's time zone.
    nonisolated static func localDateParser(_ zone: TimeZone) -> @Sendable (String) -> Date? {
        { value in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            return formatter.date(from: value)
        }
    }

    nonisolated static func dayParser(_ zone: TimeZone) -> @Sendable (String) -> Date? {
        { value in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Minimal RSS 2.0 / Atom parser: titles, links and dates.
private final class FeedParser: NSObject, XMLParserDelegate {
    private var items: [NewsItem] = []
    private var source: String
    private var inItem = false
    private var element = ""
    private var title = "", link = "", date = "", channelTitle = ""

    private init(source: String) { self.source = source }

    static func parse(_ data: Data, fallbackSource: String) -> [NewsItem] {
        let delegate = FeedParser(source: fallbackSource)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return Array(delegate.items.prefix(15))
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name
        if name == "item" || name == "entry" { inItem = true; title = ""; link = ""; date = "" }
        if inItem, name == "link", let href = attributes["href"], link.isEmpty || attributes["rel"] == "alternate" { link = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem {
            switch element {
            case "title": title += string
            case "link": link += string
            case "pubDate", "published", "updated", "dc:date": date += string
            default: break
            }
        } else if element == "title" {
            channelTitle += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if inItem, element == "title", let text = String(data: data, encoding: .utf8) { title += text }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" || name == "entry" {
            inItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), !cleanTitle.isEmpty {
                let channel = channelTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(NewsItem(title: cleanTitle, link: url, source: channel.isEmpty ? source : channel, date: Self.date(date)))
            }
        }
        element = ""
    }

    private static func date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = ISO8601DateFormatter().date(from: value) { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

// MARK: - API responses

struct OpenMeteoForecast: Decodable {
    struct Current: Decodable { let uv_index: Double? }
    struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double?]; let weather_code: [Double?]; let precipitation_probability: [Double?] }
    struct Daily: Decodable {
        let time: [String]; let weather_code: [Double?]; let temperature_2m_max: [Double?]; let temperature_2m_min: [Double?]
        let sunrise: [String]; let sunset: [String]; let uv_index_max: [Double?]; let precipitation_probability_max: [Double?]
    }
    let timezone: String
    let current: Current?
    let hourly: Hourly
    let daily: Daily
}

struct OpenMeteoAirQuality: Decodable {
    struct Current: Decodable {
        let european_aqi: Double?; let us_aqi: Double?; let pm2_5: Double?; let pm10: Double?; let uv_index: Double?
        let grass_pollen: Double?; let birch_pollen: Double?; let alder_pollen: Double?; let ragweed_pollen: Double?
    }
    let current: Current
}

private struct HNItem: Decodable { let id: Int; let title: String?; let url: String?; let score: Int?; let descendants: Int? }

private struct WikiOnThisDay: Decodable {
    struct Event: Decodable { let text: String; let year: Int; let pages: [Page] }
    struct Page: Decodable { let content_urls: URLs? }
    struct URLs: Decodable { let desktop: Desktop? }
    struct Desktop: Decodable { let page: String? }
    let selected: [Event]
}

private struct FrankfurterSeries: Decodable { let rates: [String: [String: Double]] }

private struct CoinGeckoMarket: Decodable {
    struct Sparkline: Decodable { let price: [Double] }
    let id: String; let symbol: String; let name: String
    let current_price: Double?; let price_change_percentage_24h: Double?
    let sparkline_in_7d: Sparkline?
}

private struct NagerHoliday: Decodable { let date: String; let localName: String; let name: String; let global: Bool? }

private struct IPInfoResponse: Decodable { let ip: String; let city: String?; let region: String?; let country: String?; let org: String? }
