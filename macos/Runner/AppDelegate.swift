import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "mixroom/open_file"
  private var channel: FlutterMethodChannel?
  private var initialMixroomPath: String?
  private var channelsInitialized = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    bindChannelsIfNeeded()
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for path in filenames {
      if handleIncomingPath(path) {
        sender.reply(toOpenOrPrint: .success)
        return
      }
    }
    sender.reply(toOpenOrPrint: .failure)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @discardableResult
  private func handleIncomingPath(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || !trimmed.lowercased().hasSuffix(".mixroom") {
      return false
    }
    deliverPath(trimmed)
    return true
  }

  private func deliverPath(_ path: String) {
    bindChannelsIfNeeded()
    if let channel = channel {
      channel.invokeMethod("openMixroomPath", arguments: path)
    } else {
      initialMixroomPath = path
    }
  }

  private func bindChannelsIfNeeded() {
    if channelsInitialized { return }
    guard
      let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      return
    }

    channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
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
    channelsInitialized = true
  }
}
