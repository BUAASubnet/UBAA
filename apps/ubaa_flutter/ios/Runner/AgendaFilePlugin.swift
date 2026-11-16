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
  private var batchFolder = false
  private var writingFolder = false

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AgendaFilePlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "cn.edu.buaa.ubaa/agenda-file", binaryMessenger: registrar.messenger()))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "shareReport":
      guard let presenter = registrar.viewController, presenter.presentedViewController == nil,
        let name = args["name"] as? String, name.range(of: "^UBAA-report-[0-9]+\\.json$", options: .regularExpression) != nil,
        let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "unavailable", message: "无法分享错误报告", details: nil)); return
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
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        // iPad 的分享面板必须提供锚点。
        share.popoverPresentationController?.sourceView = presenter.view
        share.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        share.completionWithItemsHandler = { _, _, _, error in
          if error != nil { result(FlutterError(code: "share_failed", message: "无法分享错误报告", details: nil)) }
          else { result(nil) }
        }
        presenter.present(share, animated: true)
      } catch { result(FlutterError(code: "share_failed", message: "无法分享错误报告", details: nil)) }

    case "selectFolder", "select":
      guard pending == nil, target == nil,
        let presenter = registrar.viewController else {
        result(FlutterError(code: "unavailable", message: "无法打开保存面板", details: nil)); return
      }
      let folder = call.method == "selectFolder"
      let fileName = args["name"] as? String ?? ""
      guard folder || (!fileName.isEmpty && !fileName.contains("/")) else {
        result(FlutterError(code: "invalid", message: "文件名无效", details: nil)); return
      }
      batchFolder = folder
      self.name = fileName
      binarySelection = folder || args["kind"] as? String == "binary"
      pending = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.title = binarySelection ? "选择保存文件夹" : "选择日历保存文件夹"
      presenter.present(picker, animated: true)
    case "writeFolderFile", "writeFile", "write", "discardFolder", "discard":
      let folderCall = call.method == "writeFolderFile" || call.method == "discardFolder"
      guard let directory = target, !writingFolder, batchFolder == folderCall,
        args["selection"] as? String == String(selection) else {
        result(FlutterError(code: "expired", message: "保存位置已失效", details: nil)); return
      }
      if !batchFolder || call.method == "discardFolder" { target = nil }
      if call.method == "discard" || call.method == "discardFolder" { result(nil); return }
      if call.method == "writeFile" || call.method == "writeFolderFile" {
        let fileName = folderCall ? (args["name"] as? String ?? "") : name
        guard let path = args["path"] as? String, !fileName.isEmpty,
          !fileName.contains("/"), fileName != ".", fileName != ".." else {
          result(FlutterError(code: "invalid", message: "缺少本机文件或文件名无效", details: nil)); return
        }
        writingFolder = true
        DispatchQueue.global(qos: .userInitiated).async {
          let scoped = directory.startAccessingSecurityScopedResource()
          defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
          let outcome: Any?
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
            outcome = folderCall ? destination.lastPathComponent : nil
          } catch {
            outcome = FlutterError(code: "write_failed", message: "文件未保存", details: nil)
          }
          DispatchQueue.main.async {
            self.writingFolder = false
            result(outcome)
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
