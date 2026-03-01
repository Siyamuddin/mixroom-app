import Flutter
import UIKit
import AVFAudio

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let channelName = "mixroom/open_file"
  private var channel: FlutterMethodChannel?
  private var hapticsChannel: FlutterMethodChannel?
  private var edgeGesturesChannel: FlutterMethodChannel?
  private var initialMixroomPath: String?
  private var didAttemptHapticsAudioSessionConfig = false
  private var channelsInitialized = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    bindChannelsIfNeeded()
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

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
  }

  func handleIncomingURL(_ url: URL) {
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
    bindChannelsIfNeeded()
    // if Flutter channel ready, emit immediately; else store for cold-start retrieval
    if let channel = channel {
      channel.invokeMethod("openMixroomPath", arguments: path)
    } else {
      initialMixroomPath = path
    }
  }

  private func performHapticImpact(style: String) {
    DispatchQueue.main.async {
      self.configureHapticsForAudioSession()

      let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
      switch style {
      case "heavy":
        feedbackStyle = .heavy
      case "medium":
        feedbackStyle = .medium
      default:
        feedbackStyle = .light
      }

      let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
      generator.prepare()
      generator.impactOccurred()
    }
  }

  private func configureHapticsForAudioSession() {
    guard #available(iOS 13.0, *) else { return }
    if didAttemptHapticsAudioSessionConfig { return }
    didAttemptHapticsAudioSessionConfig = true
    do {
      try AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    } catch {
      NSLog("mixroom: failed to enable haptics during recording: \(error)")
    }
  }

  private func setSystemGestureDeferral(enabled: Bool) {
    DispatchQueue.main.async {
      guard let vc = self.currentEdgeDeferringFlutterViewController() else { return }
      vc.setSystemGestureDeferralEnabled(enabled)
    }
  }

  private func currentFlutterViewController() -> FlutterViewController? {
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }

        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
           let vc = keyWindow.rootViewController as? FlutterViewController {
          return vc
        }

        if let vc = windowScene.windows
          .compactMap({ $0.rootViewController as? FlutterViewController })
          .first {
          return vc
        }
      }
    }

    return window?.rootViewController as? FlutterViewController
  }

  private func currentEdgeDeferringFlutterViewController()
    -> EdgeDeferringFlutterViewController?
  {
    return currentFlutterViewController() as? EdgeDeferringFlutterViewController
  }

  private func bindChannelsIfNeeded() {
    if channelsInitialized { return }
    guard let registrar = self.registrar(forPlugin: "mixroom_app_delegate_channels") else {
      return
    }
    let messenger = registrar.messenger()

    channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    hapticsChannel = FlutterMethodChannel(name: "mixroom/haptics", binaryMessenger: messenger)
    edgeGesturesChannel = FlutterMethodChannel(
      name: "mixroom/edge_gestures",
      binaryMessenger: messenger
    )

    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getInitialMixroomPath" {
        result(self.initialMixroomPath)
        self.initialMixroomPath = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    hapticsChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "App delegate released", details: nil))
        return
      }

      guard call.method == "impact" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let args = call.arguments as? [String: Any]
      let style = (args?["style"] as? String) ?? "light"
      self.performHapticImpact(style: style)
      result(nil)
    }

    edgeGesturesChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "App delegate released", details: nil))
        return
      }

      guard call.method == "setDeferred" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      self.setSystemGestureDeferral(enabled: enabled)
      result(nil)
    }

    channelsInitialized = true
  }
}
