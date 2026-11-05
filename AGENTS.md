# Hun

## Running things

Start everything through Hun, never by hand (no `xcodebuild` plus `open`, no `bun run dev`):

- macOS dev app: `hun run hun -p macOS`. It builds into `.build/xcode-dev`, launches "hun Dev", and rebuilds and relaunches on every save. Logs: `hun logs hun:macos`.
- Website: `hun run hun -p website`.

Run `hun status` first: it may already be running. If `hun` isn't on your PATH, use `/Applications/hun.app/Contents/Resources/hun`.
