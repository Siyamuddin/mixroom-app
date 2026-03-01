#include "include/juce_audio_engine/juce_audio_engine_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "juce_audio_engine_plugin.h"

void JuceAudioEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  juce_audio_engine::JuceAudioEnginePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
