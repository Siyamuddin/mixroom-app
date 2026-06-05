# Desktop Plugin Hosting Notes

## macOS signed release requirements

For third-party AU/VST3 loading in a hardened runtime build, align app signing/runtime settings with plugin hosting:

- Enable hardened runtime on the app target.
- Add `com.apple.security.cs.disable-library-validation` entitlement for the host app.
- Keep microphone/audio entitlements aligned with recording features.
- Sign and notarize with the same team identity used for the app bundle.

Use the release packager for any build sent outside the build machine:

```sh
MACOS_CODESIGN_IDENTITY="Developer ID Application: Example Company (X8Y4B4222A)" \
MACOS_NOTARY_KEYCHAIN_PROFILE="mixroom-notary" \
script/package_macos_release.sh --build-name 1.2.4 --build-number 38
```

Do not distribute a DMG created directly from `flutter build macos --release`. A release app signed with `Apple Development`, ad hoc signing, or an unsigned DMG can be killed by Taskgated on another Mac before Mixroom code starts running.

The Developer ID packager strips profile-gated entitlements, including native Sign in with Apple and keychain access groups, from the distributable DMG signature. Those entitlements require a provisioning profile and can produce an invalid entitlement blob when applied directly with Developer ID signing.

If library validation remains enabled, third-party plugins can fail to load even when scan/discovery succeeds.

## Windows

Windows desktop host scans the default VST3 directories and does not require equivalent macOS-style hardened runtime exceptions.
