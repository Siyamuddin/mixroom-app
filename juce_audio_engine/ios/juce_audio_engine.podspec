Pod::Spec.new do |s|
  s.name             = 'juce_audio_engine'
  s.version          = '0.0.1'
  s.summary          = 'JUCE audio engine for Flutter'
  s.description      = 'Internal proprietary realtime audio engine for Mixroom'
  s.homepage         = 'https://mixroom.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mixroom' => 'andrew@mixroom.ai' }
  s.source           = { :path => '.' }

  s.source_files = [
    'Classes/*.{cpp,mm,m,h}'
  ]
  s.public_header_files = 'Classes/JuceAudioEnginePlugin.h'
  s.private_header_files = 'Classes/*.h'
  # s.exclude_files = [
  #   'Classes/juce/modules/**/juce_*/*.cpp',
  #   'Classes/juce/modules/**/juce_*.cpp',
  #   'Classes/juce/modules/juce_audio_devices/native/oboe/**',
  #   'Classes/juce/modules/**/linux/**',
  #   'Classes/juce/modules/**/windows/**',
  #   'Classes/juce/modules/**/android/**',
  #   'Classes/juce/modules/**/oboe/**',
  #   'Classes/juce/modules/**/native/oboe/**',
  #   'Classes/juce/modules/**/native/*_linux.cpp',
  #   'Classes/juce/modules/**/native/*_windows.cpp',
  #   'Classes/juce/modules/**/native/*_android.cpp',
  #   'Classes/juce/modules/**/juce_audio_plugin_client/**',
  # ]

  # Link against prebuilt .a libs from the xcframework
  s.ios.vendored_libraries = [
    # Release on a real device: uncomment this and comment out the other two entries.
    'JuceModules.xcframework/ios-arm64/libJuceModules.a',
    # Debug on a real device: uncomment this and comment out the other two entries.
    # 'JuceModules.xcframework/ios-arm64/libJuceModules_debug3.a',
    # Simulator builds: keep this uncommented and comment out the two iphoneos entries above.
    # 'JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a'
  ]

  

  s.platform         = :ios, '13.0'
  s.requires_arc     = false
  s.swift_version    = '5.0'
  s.dependency       'Flutter'
  s.dependency       'onnxruntime-objc', '1.22.0'
  # s.resources = ['Assets/Plugins/**/*']


  s.frameworks = 'AVFoundation', 'AudioToolbox', 'UIKit', 'CoreGraphics', 'CoreFoundation', 'CoreMIDI', 'CoreAudioKit', 'Accelerate', 'WebKit', 'UniformTypeIdentifiers', 'MobileCoreServices' 
  s.libraries  = 'c++'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'              => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY'           => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => '$(inherited) JUCE_PLUGINHOST_AU=1 JUCE_IOS=1 NDEBUG=1',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]'   => '$(inherited) JUCE_PLUGINHOST_AU=1 JUCE_IOS=1 JUCE_IOS_AUDIO_EXPLICIT_SAMPLERATES=44100',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/JuceModules.xcframework/ios-arm64/Headers" "${PODS_TARGET_SRCROOT}/JuceModules.xcframework/ios-arm64_x86_64-simulator/Headers"',
    'OTHER_LDFLAGS[sdk=iphoneos*][config=Debug]' => '-force_load "${PODS_TARGET_SRCROOT}/JuceModules.xcframework/ios-arm64/libJuceModules_debug3.a"',
    'OTHER_LDFLAGS[sdk=iphoneos*][config=Release]' => '-force_load "${PODS_TARGET_SRCROOT}/JuceModules.xcframework/ios-arm64/libJuceModules.a"',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '-force_load "${PODS_TARGET_SRCROOT}/JuceModules.xcframework/ios-arm64_x86_64-simulator/libJuceModules_sim.a"',
    'OTHER_CFLAGS'         => '$(inherited) -isysroot "${SDK_DIR}"',
    'CLANG_ENABLE_OBJC_ARC' => 'YES'
  }
end
