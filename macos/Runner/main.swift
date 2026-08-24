import Cocoa
import Darwin

@_silgen_name("MixroomPluginScanChildMain")
private func MixroomPluginScanChildMain(
  _ formatName: UnsafePointer<CChar>,
  _ pluginIdentifier: UnsafePointer<CChar>,
  _ outputPath: UnsafePointer<CChar>
) -> Int32

let arguments = ProcessInfo.processInfo.arguments
if let marker = arguments.firstIndex(of: "--mixroom-plugin-scan-child"),
   marker + 3 < arguments.count {
  let status = arguments[marker + 1].withCString { formatName in
    arguments[marker + 2].withCString { pluginIdentifier in
      arguments[marker + 3].withCString { outputPath in
        MixroomPluginScanChildMain(formatName, pluginIdentifier, outputPath)
      }
    }
  }
  fflush(stdout)
  fflush(stderr)
  Darwin._exit(status)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
