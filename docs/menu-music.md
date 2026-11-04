# Menu bar music

The macOS app's menu bar plays music: a record in the menu bar's sky, ten
pieces in a shuffled order. One piece, Doorway (the welcome's music,
`OnboardingMusic.mp3`), ships inside the app. The other nine are downloaded the
first time someone presses play, so the app stays small and nobody downloads
music they never play.

## Where the music lives

The nine pieces are assets of the GitHub release
[`menu-music-1`](https://github.com/sourabhrathourr/hun/releases/tag/menu-music-1),
which is not an app release and is never marked Latest. It holds ten files:
Quiet City (`MenuMusic-QuietCity.m4a`) was taken out of the app in 0.6.2, but
0.6.0 and 0.6.1 still download it, so it stays.

The app has that release's address and each file's SHA-256 built in
(`HunMenuMusic.pieces` in `apps/macos/hun/hun/HunMenuMusic.swift`). It saves
the files in `~/.hun/music` and keeps a file only if its checksum matches.

## Keep `menu-music-1` exactly as it is

Every copy of Hun from 0.6.0 on downloads from this release, and old copies
stay installed for a long time. So:

- **Never delete or rename it.** Downloads would fail, and those copies of Hun
  would only ever play Doorway.
- **Never replace a file in it**, not even with a better version of the same
  piece. Its checksum would no longer match, and the app would reject it.
- **Never mark it Latest.** The website's download link and the Sparkle
  appcast (`hun.sh/appcast.xml`) use the Latest release, which must stay the
  app.

## Adding or changing music

To drop a piece, delete its line from `HunMenuMusic.pieces` and ship an app
update. Leave its file in the release: older copies still download it.

1. Publish a new release, `menu-music-2`, with all the files the new set
   needs, created with `--latest=false`. Check afterwards that the Latest
   release is still the app.
2. Point `HunMenuMusic.downloadBase` at it and update `HunMenuMusic.pieces`
   (titles, file names, checksums: `shasum -a 256 <file>`).
3. Ship that in an app update. Leave `menu-music-1` untouched for older copies.

## How the files are made

Generated with ElevenLabs from prompts based on the welcome's music and the
launch film's calm track; levelled to the welcome music's loudness (−16.3
LUFS) with one fixed gain per piece (no dynamic levelling, which boosts quiet
intros), silent tails trimmed, and encoded as 192 kbps AAC.
