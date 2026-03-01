#import <FlutterMacOS/FlutterMacOS.h>

#import "../../ios/Classes/JuceAudioEnginePlugin.h"

void JuceAudioEnginePluginRegisterWithRegistrar(id<FlutterPluginRegistrar> registrar) {
  [JuceAudioEnginePlugin registerWithRegistrar:registrar];
}
