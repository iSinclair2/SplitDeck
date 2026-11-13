import AppKit
import SwiftUI

/// Content for the widgets in `MoreWidgetCatalog`. `UtilityDeck` wraps this in its standard
/// card, so these share the deck's background, accent glow and scaling.
/// `size` is "small" (1×1), "medium" (2×1), "large" (2×2) or "banner".
struct MoreWidgetContent: View {
    let kind: String
    let size: String
    let accent: Color
    /// Per-widget settings (e.g. a weather widget's own location).
    var settings: [String: String]? = nil

    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        Group {
            switch kind {
            case "meeting": MeetingWidget(size: size, accent: accent)
            case "reminders": RemindersWidget(size: size, accent: accent)
            case "toggles": TogglesWidget(size: size, accent: accent)
            case "forecast": ForecastWidget(size: size, accent: accent, local: localWeather)
            case "airquality": AirQualityWidget(size: size, accent: accent, local: localWeather)
            case "sunmoon": SunMoonWidget(size: size, accent: accent, local: localWeather)
            case "countdown": CountdownWidget(size: size, accent: accent)
            case "habits": HabitsWidget(size: size, accent: accent)
            case "shortcuts": ShortcutsWidget(size: size, accent: accent)
            case "converter": ConverterWidget(size: size, accent: accent)
            case "disks": DisksWidget(size: size, accent: accent)
            case "bluetooth": BluetoothWidget(size: size, accent: accent)
            case "speedtest": SpeedTestWidget(size: size, accent: accent)
            case "photos": PhotoFrameWidget(size: size)
            case "news": NewsWidget(size: size, accent: accent)
            case "hackernews": HackerNewsWidget(size: size, accent: accent)
            case "onthisday": OnThisDayWidget(size: size, accent: accent)
            case "currency": CurrencyWidget(size: size, accent: accent)
            case "crypto": CryptoWidget(size: size, accent: accent)
            case "holidays": HolidaysWidget(size: size, accent: accent)
            case "publicip": PublicIPWidget(size: size, accent: accent)
            default: EmptyView()
            }
        }
        // The deck card enlarges text for at-a-glance reading; these widgets size their own
        // text and include controls (fields, pickers) that shouldn't be blown up.
        .dynamicTypeSize(.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: settings?["location"] ?? "") {
            switch kind {
            case "forecast", "sunmoon": localWeather.activate("forecast")
            case "airquality": localWeather.activate("airquality")
            default: model.activate(kind)
            }
        }
    }

    private var localWeather: LocalWeather { WeatherHub.weather(for: settings) }
}

// MARK: - Shared building blocks

private extension String {
    var isWideLayout: Bool { self == "medium" || self == "banner" }
    var isLarge: Bool { self == "large" }
    var isBanner: Bool { self == "banner" }
    var isSmall: Bool { self == "small" }
}

private enum DeckFont {
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .medium)
    static let label = Font.system(size: 12, weight: .bold)
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded).monospacedDigit() }
}

/// The soft rounded row used throughout the deck (calendar events, network rows…).
private struct DeckRow: ViewModifier {
    var compact = false
    var highlighted: Color? = nil
    func body(content: Content) -> some View {
        content
            .padding(compact ? 6 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted.map { $0.opacity(0.18) } ?? Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func deckRow(compact: Bool = false, highlighted: Color? = nil) -> some View { modifier(DeckRow(compact: compact, highlighted: highlighted)) }
}

/// Uppercase caption like the Calendar card's "TODAY".
private struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(DeckFont.label).foregroundStyle(.secondary).textCase(.uppercase)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(DeckFont.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

/// Centred icon + message, with an optional prominent action (permissions, setup).
private struct DeckEmptyState: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var accent: Color = .accentColor
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundStyle(.secondary)
            Text(title).font(DeckFont.title).multilineTextAlignment(.center)
            if let detail { Text(detail).font(DeckFont.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).controlSize(.small).tint(accent).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Loading spinner, or a retry message when the source couldn't be reached.
private struct LoadingState: View {
    let kind: String
    var message = "Loading…"
    /// Overrides the shared failure flags (used by per-location weather).
    var failed: Bool? = nil
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }
    var body: some View {
        if failed ?? model.failed.contains(kind) {
            DeckEmptyState(icon: "wifi.exclamationmark", title: "Couldn't load", detail: "Check your connection.")
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message).font(DeckFont.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small round "+" used to add items, matching the soft icon buttons.
private struct AddButton: View {
    let accent: Color
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18) }
            .buttonStyle(SoftIconButtonStyle(accent: accent, active: false))
            .help(help)
    }
}

/// Accent-tinted progress ring, as used by the Focus and System cards.
private struct DeckRing<Center: View>: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 9
    @ViewBuilder let center: Center
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
            center
        }
    }
}

private func normalized(_ values: [Double]) -> [Double] {
    guard let low = values.min(), let high = values.max(), high > low else { return values.map { _ in 50 } }
    return values.map { ($0 - low) / (high - low) * 100 }
}

private func open(_ url: URL?) { if let url { NSWorkspace.shared.open(url) } }

private func openSettingsPane(_ identifier: String) {
    open(URL(string: "x-apple.systempreferences:\(identifier)"))
}

private func relativeDays(_ date: Date) -> String {
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    switch days {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case 2..<7: return date.formatted(.dateTime.weekday(.wide))
    default: return "In \(days) days"
    }
}

/// "in 1h 5m", "in 12m", "now".
private func countdownText(to date: Date, from now: Date) -> String {
    let seconds = Int(date.timeIntervalSince(now))
    guard seconds > 59 else { return "now" }
    let hours = seconds / 3600, minutes = (seconds % 3600) / 60
    if hours >= 24 { return "in \(hours / 24)d \(hours % 24)h" }
    return hours > 0 ? "in \(hours)h \(minutes)m" : "in \(minutes)m"
}

// MARK: - Next Meeting

private struct MeetingWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        if !model.calendarAllowed {
            DeckEmptyState(icon: "calendar.badge.exclamationmark", title: "Show your next meeting", actionTitle: "Allow Calendar", accent: accent) { model.requestCalendarAccess() }
        } else if let meeting = model.meeting {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if size.isBanner {
                    HStack(spacing: 18) {
                        countdown(meeting, now: context.date, size: 34).frame(width: 180, alignment: .leading)
                        Divider()
                        details(meeting, titleSize: 18)
                        if meeting.joinURL != nil { joinButton(meeting) }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        countdown(meeting, now: context.date, size: size.isSmall ? 24 : 30)
                        details(meeting, titleSize: size.isSmall ? 15 : 18)
                        Spacer(minLength: 0)
                        HStack {
                            if meeting.joinURL != nil { joinButton(meeting) }
                            Spacer()
                            if !size.isSmall {
                                Button { open(URL(string: "ical://")) } label: { Image(systemName: "calendar").frame(width: 24, height: 24) }
                                    .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Open Calendar")
                            }
                        }
                        if size.isLarge, let after = model.meetingAfter {
                            Divider()
                            SectionLabel(text: "After that", trailing: relativeDays(after.start))
                            HStack(spacing: 7) {
                                Capsule().fill(color(after)).frame(width: 5, height: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(after.title).font(DeckFont.body).lineLimit(1)
                                    Text(after.start.formatted(date: .omitted, time: .shortened)).font(DeckFont.caption).foregroundStyle(.secondary)
                                }
                            }
                            .deckRow()
                        }
                    }
                }
            }
        } else {
            DeckEmptyState(icon: "checkmark.circle", title: "No more meetings", detail: "Nothing in the next 7 days.")
        }
    }

    private func color(_ meeting: MeetingItem) -> Color { Color(red: meeting.red, green: meeting.green, blue: meeting.blue) }

    private func countdown(_ meeting: MeetingItem, now: Date, size: CGFloat) -> some View {
        let started = meeting.start <= now
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: started ? "Happening now" : (Calendar.current.isDateInToday(meeting.start) ? "Next meeting" : relativeDays(meeting.start)))
            Text(started ? "ends \(countdownText(to: meeting.end, from: now))" : countdownText(to: meeting.start, from: now))
                .font(DeckFont.number(size)).foregroundStyle(started ? accent : .primary).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func details(_ meeting: MeetingItem, titleSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Capsule().fill(color(meeting)).frame(width: 5).frame(maxHeight: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title).font(.system(size: titleSize, weight: .bold)).lineLimit(2)
                Text("\(meeting.start.formatted(date: .omitted, time: .shortened)) – \(meeting.end.formatted(date: .omitted, time: .shortened))")
                    .font(DeckFont.caption).foregroundStyle(.secondary)
                if !meeting.location.isEmpty, meeting.joinURL == nil || !meeting.location.contains("://") {
                    Label(meeting.location, systemImage: "mappin").font(DeckFont.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func joinButton(_ meeting: MeetingItem) -> some View {
        Button { open(meeting.joinURL) } label: {
            Label("Join", systemImage: "video.fill").font(.system(size: 13, weight: .semibold)).frame(minWidth: 70, minHeight: 24)
        }
        .buttonStyle(SoftIconButtonStyle(accent: accent, active: true))
        .help(meeting.joinURL?.host() ?? "Join")
    }
}

// MARK: - Reminders

private struct RemindersWidget: View {
    let size: String
    let accent: Color
    @State private var newTitle = ""
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        if !model.remindersAllowed {
            DeckEmptyState(icon: "checklist", title: "Tick off reminders here", actionTitle: "Allow Reminders", accent: accent) { model.requestRemindersAccess() }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Reminders", trailing: model.reminders.isEmpty ? nil : "\(model.reminders.count)")
                if model.reminders.isEmpty {
                    DeckEmptyState(icon: "checkmark.circle", title: "All done")
                } else if size.isBanner {
                    HStack(spacing: 8) { ForEach(model.reminders.prefix(3)) { row($0) } }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 5) { ForEach(model.reminders.prefix(size.isLarge ? 20 : 8)) { row($0) } }
                    }
                }
                if !size.isBanner {
                    TextField("New reminder", text: $newTitle)
                        .textFieldStyle(.plain).font(DeckFont.body)
                        .deckRow(compact: true)
                        .onSubmit { model.addReminder(newTitle); newTitle = "" }
                }
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.25)) { model.completeReminder(item) } } label: {
                Image(systemName: "circle").font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: item.red, green: item.green, blue: item.blue))
            }
            .buttonStyle(.plain).help("Mark as done")
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(DeckFont.body).lineLimit(1)
                if let due = item.dueDate {
                    Text(relativeDays(due) + (Calendar.current.dateComponents([.hour], from: due).hour.map { _ in "" } ?? ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(due < Calendar.current.startOfDay(for: Date()) ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .deckRow(compact: true)
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
}

// MARK: - Quick Toggles

private struct TogglesWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isWideLayout ? 4 : 2)
        LazyVGrid(columns: columns, spacing: 8) {
            tile("Dark Mode", icon: model.darkMode ? "moon.fill" : "sun.max.fill", state: model.darkMode ? "On" : "Off", active: model.darkMode) { model.toggleDarkMode() }
            tile("Keep Awake", icon: "cup.and.heat.waves.fill", state: model.keepAwake ? "On" : "Off", active: model.keepAwake) { model.toggleKeepAwake() }
            tile("Desktop Icons", icon: model.desktopIconsHidden ? "eye.slash.fill" : "menubar.dock.rectangle", state: model.desktopIconsHidden ? "Hidden" : "Shown", active: model.desktopIconsHidden) { model.toggleDesktopIcons() }
            tile("Focus", icon: "moon.circle.fill", state: "Settings", active: false) { openSettingsPane("com.apple.Focus-Settings.extension") }
            if size.isLarge {
                tile("Sleep Display", icon: "display", state: "Now", active: false) { model.sleepDisplay() }
                tile("Lock Screen", icon: "lock.fill", state: "Now", active: false) { lockScreen() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ title: String, icon: String, state: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: size.isBanner ? 18 : 20, weight: .semibold)).frame(height: 24)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if !size.isBanner { Text(state).font(.system(size: 11, weight: .medium)).opacity(0.7) }
            }
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: size.isBanner ? 72 : 76)
            .background(active ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(active ? 0.28 : 0.10), lineWidth: 0.8))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: active)
        .help(title)
    }

    private func lockScreen() {
        // Same as Control-Command-Q; uses the login window's documented lock action.
        Task.detached {
            _ = Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"])
        }
    }
}

// MARK: - Weather helpers

private enum WeatherCode {
    static func symbol(_ code: Int, night: Bool = false) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return "—"
        }
    }

    static func isNight(_ date: Date, sun: SunTimes?) -> Bool {
        guard let sun else { return false }
        var calendar = Calendar.current
        calendar.timeZone = sun.timeZone
        let minutes = { (d: Date) in calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
        return minutes(date) < minutes(sun.sunrise) || minutes(date) > minutes(sun.sunset)
    }
}

private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

// MARK: - Forecast

private struct ForecastWidget: View {
    let size: String
    let accent: Color
    let local: LocalWeather
    private var model: LocalWeather { local }

    var body: some View {
        if model.hourly.isEmpty {
            LoadingState(kind: "forecast", message: "Loading forecast…", failed: model.forecastFailed)
        } else if size.isSmall {
            small
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Next hours", trailing: model.weather.place)
                hourlyStrip(count: size.isBanner ? 10 : 6)
                if size.isLarge {
                    Divider()
                    SectionLabel(text: "7 days")
                    dailyList
                }
            }
        }
    }

    private var small: some View {
        let now = model.hourly.first
        return VStack(alignment: .leading, spacing: 6) {
            if let now {
                HStack(alignment: .top) {
                    Image(systemName: WeatherCode.symbol(now.code, night: WeatherCode.isNight(now.time, sun: model.sun)))
                        .symbolRenderingMode(.multicolor).font(.system(size: 30))
                    Spacer()
                    Text(degrees(now.temperature)).font(DeckFont.number(34))
                }
                Text(WeatherCode.description(now.code)).font(DeckFont.title)
                if let today = model.daily.first {
                    Text("H \(degrees(today.high))  L \(degrees(today.low))").font(DeckFont.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(model.hourly.dropFirst().prefix(3)) { hour in hourCell(hour, compact: true).frame(maxWidth: .infinity) }
            }
        }
    }

    private func hourlyStrip(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(model.hourly.prefix(count)) { hour in hourCell(hour, compact: false).frame(maxWidth: .infinity) }
        }
        .deckRow()
    }

    private func hourCell(_ hour: ForecastHour, compact: Bool) -> some View {
        VStack(spacing: 4) {
            Text(hour.id == model.hourly.first?.id ? "Now" : hour.time.formatted(.dateTime.hour()))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Image(systemName: WeatherCode.symbol(hour.code, night: WeatherCode.isNight(hour.time, sun: model.sun)))
                .symbolRenderingMode(.multicolor).font(.system(size: compact ? 15 : 18)).frame(height: 20)
            Text(degrees(hour.temperature)).font(.system(size: compact ? 13 : 14, weight: .bold).monospacedDigit())
            if !compact, let rain = hour.precipitation, rain >= 20 {
                Text("\(rain)%").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan)
            }
        }
    }

    private var dailyList: some View {
        let low = model.daily.map(\.low).min() ?? 0
        let high = model.daily.map(\.high).max() ?? 1
        return VStack(spacing: 5) {
            ForEach(model.daily) { day in
                HStack(spacing: 10) {
                    Text(Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(DeckFont.body).frame(width: 48, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code)).symbolRenderingMode(.multicolor).frame(width: 24)
                    Text(degrees(day.low)).font(DeckFont.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    // Temperature range bar, scaled across the week like the Weather app.
                    GeometryReader { geometry in
                        let span = max(1, high - low)
                        let start = (day.low - low) / span * geometry.size.width
                        let width = max(6, (day.high - day.low) / span * geometry.size.width)
                        Capsule().fill(Color.primary.opacity(0.10))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [.cyan, accent, .orange], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: width).offset(x: start)
                            }
                    }
                    .frame(height: 5)
                    Text(degrees(day.high)).font(DeckFont.caption.monospacedDigit()).frame(width: 34, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Air Quality & UV

private struct AirQualityWidget: View {
    let size: String
    let accent: Color
    let local: LocalWeather
    private var model: LocalWeather { local }

    var body: some View {
        if let air = model.airQuality {
            let aqi = air.europeanAQI ?? 0
            if size.isSmall {
                VStack(spacing: 8) {
                    gauge(aqi, diameter: 104)
                    uvRow(air.uv)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 16) {
                    gauge(aqi, diameter: size.isBanner ? 92 : 120)
                    VStack(alignment: .leading, spacing: 6) {
                        metric("PM2.5", air.pm25, unit: "µg/m³")
                        metric("PM10", air.pm10, unit: "µg/m³")
                        uvRow(air.uv)
                        if size.isLarge || size.isBanner, !air.pollen.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(air.pollen.prefix(size.isBanner ? 3 : 4), id: \.name) { pollen in
                                    VStack(spacing: 1) {
                                        Text(pollen.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                        Text(pollenLevel(pollen.value)).font(.system(size: 11, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity).deckRow(compact: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            LoadingState(kind: "airquality", message: "Loading air quality…", failed: model.airQualityFailed)
        }
    }

    private func gauge(_ aqi: Double, diameter: CGFloat) -> some View {
        let category = Self.category(aqi)
        return DeckRing(progress: aqi / 100, tint: category.color, lineWidth: diameter * 0.085) {
            VStack(spacing: 0) {
                Text("\(Int(aqi.rounded()))").font(DeckFont.number(diameter * 0.28))
                Text(category.name).font(.system(size: max(10, diameter * 0.1), weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .help("European Air Quality Index")
    }

    private func metric(_ name: String, _ value: Double?, unit: String) -> some View {
        HStack {
            Text(name).font(DeckFont.caption).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—").font(.system(size: 14, weight: .bold).monospacedDigit())
            Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func uvRow(_ uv: Double?) -> some View {
        let value = uv ?? 0
        let (name, color) = Self.uvCategory(value)
        return HStack(spacing: 6) {
            Image(systemName: "sun.max.fill").foregroundStyle(color)
            Text("UV \(Int(value.rounded()))").font(.system(size: 14, weight: .bold).monospacedDigit())
            Text(name).font(DeckFont.caption).foregroundStyle(.secondary)
        }
    }

    private func pollenLevel(_ value: Double) -> String {
        switch value { case ..<1: return "None"; case ..<20: return "Low"; case ..<80: return "Med"; default: return "High" }
    }

    static func category(_ aqi: Double) -> (name: String, color: Color) {
        switch aqi {
        case ..<20: return ("Good", .green)
        case ..<40: return ("Fair", .mint)
        case ..<60: return ("Moderate", .yellow)
        case ..<80: return ("Poor", .orange)
        case ..<100: return ("Very poor", .red)
        default: return ("Extreme", .purple)
        }
    }

    static func uvCategory(_ uv: Double) -> (String, Color) {
        switch uv {
        case ..<3: return ("Low", .green)
        case ..<6: return ("Moderate", .yellow)
        case ..<8: return ("High", .orange)
        case ..<11: return ("Very high", .red)
        default: return ("Extreme", .purple)
        }
    }
}

// MARK: - Sun & Moon

private struct SunMoonWidget: View {
    let size: String
    let accent: Color
    let local: LocalWeather
    private var model: LocalWeather { local }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let moon = MoonPhase(date: context.date)
            if let sun = model.sun {
                if size.isSmall {
                    VStack(spacing: 6) {
                        sunArc(sun, now: context.date).frame(height: 70)
                        times(sun)
                        Spacer(minLength: 0)
                        HStack { moonGlyph(moon, size: 18); Text(moon.name).font(DeckFont.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                } else {
                    HStack(spacing: 16) {
                        VStack(spacing: 8) {
                            sunArc(sun, now: context.date).frame(height: size.isBanner ? 60 : 90)
                            times(sun)
                            Text(daylightText(sun, now: context.date)).font(DeckFont.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Divider()
                        VStack(spacing: 6) {
                            moonGlyph(moon, size: size.isBanner ? 34 : 48)
                            Text(moon.name).font(DeckFont.title)
                            Text("\(moon.illumination)% lit").font(DeckFont.caption).foregroundStyle(.secondary)
                            if size.isLarge {
                                Text("Full moon \(relativeDays(moon.nextFull).lowercased())").font(DeckFont.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                }
            } else {
                LoadingState(kind: "forecast", message: "Finding your location…", failed: model.forecastFailed)
            }
        }
    }

    private func times(_ sun: SunTimes) -> some View {
        HStack {
            Label(sun.sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
            Spacer()
            Label(sun.sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill")
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .symbolRenderingMode(.multicolor)
    }

    private func daylightText(_ sun: SunTimes, now: Date) -> String {
        if now < sun.sunrise { return "Sunrise \(countdownText(to: sun.sunrise, from: now))" }
        if now < sun.sunset {
            let remaining = Int(sun.sunset.timeIntervalSince(now)) / 60
            return "\(remaining / 60)h \(remaining % 60)m of daylight left"
        }
        if let next = sun.tomorrowSunrise { return "Sunrise \(countdownText(to: next, from: now))" }
        return "After sunset"
    }

    /// The sun's path from sunrise to sunset, with its current position.
    private func sunArc(_ sun: SunTimes, now: Date) -> some View {
        let total = sun.sunset.timeIntervalSince(sun.sunrise)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(sun.sunrise) / total)) : 0
        let up = now >= sun.sunrise && now <= sun.sunset
        return GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let radius = min(width / 2, height) - 6
            let center = CGPoint(x: width / 2, y: height - 2)
            let angle = Double.pi * (1 - progress)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y - radius * sin(angle))
            ZStack {
                Path { path in path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) }
                    .stroke(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                Path { path in path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * progress), clockwise: false) }
                    .stroke(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                Path { path in path.move(to: CGPoint(x: 0, y: center.y)); path.addLine(to: CGPoint(x: width, y: center.y)) }
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                Circle().fill(up ? Color.yellow : Color.secondary.opacity(0.5)).frame(width: 12, height: 12)
                    .shadow(color: up ? .orange.opacity(0.7) : .clear, radius: 6)
                    .position(point)
            }
        }
    }

    private func moonGlyph(_ moon: MoonPhase, size: CGFloat) -> some View {
        Image(systemName: moon.symbol).font(.system(size: size)).foregroundStyle(Color.primary.opacity(0.85))
    }
}

/// Moon phase calculated locally from the mean synodic month.
private struct MoonPhase {
    let fraction: Double     // 0 = new, 0.5 = full
    let date: Date

    init(date: Date) {
        self.date = date
        let knownNewMoon = Date(timeIntervalSince1970: 947_182_440) // 6 Jan 2000 18:14 UTC
        let synodic = 29.530588853
        let days = date.timeIntervalSince(knownNewMoon) / 86_400
        let phase = days.truncatingRemainder(dividingBy: synodic) / synodic
        fraction = phase < 0 ? phase + 1 : phase
    }

    var illumination: Int { Int(((1 - cos(2 * .pi * fraction)) / 2 * 100).rounded()) }

    var nextFull: Date {
        let daysToFull = ((0.5 - fraction + 1).truncatingRemainder(dividingBy: 1)) * 29.530588853
        return date.addingTimeInterval(daysToFull * 86_400)
    }

    private var index: Int { Int((fraction * 8).rounded()) % 8 }

    var name: String {
        ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"][index]
    }

    var symbol: String {
        ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter", "moonphase.waxing.gibbous",
         "moonphase.full.moon", "moonphase.waning.gibbous", "moonphase.last.quarter", "moonphase.waning.crescent"][index]
    }
}

// MARK: - Countdown

private struct CountdownWidget: View {
    let size: String
    let accent: Color
    @State private var adding = false
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    private var upcoming: [CountdownItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return model.countdowns.filter { $0.date >= today }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Countdown")
                AddButton(accent: accent, help: "Add a date") { adding = true }
                    .popover(isPresented: $adding, arrowEdge: .bottom) { editor }
            }
            if upcoming.isEmpty {
                DeckEmptyState(icon: "hourglass", title: "Count down to a date", actionTitle: "Add Date", accent: accent) { adding = true }
            } else if size.isSmall {
                hero(upcoming[0])
            } else if size.isBanner {
                HStack(spacing: 10) { ForEach(upcoming.prefix(4)) { tile($0) } }
            } else {
                if size.isLarge { hero(upcoming[0]); Divider() }
                VStack(spacing: 5) { ForEach(upcoming.dropFirst(size.isLarge ? 1 : 0).prefix(size.isLarge ? 5 : 3)) { row($0) } }
            }
        }
    }

    private func days(_ item: CountdownItem) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: item.date).day ?? 0
    }

    private func hero(_ item: CountdownItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(days(item) == 0 ? "Today" : "\(days(item))").font(DeckFont.number(size.isSmall ? 46 : 52)).foregroundStyle(accent)
            Text(days(item) == 0 ? item.title : "\(days(item) == 1 ? "day" : "days") until \(item.title)").font(DeckFont.title).lineLimit(2)
            Text(item.date.formatted(date: .complete, time: .omitted)).font(DeckFont.caption).foregroundStyle(.secondary)
        }
        .contextMenu { Button("Remove", role: .destructive) { model.removeCountdown(item) } }
    }

    private func row(_ item: CountdownItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(DeckFont.body).lineLimit(1)
                Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(days(item) == 0 ? "Today" : "\(days(item))d").font(DeckFont.number(18))
        }
        .deckRow(compact: true)
        .contextMenu { Button("Remove", role: .destructive) { model.removeCountdown(item) } }
    }

    private func tile(_ item: CountdownItem) -> some View {
        VStack(spacing: 2) {
            Text(days(item) == 0 ? "Today" : "\(days(item))").font(DeckFont.number(26))
            Text(item.title).font(DeckFont.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity).deckRow()
        .contextMenu { Button("Remove", role: .destructive) { model.removeCountdown(item) } }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Countdown").font(.headline)
            TextField("What's happening?", text: $title).textFieldStyle(.roundedBorder).frame(width: 220)
            DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Cancel") { adding = false }
                Button("Add") { model.addCountdown(title: title, date: date); title = ""; adding = false }
                    .keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }
}

// MARK: - Habits

private struct HabitsWidget: View {
    let size: String
    let accent: Color
    @State private var adding = false
    @State private var name = ""
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    private var lastSevenDays: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Habits", trailing: model.habits.isEmpty ? nil : "\(doneToday)/\(model.habits.count) today")
                AddButton(accent: accent, help: "Add a habit") { adding = true }
                    .popover(isPresented: $adding, arrowEdge: .bottom) { editor }
            }
            if model.habits.isEmpty {
                DeckEmptyState(icon: "flame", title: "Build a streak", actionTitle: "Add Habit", accent: accent) { adding = true }
            } else if size.isBanner {
                HStack(spacing: 8) { ForEach(model.habits.prefix(4)) { habitTile($0) } }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) { ForEach(model.habits.prefix(size.isLarge ? 10 : 4)) { habitRow($0) } }
                }
            }
        }
    }

    private var doneToday: Int { model.habits.filter { $0.completed.contains(MoreWidgetsModel.dayKey(Date())) }.count }

    private func habitRow(_ habit: Habit) -> some View {
        let done = habit.completed.contains(MoreWidgetsModel.dayKey(Date()))
        return HStack(spacing: 8) {
            Button { model.toggleHabit(habit) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 17)).foregroundStyle(done ? accent : .secondary)
            }
            .buttonStyle(.plain).help(done ? "Undo today" : "Done today")
            Text(habit.name).font(DeckFont.body).lineLimit(1)
            Spacer(minLength: 4)
            if !size.isSmall {
                // The past week; click a day to fix a missed check-in.
                HStack(spacing: 3) {
                    ForEach(lastSevenDays, id: \.self) { day in
                        let complete = habit.completed.contains(MoreWidgetsModel.dayKey(day))
                        Button { model.toggleHabit(habit, on: day) } label: {
                            Circle().fill(complete ? accent : Color.primary.opacity(0.12)).frame(width: 9, height: 9)
                        }
                        .buttonStyle(.plain).help(day.formatted(.dateTime.weekday(.wide)))
                    }
                }
            }
            streakBadge(habit)
        }
        .deckRow(compact: true)
        .contextMenu { Button("Remove Habit", role: .destructive) { model.removeHabit(habit) } }
    }

    private func habitTile(_ habit: Habit) -> some View {
        let done = habit.completed.contains(MoreWidgetsModel.dayKey(Date()))
        return Button { model.toggleHabit(habit) } label: {
            VStack(spacing: 4) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done ? accent : .secondary)
                Text(habit.name).font(DeckFont.caption).lineLimit(1)
                streakBadge(habit)
            }
            .frame(maxWidth: .infinity).deckRow()
        }
        .buttonStyle(.plain)
    }

    private func streakBadge(_ habit: Habit) -> some View {
        let streak = model.streak(habit)
        return HStack(spacing: 2) {
            Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? Color.orange : Color.secondary.opacity(0.5))
            Text("\(streak)").font(.system(size: 12, weight: .bold).monospacedDigit())
        }
        .font(.system(size: 11))
        .help("\(streak)-day streak")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Habit").font(.headline)
            TextField("e.g. Read 20 minutes", text: $name).textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { model.addHabit(name); name = ""; adding = false }
            HStack {
                Spacer()
                Button("Cancel") { adding = false }
                Button("Add") { model.addHabit(name); name = ""; adding = false }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }
}

// MARK: - Shortcuts

private struct ShortcutsWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Shortcuts")
                picker
            }
            if model.pinnedShortcuts.isEmpty {
                DeckEmptyState(icon: "square.stack.3d.up", title: "Run your Shortcuts", detail: "Use + to pick which ones appear here.")
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isBanner ? 5 : (size.isSmall ? 1 : 2))
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.pinnedShortcuts.prefix(size.isLarge ? 16 : (size.isSmall ? 4 : 6)), id: \.self) { button($0) }
                    }
                }
            }
        }
    }

    private var picker: some View {
        Menu {
            if model.availableShortcuts.isEmpty { Text("No shortcuts found") }
            ForEach(model.availableShortcuts, id: \.self) { name in
                Button { model.togglePinnedShortcut(name) } label: {
                    if model.pinnedShortcuts.contains(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button("Open Shortcuts") { open(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")) }
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(4).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help("Choose shortcuts")
        .onAppear { Task { await model.refreshShortcuts() } }
    }

    private func button(_ name: String) -> some View {
        let running = model.runningShortcut == name
        return Button { model.runShortcut(name) } label: {
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.gradient).frame(width: 24, height: 24)
                    if running { ProgressView().controlSize(.mini).tint(.white) } else { Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                }
                Text(name).font(DeckFont.body).lineLimit(1)
                Spacer(minLength: 0)
            }
            .deckRow(compact: true, highlighted: running ? accent : nil)
        }
        .buttonStyle(.plain)
        .disabled(running)
        .contextMenu { Button("Remove from Widget") { model.togglePinnedShortcut(name) } }
    }
}

// MARK: - Converter

private struct ConverterWidget: View {
    let size: String
    let accent: Color
    @AppStorage("converterMode") private var mode = "units"
    @AppStorage("converterCategory") private var category = "Length"
    @AppStorage("converterFrom") private var fromSymbol = "km"
    @AppStorage("converterTo") private var toSymbol = "mi"
    @AppStorage("worldClockCities") private var worldClockCities = "Europe/London,America/New_York,Asia/Tokyo"
    @State private var input = "10"
    @State private var hourOffset = 0.0

    private static let categories: [(String, [Dimension])] = [
        ("Length", [UnitLength.millimeters, UnitLength.centimeters, UnitLength.meters, UnitLength.kilometers, UnitLength.inches, UnitLength.feet, UnitLength.yards, UnitLength.miles]),
        ("Weight", [UnitMass.grams, UnitMass.kilograms, UnitMass.ounces, UnitMass.pounds, UnitMass.stones]),
        ("Temperature", [UnitTemperature.celsius, UnitTemperature.fahrenheit, UnitTemperature.kelvin]),
        ("Volume", [UnitVolume.milliliters, UnitVolume.liters, UnitVolume.cups, UnitVolume.fluidOunces, UnitVolume.pints, UnitVolume.gallons, UnitVolume.imperialPints, UnitVolume.imperialGallons]),
        ("Speed", [UnitSpeed.kilometersPerHour, UnitSpeed.milesPerHour, UnitSpeed.metersPerSecond, UnitSpeed.knots])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !size.isSmall {
                HStack(spacing: 5) {
                    Button("Units") { mode = "units" }.buttonStyle(FocusChipStyle(selected: mode == "units", accent: accent))
                    Button("Time zones") { mode = "time" }.buttonStyle(FocusChipStyle(selected: mode == "time", accent: accent))
                    Spacer()
                }
            }
            if mode == "time" && !size.isSmall { timePlanner } else { units }
        }
    }

    // Units

    private var units: some View {
        let dimensions = Self.categories.first { $0.0 == category }?.1 ?? Self.categories[0].1
        let from = dimensions.first { $0.symbol == fromSymbol } ?? dimensions[0]
        let to = dimensions.first { $0.symbol == toSymbol } ?? dimensions[min(1, dimensions.count - 1)]
        let value = Double(input.replacingOccurrences(of: ",", with: ".")) ?? 0
        let result = Measurement(value: value, unit: from).converted(to: to).value
        return VStack(alignment: .leading, spacing: 8) {
            Menu(category) {
                ForEach(Self.categories, id: \.0) { item in
                    Button(item.0) { category = item.0; fromSymbol = item.1[0].symbol; toSymbol = item.1[min(1, item.1.count - 1)].symbol }
                }
            }
            .menuStyle(.borderlessButton).fixedSize().font(DeckFont.label)
            HStack(spacing: 6) {
                TextField("0", text: $input).textFieldStyle(.plain).font(DeckFont.number(20)).multilineTextAlignment(.leading)
                unitMenu(dimensions, selection: from) { fromSymbol = $0 }
            }
            .deckRow(compact: true)
            HStack(spacing: 6) {
                Text(result.formatted(.number.precision(.significantDigits(1...6))))
                    .font(DeckFont.number(size.isSmall ? 22 : 26)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button { swap(&fromSymbol, &toSymbol) } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 20, height: 20) }
                    .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Swap units")
                unitMenu(dimensions, selection: to) { toSymbol = $0 }
            }
            .deckRow(compact: true)
        }
    }

    private func unitMenu(_ dimensions: [Dimension], selection: Dimension, choose: @escaping (String) -> Void) -> some View {
        Menu(selection.symbol) {
            ForEach(dimensions, id: \.symbol) { unit in
                Button(MeasurementFormatter.unitName(unit)) { choose(unit.symbol) }
            }
        }
        .menuStyle(.borderlessButton).fixedSize().font(DeckFont.title)
    }

    // Time zones

    private var timePlanner: some View {
        let zones = [TimeZone.current.identifier] + worldClockCities.split(separator: ",").map(String.init).filter { $0 != TimeZone.current.identifier }
        let date = Date().addingTimeInterval(hourOffset * 3600)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hourOffset == 0 ? "Now" : (hourOffset > 0 ? "+\(hourText(hourOffset))" : "−\(hourText(-hourOffset))"))
                    .font(DeckFont.label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                Slider(value: $hourOffset, in: -12...12, step: 0.5)
                Button { hourOffset = 0 } label: { Image(systemName: "arrow.uturn.backward").frame(width: 18, height: 18) }
                    .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Back to now").disabled(hourOffset == 0)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(zones.prefix(size.isLarge ? 8 : 3), id: \.self) { zone in zoneRow(zone, date: date, local: zone == TimeZone.current.identifier) }
                }
            }
        }
    }

    private func hourText(_ hours: Double) -> String { hours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(hours))h" : "\(Int(hours))h 30m" }

    private func zoneRow(_ identifier: String, date: Date, local: Bool) -> some View {
        let zone = TimeZone(identifier: identifier) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        let working = (9..<18).contains(hour)
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm EEE", options: 0, locale: .current)
        let city = local ? "Here" : (ClockCity.city(for: identifier)?.name ?? identifier)
        return HStack {
            Circle().fill(working ? Color.green : (hour >= 22 || hour < 7 ? Color.indigo : Color.orange)).frame(width: 7, height: 7)
            Text(city).font(DeckFont.body).lineLimit(1)
            Spacer()
            Text(formatter.string(from: date)).font(.system(size: 14, weight: .bold).monospacedDigit())
        }
        .deckRow(compact: true, highlighted: local ? accent : nil)
        .help(working ? "Working hours" : "Outside working hours")
    }
}

private extension MeasurementFormatter {
    static func unitName(_ unit: Unit) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        return formatter.string(from: unit).capitalized
    }
}

// MARK: - Disks

private struct DisksWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        if model.disks.isEmpty {
            LoadingState(kind: "disks")
        } else if size.isSmall, let first = model.disks.first {
            let used = 1 - Double(first.available) / Double(max(1, first.total))
            VStack(spacing: 6) {
                DeckRing(progress: used, tint: used > 0.9 ? .red : accent) {
                    VStack(spacing: 0) {
                        Text(ByteCountFormatter.string(fromByteCount: first.available, countStyle: .file)).font(DeckFont.number(19)).lineLimit(1).minimumScaleFactor(0.6)
                        Text("free").font(DeckFont.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)
                Text(first.name).font(DeckFont.caption).lineLimit(1)
                if model.disks.count > 1 { Text("+\(model.disks.count - 1) more").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { open(first.url) }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isBanner ? 3 : 1)
                LazyVGrid(columns: columns, spacing: 6) { ForEach(model.disks.prefix(size.isLarge ? 8 : 3)) { row($0) } }
            }
        }
    }

    private func row(_ disk: DiskItem) -> some View {
        let used = 1 - Double(disk.available) / Double(max(1, disk.total))
        return HStack(spacing: 10) {
            Image(systemName: disk.isInternal ? "internaldrive.fill" : "externaldrive.fill").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(disk.name).font(DeckFont.body).lineLimit(1)
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: disk.available, countStyle: .file)) free").font(DeckFont.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: used).tint(used > 0.9 ? .red : accent)
            }
            if disk.ejectable {
                Button { model.eject(disk) } label: {
                    if model.ejecting.contains(disk.url) { ProgressView().controlSize(.mini).frame(width: 20, height: 20) }
                    else { Image(systemName: "eject.fill").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20) }
                }
                .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Eject \(disk.name)")
            }
        }
        .deckRow()
        .onTapGesture { open(disk.url) }
        .help("Show in Finder")
    }
}

// MARK: - Bluetooth

private struct BluetoothWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        if !model.bluetoothLoaded {
            LoadingState(kind: "bluetooth", message: "Finding devices…")
        } else if model.bluetooth.isEmpty {
            DeckEmptyState(icon: "headphones", title: "No devices connected", actionTitle: "Bluetooth Settings", accent: accent) {
                openSettingsPane("com.apple.BluetoothSettings")
            }
        } else if size.isSmall, let first = model.bluetooth.first {
            VStack(spacing: 8) {
                Image(systemName: symbol(first)).font(.system(size: 34)).frame(height: 40)
                Text(first.name).font(DeckFont.title).lineLimit(1).minimumScaleFactor(0.7)
                batteryLine(first).frame(maxWidth: .infinity)
                if model.bluetooth.count > 1 { Text("+\(model.bluetooth.count - 1) more").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { openSettingsPane("com.apple.BluetoothSettings") }
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isBanner ? 3 : 1)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.bluetooth.prefix(size.isLarge ? 8 : 3)) { device in
                        HStack(spacing: 10) {
                            Image(systemName: symbol(device)).font(.system(size: 18)).frame(width: 26)
                            Text(device.name).font(DeckFont.body).lineLimit(1)
                            Spacer(minLength: 4)
                            batteryLine(device)
                        }
                        .deckRow()
                        .onTapGesture { openSettingsPane("com.apple.BluetoothSettings") }
                    }
                }
            }
        }
    }

    private func batteryLine(_ device: BluetoothDevice) -> some View {
        HStack(spacing: 8) {
            if device.batteries.isEmpty { Text("Connected").font(DeckFont.caption).foregroundStyle(.secondary) }
            ForEach(device.batteries, id: \.label) { battery in
                HStack(spacing: 3) {
                    if device.batteries.count > 1 { Text(String(battery.label.prefix(1))).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary) }
                    Image(systemName: batterySymbol(battery.percent)).foregroundStyle(battery.percent <= 20 ? Color.red : Color.primary)
                    Text("\(battery.percent)%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent { case 76...: return "battery.100percent"; case 51...: return "battery.75percent"; case 26...: return "battery.50percent"; case 11...: return "battery.25percent"; default: return "battery.0percent" }
    }

    private func symbol(_ device: BluetoothDevice) -> String {
        let text = (device.kind + " " + device.name).lowercased()
        if text.contains("airpods max") { return "airpodsmax" }
        if text.contains("airpods pro") { return "airpodspro" }
        if text.contains("airpods") { return "airpods" }
        if text.contains("headphone") || text.contains("headset") || text.contains("beats") { return "headphones" }
        if text.contains("keyboard") { return "keyboard" }
        if text.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if text.contains("mouse") { return "magicmouse" }
        if text.contains("speaker") { return "hifispeaker" }
        if text.contains("controller") || text.contains("gamepad") { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    }
}

// MARK: - Internet Speed

private struct SpeedTestWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Internet speed", trailing: model.speed.map { $0.date.formatted(.relative(presentation: .named)) })
            if model.speedTestRunning {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.regular)
                    Text("Testing… about 20 seconds").font(DeckFont.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let speed = model.speed {
                if size.isSmall {
                    VStack(alignment: .leading, spacing: 0) {
                        reading(speed.download, label: "Download", symbol: "arrow.down.circle.fill", big: true)
                        reading(speed.upload, label: "Upload", symbol: "arrow.up.circle.fill", big: false)
                    }
                } else {
                    HStack(spacing: 14) {
                        reading(speed.download, label: "Download", symbol: "arrow.down.circle.fill", big: true)
                        reading(speed.upload, label: "Upload", symbol: "arrow.up.circle.fill", big: true)
                        if let rpm = speed.responsiveness {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(rpm)").font(DeckFont.number(24))
                                Text("RPM · \(rpm >= 1000 ? "High" : (rpm >= 300 ? "Medium" : "Low"))").font(DeckFont.caption).foregroundStyle(.secondary)
                            }
                            .help("Responsiveness: round trips per minute under load")
                        }
                    }
                }
                if model.speedTestFailed { Text("Last test failed").font(DeckFont.caption).foregroundStyle(.red) }
            } else {
                DeckEmptyState(icon: "speedometer", title: model.speedTestFailed ? "Test failed" : "Test your connection")
            }
            Spacer(minLength: 0)
            Button { model.runSpeedTest() } label: {
                Label(model.speed == nil ? "Run Test" : "Test Again", systemImage: "play.fill").font(.system(size: 13, weight: .semibold)).frame(minWidth: 96, minHeight: 24)
            }
            .buttonStyle(SoftIconButtonStyle(accent: accent, active: true))
            .disabled(model.speedTestRunning)
        }
    }

    private func reading(_ value: Double, label: String, symbol: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value >= 100 ? "\(Int(value.rounded()))" : value.formatted(.number.precision(.fractionLength(1))))
                    .font(DeckFont.number(big ? 30 : 20))
                Text("Mbps").font(DeckFont.caption).foregroundStyle(.secondary)
            }
            Label(label, systemImage: symbol).font(DeckFont.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Photo Frame

private struct PhotoFrameWidget: View {
    let size: String
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        Group {
            if let photo = model.photo {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .overlay {
                            Image(decorative: photo.image, scale: 1).resizable().scaledToFill()
                                .id(ObjectIdentifier(photo.image))
                                .transition(.opacity)
                        }
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    if !photo.caption.isEmpty && !size.isSmall {
                        Text(photo.caption).font(DeckFont.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(1).padding(12)
                    }
                }
                .animation(.easeInOut(duration: 1.0), value: ObjectIdentifier(photo.image))
                .onTapGesture { Task { await model.nextPhoto() } }
                .help("Click for the next photo")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text(model.photoSource == "photos" && model.photosAuthorization == .denied ? "Photos access is off" : "Show your photos").font(DeckFont.title)
                    HStack(spacing: 6) {
                        Button("Choose Folder…") { model.choosePhotoFolder() }
                        Button("Use Photos") { model.usePhotosLibrary() }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(13)
            }
        }
        .contextMenu {
            Button("Next Photo") { Task { await model.nextPhoto() } }
            Divider()
            Button("Choose Folder…") { model.choosePhotoFolder() }
            Button("Use Photos Favourites") { model.usePhotosLibrary() }
        }
    }
}

// MARK: - News

private struct NewsWidget: View {
    let size: String
    let accent: Color
    @State private var managing = false
    @State private var newFeed = ""
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Headlines")
                Button { managing = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18) }
                    .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Manage feeds")
                    .popover(isPresented: $managing, arrowEdge: .bottom) { feedEditor }
            }
            if model.news.isEmpty {
                LoadingState(kind: "news", message: "Loading headlines…")
            } else if size.isBanner {
                HStack(spacing: 8) { ForEach(model.news.prefix(3)) { headline($0, lines: 2).frame(maxHeight: .infinity, alignment: .top) } }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) { ForEach(model.news.prefix(size.isLarge ? 12 : 4)) { headline($0, lines: size.isSmall ? 3 : 2) } }
                }
            }
        }
    }

    private func headline(_ item: NewsItem, lines: Int) -> some View {
        Button { open(item.link) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(DeckFont.body).lineLimit(lines).multilineTextAlignment(.leading)
                Text([item.source, item.date?.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .deckRow(compact: true)
        }
        .buttonStyle(.plain)
    }

    private var feedEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("News Feeds").font(.headline)
            ForEach(model.feeds, id: \.self) { feed in
                HStack {
                    Text(URL(string: feed)?.host() ?? feed).lineLimit(1)
                    Spacer()
                    Button { model.removeFeed(feed) } label: { Image(systemName: "minus.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("RSS or Atom feed URL", text: $newFeed).textFieldStyle(.roundedBorder)
                    .onSubmit { model.addFeed(newFeed); newFeed = "" }
                Button("Add") { model.addFeed(newFeed); newFeed = "" }.disabled(newFeed.isEmpty)
            }
        }
        .padding(14).frame(width: 320)
    }
}

// MARK: - Hacker News

private struct HackerNewsWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Hacker News", trailing: "Top")
            if model.stories.isEmpty {
                LoadingState(kind: "hackernews", message: "Loading stories…")
            } else if size.isBanner {
                HStack(spacing: 8) { ForEach(model.stories.prefix(3)) { story($0) } }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) { ForEach(model.stories.prefix(size.isLarge ? 12 : 4)) { story($0) } }
                }
            }
        }
    }

    private func story(_ item: HackerNewsStory) -> some View {
        Button { open(item.url ?? item.discussionURL) } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(item.score)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .frame(minWidth: 30, minHeight: 20).background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(DeckFont.body).lineLimit(2).multilineTextAlignment(.leading)
                    Text([item.url?.host()?.replacingOccurrences(of: "www.", with: ""), "\(item.comments) comments"].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .deckRow(compact: true)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Discussion") { open(item.discussionURL) }
            if let url = item.url { Button("Open Article") { open(url) } }
        }
    }
}

// MARK: - On This Day

private struct OnThisDayWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "On this day", trailing: Date().formatted(.dateTime.day().month(.wide)))
            if model.history.isEmpty {
                LoadingState(kind: "onthisday", message: "Loading history…")
            } else if size.isLarge {
                ScrollView(.vertical, showsIndicators: false) { VStack(spacing: 6) { ForEach(model.history.prefix(8)) { event($0, lines: 3) } } }
            } else {
                // Rotate through the day's events every minute.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let count = model.history.count
                    let start = (Calendar.current.component(.minute, from: context.date) * (size.isSmall ? 1 : 2)) % max(1, count)
                    let shown = (0..<(size.isSmall ? 1 : 2)).map { model.history[(start + $0) % count] }
                    if size.isBanner || size.isWideLayout {
                        HStack(alignment: .top, spacing: 8) { ForEach(shown) { event($0, lines: size.isBanner ? 2 : 4) } }
                    } else {
                        ForEach(shown) { event($0, lines: 5) }
                    }
                }
            }
        }
    }

    private func event(_ item: HistoryEvent, lines: Int) -> some View {
        Button { open(item.url) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(String(item.year)).font(DeckFont.number(20)).foregroundStyle(accent)
                Text(item.text).font(DeckFont.body).lineLimit(lines).multilineTextAlignment(.leading)
                Text("\(Calendar.current.component(.year, from: Date()) - item.year) years ago").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .deckRow()
        }
        .buttonStyle(.plain)
        .help("Read on Wikipedia")
    }
}

// MARK: - Currency

private struct CurrencyWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }
    private static let common = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD", "CNY", "HKD", "SGD", "INR", "SEK", "NOK", "DKK", "PLN", "CZK", "MXN", "BRL", "ZAR", "KRW", "TRY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Menu("1 \(model.currencyBase)") {
                    ForEach(Self.common, id: \.self) { code in Button(code) { model.currencyBase = code } }
                }
                .menuStyle(.borderlessButton).fixedSize().font(DeckFont.label)
                Spacer()
                Menu {
                    ForEach(Self.common.filter { $0 != model.currencyBase }, id: \.self) { code in
                        Button { toggle(code) } label: { if model.currencyTargets.contains(code) { Label(code, systemImage: "checkmark") } else { Text(code) } }
                    }
                } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose currencies")
            }
            if model.rates.isEmpty {
                LoadingState(kind: "currency", message: "Loading rates…")
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isBanner ? 3 : 1)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 5) { ForEach(model.rates.prefix(size.isLarge ? 10 : 3)) { row($0) } }
                }
                if size.isLarge { Text("European Central Bank reference rates").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
    }

    private func toggle(_ code: String) {
        if model.currencyTargets.contains(code) { model.currencyTargets.removeAll { $0 == code } } else { model.currencyTargets.append(code) }
    }

    private func row(_ rate: CurrencyRate) -> some View {
        HStack(spacing: 8) {
            Text(rate.code).font(.system(size: 13, weight: .bold)).frame(width: 38, alignment: .leading)
            if !size.isSmall {
                Sparkline(values: normalized(rate.history)).stroke((rate.change ?? 0) >= 0 ? Color.green : Color.red, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(height: 20)
            } else { Spacer(minLength: 0) }
            VStack(alignment: .trailing, spacing: 0) {
                Text(rate.rate.formatted(.number.precision(.significantDigits(4...5)))).font(.system(size: 14, weight: .bold).monospacedDigit())
                if let change = rate.change {
                    Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1))))% 30d").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(change >= 0 ? Color.green : Color.red)
                }
            }
        }
        .deckRow(compact: true)
    }
}

// MARK: - Crypto

private struct CryptoWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }
    private static let coins = [("bitcoin", "Bitcoin"), ("ethereum", "Ethereum"), ("solana", "Solana"), ("ripple", "XRP"), ("cardano", "Cardano"),
                                ("dogecoin", "Dogecoin"), ("litecoin", "Litecoin"), ("polkadot", "Polkadot"), ("chainlink", "Chainlink"), ("avalanche-2", "Avalanche")]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Crypto", trailing: "7 days")
                Menu {
                    ForEach(Self.coins, id: \.0) { coin in
                        Button { toggle(coin.0) } label: { if model.cryptoIDs.contains(coin.0) { Label(coin.1, systemImage: "checkmark") } else { Text(coin.1) } }
                    }
                } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 18, height: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose coins")
            }
            if model.coins.isEmpty {
                LoadingState(kind: "crypto", message: "Loading prices…")
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: size.isBanner ? 3 : 1)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 5) { ForEach(model.coins.prefix(size.isLarge ? 8 : 3)) { row($0) } }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if model.cryptoIDs.contains(id) { if model.cryptoIDs.count > 1 { model.cryptoIDs.removeAll { $0 == id } } } else { model.cryptoIDs.append(id) }
    }

    private func row(_ coin: CryptoCoin) -> some View {
        let up = (coin.change24h ?? 0) >= 0
        return Button { open(URL(string: "https://www.coingecko.com/en/coins/\(coin.id)")) } label: {
            HStack(spacing: 8) {
                Text(coin.symbol).font(.system(size: 13, weight: .bold)).frame(width: 40, alignment: .leading)
                if !size.isSmall {
                    Sparkline(values: normalized(coin.sparkline)).stroke(up ? Color.green : Color.red, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(height: 20)
                } else { Spacer(minLength: 0) }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(coin.price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.significantDigits(2...6))))
                        .font(.system(size: 14, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                    if let change = coin.change24h {
                        Text("\(up ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1))))% 24h").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(up ? Color.green : Color.red)
                    }
                }
            }
            .deckRow(compact: true)
        }
        .buttonStyle(.plain)
        .help(coin.name)
    }
}

// MARK: - Public Holidays

private struct HolidaysWidget: View {
    let size: String
    let accent: Color
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Public holidays", trailing: Locale.current.localizedString(forRegionCode: model.holidayCountry))
            if let next = model.holidays.first {
                if size.isBanner {
                    HStack(spacing: 8) { ForEach(model.holidays.prefix(4)) { tile($0) } }
                } else {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: next.date).day ?? 0
                    VStack(alignment: .leading, spacing: 1) {
                        Text(days == 0 ? "Today" : "\(days) \(days == 1 ? "day" : "days")").font(DeckFont.number(size.isSmall ? 30 : 34)).foregroundStyle(accent)
                        Text(next.name).font(DeckFont.title).lineLimit(2)
                        Text(next.date.formatted(date: .complete, time: .omitted)).font(DeckFont.caption).foregroundStyle(.secondary)
                    }
                    if !size.isSmall {
                        VStack(spacing: 4) {
                            ForEach(model.holidays.dropFirst().prefix(size.isLarge ? 7 : 1)) { holiday in
                                HStack {
                                    Text(holiday.name).font(DeckFont.body).lineLimit(1)
                                    Spacer()
                                    Text(holiday.date.formatted(.dateTime.day().month(.abbreviated))).font(DeckFont.caption).foregroundStyle(.secondary)
                                }
                                .deckRow(compact: true)
                            }
                        }
                    }
                }
            } else {
                LoadingState(kind: "holidays", message: "Loading holidays…")
            }
        }
    }

    private func tile(_ holiday: PublicHoliday) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(holiday.date.formatted(.dateTime.day().month(.abbreviated))).font(DeckFont.number(18)).foregroundStyle(accent)
            Text(holiday.name).font(DeckFont.caption).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).deckRow()
    }
}

// MARK: - Public IP

private struct PublicIPWidget: View {
    let size: String
    let accent: Color
    @State private var copied = false
    private var model: MoreWidgetsModel { SplitDeckLiveData.shared.more }

    var body: some View {
        if let info = model.publicIP {
            let content = VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Public IP")
                Text(info.ip).font(.system(size: info.ip.count > 15 ? 15 : (size.isSmall ? 21 : 26), weight: .bold, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                Label([info.city, info.region, info.country].filter { !$0.isEmpty }.joined(separator: ", "), systemImage: "mappin.and.ellipse")
                    .font(DeckFont.caption).foregroundStyle(.secondary).lineLimit(2)
                if !info.organisation.isEmpty && !size.isSmall {
                    Label(info.organisation.replacingOccurrences(of: #"^AS\d+\s*"#, with: "", options: .regularExpression), systemImage: "building.2")
                        .font(DeckFont.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.ip, forType: .string)
                        withAnimation { copied = true }
                        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.system(size: 12, weight: .semibold)).frame(minWidth: 64, minHeight: 22)
                    }
                    .buttonStyle(SoftIconButtonStyle(accent: accent, active: copied))
                    Button { Task { await model.refreshPublicIP() } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22) }
                        .buttonStyle(SoftIconButtonStyle(accent: accent, active: false)).help("Refresh")
                }
            }
            content
        } else {
            LoadingState(kind: "publicip", message: "Looking up your IP…")
        }
    }
}
