import Flutter
import UIKit

final class EdgeDeferringFlutterViewController: FlutterViewController {
  private var defersSystemEdges = false

  func setSystemGestureDeferralEnabled(_ enabled: Bool) {
    guard defersSystemEdges != enabled else { return }
    defersSystemEdges = enabled
    setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    setNeedsUpdateOfHomeIndicatorAutoHidden()
  }

  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
    defersSystemEdges ? [.left, .right, .bottom] : []
  }

  override var prefersHomeIndicatorAutoHidden: Bool {
    defersSystemEdges
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    setNeedsUpdateOfHomeIndicatorAutoHidden()
  }
}
