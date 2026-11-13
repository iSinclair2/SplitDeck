import AppKit
import SwiftUI

@main
struct SplitDeckApp: App {
    @NSApplicationDelegateAdaptor(SplitDeckAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
        SplitDeckGlobalShortcut.install()
    }

    var body: some Scene {
        WindowGroup("SplitDeck") {
            PlayerView()
                .background(WindowConfigurator())
        }
        // Wide enough for a four-column grid to render cards at full design scale.
        .defaultSize(width: 940, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SplitDeckCommands()
        }

        Settings {
            SettingsView()
        }

        Window("SplitDeck Help", id: "help") {
            SplitDeckHelpView()
        }
        .defaultSize(width: 720, height: 650)
    }
}

final class SplitDeckAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched as a bare SwiftPM executable (e.g. Run from Xcode) there is no
        // app bundle, so macOS treats the process as background-only and it can never
        // become active or take key focus. Promote it to a regular app and bring it forward.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.insert(.managed)
        window.minSize = NSSize(width: 300, height: 620)
        window.acceptsMouseMovedEvents = true
        let titlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        window.contentView?.additionalSafeAreaInsets = NSEdgeInsets(
            top: -titlebarHeight,
            left: 0,
            bottom: 0,
            right: 0
        )
        coordinator.configure(window: window)
    }

    @MainActor
    final class Coordinator: NSResponder {
        weak var window: NSWindow?
        weak var trackingView: NSView?
        var trackingArea: NSTrackingArea?
        var autoHide = true
        var preferencesObserver: NSObjectProtocol?
        var alwaysOnTopObserver: NSObjectProtocol?

        func configure(window: NSWindow) {
            self.window = window
            installTrackingAreaIfNeeded()
            installPreferencesObserverIfNeeded()
            applyAutoHidePreference()
            applyAlwaysOnTopPreference()
        }

        private func installPreferencesObserverIfNeeded() {
            if preferencesObserver == nil {
                preferencesObserver = NotificationCenter.default.addObserver(
                    forName: .splitDeckAutoHideChanged,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.applyAutoHidePreference() }
                }
            }
            if alwaysOnTopObserver == nil {
                alwaysOnTopObserver = NotificationCenter.default.addObserver(
                    forName: .splitDeckAlwaysOnTopChanged,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.applyAlwaysOnTopPreference() }
                }
            }
        }

        private func applyAlwaysOnTopPreference() {
            guard let window else { return }
            let enabled = UserDefaults.standard.bool(forKey: "alwaysOnTop")
            window.level = enabled ? .floating : .normal
        }

        private func applyAutoHidePreference() {
            autoHide = UserDefaults.standard.object(forKey: "autoHideWindowControls") as? Bool ?? true
            guard let window else { return }
            let point = window.mouseLocationOutsideOfEventStream
            let nearTop = point.y >= window.frame.height - 52
            setControlsHidden(autoHide && !nearTop)
        }

        private func installTrackingAreaIfNeeded() {
            guard let frameView = window?.contentView?.superview else { return }
            guard trackingView !== frameView else { return }
            if let trackingArea, let trackingView { trackingView.removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            frameView.addTrackingArea(area)
            trackingView = frameView
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { update(for: event) }
        override func mouseMoved(with event: NSEvent) { update(for: event) }
        override func mouseExited(with event: NSEvent) { setControlsHidden(autoHide) }

        private func update(for event: NSEvent) {
            guard let window else { return }
            let nearTop = event.locationInWindow.y >= window.frame.height - 52
            setControlsHidden(autoHide && !nearTop)
        }

        private func setControlsHidden(_ hidden: Bool) {
            guard let window else { return }
            let fillsUsableHeight = window.screen.map {
                window.frame.height >= $0.visibleFrame.height - 120
            } ?? false
            let expanded = window.styleMask.contains(.fullScreen) || fillsUsableHeight || window.frame.height > 900
            // In Split View and full screen, macOS owns the visible title-bar area.
            // Keep its genuine controls available there instead of drawing copies
            // inside the player content.
            let shouldHide = expanded ? false : hidden
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = shouldHide
            }
        }
    }
}

