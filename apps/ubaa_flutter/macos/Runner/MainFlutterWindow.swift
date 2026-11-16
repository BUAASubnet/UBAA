import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var reportChannel: FlutterMethodChannel?
  private var reportPicker: NSSharingServicePicker?

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
    reportChannel = FlutterMethodChannel(name: "cn.edu.buaa.ubaa/agenda-file", binaryMessenger: flutterViewController.engine.binaryMessenger)
    reportChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareReport" else { result(FlutterMethodNotImplemented); return }
      guard let self, let view = self.contentView,
        let args = call.arguments as? [String: Any], let name = args["name"] as? String,
        name.range(of: "^UBAA-report-[0-9]+\\.json$", options: .regularExpression) != nil,
        let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid", message: "错误报告不可用", details: nil)); return
      }
      do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic_reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
          if let date = try old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            date < Date().addingTimeInterval(-7 * 86400) { try? FileManager.default.removeItem(at: old) }
        }
        let file = directory.appendingPathComponent(name)
        try bytes.data.write(to: file, options: .atomic)
        let picker = NSSharingServicePicker(items: [file])
        self.reportPicker = picker
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
        result(nil)
      } catch { result(FlutterError(code: "share_failed", message: "无法分享错误报告", details: nil)) }
    }

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
