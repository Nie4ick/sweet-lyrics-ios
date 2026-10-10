import Foundation
import Observation
import QuartzCore
import UIKit

/// Follows what Spotify is playing and keeps a smooth local clock between polls.
@MainActor
@Observable
final class PlayerModel {
    enum LyricsState: Equatable {
        case idle
        case loading
        case loaded(PreparedLyrics)
        case notFound
        case unavailable(String)
        case failed(String)
    }

    private(set) var content: PlaybackSnapshot.Content?
    private(set) var isPlaying = false
    private(set) var artwork: UIImage?
    /// Small copy of the artwork for the animated background.
    private(set) var backgroundArtwork: UIImage?
    private(set) var artworkID = ""
    /// Bumped whenever new lyrics are shown, so the lyrics view starts fresh.
    private(set) var lyricsRevision = 0
    private(set) var lyricsState: LyricsState = .idle
    private(set) var statusMessage: String?
    /// Album / playlist Spotify is playing from, used to keep context when picking a track.
    private(set) var contextURI: String?
    private(set) var deviceName: String?
    var transientError: String?

    var track: TrackInfo? {
        if case .track(let track) = content { return track }
        return nil
    }

    @ObservationIgnored private let api: SpotifyAPI
    @ObservationIgnored private let lyrics: LyricsService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var rawLyrics: LyricsDocument?
    @ObservationIgnored private var preparedRomanized = false
    @ObservationIgnored private var lastArtworkURL: URL?

    // Clock anchor: position `anchorPosition` was correct at `anchorTime`. `slew` is a small
    // correction blended in over `slewDuration`, so the clock never visibly jumps or runs backwards.
    @ObservationIgnored private var anchorPosition: Double = 0
    @ObservationIgnored private var anchorTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var slew: Double = 0
    @ObservationIgnored private var slewSpan: Double = 0.8
    /// Recent differences between Spotify's reported position and our clock, newest last.
    @ObservationIgnored private var recentDrift: [Double] = []
    /// First poll of a run in which Spotify claimed to play but the position did not move.
    @ObservationIgnored private var stall: (progress: Double, at: CFTimeInterval)?
    @ObservationIgnored private var holdUntil: CFTimeInterval = 0
    @ObservationIgnored private var backoffUntil: CFTimeInterval = 0

    private static let slewDuration: Double = 0.8
    /// Larger differences are treated as a seek and applied at once.
    private static let resyncThreshold: Double = 1.0
    /// Corrections smaller than this are noise in Spotify's reported position.
    private static let driftDeadband: Double = 0.04
    /// Spotify sometimes keeps reporting `is_playing` after a pause; a position frozen this long
    /// means it is paused.
    private static let stallTimeout: Double = 1.8

    init(api: SpotifyAPI, lyrics: LyricsService, settings: AppSettings) {
        self.api = api
        self.lyrics = lyrics
        self.settings = settings
    }

    // MARK: Clock

    /// Lyrics clock in seconds at media time `now`: playback position plus the user's offset.
    func position(at now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        playbackPosition(at: now) + settings.timingOffsetMs / 1000
    }

    /// Spotify's playback position in seconds at media time `now`.
    func playbackPosition(at now: CFTimeInterval = CACurrentMediaTime()) -> Double {
        let duration = track?.duration ?? .infinity
        return min(max(0, rawPosition(at: now)), duration)
    }

    private func rawPosition(at now: CFTimeInterval) -> Double {
        guard isPlaying else { return anchorPosition }
        let elapsed = max(0, now - anchorTime)
        return anchorPosition + elapsed + slew * min(1, elapsed / slewSpan)
    }

    /// Re-anchors the clock at `position` right now, dropping any pending correction.
    private func setClock(_ position: Double, at now: CFTimeInterval = CACurrentMediaTime()) {
        anchorPosition = position
        anchorTime = now
        slew = 0
        recentDrift.removeAll()
    }

    /// Spotify can report `is_playing` for a while after playback was paused (from the Spotify
    /// app, headphones or the lock screen). If the position stops moving, believe the position.
    private func detectStall(_ snapshot: PlaybackSnapshot, trackChanged: Bool) -> Bool {
        guard snapshot.isPlaying, !trackChanged else {
            stall = nil
            return false
        }
        if let stall, abs(snapshot.progress - stall.progress) < 0.25 {
            return snapshot.measuredAt - stall.at >= Self.stallTimeout
        }
        stall = (snapshot.progress, snapshot.measuredAt)
        return false
    }

    private func apply(_ snapshot: PlaybackSnapshot?) {
        guard var snapshot else {
            // No active device. Keep the last track on screen, just stop the clock.
            if isPlaying {
                setClock(rawPosition(at: CACurrentMediaTime()))
                isPlaying = false
            }
            stall = nil
            statusMessage = "Сейчас ничего не играет в Spotify"
            return
        }
        statusMessage = nil
        contextURI = snapshot.contextURI
        deviceName = snapshot.deviceName

        let now = CACurrentMediaTime()
        let trackChanged = content != snapshot.content
        if detectStall(snapshot, trackChanged: trackChanged) {
            snapshot.isPlaying = false
        }
        // Right after a control action, polls may still describe the old state.
        if now < holdUntil && !trackChanged { return }

        let measured = snapshot.progress + (snapshot.isPlaying ? now - snapshot.measuredAt : 0)
        let stateChanged = isPlaying != snapshot.isPlaying
        let predicted = rawPosition(at: now)
        // Part of the previous correction not blended in yet: the clock is already heading there.
        let unapplied = isPlaying ? slew * (1 - min(1, max(0, now - anchorTime) / slewSpan)) : 0
        let drift = measured - (predicted + unapplied)
        if trackChanged || stateChanged || !snapshot.isPlaying || abs(drift) > Self.resyncThreshold {
            setClock(measured, at: now)
        } else {
            // Small drift: Spotify's position is noisy, so follow the median of the last few polls
            // and blend the correction in instead of jumping (a jump back re-lights sung words).
            recentDrift.append(drift)
            if recentDrift.count > 3 { recentDrift.removeFirst() }
            let median = recentDrift.sorted()[recentDrift.count / 2]
            let correction = abs(median) > Self.driftDeadband ? median : 0
            anchorPosition = predicted
            anchorTime = now
            slew = unapplied + correction
            // At most ±50 % speed while correcting, so the clock never stalls or runs backwards.
            slewSpan = max(Self.slewDuration, abs(slew) * 2)
            if correction != 0 {
                recentDrift = recentDrift.map { $0 - correction }
            }
        }

        if stateChanged { isPlaying = snapshot.isPlaying }
        if trackChanged {
            content = snapshot.content
            onContentChanged()
        }
    }

    // MARK: Polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.pollOnce()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Returns how long to wait before the next poll.
    private func pollOnce() async -> Double {
        let now = CACurrentMediaTime()
        if now < backoffUntil { return backoffUntil - now }
        do {
            apply(try await api.playbackState())
            return isPlaying ? 1.0 : 1.5
        } catch SpotifyAPIError.rateLimited(let retryAfter) {
            backoffUntil = now + retryAfter
            return retryAfter
        } catch SpotifyAuthError.notLoggedIn {
            statusMessage = SpotifyAuthError.notLoggedIn.errorDescription
            return 5
        } catch is CancellationError {
            return 1
        } catch {
            statusMessage = error.localizedDescription
            return 4
        }
    }

    func refreshNow() {
        Task { _ = await pollOnce() }
    }

    // MARK: Controls

    func togglePlay() {
        let wasPlaying = isPlaying
        control({ [api] in
            if wasPlaying { try await api.pause() } else { try await api.play() }
        }, optimistic: { [weak self] in
            guard let self else { return }
            self.setClock(self.rawPosition(at: CACurrentMediaTime()))
            self.stall = nil
            self.isPlaying = !wasPlaying
        })
    }

    func next() { control({ [api] in try await api.next() }) }
    func previous() { control({ [api] in try await api.previous() }) }

    func seek(to seconds: Double) {
        control({ [api] in try await api.seek(to: seconds) }, optimistic: { [weak self] in
            self?.setClock(seconds)
        })
    }

    /// Jumps to an upcoming track by skipping everything queued before it.
    func skipAhead(_ count: Int) {
        guard count > 0 else { return }
        control({ [api] in
            for index in 0..<count {
                if index > 0 { try await Task.sleep(for: .milliseconds(150)) }
                try await api.next()
            }
        })
    }

    /// Plays `track`, continuing with the album or playlist it came from when there is one.
    func play(_ track: TrackSummary, context: String?) {
        let contexts = [context, track.albumURI].compactMap { $0 }.filter(Self.supportsOffset)
        control({ [api] in
            for contextURI in contexts {
                do {
                    try await api.play(trackURI: track.uri, inContext: contextURI)
                    return
                } catch SpotifyAPIError.http(let status, _) where status == 400 || status == 404 {
                    continue // The track isn't part of that context (or it is gone); try the next.
                }
            }
            try await api.play(uris: [track.uri])
        })
    }

    func addToQueue(_ track: TrackSummary) {
        Task {
            do {
                try await api.addToQueue(track.uri)
            } catch {
                transientError = error.localizedDescription
            }
        }
    }

    func upcomingTracks() async throws -> [TrackSummary] { try await api.queue() }
    func recentTracks() async throws -> [TrackSummary] { try await api.recentlyPlayed() }
    func searchTracks(_ query: String, offset: Int) async throws -> [TrackSummary] {
        try await api.search(query, offset: offset)
    }

    /// Only albums and playlists accept a starting track (`offset`).
    private static func supportsOffset(_ uri: String) -> Bool {
        uri.hasPrefix("spotify:album:") || uri.hasPrefix("spotify:playlist:")
    }

    private func control(_ action: @escaping () async throws -> Void, optimistic: (() -> Void)? = nil) {
        optimistic?()
        // Ignore stale polls for a moment so the optimistic state isn't undone.
        holdUntil = CACurrentMediaTime() + 1.5
        Task {
            do {
                try await action()
                try? await Task.sleep(for: .milliseconds(400))
            } catch {
                transientError = error.localizedDescription
            }
            holdUntil = 0
            _ = await pollOnce()
        }
    }

    // MARK: Lyrics & artwork

    private func onContentChanged() {
        lyricsTask?.cancel()
        lyricsTask = nil
        rawLyrics = nil
        switch content {
        case .track:
            loadLyrics(force: false)
        case .episode:
            lyricsState = .unavailable("Для подкастов тексты недоступны")
        case .ad:
            lyricsState = .unavailable("Реклама")
        case .unknown:
            lyricsState = .unavailable("Не удалось распознать трек")
        case .none:
            lyricsState = .idle
        }
        loadArtwork()
    }

    func loadLyrics(force: Bool) {
        guard let track else { return }
        lyricsTask?.cancel()
        lyricsState = .loading
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.lyrics.lyrics(for: track, ignoreCache: force)
            guard !Task.isCancelled, self.track?.id == track.id else { return }
            self.lyricsTask = nil
            switch result {
            case .found(let document):
                self.rawLyrics = document
                self.preparedRomanized = self.settings.showRomanization
                self.lyricsRevision += 1
                self.lyricsState = .loaded(PreparedLyrics(document: document, romanized: self.settings.showRomanization))
            case .notFound:
                self.lyricsState = .notFound
            case .failed(let reason):
                if reason != "cancelled" { self.lyricsState = .failed(reason) }
            }
        }
    }

    func clearLyricsCache() {
        lyrics.clearCache()
    }

    /// Re-prepares the current lyrics after a display setting changed.
    func settingsChanged() {
        guard let rawLyrics, preparedRomanized != settings.showRomanization else { return }
        preparedRomanized = settings.showRomanization
        lyricsRevision += 1
        lyricsState = .loaded(PreparedLyrics(document: rawLyrics, romanized: settings.showRomanization))
    }

    private func loadArtwork() {
        let url: URL?
        switch content {
        case .track(let track): url = track.artworkURL
        case .episode(_, _, let artworkURL): url = artworkURL
        default: url = nil
        }
        guard url != lastArtworkURL else { return }
        lastArtworkURL = url
        artworkTask?.cancel()
        guard let url else {
            artwork = nil
            backgroundArtwork = nil
            artworkID = ""
            return
        }
        artworkTask = Task { [weak self] in
            guard let response = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: response.0),
                  !Task.isCancelled,
                  let self
            else { return }
            self.artwork = image
            self.backgroundArtwork = image.downscaled(to: 160)
            self.artworkID = url.absoluteString
        }
    }
}
