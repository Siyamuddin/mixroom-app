# Independent MixRoom macOS build

Use the `Hackathon` flavor for the DIGITAL AF app. It has its own bundle identifier, `io.github.siyamuddin.mixroom.hackathon`, and displays as **MixRoom**. The ordinary Runner configurations are retained separately.

```sh
tool/run_hackathon.sh --relay-url http://127.0.0.1:8766/api/voice
tool/build_hackathon.sh --relay-url http://127.0.0.1:8766/api/voice
```

First start the Mac's Python backend as described in [the manual guide](../docs/MANUAL_TESTING.md). Its current native relay is `http://127.0.0.1:8766/api/voice`; the script's unchanged default, port 8765, is for Docker. The hosted controls at [mix-voice-studio.lovable.app](https://mix-voice-studio.lovable.app) use HTTPS to reach the same backend, while native audio stays on this Mac. Published-browser sign-in, pairing-code creation, and revocation are verified; native microphone and full feature acceptance remain pending. Hosted source is the private [mixroom-voice repository](https://github.com/Siyamuddin/mixroom-voice).

Run defaults to debug; build defaults to release. `--profile`, `--debug`, `--release`, and `--no-pub` are supported. Use `--dry-run` to inspect the command without fetching dependencies, compiling, or launching. `--relay-url` or `MIXROOM_VOICE_RELAY_URL` can override the address. HTTP is permitted only for exact loopback hosts; remote addresses require HTTPS.

The scripts pass `MIXROOM_HACKATHON=true` and the public relay URL to Flutter. The dedicated native configurations also append the isolation flag to inherited Dart defines, including the Flutter Assemble target. Do not supply production debug files or provider credentials. The scripts reject arbitrary build options and URLs containing credentials, queries, or fragments.

The separate Hackathon plist has no original OAuth callbacks, Google client IDs, Sparkle feed, or update-signing key. Automatic update checks are disabled. The entitlements retain microphone, networking, and applicable local audio/plugin permissions, while removing Apple sign-in and shared keychain groups. The independent app imports the existing project-file type as an alternate handler instead of claiming ownership. Existing attribution is retained.

These configurations use local ad-hoc signing and clear the original development team. This is suitable for local hackathon testing; it is not a notarized distribution setup. The Hackathon Dart startup must continue to disable production services and use its independent project-storage directory.

`ruby tool/configure_hackathon_macos.rb` regenerates the project configurations, independent plist/entitlements, and shared scheme. It does not build, install, call providers, or load secrets. CocoaPods has matching Debug/Profile/Release-Hackathon mappings; Flutter may need to regenerate dependencies on the first actual build.

Configuration validation is separate from compilation. Successful plist, shell, and Xcode-project parsing checks do not establish that the app builds, launches, records, or connects to the relay. Verify those through the normal native demo checks after a build completes.

The isolated debug build succeeded on October 1, 2026, and its deep code-signature check passed. It is available at `build/macos/Build/Products/Debug-Hackathon/MixRoom.app`. Open that bundle directly for manual testing; rebuilding is not required. See [the manual checklist](../docs/MANUAL_TESTING.md).

To reproduce the build on this Mac with less generated native metadata:

```sh
XCODE_XCCONFIG_FILE="$PWD/tool/hackathon_low_disk.xcconfig" tool/build_hackathon.sh --debug --no-pub --relay-url http://127.0.0.1:8766/api/voice
```

This disables compiler indexing and native debug symbols for that invocation, reducing disk use but limiting native crash-debugging detail. It does not disable Flutter debug mode or change the app's voice features. The ordinary build remains available without the override.
