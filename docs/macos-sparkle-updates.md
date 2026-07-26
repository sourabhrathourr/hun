# In-App Updates for the Website-Distributed macOS App

_Verified against Sparkle 2.9.4 documentation and Apple documentation on
2026-07-26._

## Recommendation

Use **Sparkle 2** for Hun's in-app updates. Keep Sparkle's standard installer
and update window, and layer a SwiftUI “Update available” banner on top using
Sparkle's **Gentle Update Reminders** delegate APIs.

This gives Hun a quiet, Codex-style banner while delegating download
verification, authorization, replacement of the installed app, and relaunch to
Sparkle. Implementing a complete custom `SPUUserDriver` is unnecessary for this
design and would make Hun responsible for many update states and error paths.

Important: an installed app can only discover future Sparkle updates if that
installed version already contains Sparkle and its appcast configuration. If
the current `0.2.2` DMG is published without Sparkle, those users will need one
manual download before they can receive in-app updates. If the DMG has not been
published yet, integrate and test Sparkle before calling it the first public
release.

Sources: [Sparkle basic setup](https://sparkle-project.org/documentation/),
[SwiftUI programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[Gentle Update Reminders](https://sparkle-project.org/documentation/gentle-reminders/),
[Custom User Interfaces](https://sparkle-project.org/documentation/custom-user-interfaces/).

## One-time integration

1. Add `https://github.com/sparkle-project/Sparkle` through Xcode's Swift
   Package Manager support and link the `Sparkle` product to the app target.
2. Generate an EdDSA keypair once with Sparkle's `generate_keys` tool. It saves
   the private key in the login Keychain and prints the public key. Back up the
   private key securely and never place it on the web server.
3. Add these generated Info.plist values to the **Release** app:

   - `SUFeedURL`: the HTTPS address of the appcast, such as
     `https://example.com/updates/appcast.xml`
   - `SUPublicEDKey`: the printed base64 public EdDSA key
   - `SUEnableAutomaticChecks`: `YES` if Hun should check automatically without
     Sparkle's second-launch permission prompt
   - `SUAutomaticallyUpdate`: `NO` initially, so the user chooses when to
     install and relaunch

   Sparkle's default scheduled interval is one day. Do not add a timer that
   repeatedly calls `checkForUpdatesInBackground`; Sparkle warns that manual
   calls can interfere with its scheduler.
4. Retain one `SPUStandardUpdaterController`, start it with the app, and add a
   **Check for Updates…** app-menu command. Sparkle documents observing
   `updater.canCheckForUpdates` to enable or disable that command.
5. Keep `CFBundleVersion` numeric and strictly increasing. Use it for
   `sparkle:version`; use `CFBundleShortVersionString` for the user-facing
   version. For example, the release after `0.2.2 (3)` can be `0.2.3 (4)`.

Sparkle recommends HTTPS, a Developer ID-signed and notarized application, and
an EdDSA signature on every update archive. The EdDSA archive signature is
separate from Apple's code signature: keep both.

Sources: [Sparkle basic setup and EdDSA signing](https://sparkle-project.org/documentation/),
[Customizing Sparkle](https://sparkle-project.org/documentation/customization/),
[SPUUpdater API](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html),
[Publishing an update](https://sparkle-project.org/documentation/publishing/).

## Banner and Update button

Use an app-owned, main-actor observable update model that also conforms to
`SPUStandardUserDriverDelegate`:

- Return `true` from `supportsGentleScheduledUpdateReminders`.
- In `standardUserDriverShouldHandleShowingScheduledUpdate`, return `false`
  when Hun wants to replace the scheduled update alert with its banner.
- In `standardUserDriverWillHandleShowingUpdate`, capture the
  `SUAppcastItem` when `handleShowingUpdate` is false and expose its
  `displayVersionString` to SwiftUI.
- Show a banner such as **Hun 0.2.3 is available** with an **Update** button.
- Make the button call `SPUStandardUpdaterController.checkForUpdates(_:)`.
  That is then a user-initiated check, so Sparkle brings its standard update
  window into focus with release notes and installation choices.
- Clear the banner from
  `standardUserDriverWillFinishUpdateSession`.

Keep Sparkle's standard UI after the button click. A full custom
`SPUUserDriver` must correctly represent not-downloaded, downloaded, and
installing states; permission and authorization prompts; progress; errors;
informational-only, major, and critical updates; and install/relaunch choices.
That is considerably more surface area than a banner requires.

Sources: [Gentle Update Reminders and official button example](https://sparkle-project.org/documentation/gentle-reminders/),
[SwiftUI setup](https://sparkle-project.org/documentation/programmatic-setup/),
[`SPUUserDriver` states and replies](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html).

## What happens after the user clicks Update

Sparkle downloads the archive, validates the EdDSA signature and Apple code
signature, extracts it, obtains authorization when required, and safely
replaces the installed app. At the ready-to-install stage, accepting the
installation installs immediately and relaunches the app if it is still
running. If the app quits by itself, Sparkle can install the prepared update on
termination.

The app must be copied to a writable installation location such as
`/Applications`; an app launched directly from a read-only DMG may not be
updatable. Keep the `/Applications` symlink in the website DMG.

Sources: [`SPUUserDriver` install and relaunch contract](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html),
[Sparkle distribution guidance](https://sparkle-project.org/documentation/).

## Appcast

The appcast is a static RSS/XML feed hosted over HTTPS. Generate it with
Sparkle's `generate_appcast` tool instead of editing signatures and byte
lengths by hand. Each release item should include:

- a strictly increasing `sparkle:version`
- a human-readable `sparkle:shortVersionString`
- `pubDate`
- the final DMG's HTTPS enclosure URL, byte length, and generated
  `sparkle:edSignature`
- release notes
- `sparkle:minimumSystemVersion` in three-component form, currently `15.0.0`
  for Hun
- `sparkle:hardwareRequirements` set to `arm64` while Hun is Apple
  silicon-only

Sparkle 2.9 supports the `arm64` hardware requirement and Markdown release
notes on macOS 12 or later. `generate_appcast` can also create signed delta
updates when old and new archives are retained.

`SURequireSignedFeed` plus `SUVerifyUpdateBeforeExtraction` can additionally
authenticate feed and release-note content. Sparkle describes feed signing as
optional and notes that every feed or release-note edit then requires
re-signing. Enable it only as part of a release pipeline that always runs
`generate_appcast`; archive EdDSA signing remains required either way.

Sources: [Publishing an update](https://sparkle-project.org/documentation/publishing/),
[Appcast and `generate_appcast`](https://sparkle-project.org/documentation/),
[Delta updates](https://sparkle-project.org/documentation/delta-updates/).

## Repeatable release process

For every release:

1. Increase both versions, for example from `0.2.2 (3)` to `0.2.3 (4)`, and
   write release notes.
2. Build the Release app for `arm64`.
3. Sign all nested executable code, including Hun's bundled CLI and Sparkle's
   framework/helper bundles, from the inside out with the same Developer ID
   Application identity; then sign the outer app.
4. Create and sign the DMG, submit it to Apple's notary service, wait for
   `Accepted`, staple the ticket, and validate the final DMG.
5. Put the **final stapled DMG** in the retained updates directory and run
   Sparkle's `generate_appcast`. Stapling changes the DMG, so generate its
   EdDSA signature only after stapling.
6. Confirm the generated item has `15.0.0` and `arm64` requirements and points
   to the intended HTTPS DMG URL.
7. Upload the DMG, release notes, and any delta files first. Publish the new
   appcast last so clients never see an enclosure URL that is not live.
8. Test an update from the previous **notarized production build**, including
   banner appearance, release notes, download, installation, relaunch, the new
   version number, bundled CLI behavior, and **Check for Updates…**.
9. Update the website's direct-download button to the same final DMG. Keep old
   full archives if delta generation is desired.

Sparkle recommends Xcode Archive plus Developer ID distribution because Xcode
correctly signs Sparkle's helper tools. Hun's current manual release script
signs only its bundled CLI and the outer app; after adding Sparkle, that script
must be extended to sign and verify Sparkle's nested code inside-out, or be
replaced by an Xcode archive/export step. Do not ship the first Sparkle build
until the notarized app and an update from an older notarized build both pass.

Sources: [Sparkle distribution guidance](https://sparkle-project.org/documentation/),
[Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Apple packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Suggested rollout

1. Integrate Sparkle and the banner before the first public Hun DMG if
   possible.
2. Ship the standard full-DMG update path first; add deltas only after full
   updates are proven.
3. Keep automatic checking on and automatic installation off initially.
4. Add update settings later so users can change Sparkle's persisted
   `automaticallyChecksForUpdates` and `automaticallyDownloadsUpdates`
   properties. Do not maintain duplicate user defaults.
5. If Intel support is introduced, publish an Intel-compatible item/feed and
   keep the `arm64` hardware requirement on Apple silicon-only releases.
