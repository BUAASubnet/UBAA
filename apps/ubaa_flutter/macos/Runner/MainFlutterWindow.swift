import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var platformChannel: PlatformChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    platformChannel = PlatformChannel(messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }
}
