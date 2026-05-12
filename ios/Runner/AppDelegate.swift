import Flutter
import UIKit
import AVFAudio

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentInteractionControllerDelegate {

  private let channelName = "mixroom/open_file"
  private var channel: FlutterMethodChannel?
  private var hapticsChannel: FlutterMethodChannel?
  private var edgeGesturesChannel: FlutterMethodChannel?
  private var savedExportsChannel: FlutterMethodChannel?
  private var savedExportDocumentController: UIDocumentInteractionController?
  private var savedExportScopedURL: URL?
  private var initialMixroomPath: String?
  private var initialMixroomUrl: String?
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
    if handleIncomingURL(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    if isMixroomEducationInviteURL(url) {
      deliverURL(url.absoluteString)
      return true
    }

    // Only .mixroom file imports are handled here. OAuth/AppAuth callbacks
    // must keep flowing through Flutter/plugin delegates.
    if !url.path.lowercased().hasSuffix(".mixroom") { return false }

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
    return true
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

  private func deliverURL(_ url: String) {
    bindChannelsIfNeeded()
    initialMixroomUrl = url
    if let channel = channel {
      channel.invokeMethod("openMixroomUrl", arguments: url)
    } else {
      initialMixroomUrl = url
    }
  }

  private func isMixroomEducationInviteURL(_ url: URL) -> Bool {
    guard url.scheme == "mixroom", url.host == "education" else { return false }
    return url.pathComponents.dropFirst().first == "invites"
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
    savedExportsChannel = FlutterMethodChannel(
      name: "mixroom/saved_exports",
      binaryMessenger: messenger
    )

    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getInitialMixroomPath" {
        result(self.initialMixroomPath)
        self.initialMixroomPath = nil
      } else if call.method == "getInitialMixroomUrl" {
        result(self.initialMixroomUrl)
        self.initialMixroomUrl = nil
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

    savedExportsChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      guard call.method == "openSavedExport" || call.method == "shareSavedExport" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(false)
        return
      }
      if call.method == "shareSavedExport" {
        self.shareSavedExport(path: path, result: result)
      } else {
        self.openSavedExport(path: path, result: result)
      }
    }

    channelsInitialized = true
  }

  private func openSavedExport(path: String, result: @escaping FlutterResult) {
    guard let url = resolvedSavedExportURL(path: path),
          let presenter = topPresentingViewController() else {
      result(false)
      return
    }

    DispatchQueue.main.async {
      let didStartAccess = self.startAccessingSavedExportIfNeeded(url: url)
      if !self.savedExportExists(url: url) {
        self.stopAccessingSavedExportIfNeeded(url: url, didStartAccess: didStartAccess)
        result(false)
        return
      }

      UIApplication.shared.open(url, options: [:]) { success in
        if success {
          self.stopAccessingSavedExportIfNeeded(url: url, didStartAccess: didStartAccess)
          result(true)
          return
        }
        self.presentSavedExportOptions(
          url: url,
          presenter: presenter,
          didStartAccess: didStartAccess,
          result: result
        )
      }
    }
  }

  private func shareSavedExport(path: String, result: @escaping FlutterResult) {
    guard let url = resolvedSavedExportURL(path: path),
          let presenter = topPresentingViewController() else {
      result(false)
      return
    }

    DispatchQueue.main.async {
      let didStartAccess = self.startAccessingSavedExportIfNeeded(url: url)
      if !self.savedExportExists(url: url) {
        self.stopAccessingSavedExportIfNeeded(url: url, didStartAccess: didStartAccess)
        result(false)
        return
      }

      let activityViewController = UIActivityViewController(
        activityItems: [url],
        applicationActivities: nil
      )
      activityViewController.completionWithItemsHandler = { _, _, _, _ in
        self.stopAccessingSavedExportIfNeeded(url: url, didStartAccess: didStartAccess)
      }
      if let popover = activityViewController.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 1,
          height: 1
        )
        popover.permittedArrowDirections = []
      }

      presenter.present(activityViewController, animated: true)
      result(true)
    }
  }

  private func resolvedSavedExportURL(path: String) -> URL? {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return nil
    }
    if let url = URL(string: trimmed), url.scheme != nil {
      return url
    }
    if trimmed.hasPrefix("/") {
      return URL(fileURLWithPath: trimmed)
    }
    return nil
  }

  private func topPresentingViewController() -> UIViewController? {
    var current = currentFlutterViewController() ?? window?.rootViewController
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }

  private func startAccessingSavedExportIfNeeded(url: URL) -> Bool {
    guard url.isFileURL else { return false }
    return url.startAccessingSecurityScopedResource()
  }

  private func stopAccessingSavedExportIfNeeded(url: URL, didStartAccess: Bool) {
    guard didStartAccess, url.isFileURL else { return }
    url.stopAccessingSecurityScopedResource()
  }

  private func savedExportExists(url: URL) -> Bool {
    if !url.isFileURL {
      return true
    }
    return FileManager.default.fileExists(atPath: url.path)
  }

  private func presentSavedExportOptions(
    url: URL,
    presenter: UIViewController,
    didStartAccess: Bool,
    result: @escaping FlutterResult
  ) {
    let controller = UIDocumentInteractionController(url: url)
    controller.delegate = self
    savedExportDocumentController = controller
    savedExportScopedURL = didStartAccess ? url : nil

    if controller.presentPreview(animated: true) {
      result(true)
      return
    }

    if controller.presentOptionsMenu(from: presenter.view.bounds, in: presenter.view, animated: true) {
      result(true)
      return
    }

    releaseSavedExportDocumentController()
    result(false)
  }

  private func releaseSavedExportDocumentController() {
    if let url = savedExportScopedURL {
      url.stopAccessingSecurityScopedResource()
    }
    savedExportScopedURL = nil
    savedExportDocumentController = nil
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return topPresentingViewController()
      ?? currentFlutterViewController()
      ?? window?.rootViewController
      ?? UIViewController()
  }

  func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
    releaseSavedExportDocumentController()
  }

  func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
    releaseSavedExportDocumentController()
  }

  func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
    releaseSavedExportDocumentController()
  }
}
