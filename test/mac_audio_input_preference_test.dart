import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/mac_audio_input_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('missing and empty preferences load as no selection', () async {
    expect(await MacAudioInputPreference.loadUID(), isNull);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'mixroom.audio.mac_input_uid.v1': '   ',
    });
    expect(await MacAudioInputPreference.loadUID(), isNull);
  });

  test('stored UID is trimmed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mixroom.audio.mac_input_uid.v1': '  coreaudio-input-42  ',
    });

    expect(await MacAudioInputPreference.loadUID(), 'coreaudio-input-42');
  });

  test(
    'save stores a normalized UID and replaces the previous value',
    () async {
      expect(
        await MacAudioInputPreference.saveUID('  coreaudio-input-1  '),
        isTrue,
      );
      expect(await MacAudioInputPreference.loadUID(), 'coreaudio-input-1');

      expect(
        await MacAudioInputPreference.saveUID('coreaudio-input-2'),
        isTrue,
      );
      expect(await MacAudioInputPreference.loadUID(), 'coreaudio-input-2');
    },
  );

  test('null or empty selection clears the preference', () async {
    await MacAudioInputPreference.saveUID('coreaudio-input-1');

    expect(await MacAudioInputPreference.saveUID(null), isTrue);
    expect(await MacAudioInputPreference.loadUID(), isNull);

    await MacAudioInputPreference.saveUID('coreaudio-input-2');
    expect(await MacAudioInputPreference.saveUID('  '), isTrue);
    expect(await MacAudioInputPreference.loadUID(), isNull);
  });
}
