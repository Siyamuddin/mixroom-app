import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
