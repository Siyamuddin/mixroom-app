import Cocoa
import Darwin
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  #if DEBUG
  private func runProbe(_ symbolName: String) throws -> UInt32 {
    let processHandle = dlopen(nil, RTLD_NOW)
    XCTAssertNotNil(processHandle)
    guard let processHandle else { return 0 }
    let symbol = symbolName.withCString { dlsym(processHandle, $0) }
    guard let symbol else {
      XCTFail("Missing regression probe: \(symbolName)")
      return 0
    }

    typealias Probe = @convention(c) () -> UInt32
    let probe = unsafeBitCast(symbol, to: Probe.self)
    return probe()
  }

  func testHostedPluginWindowCleanupRegressionProbe() throws {
    let result = try runProbe(
      "mixroomRunHostedPluginWindowCleanupRegressionProbe"
    )

    XCTAssertEqual(
      result,
      0x7f,
      "The probe must clean ordinary, sheet, and modal auxiliaries while preserving primary, unrelated, and Flutter host windows"
    )
  }

  func testHostedPluginWindowCaptureRegressionProbe() throws {
    let result = try runProbe(
      "mixroomRunHostedPluginWindowCaptureRegressionProbe"
    )

    XCTAssertEqual(
      result,
      0x1ff,
      "The capture probe must handle JUCE auxiliaries, close-driven modals, and nested capture without claiming unrelated or Flutter windows"
    )
  }

  func testHostedPluginEditorLifetimeRegressionProbe() throws {
    var primaryCloseNotifications = 0
    let closeObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("MixroomHostedPluginEditorSpacebarNotification"),
      object: nil,
      queue: .main
    ) { notification in
      if notification.userInfo?["event"] as? String == "pluginEditorClosed" {
        primaryCloseNotifications += 1
      }
    }
    defer { NotificationCenter.default.removeObserver(closeObserver) }

    let result = try runProbe(
      "mixroomRunHostedPluginEditorLifetimeRegressionProbe"
    )

    XCTAssertEqual(
      result,
      0x1f,
      "The lifetime probe must retain processors, ignore stale close callbacks, destroy editors first, and release capture during exception unwinding"
    )
    XCTAssertEqual(
      primaryCloseNotifications,
      2,
      "Each genuinely destroyed primary editor must emit exactly one close notification"
    )
  }
  #endif

}
