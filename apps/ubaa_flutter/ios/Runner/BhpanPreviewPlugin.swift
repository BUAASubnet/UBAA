import Flutter
import QuickLook
import UIKit

/// 使用 Quick Look 打开本机临时文件，并在用户关闭预览后完成通道调用。
final class BhpanPreviewPlugin: NSObject, FlutterPlugin, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private let registrar: FlutterPluginRegistrar
  private var pending: FlutterResult?
  private var previewURL: URL?

  init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BhpanPreviewPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "cn.edu.buaa.ubaa/bhpan-preview", binaryMessenger: registrar.messenger()))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "preview" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending == nil,
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String,
      FileManager.default.fileExists(atPath: path),
      let presenter = registrar.viewController else {
      result(FlutterError(code: "unavailable", message: "无法打开系统预览", details: nil))
      return
    }

    previewURL = URL(fileURLWithPath: path)
    pending = result
    let preview = QLPreviewController()
    preview.dataSource = self
    preview.delegate = self
    preview.modalPresentationStyle = .fullScreen
    presenter.present(preview, animated: true)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    previewURL! as NSURL
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    finish()
  }

  private func finish() {
    let callback = pending
    pending = nil
    previewURL = nil
    callback?(nil)
  }
}
