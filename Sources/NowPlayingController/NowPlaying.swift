import AppKit
import CoreServices
import Foundation
import ImageIO

struct NowPlayingItem: Equatable, Sendable {
    var title = "Nothing Playing"
    var artist = "Start some media on your Mac"
    var album = ""
    var duration = 0.0
    var elapsed = 0.0
    var timestamp = 0.0
    var rate = 0.0
    var isPlaying = false
    var sourceBundle = ""
    /// Changes whenever the player's artwork changes, even when it doesn't send the image itself.
    var artworkIdentifier = ""
    var artwork: Data?

    var trackKey: String { "\(sourceBundle)|\(artist)|\(title)|\(album)" }

    var estimatedElapsed: Double {
        guard isPlaying, timestamp > 0 else { return elapsed }
        return min(duration, max(0, elapsed + (Date().timeIntervalSince1970 - timestamp) * max(rate, 1)))
    }
}

enum ArtworkResolver {
    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let artworkUrl100: URL?
        let artistName: String?
        let trackName: String?
        let collectionName: String?
    }

    static func fetch(artist: String, title: String, album: String, sourceBundle: String) async -> Data? {
        if sourceBundle == "com.apple.Music", let data = await appleMusicArtwork() {
            return data
        }
        if sourceBundle == "com.spotify.client", let data = await spotifyArtwork() {
            return data
        }
        // Browsers rarely pass artwork to Now Playing; use the playing tab's video thumbnail.
        if BrowserArtwork.isBrowser(sourceBundle),
           let data = await BrowserArtwork.fetch(title: title, sourceBundle: sourceBundle) {
            return data
        }
        guard !artist.isEmpty, !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = components?.url,
              let responseData = await download(url),
              let result = try? JSONDecoder().decode(SearchResponse.self, from: responseData) else { return nil }
        let wantedArtist = normalized(artist)
        let wantedTitle = normalized(title)
        let wantedAlbum = normalized(album)
        let ranked = result.results.compactMap { candidate -> (Int, URL)? in
            guard let url = candidate.artworkUrl100 else { return nil }
            let candidateArtist = normalized(candidate.artistName ?? "")
            let candidateTitle = normalized(candidate.trackName ?? "")
            let candidateAlbum = normalized(candidate.collectionName ?? "")
            // Both artist and title must match; the album decides between versions
            // (single, album, live, compilation) that otherwise look identical.
            let artistScore = candidateArtist == wantedArtist ? 6
                : (!candidateArtist.isEmpty && (candidateArtist.contains(wantedArtist) || wantedArtist.contains(candidateArtist)) ? 3 : 0)
            let titleScore = candidateTitle == wantedTitle ? 8
                : (!candidateTitle.isEmpty && (candidateTitle.contains(wantedTitle) || wantedTitle.contains(candidateTitle)) ? 3 : 0)
            guard artistScore > 0, titleScore > 0 else { return nil }
            var albumScore = 0
            if !wantedAlbum.isEmpty {
                if candidateAlbum == wantedAlbum { albumScore = 6 }
                else if candidateAlbum.contains(wantedAlbum) || wantedAlbum.contains(candidateAlbum) { albumScore = 3 }
            }
            return (artistScore + titleScore + albumScore, url)
        }
        guard let match = ranked.max(by: { $0.0 < $1.0 }), match.0 >= 9 else { return nil }
        let smallURL = match.1

        let largeURL = URL(string: smallURL.absoluteString.replacingOccurrences(of: "100x100bb", with: "600x600bb")) ?? smallURL
        return await download(largeURL)
    }

    /// Runs in a separate `osascript` process so the main thread (and any running
    /// artwork animation) is never blocked. The image is passed back through a temp file
    /// because `osascript` can only print text.
    private static func appleMusicArtwork() async -> Data? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("splitdeck-artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let source = """
        tell application "Music"
            if not (exists current track) then return ""
            if (count of artworks of current track) is 0 then return ""
            set artworkData to raw data of artwork 1 of current track
        end tell
        set handle to open for access (POSIX file "\(file.path)") with write permission
        set eof handle to 0
        write artworkData to handle
        close access handle
        return "ok"
        """
        guard await run(executable: "/usr/bin/osascript", arguments: ["-e", source]) != nil else { return nil }
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    private static func spotifyArtwork() async -> Data? {
        guard let output = await run(
            executable: "/usr/bin/osascript",
            arguments: ["-e", "tell application \"Spotify\" to get artwork url of current track"]
        ), let value = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: value) else { return nil }
        return await download(url)
    }

    private static func download(_ url: URL) async -> Data? {
        await run(
            executable: "/usr/bin/curl",
            arguments: ["--fail", "--silent", "--show-error", "--location", "--max-time", "10", url.absoluteString]
        )
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func run(executable: String, arguments: [String]) async -> Data? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 && !data.isEmpty ? data : nil
        }.value
    }

}

/// Artwork for media playing in a web browser. The browser is asked (over Apple Events)
/// for its open tabs; the tab whose title matches what's playing gives the page URL, and
/// the thumbnail comes from the site: YouTube's own thumbnail server, or the page's
/// `og:image` preview for other sites (Vimeo, Twitch, SoundCloud, Bandcamp, iPlayer…).
enum BrowserArtwork {
    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi"
    ]
    private static let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "twitch.tv", "soundcloud.com", "bandcamp.com",
                                     "dailymotion.com", "bbc.co.uk", "mixcloud.com", "nebula.tv", "music.apple.com"]

    static func isBrowser(_ bundleIdentifier: String) -> Bool {
        safari.contains(bundleIdentifier) || chromium.contains(bundleIdentifier)
    }

    static func fetch(title: String, sourceBundle: String) async -> Data? {
        guard let page = await playingTabURL(title: title, browser: sourceBundle) else { return nil }
        if let id = youTubeID(page) { return await youTubeThumbnail(id) }
        return await previewImage(of: page)
    }

    // MARK: Finding the tab

    private static func playingTabURL(title: String, browser: String) async -> URL? {
        // Safari calls a tab's title "name"; Chromium browsers call it "title".
        let titleProperty = safari.contains(browser) ? "name" : "title"
        let script = """
        set output to ""
        tell application id "\(browser)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set output to output & (URL of t) & tab & (\(titleProperty) of t) & linefeed
                    end try
                end repeat
            end repeat
        end tell
        return output
        """
        guard let data = await Shell.runAsync("/usr/bin/osascript", ["-e", script]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let tabs = text.split(separator: "\n").compactMap { line -> (url: URL, title: String)? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let url = URL(string: parts[0]), url.scheme?.hasPrefix("http") == true else { return nil }
            return (url, parts[1])
        }
        let wanted = normalised(title)
        func isMedia(_ url: URL) -> Bool { mediaHosts.contains { url.host()?.hasSuffix($0) == true } }
        // Best: a tab whose title contains what's playing. Otherwise, the only media-site tab.
        let scored = tabs.map { tab -> (URL, Int) in
            let tabTitle = normalised(tab.title)
            var score = 0
            if !wanted.isEmpty, tabTitle.contains(wanted) || (!tabTitle.isEmpty && wanted.contains(tabTitle)) { score += 3 }
            if isMedia(tab.url) { score += 1 }
            if youTubeID(tab.url) != nil { score += 1 }
            return (tab.url, score)
        }
        if let best = scored.filter({ $0.1 >= 3 }).max(by: { $0.1 < $1.1 }) { return best.0 }
        let mediaTabs = tabs.filter { isMedia($0.url) }
        return mediaTabs.count == 1 ? mediaTabs[0].url : nil
    }

    private static func normalised(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: YouTube

    /// Video ID from watch, youtu.be, Shorts, live, embed and YouTube Music links.
    static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = path.first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                id = v
            } else if path.count >= 2, ["shorts", "live", "embed", "v"].contains(path[0]) {
                id = path[1]
            }
        }
        guard let id, id.count == 11, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    private static func youTubeThumbnail(_ id: String) async -> Data? {
        // maxresdefault is 1280×720 with no bars, but isn't generated for every video.
        if let data = await Web.data(URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")!), isUsableImage(data) {
            return data
        }
        // hqdefault always exists but is 4:3 with black bars above and below a 16:9 frame.
        guard let data = await Web.data(URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")!) else { return nil }
        return cropToWidescreen(data) ?? data
    }

    // MARK: Other sites

    /// The page's `og:image` (or `twitter:image`) link-preview picture.
    private static func previewImage(of page: URL) async -> Data? {
        guard let html = await Web.data(page).flatMap({ String(data: $0.prefix(600_000), encoding: .utf8) ?? String(data: $0.prefix(600_000), encoding: .isoLatin1) }) else { return nil }
        let patterns = [
            #"<meta[^>]+(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image)["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let link = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            guard let imageURL = URL(string: link, relativeTo: page)?.absoluteURL,
                  let data = await Web.data(imageURL), isUsableImage(data) else { continue }
            return data
        }
        return nil
    }

    // MARK: Image helpers

    /// Rejects placeholders and tiny icons (YouTube serves a 120×90 grey image for some misses).
    private static func isUsableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return width >= 200 && height >= 150
    }

    /// Trims a 4:3 image to its centred 16:9 band (removing letterbox bars).
    private static func cropToWidescreen(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let bandHeight = (width * 9 / 16).rounded()
        guard bandHeight < height,
              let cropped = image.cropping(to: CGRect(x: 0, y: ((height - bandHeight) / 2).rounded(), width: width, height: bandHeight)) else { return nil }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

/// Automation (Apple Events) permission for the players SplitDeck asks for artwork.
/// Without it, artwork requests to Music or Spotify fail silently and SplitDeck has to
/// fall back to a less reliable online search.
enum MediaAutomationPermission {
    enum State: Sendable { case allowed, denied, notDetermined, notRunning }

    struct Player: Identifiable, Sendable {
        let name: String
        let bundleIdentifier: String
        var id: String { bundleIdentifier }
    }

    static let players = [
        Player(name: "Music", bundleIdentifier: "com.apple.Music"),
        Player(name: "Spotify", bundleIdentifier: "com.spotify.client"),
        Player(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        Player(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
        Player(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac"),
        Player(name: "Brave", bundleIdentifier: "com.brave.Browser"),
        Player(name: "Arc", bundleIdentifier: "company.thebrowser.Browser"),
        Player(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi")
    ]

    /// Players installed on this Mac.
    static var installedPlayers: [Player] {
        players.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
    }

    /// Checks (and with `askUser`, requests) permission. This blocks while the system
    /// prompt is shown, so call it off the main thread.
    nonisolated static func state(for bundleIdentifier: String, askUser: Bool) -> State {
        var target = AEAddressDesc()
        let created = bundleIdentifier.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
        guard created == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }
        switch Int(AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, askUser)) {
        case Int(noErr): return .allowed
        case errAEEventNotPermitted: return .denied
        case procNotFound: return .notRunning
        default: return .notDetermined
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum MediaRemoteBridge {
    private static let queryScript = #"""
    ObjC.import("Foundation");

    function run() {
      try {
        const framework = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/");
        framework.load;
        const request = $.NSClassFromString("MRNowPlayingRequest");
        if (!request) return JSON.stringify({ error: "MediaRemote unavailable" });

        const result = { isPlaying: request.localIsPlaying ? true : false };
        const item = request.localNowPlayingItem;
        if (item && item.nowPlayingInfo) {
          const info = item.nowPlayingInfo;
          const keys = info.keyEnumerator;
          let key;
          while ((key = keys.nextObject) && !key.isNil()) {
            const name = ObjC.unwrap(key);
            const value = info.objectForKey(key);
            if (!value || value.isNil()) continue;
            const shortName = name.replace("kMRMediaRemoteNowPlayingInfo", "");
            if (value.isKindOfClass($.NSDate)) result[shortName] = value.timeIntervalSince1970;
            else if (value.isKindOfClass($.NSNumber) || value.isKindOfClass($.NSString)) result[shortName] = ObjC.unwrap(value);
            else if (shortName === "ArtworkData" && value.isKindOfClass($.NSData)) result.artworkBase64 = ObjC.unwrap(value.base64EncodedStringWithOptions(0));
          }
        }
        const path = request.localNowPlayingPlayerPath;
        if (path && path.client) {
          const client = path.client;
          if (client.parentApplicationBundleIdentifier && !client.parentApplicationBundleIdentifier.isNil())
            result.sourceBundle = ObjC.unwrap(client.parentApplicationBundleIdentifier);
          else if (client.bundleIdentifier && !client.bundleIdentifier.isNil())
            result.sourceBundle = ObjC.unwrap(client.bundleIdentifier);
        }
        return JSON.stringify(result);
      } catch (error) {
        return JSON.stringify({ error: error.toString() });
      }
    }
    """#

    static func query() -> NowPlayingItem? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", queryScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil else { return nil }

        func string(_ key: String) -> String { json[key] as? String ?? "" }
        func number(_ key: String) -> Double { (json[key] as? NSNumber)?.doubleValue ?? 0 }
        let title = string("Title")
        guard !title.isEmpty else { return nil }

        let encodedArtwork = string("artworkBase64")
        let artwork = encodedArtwork.isEmpty ? nil : Data(base64Encoded: encodedArtwork)

        return NowPlayingItem(
            title: title,
            artist: string("Artist"),
            album: string("Album"),
            duration: number("Duration"),
            elapsed: number("ElapsedTime"),
            timestamp: number("Timestamp"),
            rate: number("PlaybackRate"),
            isPlaying: json["isPlaying"] as? Bool ?? false,
            sourceBundle: string("sourceBundle"),
            artworkIdentifier: string("ArtworkIdentifier"),
            artwork: artwork?.isEmpty == false ? artwork : nil
        )
    }

    static func seek(to seconds: Double, sourceBundle: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        switch sourceBundle {
        case "com.apple.Music":
            process.arguments = ["-e", "tell application \"Music\" to set player position to \(seconds)"]
        case "com.spotify.client":
            process.arguments = ["-e", "tell application \"Spotify\" to set player position to \(Int(seconds * 1000))"]
        default:
            let script = """
            ObjC.import("Foundation");
            function run() {
              const framework = $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/MediaRemote.framework/");
              framework.load;
              $.MRMediaRemoteSetElapsedTime(\(seconds));
            }
            """
            process.arguments = ["-l", "JavaScript", "-e", script]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

enum MediaKey {
    case playPause, previous, next

    private var code: Int32 {
        switch self {
        case .playPause: return 16
        case .next: return 17
        case .previous: return 18
        }
    }

    /// Simulated media key. Works with any player, but macOS drops it unless SplitDeck
    /// has Accessibility permission.
    func send() {
        post(state: 0xA)
        post(state: 0xB)
    }

    /// Sends the command straight to Music or Spotify over Apple Events, which only needs
    /// the Automation permission. Returns false for other players or if it was refused.
    nonisolated func sendToPlayer(_ bundleIdentifier: String) -> Bool {
        guard ["com.apple.Music", "com.spotify.client"].contains(bundleIdentifier) else { return false }
        let command: String
        switch self {
        case .playPause: command = "playpause"
        case .next: command = "next track"
        case .previous: command = "previous track"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleIdentifier)\" to \(command)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func post(state: Int32) {
        let data1 = (code << 16) | (state << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(data1),
            data2: -1
        )?.cgEvent else { return }
        event.post(tap: .cghidEventTap)
    }
}
