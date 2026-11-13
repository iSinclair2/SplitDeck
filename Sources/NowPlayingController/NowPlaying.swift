import AppKit
import CoreServices
import Foundation

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
        Player(name: "Spotify", bundleIdentifier: "com.spotify.client")
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
