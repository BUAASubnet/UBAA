import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // 首帧前的窗口底色按保存的主题与 Flutter surface 一致，避免启动时闪色。
    let background = MainFlutterWindow.launchBackground(appearance: effectiveAppearance)
    flutterViewController.backgroundColor = background
    backgroundColor = background
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    title = "UBAA"
  }

  /// 偏好键与 Dart 端 ThemePreferenceStore 一致；未保存时跟随系统外观。
  private static func launchBackground(appearance: NSAppearance) -> NSColor {
    let dark: Bool
    switch UserDefaults.standard.string(forKey: "flutter.ubaa.preferences.theme") {
    case "dark": dark = true
    case "light": dark = false
    default: dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    return dark
      ? NSColor(srgbRed: 0x11 / 255.0, green: 0x1C / 255.0, blue: 0x29 / 255.0, alpha: 1)
      : NSColor(srgbRed: 0xFC / 255.0, green: 0xFD / 255.0, blue: 0xFF / 255.0, alpha: 1)
  }
}
