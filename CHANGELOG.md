# Changelog

## 0.1.1 — 2026-11-13

### Media
- Artwork always fills its container edge to edge, for both square album art and 16:9 video thumbnails. It could previously sit off-centre in the 1×1 and 2×2 cards.
- Artwork for media playing in a browser: SplitDeck asks Safari, Chrome, Edge, Brave, Arc or Vivaldi which tab is playing, and shows the YouTube thumbnail or the page's own preview image for other sites (Vimeo, Twitch, SoundCloud and more). Browsers are listed in Settings → Permissions.

### Fixes
- Opening the layout drawer in full-screen Split View no longer crashes the app. The drawer now overlays the deck instead of widening the window's minimum size.
- The World Clocks style toggle is always visible and switches the clocks immediately (it previously waited for the next 30-second refresh).
- Click-to-open actions on widgets (Calendar, Activity Monitor, Battery, Disks, Bluetooth, Photo Frame, media artwork) and click-to-add in the layout drawer are now real buttons, so clicks can't be mistaken for dragging the window.

## 0.1.0 — 2026-11-13

Initial open-source release.

### Layout
- Resizable grid of 1×1, 2×1 and 2×2 widgets with full-width Header and Footer banners.
- Edit the layout directly on the deck from a slide-out drawer (⇧⌘L), with widgets grouped by type, live previews at every size, and banner pickers for the header and footer.
- Drag to add, move and resize; add the same widget more than once.
- Per-widget settings: weather location, World Clock cities and style, and notification counts.
- Built-in Work, Minimal, Dashboard, Home and News & Markets presets that adapt to 2–5 columns; save, update, rename and delete your own presets.

### Widgets
- Media with artwork, smooth crossfades between tracks, and playback controls for Music and Spotify that work without Accessibility access.
- Time & Weather, Forecast (hourly and 7-day), Air Quality & UV, and Sun & Moon, with place search or precise location.
- Calendar, Next Meeting with Join links, Month, World Clocks, Countdown and Public Holidays.
- Focus timer, Reminders, Habits, Scratchpad, Clipboard history, Shortcuts and a unit and time-zone converter.
- Quick Shelf, Recent Files, Launcher and Disks.
- System, Performance, Network, Internet Speed, Public IP, Bluetooth Devices, Quick Toggles and notification badges.
- Photo Frame, News (RSS/Atom), Hacker News, On This Day, Currency and Crypto.

### Distribution
- Universal app for Apple silicon and Intel Macs running macOS 14 or later.

### Appearance and privacy
- Light, dark, solid, liquid-glass and artwork-derived appearances; Meeting Mode.
- Permissions are requested only when a widget needs them. No analytics, accounts or API keys.
