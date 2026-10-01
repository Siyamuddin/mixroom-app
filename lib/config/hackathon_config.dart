/// Compile-time isolation for the independent DIGITAL AF build.
/// No credentials belong in Dart defines: only the public relay URL is supplied.
abstract final class HackathonConfig {
  static const enabled = bool.fromEnvironment(
    'MIXROOM_HACKATHON',
    defaultValue: false,
  );

  static const relayBaseUrl = String.fromEnvironment(
    'MIXROOM_VOICE_RELAY_URL',
    defaultValue: 'http://127.0.0.1:8765/api/voice',
  );

  static const projectDirectory = 'mixroom_hackathon_projects';
}
