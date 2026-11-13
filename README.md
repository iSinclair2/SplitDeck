# SplitDeck

SplitDeck is an open-source native macOS companion window designed to stay useful beside full-screen and Split View apps. It combines system media controls with a configurable grid of widgets—without requiring an account, sign-in or API key.

## Features

- Controls the Mac's active Now Playing source, with artwork and smooth track transitions.
- A resizable grid of 1×1, 2×1 and 2×2 widgets, plus full-width Header and Footer banners.
- Edit the layout directly on the deck: a slide-out drawer (⇧⌘L) shows every widget with a live preview at each size. Drag to add, move and resize; the same widget can be added more than once.
- Per-widget settings, such as a different location for each weather widget, or its own list of world-clock cities.
- Built-in Work, Minimal, Dashboard, Home and News & Markets presets that adapt to 2–5 columns, plus your own saved presets.
- Light, dark, solid, liquid-glass and artwork-derived appearances, and Meeting Mode.
- No analytics and no user account.

### Widgets

| Group | Widgets |
|---|---|
| Time & Calendar | Time & Weather, Calendar, Next Meeting (with a Join button for video calls), Month, World Clocks, Countdown, Public Holidays |
| Productivity | Focus timer, Reminders, Habits, Scratchpad, Clipboard history, Shortcuts, Unit & time-zone converter |
| Files & Apps | Quick Shelf, Recent Files, Launcher, Disks |
| Media & Photos | Media, Audio, Photo Frame |
| Weather & Outdoors | Forecast (hourly and 7-day), Air Quality & UV, Sun & Moon |
| System & Network | System/battery, Performance, Network, Internet Speed, Public IP, Bluetooth Devices, Quick Toggles, Notification badges |
| News & Markets | News (any RSS/Atom feed), Hacker News, On This Day, Currency, Crypto |

## Requirements

- macOS 14 or later.
- Xcode with the matching macOS SDK for development.
- Releases are universal (Apple silicon and Intel). Apple silicon is the most tested.

## Install

1. Download `SplitDeck-<version>-macOS.zip` from the Releases page and double-click it to unzip.
2. Move **SplitDeck.app** to your Applications folder.
3. Open it. Xcode is not needed; the download is a ready-to-run app for Apple silicon and Intel Macs on macOS 14 or later.

The app is open source and ad-hoc signed, but not notarised by Apple, so the first launch is blocked with a warning. To allow it:

- **macOS 15 Sequoia and later:** try to open the app once, then go to **System Settings → Privacy & Security**, scroll to the message about SplitDeck and click **Open Anyway**. Confirm with your password.
- **macOS 14 Sonoma:** right-click (or Control-click) the app, choose **Open**, then click **Open** in the dialog.

You only need to do this once.

## Build

Open `Package.swift` in Xcode and run the `NowPlayingController` executable target, or use:

```sh
chmod +x scripts/build-app.sh scripts/package-release.sh
./scripts/build-app.sh
open SplitDeck.app
```

Running the bundled `SplitDeck.app` (rather than the raw executable from Xcode) gives the app its bundle identifier, so permissions and settings behave as they will for users.

Create release archives with:

```sh
./scripts/package-release.sh 0.1.0
```

The archives are written to `dist/`.

## Permissions

SplitDeck asks for each permission only when a widget needs it, usually from a button inside that widget. **Settings → Permissions** shows and requests Calendar, Reminders, Accessibility and Automation access.

| Permission | Used for |
|---|---|
| Calendars | Calendar, Month and Next Meeting widgets |
| Reminders | Reminders widget (read, complete and add) |
| Accessibility | Unread badge counts from Dock icons, never notification content; also the media-key fallback for players other than Music and Spotify |
| Automation | Music and Spotify, for exact artwork and playback controls; System Events, for the Dark Mode quick toggle |
| Files & Folders | Recent Files reads your Documents and Downloads folders, only after you click Allow |
| Photos | Photo Frame, when set to show your Photos favourites |
| Bluetooth | Battery levels in Bluetooth Devices |
| Location | Weather, only when a location is set to Precise |

Clipboard history, dragged files, scratchpad notes, habits, countdowns, media metadata and all settings stay on your Mac. Clipboard history skips anything password managers mark as concealed.

## Network services

Online widgets use free public services that need no account or key. Apart from the default weather, which refreshes while SplitDeck is running, each service is contacted only while its widget is in your layout or visible in the layout drawer:

| Service | Used by |
|---|---|
| [wttr.in](https://wttr.in) | Current weather (every 15 minutes), and an approximate location from your IP address when no place is chosen |
| [Open-Meteo](https://open-meteo.com) | Hourly and 7-day forecast, sunrise and sunset, air quality, UV, pollen, and place search |
| iTunes Search API | Fallback artwork when the player provides none |
| [Frankfurter](https://frankfurter.dev) | Currency rates (European Central Bank) |
| [CoinGecko](https://www.coingecko.com) | Crypto prices |
| [Hacker News API](https://github.com/HackerNews/API) | Hacker News |
| Wikipedia REST API | On This Day |
| [Nager.Date](https://date.nager.at) | Public holidays |
| [ipinfo.io](https://ipinfo.io) | Public IP |
| Feeds you add | News (BBC News by default) |

Internet Speed uses Apple's built-in `networkQuality` tool.

## Distribution notes

The release script produces an ad-hoc signed app. Distributing without the Gatekeeper warning requires an Apple Developer ID certificate and notarisation. Because each ad-hoc build has a new signature, macOS asks for permissions again after updating to a new build.

SplitDeck reads Now Playing information through Apple's private MediaRemote framework. This makes the app unsuitable for the Mac App Store and means a future macOS update could require changes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and focused pull requests are welcome.

## Licence

SplitDeck is available under the [MIT License](LICENSE).
