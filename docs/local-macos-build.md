# OpenClicky on Mike’s Mac

## Build and signing

Use Xcode with the existing `cursor-buddy` scheme and My Mac destination.
Do not run terminal `xcodebuild` or disable signing to bypass a build error.

- Apple account: `mike.jeffrey.pearlman@gmail.com`.
- Debug signing: `Apple Development: Michael Pearlman (P6JRB6LA3Y)`, team `7NXF7EKRNY`.
- Debug app and widget group: `7NXF7EKRNY.com.jkneen.openclicky`.
- `OPENCLICKY_APP_GROUP_IDENTIFIER` supplies both entitlements and runtime Info.plist values.
- Team-prefixed macOS app groups do not require provisioning profiles.
- Release retains the original developer’s group and signing settings.

Xcode’s per-user project settings place Derived Data under
`/Users/mike/Library/Developer/Xcode/OpenClickyBuild.noindex`.
The `.noindex` directory keeps development copies out of Spotlight.
The user launches `/Applications/OpenClicky.app`.

After building in Xcode, verify the app with `codesign --verify --deep --strict`.
Preserve the previous installed copy before replacing it. Copy the entire signed
bundle without re-signing it. Never install an ad-hoc or linker-only signed build:
its identity changes between builds and invalidates macOS permission approvals.
Register the installed path with Launch Services; unregister old development paths.

## Permission behavior

Startup does not enumerate ScreenCaptureKit content or request microphone access.
The user’s permission buttons and actual feature use request access.
Full Disk Access status remains unknown: macOS has no public passive status API.
Never probe Mail, Messages, or Safari files during status polling.
A second launch exits and activates the existing instance instead of quitting it.
Tutor Mode also waits for Accessibility and verified Screen Content access before
its automatic idle capture. Removing the startup prewarm alone is insufficient:
the tutor idle detector fires after three seconds.

The app requires `com.apple.security.automation.apple-events` for System Events
automation under Hardened Runtime. Keep that entitlement in the signed bundle.

## Repairing approvals from older unsigned builds

The September 3 permission loop had two confirmed causes. macOS logs rejected
ScreenCapture, Accessibility, and Microphone approvals because their saved
requirements referenced the old binary hash `ebee2aa3b3f74889b06dbef9f49f66e63f12180e`.
The installed development-signed app uses a certificate requirement instead.
Tutor Mode then requested capture automatically after three idle seconds.
Toggling the stale entries did not replace their saved signing requirement.

After verifying stable signing, reset only affected OpenClicky services with
`tccutil reset <service> com.jkneen.openclicky`, then grant access through macOS
and reopen the installed app. Do not run resets automatically on launch, reset
other apps, or edit the TCC databases. Future builds must retain the same signing
identity and designated requirement so these approvals survive updates.

Apple references:
- https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events

## Verification

The OCComputerUseCore package tests run with `swift test --package-path Packages/OCComputerUseCore`.
Use `swiftc -parse` for lightweight Swift syntax checks.
Build and inspect the installed, signed application for permission-flow verification.

Apple reference: https://developer.apple.com/documentation/xcode/accessing-app-group-containers
