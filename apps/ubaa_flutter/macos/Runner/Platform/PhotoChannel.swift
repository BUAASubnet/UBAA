import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// 系统选择器只授权用户选定文件，不请求整库访问，也不写入原文件。
@available(macOS 11.0, *)
final class PhotoChannel: NSObject {
  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var pending: FlutterResult?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    self.channel = FlutterMethodChannel(name: "cn.edu.buaa.ubaa/platform", binaryMessenger: messenger)
    self.window = window
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "photo.capability": result(true)
    case "permission.request":
      // granted 表示可请求系统选择；文件读取权由 OpenPanel 的用户选择授予。
      result(call.arguments as? String == "photos" ? "granted" : "unavailable")
    case "photo.pick":
      guard pending == nil, let window = window else {
        result(FlutterError(code: "photo_busy", message: "图片选择器暂不可用", details: nil))
        return
      }
      pending = result
      let panel = NSOpenPanel()
      panel.title = "选择图片"
      panel.prompt = "选择"
      panel.allowedContentTypes = [.image]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.beginSheetModal(for: window) { [weak self] response in
        guard let self = self else { return }
        guard response == .OK, let url = panel.url else { self.finish(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          do {
            let photo = try PhotoPayload.read(url)
            self.finish(["bytes": FlutterStandardTypedData(bytes: photo.bytes),
                         "fileName": photo.fileName, "mimeType": photo.mimeType])
          } catch {
            self.finish(FlutterError(code: "photo_read_failed", message: "无法读取图片，请选择不超过10MiB的图片", details: nil))
          }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func finish(_ value: Any?) {
    DispatchQueue.main.async {
      let reply = self.pending
      self.pending = nil
      reply?(value)
    }
  }
}
