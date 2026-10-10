import Foundation
import QuartzCore

struct TrackInfo: Equatable, Hashable {
    var id: String
    var uri: String
    var title: String
    var artists: [String]
    var album: String
    var duration: Double
    var artworkURL: URL?
    var isLocal: Bool

    var artistLine: String { artists.joined(separator: ", ") }
}

struct PlaybackSnapshot {
    enum Content: Equatable {
        case track(TrackInfo)
        case episode(title: String, show: String, artworkURL: URL?)
        case ad
        case unknown
    }

    var content: Content
    var isPlaying: Bool
    var progress: Double
    /// When the progress value was valid, in `CACurrentMediaTime()` seconds (latency compensated).
    var measuredAt: CFTimeInterval
}

enum SpotifyAPIError: LocalizedError {
    case premiumRequired
    case noActiveDevice
    case rateLimited(retryAfter: Double)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .premiumRequired: return "Управление воспроизведением через Web API доступно только с Spotify Premium."
        case .noActiveDevice: return "Нет активного устройства Spotify. Включите музыку в приложении Spotify."
        case .rateLimited: return "Spotify временно ограничил запросы, повторим позже."
        case .http(let code, let message): return "Spotify API: HTTP \(code) \(message)"
        }
    }
}

/// The handful of Web API endpoints the app needs.
@MainActor
final class SpotifyAPI {
    private let auth: SpotifyAuth
    private let session: URLSession

    init(auth: SpotifyAuth) {
        self.auth = auth
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    /// `nil` when nothing is playing (HTTP 204).
    func currentlyPlaying() async throws -> PlaybackSnapshot? {
        let sentAt = CACurrentMediaTime()
        let (data, status) = try await send("GET", "/me/player/currently-playing?additional_types=track,episode")
        let receivedAt = CACurrentMediaTime()
        if status == 204 || data.isEmpty { return nil }
        try check(status, data)

        let payload = try JSONDecoder().decode(CurrentlyPlayingPayload.self, from: data)
        let content: PlaybackSnapshot.Content
        switch payload.currently_playing_type {
        case "ad":
            content = .ad
        case "episode":
            content = .episode(
                title: payload.item?.name ?? "",
                show: payload.item?.show?.name ?? "",
                artworkURL: payload.item?.images?.first.flatMap { URL(string: $0.url) }
            )
        default:
            if let item = payload.item, let uri = item.uri {
                let images = item.album?.images ?? []
                content = .track(TrackInfo(
                    id: item.id ?? uri,
                    uri: uri,
                    title: item.name,
                    artists: item.artists?.map(\.name) ?? [],
                    album: item.album?.name ?? "",
                    duration: Double(item.duration_ms ?? 0) / 1000,
                    artworkURL: (images.first { ($0.width ?? 0) >= 300 } ?? images.first).flatMap { URL(string: $0.url) },
                    isLocal: item.is_local ?? false
                ))
            } else {
                content = .unknown
            }
        }
        // The server read the position roughly half way through the round trip.
        let measuredAt = sentAt + (receivedAt - sentAt) / 2
        return PlaybackSnapshot(
            content: content,
            isPlaying: payload.is_playing,
            progress: Double(payload.progress_ms ?? 0) / 1000,
            measuredAt: measuredAt
        )
    }

    func play() async throws { try await control("PUT", "/me/player/play") }
    func pause() async throws { try await control("PUT", "/me/player/pause") }
    func next() async throws { try await control("POST", "/me/player/next") }
    func previous() async throws { try await control("POST", "/me/player/previous") }
    func seek(to seconds: Double) async throws {
        try await control("PUT", "/me/player/seek?position_ms=\(max(0, Int(seconds * 1000)))")
    }

    // MARK: Plumbing

    private func control(_ method: String, _ path: String) async throws {
        let (data, status) = try await send(method, path)
        try check(status, data)
    }

    private func check(_ status: Int, _ data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let error = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
        let message = error?.message ?? ""
        switch status {
        case 403 where message.lowercased().contains("premium") || error?.reason == "PREMIUM_REQUIRED":
            throw SpotifyAPIError.premiumRequired
        case 404: throw SpotifyAPIError.noActiveDevice
        default: throw SpotifyAPIError.http(status, message)
        }
    }

    private func send(_ method: String, _ path: String, retried: Bool = false) async throws -> (Data, Int) {
        let token = try await auth.accessToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" { request.setValue("0", forHTTPHeaderField: "Content-Length") }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 && !retried {
            _ = try await auth.accessToken(forceRefresh: true)
            return try await send(method, path, retried: true)
        }
        if status == 429 {
            let retryAfter = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
            throw SpotifyAPIError.rateLimited(retryAfter: retryAfter)
        }
        return (data, status)
    }

    private struct ErrorPayload: Decodable {
        struct Inner: Decodable { let status: Int?; let message: String?; let reason: String? }
        let error: Inner
    }

    private struct CurrentlyPlayingPayload: Decodable {
        struct Image: Decodable { let url: String; let width: Int? }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String?; let images: [Image]? }
        struct Show: Decodable { let name: String? }
        struct Item: Decodable {
            let id: String?
            let uri: String?
            let name: String
            let duration_ms: Int?
            let is_local: Bool?
            let artists: [Artist]?
            let album: Album?
            let images: [Image]?
            let show: Show?
        }
        let progress_ms: Int?
        let is_playing: Bool
        let currently_playing_type: String?
        let item: Item?
    }
}
