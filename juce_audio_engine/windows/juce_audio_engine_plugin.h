#ifndef FLUTTER_PLUGIN_JUCE_AUDIO_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_JUCE_AUDIO_ENGINE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace juce_audio_engine {

class JuceAudioEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  JuceAudioEnginePlugin();
  ~JuceAudioEnginePlugin() override;

  JuceAudioEnginePlugin(const JuceAudioEnginePlugin&) = delete;
  JuceAudioEnginePlugin& operator=(const JuceAudioEnginePlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace juce_audio_engine

#endif  // FLUTTER_PLUGIN_JUCE_AUDIO_ENGINE_PLUGIN_H_
