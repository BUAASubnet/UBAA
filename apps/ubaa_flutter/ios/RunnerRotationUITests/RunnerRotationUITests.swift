import XCTest

/// 原生旋转由 XCTest 执行；回环端口仅交换显式测试的阶段标记。
final class RunnerRotationUITests: XCTestCase {
  private func readMarker(runId: String) -> String? {
    let completed = DispatchSemaphore(value: 0)
    var marker: String?
    var request = URLRequest(url: URL(string: "http://127.0.0.1:48763/rotation-marker")!)
    request.timeoutInterval = 2
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
      if let data = data,
         let record = try? JSONSerialization.jsonObject(with: data) as? [String: String],
         record["runId"] == runId {
        marker = record["phase"]
      }
      completed.signal()
    }
    task.resume()
    if completed.wait(timeout: .now() + 3) == .timedOut { task.cancel() }
    return marker
  }

  private func waitMarker(_ expected: String, runId: String, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if readMarker(runId: runId) == expected { return }
      Thread.sleep(forTimeInterval: 0.5)
    }
    XCTFail("未收到真实 Flutter 窗口确认：\(expected)")
  }

  func testRotateActiveInspection() {
    continueAfterFailure = false
    guard let runId = ProcessInfo.processInfo.environment["UBAA_ROTATION_RUN_ID"], !runId.isEmpty else {
      XCTFail("缺少本轮唯一运行标识")
      return
    }
    XCUIDevice.shared.orientation = .portrait
    for theme in ["dark", "light"] {
      waitMarker("ubaa-rotation-ready-\(theme)", runId: runId, timeout: 180)
      // 同运行标识的握手已确认 Flutter 测试活跃；不启动或重装任何 App。
      XCUIDevice.shared.orientation = .landscapeLeft
      waitMarker("ubaa-rotation-landscape-\(theme)", runId: runId, timeout: 60)
      XCUIDevice.shared.orientation = .portrait
      waitMarker("ubaa-rotation-portrait-\(theme)", runId: runId, timeout: 60)
    }
  }
}
