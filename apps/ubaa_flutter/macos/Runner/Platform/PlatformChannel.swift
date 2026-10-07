import Cocoa
import FlutterMacOS

protocol PlatformMethodHandler: AnyObject {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult)
}

/// macOS 统一平台通道的唯一拥有者，各能力只负责处理自己的方法。
final class PlatformChannel: NSObject {
  private let channel: FlutterMethodChannel
  private let photos: PlatformMethodHandler?

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "cn.edu.buaa.ubaa/platform", binaryMessenger: messenger)
    // 照片能力由宿主版本决定，安全存储交给独立插件注册。
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
      if let photos = self.photos {
        photos.handle(call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
