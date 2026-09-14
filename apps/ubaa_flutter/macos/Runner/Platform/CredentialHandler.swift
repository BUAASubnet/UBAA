import FlutterMacOS
import Foundation

/// 凭据处理器不注册通道；系统存储在独立串行队列执行，避免阻塞主线程。
final class CredentialHandler: PlatformMethodHandler {
  private let store = KeychainCredentialStore()
  private let queue = DispatchQueue(label: "cn.edu.buaa.ubaa.credentials")

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "credentials.capability" {
      result(true)
      return
    }
    guard ["credentials.read", "credentials.write", "credentials.clear"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    queue.async {
      let reply: Any?
      do {
        switch call.method {
        case "credentials.read": reply = try self.store.read(call.arguments)
        case "credentials.write":
          try self.store.write(call.arguments)
          reply = nil
        default:
          try self.store.clear(call.arguments)
          reply = nil
        }
      } catch {
        let failure = error as? CredentialStoreFailure ?? .storageFailure
        reply = FlutterError(code: failure.rawValue, message: failure.message, details: nil)
      }
      DispatchQueue.main.async { result(reply) }
    }
  }
}
