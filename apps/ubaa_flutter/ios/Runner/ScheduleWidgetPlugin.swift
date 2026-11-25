import Flutter
import UIKit
import WidgetKit

final class WidgetLaunchInbox {
  private var pending: String?
  private var ready = false
  private var launch: ((String) -> Void)?

  func connect(launch: @escaping (String) -> Void) {
    ready = false
    self.launch = launch
  }

  func receive(_ url: URL) {
    let raw = url.absoluteString
    guard raw.hasPrefix("ubaa://widget/open?") else { return }
    if ready, let launch {
      launch(raw)
    } else {
      pending = raw
    }
  }

  func take() -> String? {
    ready = true
    let raw = pending
    pending = nil
    return raw
  }
}

/// 与 Android `WidgetChannel.kt` 同合同：`begin` 更换发布代次，
/// `publish` 提交课表投影并立即刷新全部桌面组件。
final class ScheduleWidgetPlugin: NSObject, FlutterPlugin {
  private static let launchInbox = WidgetLaunchInbox()
  private let store: ScheduleWidgetStore
  private let reload: () -> Void

  init(store: ScheduleWidgetStore = .shared, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
    self.store = store
    self.reload = reload
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let launchChannel = FlutterMethodChannel(
      name: "cn.edu.buaa.ubaa/widget-launch", binaryMessenger: registrar.messenger())
    launchInbox.connect { launchChannel.invokeMethod("launch", arguments: $0) }
    launchChannel.setMethodCallHandler { call, result in
      if call.method == "take" { result(launchInbox.take()) } else { result(FlutterMethodNotImplemented) }
    }
    registrar.addMethodCallDelegate(
      ScheduleWidgetPlugin(), channel: FlutterMethodChannel(
        name: "cn.edu.buaa.ubaa/schedule-widgets", binaryMessenger: registrar.messenger()))
  }

  static func receiveLaunch(_ url: URL) {
    launchInbox.receive(url)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    DispatchQueue.global(qos: .userInitiated).async {
      let reply: Any?
      do {
        switch call.method {
        case "begin":
          reply = try self.store.begin(owner: args["owner"] as? String)
        case "publish":
          guard let scope = args["scope"] as? String, !scope.isEmpty else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          guard let snapshot = args["snapshot"] as? [String: Any] else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          // 与 Android `check(WidgetStore.publish(...))` 一致：发布代次失效按存储失败处理。
          guard try self.store.publish(scope: scope, snapshotJSON: snapshot) else {
            throw ScheduleWidgetStore.StoreError.corrupt
          }
          reply = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async {
          self.reload()
          result(reply)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "widget_storage_failure",
              message: "桌面课表安全存储暂不可用", details: nil))
        }
      }
    }
  }
}
