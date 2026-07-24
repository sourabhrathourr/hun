# Distributing a Notarized macOS App as a DMG

_Verified against Apple documentation on 2026-07-25._

This is Apple’s **Direct Distribution** path. It does not publish the app on
the Mac App Store and does not involve App Review. You sign the app with
Developer ID, package it in a signed DMG, submit that DMG to Apple’s automated
notary service, staple the returned ticket, and host the final DMG yourself.

## 1. Prerequisites

- Join the paid Apple Developer Program. Developer ID certificates are issued
  only to Apple Developer Program or Apple Developer Enterprise Program
  members.
- Install a current Xcode and select it with `xcode-select` if multiple copies
  are installed.
- In Xcode, add the Apple Account and select the correct team for every target.
- Create/install a **Developer ID Application** certificate. This signs both
  the app and the DMG. A **Developer ID Installer** certificate is only needed
  for a `.pkg`, not a drag-to-Applications DMG.

Check that the signing identity and its private key are available:

```sh
security find-identity -p codesigning -v
```

Source: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[Developer ID certificate glossary](https://developer.apple.com/help/glossary/developer-id-certificate/).

## 2. Prepare the release target

For every executable target:

- Enable **Hardened Runtime** in **Signing & Capabilities**.
- Keep entitlements minimal and add hardened-runtime exceptions only when the
  app actually needs them.
- Ensure `com.apple.security.get-task-allow` is absent or false in the release
  signature.
- Use a secure timestamp. Xcode’s distribution export does this by default;
  manual signing uses `--timestamp`.
- Sign nested code from the inside out. Do not use `codesign --deep` to sign.
- If a restricted entitlement requires a provisioning profile, use a
  Developer ID distribution profile. App Sandbox is recommended, but unlike
  Mac App Store distribution, it is not required.

Inspect the final entitlements when needed:

```sh
codesign -d --entitlements - --xml "build/Hun.app"
```

Sources: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime),
[Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[macOS distribution comparison](https://developer.apple.com/macos/distribution/).

## 3. Archive and export a Developer ID-signed app

The Xcode UI route is:

1. Select the app scheme and a generic Mac destination.
2. Choose **Product > Archive**.
3. In **Window > Organizer > Archives**, select the archive.
4. Click **Distribute App** and choose **Direct Distribution**, or use
   **Custom > Developer ID** when controlling the export/notarization steps
   yourself.

For an automated build, archive and export with `xcodebuild`:

```sh
xcodebuild archive \
  -scheme "Hun" \
  -configuration Release \
  -archivePath "build/Hun.xcarchive"

xcodebuild -exportArchive \
  -archivePath "build/Hun.xcarchive" \
  -exportOptionsPlist "ExportOptions.plist" \
  -exportPath "build/export"
```

Use `method = developer-id` in the export options. A reliable way to obtain a
compatible `ExportOptions.plist` is to perform one Developer ID export in Xcode
and retain the generated plist; `xcodebuild -help` lists the keys supported by
the installed Xcode.

Source: [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[Distributing apps for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## 4. Verify the exported app before packaging

```sh
codesign --verify --deep --strict --verbose=2 "build/export/Hun.app"
codesign -dvvv "build/export/Hun.app"
spctl --assess --type execute --verbose=4 "build/export/Hun.app"
```

The displayed authority should be the intended **Developer ID Application**
identity. Treat failures in nested helpers, frameworks, extensions, XPC
services, or bundled command-line tools as signing failures to fix before
notarization.

Source: [TN2206: macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/).

## 5. Build and sign the DMG

Create a staging directory containing the exported app and, optionally, a
symlink to `/Applications`. Preserve bundle symlinks with `ditto`:

```sh
mkdir -p "build/dmg-root"
ditto "build/export/Hun.app" "build/dmg-root/Hun.app"
ln -s /Applications "build/dmg-root/Applications"

hdiutil create \
  -srcFolder "build/dmg-root" \
  -format UDZO \
  -volname "Hun" \
  -o "build/Hun.dmg"
```

Sign the completed DMG with the same Developer ID Application identity. Give
the DMG a unique signing identifier derived from the app bundle ID:

```sh
codesign \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  --timestamp \
  --identifier "com.example.hun.dmg" \
  "build/Hun.dmg"
```

Do any layout/background customization before this signing step. Do not modify
the app or DMG after signing. For nested containers, Apple’s order is: sign the
app, create and sign each container from inner to outer, then notarize only the
outermost file users will download.

Verify before upload:

```sh
hdiutil verify "build/Hun.dmg"
codesign --verify --verbose=2 "build/Hun.dmg"
spctl --assess --type open \
  --context context:primary-signature \
  --verbose "build/Hun.dmg"
```

Source: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
[TN2206: Signing Disk Images](https://developer.apple.com/library/archive/technotes/tn2206/#//apple_ref/doc/uid/DTS40007919-CH1-TNTAG301).

## 6. Store notary credentials once

Create an app-specific password for the Apple Account, then save the credentials
in the login keychain instead of placing secrets in a build script:

```sh
xcrun notarytool store-credentials "hun-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP-SPECIFIC-PASSWORD"
```

Keep the Developer ID private key and notarization credentials secret. Use a
dedicated secured signing machine/keychain or CI secret store.

Source: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Using app-specific passwords](https://support.apple.com/102654).

## 7. Submit the final DMG and inspect the result

`notarytool` is the current tool. Apple stopped accepting `altool`
notarization uploads on 2023-11-01.

```sh
xcrun notarytool submit "build/Hun.dmg" \
  --keychain-profile "hun-notary" \
  --wait
```

Continue only when the returned status is `Accepted`. Save the submission ID
and inspect the JSON log even after success, because it can contain warnings:

```sh
xcrun notarytool log "SUBMISSION-ID" \
  --keychain-profile "hun-notary" \
  "build/notarization-log.json"
```

Submitting the signed outermost DMG is sufficient: the notary service also
processes its signed nested app and generates tickets for the top-level and
nested items.

Source: [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

## 8. Staple and validate

Stapling lets Gatekeeper find the notarization ticket even when the user’s Mac
is offline:

```sh
xcrun stapler staple "build/Hun.dmg"
xcrun stapler validate "build/Hun.dmg"
```

Do not alter, rebuild, or re-sign the DMG after stapling. The stapled DMG is the
release artifact.

Source: [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## 9. Test the artifact users will actually receive

Upload the DMG to a temporary web location, download it through a browser on a
clean Mac so it receives the quarantine attribute, then:

1. Open the downloaded DMG.
2. Drag the app to `/Applications`.
3. Launch it normally from `/Applications`.
4. Confirm the expected “downloaded from the Internet” first-launch prompt,
   with no “developer cannot be verified” or “Apple cannot check it for
   malicious software” error.
5. Test a clean install and an upgrade from the previous public version.
6. Test all supported macOS versions and CPU architectures.

A local build that never passed through an Internet download does not fully
exercise Gatekeeper’s first-launch path.

Sources: [TN2206: Checking Gatekeeper conformance](https://developer.apple.com/library/archive/technotes/tn2206/),
[Packaging Mac software for distribution — Test your product](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
[Safely open apps on your Mac](https://support.apple.com/102445).

## 10. Host and maintain releases

- Host the exact stapled DMG on a website or object-storage/CDN URL, preferably
  over HTTPS. A normal download button can link directly to it.
- Do not unpack, recompress, patch, or otherwise transform the final file at the
  hosting layer.
- Publish the version, minimum supported macOS version, architecture support,
  file size, and optionally a SHA-256 checksum.
- Apple manages neither hosting nor software updates for Developer ID apps.
  Either tell users to download each new DMG or implement and secure an update
  mechanism. Every update must repeat the release pipeline: release build,
  Developer ID signing, signed DMG, notarization, stapling, and Gatekeeper test.
- Keep the bundle identifier and signing identity/team stable across updates.
  Increment `CFBundleShortVersionString` and `CFBundleVersion`.
- Keep old accepted artifacts and notarization submission IDs/logs for release
  traceability. Plan certificate renewal before the next release; do not revoke
  a Developer ID certificate casually because revocation affects software
  signed with it.

Apple explicitly classifies distribution, software updates, download support,
and marketing outside the Mac App Store as **managed by the developer**.

Sources: [Distributing software on macOS](https://developer.apple.com/macos/distribution/),
[Distribution overview](https://developer.apple.com/documentation/technologyoverviews/distribution),
[Developer ID certificate lifecycle](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[URLSession and HTTPS/ATS](https://developer.apple.com/documentation/foundation/urlsession).

## Release checklist

- [ ] Release archive exported with Developer ID
- [ ] Hardened Runtime enabled; release entitlements audited
- [ ] App signature passes `codesign` and `spctl`
- [ ] Read-only UDZO DMG created and signed with Developer ID Application
- [ ] DMG integrity and signature verified
- [ ] `notarytool submit --wait` returns `Accepted`
- [ ] Notarization log reviewed
- [ ] Ticket stapled to and validated on the DMG
- [ ] Exact final DMG downloaded from the host and tested through Gatekeeper
- [ ] Clean-install and upgrade paths tested on supported Macs
