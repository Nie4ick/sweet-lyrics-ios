import AVFoundation

/// The delay between Spotify's playback position and what reaches the ears on this iPhone's
/// current audio output (AirPods and other Bluetooth headphones add ~150–250 ms).
enum AudioRoute {
    /// An ambient, mixable session: it never interrupts Spotify, but lets iOS report the
    /// latency of the current route.
    static func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Output latency of the current route in seconds (clamped to something plausible).
    static var outputLatency: Double {
        min(max(AVAudioSession.sharedInstance().outputLatency, 0), 0.5)
    }
}
