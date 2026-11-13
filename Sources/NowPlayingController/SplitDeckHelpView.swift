import SwiftUI

struct SplitDeckHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SplitDeck Help").font(.largeTitle.bold())
                    Text("Keep useful controls and information visible alongside your full-screen apps.")
                        .font(.title3).foregroundStyle(.secondary)
                }

                helpSection("Getting started", "Choose Edit Layout (⇧⌘L, or the layout button beside Settings at the bottom of the window). A drawer slides out beside the deck with every widget, grouped by type, with a live preview at each size.")
                helpSection("Arranging widgets", "Drag a preview onto the deck, or click it to add the widget in the first free space. While editing, drag widgets on the deck to move them, use the corner handle to resize, and × to remove. Add the same widget as many times as you like.")
                helpSection("Header and footer", "Pick a full-width banner for the header and footer from the dropdowns at the top of the drawer, and choose Slim, Standard or Tall heights. You can also drag a widget onto either banner area.")
                helpSection("Widget settings", "Widgets with their own options show a ⚙︎ button while editing. Weather widgets can each follow a different place, World Clocks keep their own list of cities, and Notifications can hide unread counts.")
                helpSection("Permissions", "SplitDeck asks for access only when a widget needs it. Calendar, Reminders, Recent Files, Photos, Bluetooth and notification badges each show a button inside the widget; click it and follow the macOS prompt. Settings → Permissions shows and requests Calendar, Reminders, Accessibility and Automation access.")
                helpSection("Appearance", "Use Appearance settings to follow the system theme or choose Light or Dark. Album Colours can colour the background and widget accent from the current artwork. Widget backgrounds can be turned off for a borderless layout.")
                helpSection("Presets", "The Presets section of the drawer applies the built-in Work, Minimal, Dashboard, Home and News & Markets layouts at your current column count, and saves, updates, renames or deletes your own presets. Saved presets are also in the SplitDeck Controls menu.")
                helpSection("Meeting Mode", "Meeting Mode temporarily hides notifications, clipboard content, Quick Shelf and Scratchpad. Turn it off from the bottom of the SplitDeck window or from the SplitDeck Controls menu.")
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(36)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.bold())
            Text(text).font(.body).foregroundStyle(.secondary).lineSpacing(4)
        }
    }
}
