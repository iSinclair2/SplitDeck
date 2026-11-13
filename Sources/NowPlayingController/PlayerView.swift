import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openSettings) private var openSettings
    @State private var model = SplitDeckLiveData.shared.player
    @State private var badges = SplitDeckLiveData.shared.badges
    @State private var unreadHeight: CGFloat = 170
    @State private var dividerDragStartHeight: CGFloat?
    @State private var utilityHeight: CGFloat = 170
    @AppStorage("backgroundStyle") private var backgroundStyle = "album"
    @AppStorage("albumArtworkEnabled") private var albumArtworkEnabled = true
    @AppStorage("notificationBarEnabled") private var notificationBarEnabled = true
    @AppStorage("todaySectionEnabled") private var todaySectionEnabled = true
    @AppStorage("focusSectionEnabled") private var focusSectionEnabled = true
    @AppStorage("quickShelfEnabled") private var quickShelfEnabled = true
    @AppStorage("systemStatusEnabled") private var systemStatusEnabled = true
    @AppStorage("scratchpadEnabled") private var scratchpadEnabled = true
    @AppStorage("layoutOrder") private var layoutOrderString = "notifications,utilities,player"
    @AppStorage("infoBarEnabled") private var infoBarEnabled = true
    @AppStorage("utilityRowCount") private var utilityRowCount = 1
    @AppStorage("utilityDeckEnabled") private var utilityDeckEnabled = true
    @AppStorage("mediaPlayerEnabled") private var mediaPlayerEnabled = true
    @AppStorage("clipboardHistoryEnabled") private var clipboardHistoryEnabled = true
    @AppStorage("meetingMode") private var meetingMode = false
    @AppStorage("worldClocksEnabled") private var worldClocksEnabled = true
    @AppStorage("monthCalendarEnabled") private var monthCalendarEnabled = true
    @AppStorage("networkWidgetEnabled") private var networkWidgetEnabled = true
    @AppStorage("audioWidgetEnabled") private var audioWidgetEnabled = true
    @AppStorage("performanceWidgetEnabled") private var performanceWidgetEnabled = true
    @AppStorage("recentFilesEnabled") private var recentFilesEnabled = true
    @AppStorage("launcherWidgetEnabled") private var launcherWidgetEnabled = true
    @AppStorage("notificationBadgeVisible") private var notificationBadgeVisible = true
    @AppStorage("placement_info") private var infoPlacement = "header"
    @AppStorage("placement_notifications") private var notificationsPlacement = "footer"
    @AppStorage("placement_utilities") private var utilitiesPlacement = "body"
    @AppStorage("placement_player") private var playerPlacement = "body"
    @AppStorage("size_info") private var infoSize = "medium"
    @AppStorage("size_notifications") private var notificationsSize = "medium"
    @AppStorage("size_player") private var playerSize = "medium"
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("accentSource") private var accentSource = "system"
    @State private var artworkAccent = Color.accentColor
    private static let artworkCrossfade = Animation.easeInOut(duration: 0.8)

    private var showsUnreadSection: Bool {
        !meetingMode && notificationBarEnabled && (!badges.hasAccessibilityPermission || !visibleBadgedApps.isEmpty)
    }

    private var effectiveUnreadHeight: CGFloat {
        notificationsSize == "small" ? 112 : (notificationsSize == "large" ? 230 : unreadHeight)
    }

    private var visibleBadgedApps: [BadgedApp] {
        badges.apps
    }

    private var showsUtilityDeck: Bool {
        utilityDeckEnabled && (todaySectionEnabled || focusSectionEnabled || quickShelfEnabled || systemStatusEnabled || scratchpadEnabled || clipboardHistoryEnabled || worldClocksEnabled || monthCalendarEnabled || networkWidgetEnabled || audioWidgetEnabled || performanceWidgetEnabled || recentFilesEnabled || launcherWidgetEnabled)
    }

    private var effectiveUtilityHeight: CGFloat {
        minimumUtilityHeight
    }

    private var minimumUtilityHeight: CGFloat {
        CGFloat(utilityRowCount * 146 + 16)
    }

    private static let drawerWidth: CGFloat = 330
    private var layoutSession: LayoutEditSession { .shared }
    /// How much the window grew to fit the drawer, so exactly that is given back.
    @State private var widenedForDrawer: CGFloat = 0

    var body: some View {
        // The drawer overlays the deck rather than sitting beside it in an HStack, so opening
        // it never raises the window's minimum width. (A full-screen Split View tile can't
        // grow, and a minimum wider than the tile crashed the app.) When there's room, the
        // deck is inset so nothing is hidden behind the drawer.
        GeometryReader { outer in
            let drawerWidth = min(Self.drawerWidth, outer.size.width)
            let insetsDeck = layoutSession.isEditing && outer.size.width - drawerWidth >= 300
            ZStack(alignment: .trailing) {
                GeometryReader { geometry in
                    let topInset: CGFloat = geometry.size.height > 900 ? 56 : 28

                    ZStack {
                        background
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                        VStack(spacing: 0) {
                            Color.clear.frame(height: topInset)
                            UtilityDeck(player: model, badges: badges)
                                .environment(\.controlActiveState, .active)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .padding(.trailing, insetsDeck ? drawerWidth : 0)
                if layoutSession.isEditing {
                    LayoutDrawer()
                        .frame(width: drawerWidth)
                        .shadow(color: .black.opacity(insetsDeck ? 0 : 0.3), radius: 18, x: -4)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onChange(of: layoutSession.isEditing) { _, editing in resizeWindowForDrawer(editing) }
        .frame(minWidth: 300, idealWidth: 940, minHeight: 620, idealHeight: 900)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .bottomTrailing) {
            if (controlActiveState == .key || meetingMode) && !layoutSession.isEditing {
                HStack(spacing: 8) {
                    if controlActiveState == .key {
                        Button { meetingMode.toggle() } label: {
                            Label(meetingMode ? "Meeting On" : "Meeting", systemImage: meetingMode ? "person.crop.circle.badge.checkmark" : "person.2.slash")
                                .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 28)
                                .background(meetingMode ? AnyShapeStyle(Color.accentColor.opacity(0.28)) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                        }
                        .buttonStyle(.plain).help(meetingMode ? "Turn off Meeting Mode" : "Turn on Meeting Mode")
                    } else {
                        Label(meetingMode ? "Meeting On" : "Meeting", systemImage: meetingMode ? "person.crop.circle.badge.checkmark" : "person.2.slash")
                            .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 28)
                            .background(.ultraThinMaterial, in: Capsule())
                            .help("Meeting Mode is hiding private and distracting widgets")
                    }
                    if controlActiveState == .key {
                        Button { layoutSession.begin() } label: {
                            Image(systemName: "rectangle.3.group")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain).help("Edit Layout (⇧⌘L)")
                        Button { openSettings() } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain).help("SplitDeck Settings")
                    }
                }
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
        }
        .task { model.start() }
        .task { badges.start() }
        .preferredColorScheme(AppAppearance.shared.scheme(for: appearanceMode))
        .onAppear { applyApplicationAppearance() }
        .onChange(of: appearanceMode) { _, _ in applyApplicationAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: .splitDeckAppearanceChanged)) { _ in
            applyApplicationAppearance()
        }
        .onChange(of: model.artworkRevision, initial: true) { _, _ in
            withAnimation(Self.artworkCrossfade) { updateArtworkAccent() }
        }
        .onChange(of: accentSource) { _, _ in updateArtworkAccent() }
        .tint(accentSource == "artwork" ? artworkAccent : .accentColor)
    }

    /// Grows the window to make room for the drawer, so the deck keeps its size while
    /// editing, then gives the space back afterwards.
    private func resizeWindowForDrawer(_ editing: Bool) {
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "SplitDeck" }),
              !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        if editing {
            guard let screen = window.screen?.visibleFrame else { return }
            let extra = min(Self.drawerWidth, max(0, screen.width - frame.width))
            guard extra > 0 else { return }
            frame.size.width += extra
            if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
            widenedForDrawer = extra
        } else {
            guard widenedForDrawer > 0 else { return }
            frame.size.width = max(window.minSize.width, frame.width - widenedForDrawer)
            widenedForDrawer = 0
        }
        window.setFrame(frame, display: true, animate: true)
    }

    private func applyApplicationAppearance() {
        let appearance = appearanceMode == "light" ? NSAppearance(named: .aqua) : (appearanceMode == "dark" ? NSAppearance(named: .darkAqua) : nil)
        NSApplication.shared.appearance = appearance
        NSApplication.shared.windows.forEach { $0.appearance = appearance; $0.contentView?.needsDisplay = true }
    }

    private func updateArtworkAccent() {
        artworkAccent = playerAccentColor
    }

    private var playerAccentColor: Color {
        guard let color = model.artworkImage?.splitDeckContrastAccent else { return .accentColor }
        return Color(nsColor: color)
    }

    private var layoutOrder: [String] {
        var valid = layoutOrderString.split(separator: ",").map(String.init).filter { ["info", "notifications", "utilities", "player"].contains($0) }
        if !valid.contains("info") { valid.insert("info", at: 0) }
        return Set(valid) == Set(["info", "notifications", "utilities", "player"]) ? valid : ["info", "notifications", "utilities", "player"]
    }

    private var positionedLayoutOrder: [String] {
        ["header", "body", "footer"].flatMap { zone in
            layoutOrder.filter { placement(for: $0) == zone }
        }
    }

    private func placement(for section: String) -> String {
        switch section {
        case "info": return infoPlacement
        case "notifications": return notificationsPlacement
        case "utilities": return utilitiesPlacement
        default: return playerPlacement
        }
    }

    @ViewBuilder
    private func contentSection(_ section: String, artworkSize: CGFloat, compactPlayer: Bool) -> some View {
        switch section {
        case "info":
            if infoBarEnabled { InfoBar().frame(height: infoSize == "small" ? 68 : (infoSize == "large" ? 112 : 84)) }
        case "notifications":
            if showsUnreadSection {
                unreadShelf(iconSize: max(48, min(112, effectiveUnreadHeight - 70)))
                    .frame(height: effectiveUnreadHeight)
                resizeDivider
            }
        case "utilities":
            if showsUtilityDeck {
                UtilityDeck(player: model, badges: badges).frame(height: effectiveUtilityHeight).clipped()
            }
        default:
            if mediaPlayerEnabled {
                if compactPlayer {
                    compactMediaPlayer(artworkSize: artworkSize)
                } else {
                    Spacer(minLength: 16)
                    if albumArtworkEnabled {
                        artwork.frame(width: artworkSize, height: artworkSize)
                    } else {
                        Spacer(minLength: 24)
                    }
                    metadata.padding(.horizontal, 28).padding(.top, 24)
                    progress.padding(.horizontal, 28).padding(.top, 20)
                    controls.padding(.horizontal, 34).padding(.vertical, 28)
                    Spacer(minLength: 12)
                }
            }
        }
    }

    private func compactMediaPlayer(artworkSize: CGFloat) -> some View {
        HStack(spacing: 16) {
            if albumArtworkEnabled {
                artwork.frame(width: artworkSize, height: artworkSize)
            }
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.item.title).font(.headline.bold()).lineLimit(1)
                    Text([model.item.artist, model.item.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                progress
                controls
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func unreadShelf(iconSize: CGFloat) -> some View {
        let badgeSize = max(17, min(34, iconSize * 0.36))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Unread Notifications").font(.caption.bold()).textCase(.uppercase).tracking(1.1)
                Spacer()
                if !badges.hasAccessibilityPermission {
                    Button("Allow Access") { badges.requestPermissionIfNeeded() }
                        .buttonStyle(.plain).font(.caption.bold())
                }
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 28)

            if badges.hasAccessibilityPermission && !visibleBadgedApps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(visibleBadgedApps) { app in
                            Button { badges.open(app) } label: {
                                ZStack(alignment: .topTrailing) {
                                    StableAppIconView(app: app)
                                        .frame(width: iconSize, height: iconSize)
                                    if notificationBadgeVisible { Text(app.badge)
                                        .font(.system(size: badgeSize * 0.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, badgeSize * 0.22)
                                        .frame(minWidth: badgeSize, minHeight: badgeSize)
                                        .background(.red, in: Capsule())
                                        .offset(x: badgeSize * 0.15, y: -badgeSize * 0.15) }
                                }
                                .frame(width: iconSize + badgeSize * 0.55, height: iconSize + badgeSize * 0.55)
                            }
                            .buttonStyle(.plain).help("\(app.name): \(app.badge) unread")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
                }
            } else {
                Text(badges.hasAccessibilityPermission ? "No unread app badges" : "Accessibility access is required")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 28).frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.top, 16)
    }

    private var resizeDivider: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.36)).frame(width: 38, height: 4)
        }
        .frame(height: 10).contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dividerDragStartHeight == nil {
                        dividerDragStartHeight = unreadHeight
                    }
                    unreadHeight = min(250, max(132, (dividerDragStartHeight ?? unreadHeight) + value.translation.height))
                }
                .onEnded { value in
                    unreadHeight = min(250, max(132, (dividerDragStartHeight ?? unreadHeight) + value.translation.height))
                    dividerDragStartHeight = nil
                }
        )
        .transaction { transaction in transaction.animation = nil }
    }


    @ViewBuilder private var background: some View {
        if backgroundStyle == "album" {
            // Each artwork gets its own identity, so on a change the old layer fades out
            // while the new one fades in over the solid base colour.
            ZStack {
                (effectiveLightAppearance ? Color(white: 0.94) : Color(white: 0.055))
                if let image = model.artworkImage {
                    artworkBackgroundLayer(image)
                        .id(model.artworkRevision)
                        .transition(.opacity)
                }
            }
            .animation(Self.artworkCrossfade, value: model.artworkRevision)
            .ignoresSafeArea()
        } else if backgroundStyle == "glass" {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(.white.opacity(0.035))
                .ignoresSafeArea()
        } else {
            (effectiveLightAppearance ? Color(white: 0.94) : Color(white: 0.055)).ignoresSafeArea()
        }
    }

    private func artworkBackgroundLayer(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().scaledToFill().blur(radius: 55)
            .saturation(effectiveLightAppearance ? 0.78 : 1)
            .brightness(effectiveLightAppearance ? 0.06 : 0)
            .overlay(effectiveLightAppearance ? Color.white.opacity(0.42) : Color.black.opacity(0.48))
    }

    private var effectiveLightAppearance: Bool {
        appearanceMode == "light" || (appearanceMode == "system" && colorScheme == .light)
    }

    private var artwork: some View {
        ZStack { artworkContent.id(model.artworkRevision).transition(.opacity) }
            .animation(Self.artworkCrossfade, value: model.artworkRevision)
    }

    @ViewBuilder private var artworkContent: some View {
        if let image = model.artworkImage {
            ArtworkFill(image: image)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        } else if let icon = sourceAppIcon {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .padding(36)
                }
                .shadow(color: .black.opacity(0.28), radius: 20, y: 10)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
                .aspectRatio(1, contentMode: .fit)
                .overlay(Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.white.opacity(0.6)))
        }
    }

    private var sourceAppIcon: NSImage? {
        guard !model.item.sourceBundle.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: model.item.sourceBundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.item.title).font(.title2.bold()).lineLimit(1)
            Text([model.item.artist, model.item.album].filter { !$0.isEmpty }.joined(separator: " — "))
                .font(.title3).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { model.isScrubbing ? model.scrubValue : model.displayElapsed },
                    set: { model.updateScrubValue($0) }
                ),
                in: 0...max(model.item.duration, 1),
                onEditingChanged: { editing in
                    if editing { model.beginScrubbing() } else { model.endScrubbing() }
                }
            )
            .tint(.white)
            HStack {
                Text(time(model.isScrubbing ? model.scrubValue : model.displayElapsed))
                Spacer()
                Text(model.item.duration > 0 ? "−\(time(max(0, model.item.duration - (model.isScrubbing ? model.scrubValue : model.displayElapsed))))" : "–:––")
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.66))
        }
    }

    private var controls: some View {
        HStack {
            Button { model.send(.previous) } label: { Image(systemName: "backward.fill") }
            Spacer()
            Button { model.send(.playPause) } label: {
                Image(systemName: model.item.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.system(size: 40))
            Spacer()
            Button { model.send(.next) } label: { Image(systemName: "forward.fill") }
        }
        .font(.system(size: 29)).buttonStyle(.plain).foregroundStyle(.white)
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct StableAppIconView: NSViewRepresentable {
    let app: BadgedApp

    final class Coordinator {
        var representedID: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = false
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard context.coordinator.representedID != app.id else { return }
        update(view, coordinator: context.coordinator)
    }

    private func update(_ view: NSImageView, coordinator: Coordinator) {
        view.image = AppIconCache.shared.image(for: app)
        coordinator.representedID = app.id
    }
}

@MainActor
private final class AppIconCache {
    static let shared = AppIconCache()
    private var images: [String: NSImage] = [:]

    func image(for app: BadgedApp) -> NSImage {
        if let cached = images[app.id] { return cached }
        let resolved = app.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!
        images[app.id] = resolved
        return resolved
    }
}
