import FlutterMacOS
import Foundation

@_silgen_name("JuceAudioEnginePluginRegisterWithRegistrar")
private func JuceAudioEnginePluginRegisterWithRegistrar(
  _ registrar: FlutterPluginRegistrar
)

@_silgen_name("JuceAudioEnginePluginShutdownForApplicationTermination")
private func JuceAudioEnginePluginShutdownForApplicationTermination()

public final class JuceAudioEnginePluginSwift: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    JuceAudioEnginePluginRegisterWithRegistrar(registrar)
  }

  public static func shutdownForApplicationTermination() {
    JuceAudioEnginePluginShutdownForApplicationTermination()
  }
}
