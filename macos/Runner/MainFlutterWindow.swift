import Cocoa
import FlutterMacOS

/// Transparent overlay that receives Finder file drags while letting normal
/// mouse/trackpad events pass through to Flutter (`hitTest` returns nil).
private final class FinderDropSurfaceView: NSView {
  weak var owner: MainFlutterWindow?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Pointer events pass through to Flutter. AppKit still queries this view
    // for drag destinations because it registered dragged types.
    return nil
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    owner?.handleDraggingEntered(sender) ?? []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    owner?.handleDraggingUpdated(sender) ?? []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    owner?.handleDraggingExited(sender)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    owner?.handlePrepareForDragOperation(sender) ?? false
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    owner?.handlePerformDragOperation(sender) ?? false
  }
}

class MainFlutterWindow: NSWindow {
  private let finderDropChannelName = "mixroom/finder_drop"
  private let titleBarDragRegionHeight: CGFloat = 34
  private weak var flutterViewController: FlutterViewController?
  private var finderDropChannel: FlutterMethodChannel?
  private var pendingFinderDropPayloads: [[String: Any]] = []
  private var dropSurfaceView: FinderDropSurfaceView?
  private var cachedDragItems: [[String: Any]] = []
  private var lastDragUpdateUptime: TimeInterval = 0
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
    self.flutterViewController = flutterViewController
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
    bindFinderDropChannelIfNeeded(flutterViewController: flutterViewController)
    installFinderDropSurface(on: flutterViewController.view)
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

  private func installFinderDropSurface(on flutterView: NSView) {
    dropSurfaceView?.removeFromSuperview()
    let surface = FinderDropSurfaceView(frame: flutterView.bounds)
    surface.autoresizingMask = [.width, .height]
    surface.owner = self
    flutterView.addSubview(surface, positioned: .above, relativeTo: nil)
    dropSurfaceView = surface
  }

  func handleDraggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let items = buildFinderDropItems(from: sender.draggingPasteboard), !items.isEmpty else {
      cachedDragItems = []
      return []
    }
    cachedDragItems = items
    if let payload = buildFinderDragPayload(items: items, sender: sender) {
      invokeFinderMethod("finderDragEntered", arguments: payload)
    }
    return .copy
  }

  func handleDraggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let items: [[String: Any]]
    if !cachedDragItems.isEmpty {
      items = cachedDragItems
    } else if let built = buildFinderDropItems(from: sender.draggingPasteboard), !built.isEmpty {
      cachedDragItems = built
      items = built
    } else {
      return []
    }

    // Throttle Flutter updates so we don't flood the platform channel.
    let now = ProcessInfo.processInfo.systemUptime
    if now - lastDragUpdateUptime >= 0.016 {
      lastDragUpdateUptime = now
      if let payload = buildFinderDragPayload(items: items, sender: sender) {
        invokeFinderMethod("finderDragUpdated", arguments: payload)
      }
    }
    return .copy
  }

  func handleDraggingExited(_ sender: NSDraggingInfo?) {
    cachedDragItems = []
    lastDragUpdateUptime = 0
    invokeFinderMethod(
      "finderDragExited",
      arguments: [
        "source": "finder"
      ]
    )
  }

  func handlePrepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    if !cachedDragItems.isEmpty {
      return true
    }
    return !(buildFinderDropItems(from: sender.draggingPasteboard)?.isEmpty ?? true)
  }

  func handlePerformDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let items: [[String: Any]]
    if !cachedDragItems.isEmpty {
      items = cachedDragItems
    } else if let built = buildFinderDropItems(from: sender.draggingPasteboard), !built.isEmpty {
      items = built
    } else {
      return false
    }
    guard let payload = buildFinderDragPayload(items: items, sender: sender) else {
      return false
    }
    cachedDragItems = []
    lastDragUpdateUptime = 0
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

  private func buildFinderDragPayload(
    items: [[String: Any]],
    sender: NSDraggingInfo
  ) -> [String: Any]? {
    if items.isEmpty {
      return nil
    }
    var payload: [String: Any] = [
      "source": "finder",
      "items": items
    ]
    if let location = flutterLocation(from: sender) {
      payload["location"] = location
    }
    return payload
  }

  private func flutterLocation(from sender: NSDraggingInfo) -> [String: Double]? {
    guard let view = flutterViewController?.view else {
      return nil
    }
    let locationInView = view.convert(sender.draggingLocation, from: nil)
    // Flutter's macOS view is flipped on current embeddings, while AppKit's
    // traditional views are not. Convert only when necessary so Finder drops
    // retain the cursor's actual row instead of vertically mirroring it.
    let flutterY = view.isFlipped
      ? locationInView.y
      : view.bounds.height - locationInView.y
    return [
      "x": Double(locationInView.x),
      "y": Double(flutterY)
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
      if url.isFileURL {
        _ = url.startAccessingSecurityScopedResource()
      }
      let resolved = url.standardizedFileURL
      let path = resolved.path.trimmingCharacters(in: .whitespacesAndNewlines)
      if path.isEmpty {
        return nil
      }

      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      // During drag, some providers briefly omit filesystem presence; still
      // accept known audio / project extensions so the cursor stays as copy.
      let ext = resolved.pathExtension.lowercased()
      let looksLikeMixroom = path.lowercased().hasSuffix(".mixroom")
      let looksLikeAudio = supportedAudioExtensions.contains(ext)
      if !exists && !looksLikeMixroom && !looksLikeAudio && !isDirectory.boolValue {
        return nil
      }

      let kind: String
      if looksLikeMixroom {
        kind = "mixroom"
      } else if exists && isDirectory.boolValue {
        kind = "folder"
      } else if looksLikeAudio {
        kind = "audio"
      } else {
        return nil
      }

      return [
        "path": path,
        "kind": kind,
        "isDirectory": exists && isDirectory.boolValue
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

  private func invokeFinderMethod(_ method: String, arguments: [String: Any]) {
    finderDropChannel?.invokeMethod(method, arguments: arguments)
  }
}
