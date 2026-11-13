import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class PlayerModel {
    var item = NowPlayingItem()
    var displayElapsed = 0.0
    var scrubValue = 0.0
    var isScrubbing = false
    private(set) var artworkImage: NSImage?
    /// Increments once each time `artworkImage` changes. Views key crossfades on this.
    private(set) var artworkRevision = 0
    private var polling = false
    /// Consecutive polls that found nothing playing. Players often report an empty
    /// item for a moment between tracks, so a single miss isn't treated as "stopped".
    private var missedPolls = 0
    private static let missedPollsBeforeReset = 3
    private var started = false
    private var artworkTask: Task<Void, Never>?
    /// Artwork found by `ArtworkResolver` for tracks whose player reports none.
    private var fetchedArtworkCache: [String: Data] = [:]
    /// The previous track's artwork bytes, used to spot stale artwork after a track change.
    private var previousTrackArtwork: Data?
    private var trackChangedAt = Date.distantPast
    private var fetchAttempted = false

    /// MediaRemote can report a new title before it updates the artwork, so for a short
    /// time after a track change the old track's artwork is treated as unknown.
    private static let artworkSettleInterval: TimeInterval = 2
    /// A query takes ~50 ms, so polling twice a second keeps track changes responsive.
    private static let pollInterval: Duration = .milliseconds(500)

    func start() {
        guard !started else { return }
        started = true
        Task {
            while !Task.isCancelled {
                if !isScrubbing { displayElapsed = item.estimatedElapsed }
                await refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh() async {
        guard !polling else { return }
        polling = true
        let result = await Task.detached(priority: .utility) { MediaRemoteBridge.query() }.value
        if var result {
            missedPolls = 0
            let isSameTrack = result.trackKey == item.trackKey
            if !isSameTrack {
                artworkTask?.cancel()
                artworkTask = nil
                previousTrackArtwork = item.artwork ?? previousTrackArtwork
                trackChangedAt = Date()
                fetchAttempted = false
            }
            let settling = Date().timeIntervalSince(trackChangedAt) < Self.artworkSettleInterval
            var reported = result.artwork
            // Still showing the previous track's artwork: wait (briefly) for the player to catch up
            // instead of displaying or fetching anything for it.
            let staleArtwork = settling && reported != nil && reported == previousTrackArtwork
            if staleArtwork { reported = nil }
            // Same track, but the player says its artwork changed (e.g. it finished loading).
            let artworkReplaced = isSameTrack && !result.artworkIdentifier.isEmpty
                && result.artworkIdentifier != item.artworkIdentifier
            if artworkReplaced, reported == nil { fetchAttempted = false }

            if let data = reported {
                // The player's own artwork is authoritative: follow it whenever it changes.
                if data != item.artwork || artworkImage == nil, let image = NSImage(data: data) {
                    artworkTask?.cancel()
                    artworkTask = nil
                    showArtwork(image)
                }
                result.artwork = data
            } else if isSameTrack, !artworkReplaced, let current = item.artwork {
                result.artwork = current
            } else if !artworkReplaced, let cached = fetchedArtworkCache[result.trackKey] {
                result.artwork = cached
                showArtwork(NSImage(data: cached))
            } else {
                // Nothing for the new track yet. Keep the outgoing artwork on screen so the
                // next image crossfades in, rather than flashing the placeholder; it is only
                // cleared if the fallback lookup finds nothing.
                result.artwork = nil
            }

            item = result
            if !isScrubbing { displayElapsed = result.estimatedElapsed }
            // Players such as Music report only an artwork identifier, never the image, so
            // look it up straight away rather than waiting out the settle interval.
            if reported == nil, result.artwork == nil, !staleArtwork, !fetchAttempted {
                fetchAttempted = true
                fetchArtwork(for: result)
            }
        } else {
            missedPolls += 1
            if missedPolls >= Self.missedPollsBeforeReset {
                item = NowPlayingItem()
                displayElapsed = 0
            }
        }
        polling = false
    }

    private func showArtwork(_ image: NSImage?) {
        guard image !== artworkImage else { return }
        artworkImage = image
        artworkRevision &+= 1
    }

    private func fetchArtwork(for track: NowPlayingItem) {
        artworkTask?.cancel()
        artworkTask = Task {
            let data = await ArtworkResolver.fetch(
                artist: track.artist,
                title: track.title,
                album: track.album,
                sourceBundle: track.sourceBundle
            )
            guard !Task.isCancelled, item.trackKey == track.trackKey else { return }
            artworkTask = nil
            // The player may have supplied artwork while the lookup was running.
            guard item.artwork == nil else { return }
            guard let data, let image = NSImage(data: data) else {
                // No artwork anywhere: stop showing the previous track's.
                showArtwork(nil)
                return
            }
            fetchedArtworkCache[track.trackKey] = data
            item.artwork = data
            showArtwork(image)
        }
    }

    func send(_ key: MediaKey) {
        // Reflect play/pause immediately; the next poll confirms the real state.
        if key == .playPause, item.trackKey != NowPlayingItem().trackKey { item.isPlaying.toggle() }
        let sourceBundle = item.sourceBundle
        Task {
            let handled = await Task.detached(priority: .userInitiated) { key.sendToPlayer(sourceBundle) }.value
            if !handled { key.send() }
            try? await Task.sleep(for: .milliseconds(350))
            await refresh()
        }
    }

    func beginScrubbing() {
        isScrubbing = true
        scrubValue = displayElapsed
    }

    func updateScrubValue(_ value: Double) {
        if !isScrubbing { beginScrubbing() }
        scrubValue = value
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        let destination = scrubValue
        let sourceBundle = item.sourceBundle
        displayElapsed = destination
        isScrubbing = false
        Task {
            await Task.detached(priority: .userInitiated) {
                MediaRemoteBridge.seek(to: destination, sourceBundle: sourceBundle)
            }.value
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
        }
    }
}
