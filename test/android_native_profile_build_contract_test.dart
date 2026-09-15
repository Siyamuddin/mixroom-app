import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String gradle;
  late String cmake;

  setUpAll(() {
    gradle = File('juce_audio_engine/android/build.gradle').readAsStringSync();
    cmake = File(
      'juce_audio_engine/android/src/main/cpp/CMakeLists.txt',
    ).readAsStringSync();
  });

  test('Flutter Profile selects the optimized native plugin variant', () {
    expect(gradle, contains('profile {'));
    expect(gradle, contains('initWith debug'));
    expect(gradle, contains('arguments "-DMIXROOM_ANDROID_PROFILE=ON"'));
  });

  test('native Profile keeps symbols and enables release optimization', () {
    expect(cmake, contains('option(MIXROOM_ANDROID_PROFILE'));
    expect(cmake, contains('if(MIXROOM_ANDROID_PROFILE)'));
    expect(cmake, contains('add_compile_options(-O2 -g)'));
    expect(cmake, contains('add_compile_definitions(NDEBUG)'));
  });
}
