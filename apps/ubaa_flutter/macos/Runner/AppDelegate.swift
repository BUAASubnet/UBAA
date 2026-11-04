import Cocoa
import Darwin
import FlutterMacOS

class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(activateGUI),
      name: Notification.Name("cn.edu.ubaa.activate_gui"), object: String(geteuid()))
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @objc private func activateGUI() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
  }
}
