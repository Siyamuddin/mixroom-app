# Desktop Plugin Hosting Notes

## macOS signed release requirements

For third-party AU/VST3 loading in a hardened runtime build, align app signing/runtime settings with plugin hosting:

- Enable hardened runtime on the app target.
- Add `com.apple.security.cs.disable-library-validation` entitlement for the host app.
- Keep microphone/audio entitlements aligned with recording features.
- Sign and notarize with the same team identity used for the app bundle.

If library validation remains enabled, third-party plugins can fail to load even when scan/discovery succeeds.

## Windows

Windows desktop host scans the default VST3 directories and does not require equivalent macOS-style hardened runtime exceptions.
