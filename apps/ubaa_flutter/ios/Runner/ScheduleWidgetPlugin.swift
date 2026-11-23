import Flutter
import UIKit
import WidgetKit

/// 与 Android `WidgetChannel.kt` 同合同：`begin` 更换发布代次，
/// `publish` 提交课表投影并立即刷新全部桌面组件。
final class ScheduleWidgetPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addMethodCallDelegate(
      ScheduleWidgetPlugin(), channel: FlutterMethodChannel(
        name: "cn.edu.buaa.ubaa/schedule-widgets", binaryMessenger: registrar.messenger()))
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    DispatchQueue.global(qos: .userInitiated).async {
      let reply: Any?
      do {
        switch call.method {
        case "begin":
          reply = try ScheduleWidgetStore.begin(owner: args["owner"] as? String)
        case "publish":
          guard let scope = args["scope"] as? String, !scope.isEmpty else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          guard let snapshot = args["snapshot"] as? [String: Any] else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          // 与 Android `check(WidgetStore.publish(...))` 一致：发布代次失效按存储失败处理。
          guard try ScheduleWidgetStore.publish(scope: scope, snapshotJSON: snapshot) else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          reply = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async {
          // 发布与撤销都立即换图，安全存储失效时不继续展示上一份课程。
          WidgetCenter.shared.reloadAllTimelines()
          result(reply)
        }
      } catch {
        DispatchQueue.main.async {
          WidgetCenter.shared.reloadAllTimelines()
          result(
            FlutterError(
              code: "widget_storage_failure",
              message: "桌面课表安全存储暂不可用", details: nil))
        }
      }
    }
  }
}
