import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var photoChannel: NSObject?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if #available(macOS 11.0, *) {
      photoChannel = PhotoChannel(messenger: flutterViewController.engine.binaryMessenger, window: self)
    }

    super.awakeFromNib()
  }
}
