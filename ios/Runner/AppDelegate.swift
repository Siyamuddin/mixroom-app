import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let channelName = "mixroom/open_file"
  private var channel: FlutterMethodChannel?
  private var initialMixroomPath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

      channel?.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "getInitialMixroomPath" {
          result(self.initialMixroomPath)
          self.initialMixroomPath = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {

    handleIncomingURL(url)
    return true
  }

  private func handleIncomingURL(_ url: URL) {
    // Only .mixroom files
    if !url.path.lowercased().hasSuffix(".mixroom") { return }

    // Security scoped (Files/iCloud providers)
    var didStartAccess = false
    if url.startAccessingSecurityScopedResource() {
      didStartAccess = true
    }
    defer {
      if didStartAccess { url.stopAccessingSecurityScopedResource() }
    }

    // Copy into temp so Flutter always has real filesystem access
    let tempDir = FileManager.default.temporaryDirectory
    let dest = tempDir.appendingPathComponent("incoming_\(UUID().uuidString).mixroom")

    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.copyItem(at: url, to: dest)
      deliverPath(dest.path)
    } catch {
      // fallback: try original path (might fail in Flutter if security scoped)
      deliverPath(url.path)
    }
  }

  private func deliverPath(_ path: String) {
    // if Flutter channel ready, emit immediately; else store for cold-start retrieval
    if let channel = channel {
      channel.invokeMethod("openMixroomPath", arguments: path)
    } else {
      initialMixroomPath = path
    }
  }
}
