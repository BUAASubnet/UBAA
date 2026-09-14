import Cocoa
import FlutterMacOS

protocol PlatformMethodHandler: AnyObject {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult)
}

/// macOS 统一平台通道的唯一拥有者，各能力只负责处理自己的方法。
final class PlatformChannel: NSObject {
  private let channel: FlutterMethodChannel
  private let photos: PlatformMethodHandler?
  private let credentials = CredentialHandler()

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "cn.edu.buaa.ubaa/platform", binaryMessenger: messenger)
    // 照片的系统版本要求不能限制独立的 Keychain 能力。
    if #available(macOS 11.0, *) {
      photos = PhotoHandler(window: window)
    } else {
      photos = nil
    }
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      if call.method.hasPrefix("credentials.") {
        self.credentials.handle(call, result: result)
      } else if let photos = self.photos {
        photos.handle(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
