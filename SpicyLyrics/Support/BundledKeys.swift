import Foundation

/// Keys built into the app (see `scripts/generate-bundled-keys.sh`). They are stored XOR-masked
/// so they don't show up in plain text in the bundle. That stops casual inspection only: both
/// are public client identifiers that the app sends over the network anyway.
enum BundledKeys {
    typealias Masked = (mask: [UInt8], data: [UInt8])

    static var spotifyClientID: String? { reveal(maskedSpotifyClientID) }
    static var spicyLyricsKey: String? { reveal(maskedSpicyLyricsKey) }

    private static func reveal(_ masked: Masked) -> String? {
        guard !masked.data.isEmpty, masked.data.count == masked.mask.count else { return nil }
        let bytes = zip(masked.data, masked.mask).map { $0 ^ $1 }
        return String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}
