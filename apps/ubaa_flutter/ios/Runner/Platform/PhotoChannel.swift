import Flutter
import PhotosUI
import UniformTypeIdentifiers

/// PHPicker 的界面和访问授权由系统提供；只读取用户选中的单张图片。
@available(iOS 14.0, *)
final class PhotoChannel: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar
  private var pending: FlutterResult?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "cn.edu.buaa.ubaa/platform", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "photo.capability": result(true)
    case "permission.request":
      // 允许请求系统选择器不等于拥有相册访问权；取消不会交付任何数据。
      result(call.arguments as? String == "photos" ? "granted" : "unavailable")
    case "photo.pick":
      guard pending == nil, let presenter = registrar.viewController,
            presenter.presentedViewController == nil else {
        result(FlutterError(code: "photo_busy", message: "图片选择器暂不可用", details: nil))
        return
      }
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      config.preferredAssetRepresentationMode = .current
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      pending = result
      presenter.present(picker, animated: true)
      picker.presentationController?.delegate = self
    default: result(FlutterMethodNotImplemented)
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else { finish(nil); return }
    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
      guard error == nil, let url = url else { self.failed(); return }
      do {
        // 系统临时 URL 只在回调内有效；当场读取，绝不保存 URL 或复制到持久目录。
        let photo = try PhotoPayload.read(url, suggestedName: provider.suggestedName)
        self.finish(["bytes": FlutterStandardTypedData(bytes: photo.bytes),
                     "fileName": photo.fileName, "mimeType": photo.mimeType])
      } catch { self.failed() }
    }
  }

  private func failed() {
    finish(FlutterError(code: "photo_read_failed", message: "无法读取图片，请选择不超过10MiB的图片", details: nil))
  }

  private func finish(_ value: Any?) {
    DispatchQueue.main.async {
      let reply = self.pending
      self.pending = nil
      reply?(value)
    }
  }
}
