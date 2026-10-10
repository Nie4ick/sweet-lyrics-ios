# Spicy Lyrics for iOS (Unofficial Port)

> **VERY EARLY VERSION — experimental and under active development.**
> This project is at a very early stage. Expect bugs, incomplete features, rough edges,
> and breaking changes. It is not ready for everyday use. Reliable builds and playback
> behavior are not guaranteed yet.

A standalone iOS app that displays **word-by-word synchronized lyrics** for songs playing
on Spotify. It ports the [Spicy Lyrics](https://github.com/Spikerko/spicy-lyrics)
Spicetify extension, taking inspiration from the Android app
[spicylyrics/mobile](https://github.com/spicylyrics/mobile).

## Ported Features

These features are implemented in the prototype and still need testing and refinement.

| Feature | iOS implementation |
| --- | --- |
| Word-by-word highlighting | Port of `LyricsAnimator.ts`: NotSung/Active/Sung states, syllable gradients, cubic splines for scale/y-offset/glow, and [spr](https://github.com/Fraktality/spr) springs |
| Per-letter animation | Syllables longer than one second are split into letters with a proximity effect, following `Emphasize.ts` |
| Line blur | Blur increases with distance from the active line (`BlurMultiplier = 1.25`) |
| Duets and backing vocals | Right-aligned `OppositeAligned` lines and smaller backing vocals below the main line |
| Instrumental breaks | Three animated dots during gaps of at least three seconds |
| Line-synced and static lyrics | `Line` and `Static` lyric types |
| Dynamic background | Blurred album artwork with a Metal distortion shader inspired by Kawarp |
| Lyrics sources | Spicy Lyrics API with [LRCLIB](https://lrclib.net) as a fallback |
| Romanization | Supported when returned by the API (`TransliteratedText`) |
| Seeking | Tap a lyric line to seek to it; requires Spotify Premium |

## Spotify Connection

The app connects through the official **Spotify Web API**:

- OAuth sign-in using Authorization Code + PKCE, without a client secret.
- Requests to `/me/player/currently-playing` once per second while the app is open.
  Between requests, playback position is estimated locally with smooth drift correction.
- Play/pause, next/previous, and seeking through the Web API; these controls require
  **Spotify Premium**.

For the current prototype, set up your own Spotify developer app:

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and select **Create app**.
2. Add the redirect URI `spicylyrics-ios://callback`.
3. Select **Web API** under “Which API/SDKs are you planning to use”.
4. Add your Spotify account email under **User Management** for development access.
5. Copy the **Client ID** and enter it on the app's onboarding screen.

## Lyrics Source: Spicy Lyrics Key

- **With a key (recommended):** obtain a client key (`sl_pk_…`) from
  [Spicy Lyrics Developers](https://developers.spicylyrics.org) and enter it under
  *Settings → Lyrics Sources*. The app uses `GET /v1/lyrics/{trackId}`, as the Android app does.
- **Without a key:** the app sends a `POST /query` request using your Spotify token,
  following the Spicetify extension. SLObjPack responses are decoded on the device.
  The server may reject tokens from third-party apps. If that happens, the app prompts
  you to add a key and falls back to LRCLIB for line-synced lyrics.

## Building

Requires a Mac with Xcode 16+ targeting iOS 17+, **or** GitHub Actions.
Build and installation paths are experimental at this stage.

### On a Mac

```bash
brew install xcodegen
xcodegen generate
open SpicyLyrics.xcodeproj
```

Select your development team in Xcode under **Signing & Capabilities**. If the bundle
identifier is unavailable, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
Then build and run the app on your iPhone.

### Without a Mac: GitHub Actions and Sideloading

1. Push the project to your GitHub repository.
2. The workflow in `.github/workflows/ios-build.yml` is configured to build an
   **unsigned** `SpicyLyrics-unsigned.ipa` on a macOS runner. After a successful run,
   download it from *Actions → latest run → Artifacts*.
3. Sign and install the IPA using [Sideloadly](https://sideloadly.io) or
   [AltStore](https://altstore.io) with your Apple ID. With a free account, the original
   setup instructions call for refreshing the installation every seven days.

## Project Structure

```text
SpicyLyrics/
  App/          Entry point and lifecycle; polling while the app is open
  Spotify/      OAuth PKCE, Web API, player model, and playback clock
  Lyrics/       Models, parsers (Spicy JSON, LRC), SLObjPack, service, and disk cache
  Rendering/    Springs, splines, animator, lyric line rendering, and scrolling
  Background/   Dynamic background and Metal shader
  UI/           Onboarding, now playing screen, playback controls, and settings
```

## Current Limitations

- **Very early prototype:** features, UI, and integrations may be incomplete or unstable.
- Spotify polling runs while the app is open; continuous background polling is not supported.
- Playback controls require Spotify Premium.
- Lyric translations, Genius integration, and local TTML files are not supported in this version.

## License and Credits

Licensed under **AGPL-3.0**, following the original projects. See [LICENSE](LICENSE).
This is an unofficial project and is not affiliated with Spotify AB or the creators of Spicy Lyrics.
