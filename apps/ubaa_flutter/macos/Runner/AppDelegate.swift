import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    // 应用只允许单实例：同一用户已有实例时唤起它并退出，不再创建引擎。
    AppDelegate.yieldToRunningInstance()
    super.init()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private static func yieldToRunningInstance() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    let current = ProcessInfo.processInfo.processIdentifier
    let other = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).first { $0.processIdentifier != current && !$0.isTerminated }
    guard let other else { return }
    other.activate(options: [.activateAllWindows])
    exit(EXIT_SUCCESS)
  }
}
