#!/usr/bin/env bash
# Writes altstore-source.json: an AltStore / SideStore source listing every stable release with
# its unsigned IPA. CI attaches it to each stable release, so the source URL never changes:
#   https://github.com/<repo>/releases/latest/download/altstore-source.json
set -euo pipefail

repo="${GH_REPO:?GH_REPO must be owner/name}"
raw="https://raw.githubusercontent.com/$repo/main"
out="${1:-altstore-source.json}"

versions='[]'
for tag in $(gh release list --repo "$repo" --limit 100 --exclude-pre-releases --json tagName --jq '.[].tagName'); do
    entry=$(gh release view "$tag" --repo "$repo" --json tagName,publishedAt,body,assets --jq '
        (.assets | map(select(.name | endswith("-unsigned.ipa"))) | first) as $ipa
        | select($ipa != null)
        | {
            version: (.tagName | ltrimstr("v")),
            date: .publishedAt,
            localizedDescription: ((.body // "") | .[0:4000]),
            downloadURL: $ipa.url,
            size: $ipa.size,
            minOSVersion: "17.0"
          }')
    if [ -n "$entry" ]; then
        versions=$(jq --argjson entry "$entry" '. + [$entry]' <<<"$versions")
    fi
done

jq -n --argjson versions "$versions" --arg repo "$repo" --arg raw "$raw" '{
    name: "Spicy Lyrics (unofficial)",
    identifier: "com.spicylyrics.unofficial.source",
    subtitle: "Word-synced lyrics for Spotify",
    description: "Unofficial iOS port of the Spicy Lyrics extension. Builds come from GitHub releases.",
    iconURL: ($raw + "/SpicyLyrics/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
    website: ("https://github.com/" + $repo),
    tintColor: "#8B5CF6",
    apps: [{
        name: "Spicy Lyrics",
        bundleIdentifier: "com.spicylyrics.unofficial.ios",
        developerName: "Sppq",
        subtitle: "Word-synced lyrics for Spotify",
        localizedDescription: "Word-by-word synced lyrics for what plays in Spotify, with the animations of the Spicy Lyrics extension, an Apple Music style player and your own TTML files.",
        iconURL: ($raw + "/SpicyLyrics/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
        tintColor: "#8B5CF6",
        category: "entertainment",
        screenshots: [],
        versions: $versions,
        appPermissions: { entitlements: [], privacy: {} }
    }],
    news: []
}' > "$out"

echo "Wrote $out with $(jq '.apps[0].versions | length' "$out") version(s)"
