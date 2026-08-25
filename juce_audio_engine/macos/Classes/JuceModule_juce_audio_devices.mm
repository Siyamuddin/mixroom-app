// The repository's canonical JUCE source tree currently lives under
// android/src/main/cpp, but this macOS translation unit compiles that source
// directly. iOS does not use this file: it links JuceModules.xcframework and
// uses JUCE's separate juce_Audio_ios.cpp backend.
#include "../../android/src/main/cpp/juce/modules/juce_audio_devices/juce_audio_devices.mm"
