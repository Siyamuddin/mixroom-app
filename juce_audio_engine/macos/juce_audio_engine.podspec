Pod::Spec.new do |s|
  s.name             = 'juce_audio_engine'
  s.version          = '0.0.1'
  s.summary          = 'JUCE audio engine for Flutter (macOS)'
  s.description      = 'Real-time JUCE audio engine and plugin host bridge for Mixroom desktop.'
  s.homepage         = 'https://mixroom.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mixroom' => 'andrew@mixroom.ai' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Classes/*.{h,m,mm,cpp,c,swift}'
  ]
  s.public_header_files = 'Classes/JuceAudioEnginePlugin.h'
  s.private_header_files = 'Classes/*.h'

  s.dependency 'FlutterMacOS'

  s.frameworks = [
    'Cocoa',
    'AVFoundation',
    'AudioToolbox',
    'CoreAudio',
    'CoreAudioKit',
    'CoreMIDI',
    'AudioUnit',
    'CoreServices',
    'Accelerate'
  ]
  s.libraries = 'c++'

  s.platform = :osx, '14.0'
  s.requires_arc = false
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../ios/Classes" "${PODS_TARGET_SRCROOT}/../android/src/main/cpp" "${PODS_TARGET_SRCROOT}/../android/src/main/cpp/juce/modules" "${PODS_TARGET_SRCROOT}/../android/src/main/cpp/juce/modules/juce_audio_processors/format_types/VST3_SDK"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1 JUCE_PLUGINHOST_AU=1 JUCE_PLUGINHOST_VST3=1 JUCE_PLUGINHOST_VST=0 JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_USE_CAMERA=0 JUCE_DONT_DECLARE_PROJECTINFO=1 JUCE_MODAL_LOOPS_PERMITTED=1 JUCE_USE_HARFBUZZ=0 JUCE_STRICT_REFCOUNTEDPOINTER=1'
  }
end
