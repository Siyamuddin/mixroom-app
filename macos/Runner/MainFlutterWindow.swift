import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let finderDropChannelName = "mixroom/finder_drop"
  private let titleBarDragRegionHeight: CGFloat = 34
  private var finderDropChannel: FlutterMethodChannel?
  private var pendingFinderDropPayloads: [[String: Any]] = []
  private let supportedAudioExtensions: Set<String> = [
    "wav",
    "wave",
    "aif",
    "aiff",
    "flac",
    "mp3",
    "m4a",
    "aac",
    "ogg",
    "opus"
  ]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    let minimumSize = NSSize(width: 1180, height: 720)
    self.minSize = minimumSize

    var frame = self.frame
    frame.size.width = max(frame.size.width, 1360)
    frame.size.height = max(frame.size.height, 820)
    self.setFrame(frame, display: true)
    self.center()
    self.title = ""
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.isMovableByWindowBackground = true
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    registerForDraggedTypes([.fileURL])
    bindFinderDropChannelIfNeeded(flutterViewController: flutterViewController)
  }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      if event.clickCount == 2 && isInTitleBarDragRegion(event.locationInWindow) {
        self.performZoom(nil)
        return
      }

      sendMouseDownWithTitleBarDragRegion(event)
    case .rightMouseDown, .otherMouseDown:
      sendMouseDownWithTitleBarDragRegion(event)
    default:
      super.sendEvent(event)
    }
  }

  private func sendMouseDownWithTitleBarDragRegion(_ event: NSEvent) {
    let previousMovableByBackground = self.isMovableByWindowBackground
    self.isMovableByWindowBackground = isInTitleBarDragRegion(event.locationInWindow)
    super.sendEvent(event)
    self.isMovableByWindowBackground = previousMovableByBackground
  }

  private func isInTitleBarDragRegion(_ location: NSPoint) -> Bool {
    location.y >= max(0, self.frame.height - titleBarDragRegionHeight)
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    hasSupportedFinderDropItems(sender.draggingPasteboard) ? .copy : []
  }

  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    hasSupportedFinderDropItems(sender.draggingPasteboard)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let payload = buildFinderDropPayload(from: sender.draggingPasteboard) else {
      return false
    }
    deliverFinderDropPayload(payload)
    return true
  }

  private func bindFinderDropChannelIfNeeded(flutterViewController: FlutterViewController) {
    if finderDropChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: finderDropChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getPendingFinderDrops" {
        result(self.pendingFinderDropPayloads)
        self.pendingFinderDropPayloads.removeAll()
        return
      }
      result(FlutterMethodNotImplemented)
    }
    finderDropChannel = channel
  }

  private func hasSupportedFinderDropItems(_ pasteboard: NSPasteboard) -> Bool {
    guard let items = buildFinderDropItems(from: pasteboard) else {
      return false
    }
    return !items.isEmpty
  }

  private func buildFinderDropPayload(from pasteboard: NSPasteboard) -> [String: Any]? {
    guard let items = buildFinderDropItems(from: pasteboard), !items.isEmpty else {
      return nil
    }
    return [
      "source": "finder",
      "items": items
    ]
  }

  private func buildFinderDropItems(from pasteboard: NSPasteboard) -> [[String: Any]]? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
      return nil
    }

    return urls.compactMap { url in
      let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
      if path.isEmpty {
        return nil
      }

      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      if !exists {
        return nil
      }

      let kind: String
      if path.lowercased().hasSuffix(".mixroom") {
        kind = "mixroom"
      } else if isDirectory.boolValue {
        kind = "folder"
      } else if supportedAudioExtensions.contains(url.pathExtension.lowercased()) {
        kind = "audio"
      } else {
        return nil
      }

      return [
        "path": path,
        "kind": kind,
        "isDirectory": isDirectory.boolValue
      ]
    }
  }

  private func deliverFinderDropPayload(_ payload: [String: Any]) {
    if let finderDropChannel = finderDropChannel {
      finderDropChannel.invokeMethod("deliverFinderDrop", arguments: payload)
    } else {
      pendingFinderDropPayloads.append(payload)
    }
  }
}
