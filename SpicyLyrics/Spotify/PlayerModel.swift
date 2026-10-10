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

    // Clock anchor: position `anchorPosition` was correct at `anchorTime`.
    @ObservationIgnored private var anchorPosition: Double = 0
    @ObservationIgnored private var anchorTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var holdUntil: CFTimeInterval = 0
    @ObservationIgnored private var backoffUntil: CFTimeInterval = 0

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
        isPlaying ? anchorPosition + (now - anchorTime) : anchorPosition
    }

    private func apply(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot else {
            // No active device. Keep the last track on screen, just stop the clock.
            if isPlaying {
                anchorPosition = rawPosition(at: CACurrentMediaTime())
                isPlaying = false
            }
            statusMessage = "Сейчас ничего не играет в Spotify"
            return
        }
        statusMessage = nil

        let now = CACurrentMediaTime()
        let trackChanged = content != snapshot.content
        // Right after a control action, polls may still describe the old state.
        if now < holdUntil && !trackChanged { return }

        let measured = snapshot.progress + (snapshot.isPlaying ? now - snapshot.measuredAt : 0)
        let stateChanged = isPlaying != snapshot.isPlaying
        let predicted = rawPosition(at: now)
        let drift = measured - predicted
        if trackChanged || stateChanged || abs(drift) > 0.35 {
            anchorPosition = measured
        } else {
            // Small drift: nudge instead of jumping, so words don't stutter.
            anchorPosition = predicted + drift * 0.35
        }
        anchorTime = now

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
            apply(try await api.currentlyPlaying())
            return isPlaying ? 1.0 : 2.5
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
            let now = CACurrentMediaTime()
            self.anchorPosition = self.rawPosition(at: now)
            self.anchorTime = now
            self.isPlaying = !wasPlaying
        })
    }

    func next() { control({ [api] in try await api.next() }) }
    func previous() { control({ [api] in try await api.previous() }) }

    func seek(to seconds: Double) {
        control({ [api] in try await api.seek(to: seconds) }, optimistic: { [weak self] in
            self?.anchorPosition = seconds
            self?.anchorTime = CACurrentMediaTime()
        })
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
