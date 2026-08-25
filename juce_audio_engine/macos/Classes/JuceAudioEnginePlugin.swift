import FlutterMacOS
import Foundation

@_silgen_name("JuceAudioEnginePluginRegisterWithRegistrar")
private func JuceAudioEnginePluginRegisterWithRegistrar(
  _ registrar: FlutterPluginRegistrar
)

@_silgen_name("JuceAudioEnginePluginShutdownForApplicationTermination")
private func JuceAudioEnginePluginShutdownForApplicationTermination()

@_silgen_name("JuceAudioEnginePluginPanicLiveMidiNotesForApplicationDeactivation")
private func JuceAudioEnginePluginPanicLiveMidiNotesForApplicationDeactivation()

public final class JuceAudioEnginePluginSwift: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    JuceAudioEnginePluginRegisterWithRegistrar(registrar)
  }

  public static func shutdownForApplicationTermination() {
    JuceAudioEnginePluginShutdownForApplicationTermination()
  }

  public static func panicLiveMidiNotesForApplicationDeactivation() {
    JuceAudioEnginePluginPanicLiveMidiNotesForApplicationDeactivation()
  }
}
