import Flutter
import UIKit
import UniformTypeIdentifiers

/// 先选择文件夹，收到 Dart 的保存请求后才创建日历文件。
final class AgendaFilePlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private let registrar: FlutterPluginRegistrar
  private var pending: FlutterResult?
  private var target: URL?
  private var name = ""
  private var selection = 0
  private var binarySelection = false

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AgendaFilePlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "cn.edu.buaa.ubaa/agenda-file", binaryMessenger: registrar.messenger()))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "select":
      guard pending == nil, target == nil,
        let name = args["name"] as? String, !name.contains("/"), !name.isEmpty,
        let presenter = registrar.viewController else {
        result(FlutterError(code: "unavailable", message: "无法打开保存面板", details: nil)); return
      }
      self.name = name
      binarySelection = args["kind"] as? String == "binary"
      pending = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.title = binarySelection ? "选择保存文件夹" : "选择日历保存文件夹"
      presenter.present(picker, animated: true)
    case "write", "writeFile", "discard":
      guard let directory = target, args["selection"] as? String == String(selection) else {
        result(FlutterError(code: "expired", message: "保存位置已失效", details: nil)); return
      }
      target = nil
      if call.method == "discard" { result(nil); return }
      if call.method == "writeFile" {
        guard let path = args["path"] as? String else {
          result(FlutterError(code: "invalid", message: "缺少本机文件", details: nil)); return
        }
        let fileName = name
        let scoped = directory.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
          defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
          do {
            var destination = directory.appendingPathComponent(fileName)
            var suffix = 1
            let base = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            while FileManager.default.fileExists(atPath: destination.path) {
              let candidate = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
              destination = directory.appendingPathComponent(candidate)
              suffix += 1
            }
            let temporary = directory.appendingPathComponent(".ubaa-\(UUID().uuidString).part")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: temporary)
            try FileManager.default.moveItem(at: temporary, to: destination)
            DispatchQueue.main.async { result(nil) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "write_failed", message: "文件未保存", details: nil)) }
          }
        }
        return
      }
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalid", message: "缺少日历内容", details: nil)); return
      }
      let scoped = directory.startAccessingSecurityScopedResource()
      defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
      do {
        var destination = directory.appendingPathComponent(name)
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) {
          destination = directory.appendingPathComponent("\((name as NSString).deletingPathExtension) (\(suffix)).ics")
          suffix += 1
        }
        try bytes.data.write(to: destination, options: .withoutOverwriting)
        result(nil)
      } catch {
        result(FlutterError(code: "write_failed", message: "日历文件未保存", details: nil))
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    target = urls.first
    selection += 1
    let result = pending
    pending = nil
    result?(target == nil ? nil : String(selection))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending
    pending = nil
    result?(nil)
  }
}
