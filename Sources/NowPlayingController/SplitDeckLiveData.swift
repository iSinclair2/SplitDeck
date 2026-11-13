import SwiftUI

/// Live data shared by every view that renders widgets: the main deck and the
/// layout drawer. Sharing one set of models means drawer previews show
/// exactly what the deck shows, without starting a second set of polling loops.
@MainActor
final class SplitDeckLiveData {
    static let shared = SplitDeckLiveData()

    let player = PlayerModel()
    let badges = DockBadgeModel()
    let utility = UtilityDeckModel()
    let extras = ExtraWidgetsModel()
    let weather = WeatherModel()
    let more = MoreWidgetsModel()

    private init() { }
}

/// A single real widget rendered by `UtilityDeck`, for use outside the deck.
/// Sizes are the layout sizes: "small", "medium", "large" or "banner".
struct LiveWidgetPreview: View {
    let kind: String
    let size: String

    var body: some View {
        UtilityDeck(
            player: SplitDeckLiveData.shared.player,
            badges: SplitDeckLiveData.shared.badges,
            preview: WidgetPreviewSpec(kind: kind, size: size)
        )
        .allowsHitTesting(false)
        // The widget itself is inert, but the container still needs a hit-testable
        // surface so drag (move / add) and the editor's overlays receive the mouse.
        .overlay { Color.clear.contentShape(Rectangle()) }
    }

    /// Width / height of the widget's design canvas, for sizing containers.
    static func aspectRatio(for size: String) -> CGFloat {
        switch size {
        case "medium": return 432.0 / 210.0
        case "banner": return 880.0 / 140.0
        default: return 1
        }
    }
}

struct WidgetPreviewSpec: Equatable {
    let kind: String
    let size: String
}

/// Resolves the Interface setting to a concrete colour scheme. Passing `nil` to
/// `preferredColorScheme` after a forced light/dark scheme doesn't take effect until the
/// window is refocused, so "System" is resolved here and kept in sync with macOS.
@Observable
@MainActor
final class AppAppearance {
    static let shared = AppAppearance()

    private(set) var systemScheme: ColorScheme = AppAppearance.currentSystemScheme()

    private init() {
        Task {
            for await _ in DistributedNotificationCenter.default().notifications(named: Notification.Name("AppleInterfaceThemeChangedNotification")) {
                // The global default updates just after the notification is posted.
                try? await Task.sleep(for: .milliseconds(100))
                systemScheme = AppAppearance.currentSystemScheme()
            }
        }
    }

    func scheme(for mode: String) -> ColorScheme {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return systemScheme
        }
    }

    /// Reads the system-wide setting, independent of SplitDeck's own appearance override.
    private static func currentSystemScheme() -> ColorScheme {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }
}

/// Artwork that always covers its container edge to edge, whatever its shape (square
/// album art or a 16:9 video thumbnail), cropping the overflow from the centre.
/// `scaledToFill()` alone sizes the image larger than its container, which also enlarges
/// any stack it's in; drawing it as an overlay on a frame that takes exactly the offered
/// size keeps the layout fixed and the artwork filling it.
struct ArtworkFill: View {
    let image: NSImage

    var body: some View {
        Color.clear
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
            .clipped()
    }
}

/// Makes a view clickable by wrapping it in a plain button. The deck window moves when
/// its background is dragged, and AppKit can treat a click on a non-control view as the
/// start of a window drag, so `onTapGesture` isn't reliable there; a real button is.
private struct ClickAction: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        Button(action: action) { content.contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

extension View {
    func clickAction(perform action: @escaping () -> Void) -> some View {
        modifier(ClickAction(action: action))
    }
}
