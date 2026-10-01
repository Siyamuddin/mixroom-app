# Independent MixRoom macOS build

Use the `Hackathon` flavor for the DIGITAL AF app. It has its own bundle identifier, `io.github.siyamuddin.mixroom.hackathon`, and displays as **MixRoom**. The ordinary Runner configurations are retained separately.

```sh
cd voice_backend && docker compose up --build -d && cd ..
tool/run_hackathon.sh
tool/build_hackathon.sh
```

First configure the private environment as described in [the backend guide](../voice_backend/README.md). The native relay defaults to `http://127.0.0.1:8765/api/voice`. Run defaults to debug; build defaults to release. `--profile`, `--debug`, `--release`, and `--no-pub` are supported. Use `--dry-run` to inspect the command without fetching dependencies, compiling, or launching. `--relay-url` or `MIXROOM_VOICE_RELAY_URL` can override the address. HTTP is permitted only for exact loopback hosts; remote addresses require HTTPS.

The scripts pass `MIXROOM_HACKATHON=true` and the public relay URL to Flutter. The dedicated native configurations also append the isolation flag to inherited Dart defines, including the Flutter Assemble target. Do not supply production debug files, API keys, or n8n secrets. The scripts reject arbitrary build options and URLs containing credentials, queries, or fragments.

The separate Hackathon plist has no original OAuth callbacks, Google client IDs, Sparkle feed, or update-signing key. Automatic update checks are disabled. The entitlements retain microphone, networking, and applicable local audio/plugin permissions, while removing Apple sign-in and shared keychain groups. The independent app imports the existing project-file type as an alternate handler instead of claiming ownership. Existing attribution is retained.

These configurations use local ad-hoc signing and clear the original development team. This is suitable for local hackathon testing; it is not a notarized distribution setup. The Hackathon Dart startup must continue to disable production services and use its independent project-storage directory.

`ruby tool/configure_hackathon_macos.rb` regenerates the project configurations, independent plist/entitlements, and shared scheme. It does not build, install, call providers, or load secrets. CocoaPods has matching Debug/Profile/Release-Hackathon mappings; Flutter may need to regenerate dependencies on the first actual build.

Configuration validation is separate from compilation. Successful plist, shell, and Xcode-project parsing checks do not establish that the app builds, launches, records, or connects to the relay. Verify those through the normal native demo checks after a build completes.
