import Foundation
import Security

private enum SyntheticFailure: Error { case operation }
private struct TestFailure: Error { let message: String }

private final class FailureCount {
  private let lock = NSLock()
  private var value = 0
  func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
  var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// 包括进程交互策略在内的全部调用均为合成实现。
private final class RecordingLegacyKeychain: LegacyKeychainAPI {
  private let lock = NSLock()
  private var currentAllowed: Bool
  private var trace: [String] = []
  private var getCount = 0
  private var operationCount = 0
  var getStatus = errSecSuccess
  var setStatuses: [OSStatus] = []
  var operationStatus = errSecSuccess
  var throwsOperation = false
  var mutateFailedSet = false
  var onGet: ((Int) -> Void)?
  var onOperation: ((Int) -> Void)?

  init(allowed: Bool) { currentAllowed = allowed }
  var events: [String] { lock.lock(); defer { lock.unlock() }; return trace }
  var allowed: Bool { lock.lock(); defer { lock.unlock() }; return currentAllowed }

  func getUserInteractionAllowed() -> (OSStatus, Bool) {
    lock.lock()
    trace.append("get")
    getCount += 1
    let count = getCount
    let result = (getStatus, currentAllowed)
    lock.unlock()
    onGet?(count)
    return result
  }

  func setUserInteractionAllowed(_ allowed: Bool) -> OSStatus {
    lock.lock()
    defer { lock.unlock() }
    trace.append("set:\(allowed)")
    let status = setStatuses.isEmpty ? errSecSuccess : setStatuses.removeFirst()
    if status == errSecSuccess || mutateFailedSet { currentAllowed = allowed }
    return status
  }

  private func operation(_ name: String) throws -> OSStatus {
    lock.lock()
    trace.append(name)
    operationCount += 1
    let count = operationCount
    lock.unlock()
    onOperation?(count)
    if throwsOperation { throw SyntheticFailure.operation }
    return operationStatus
  }

  func copyMatching(_ query: [String: Any]) throws -> (OSStatus, CFTypeRef?) {
    (try operation("read"), nil)
  }
  func add(_ attributes: [String: Any]) throws -> OSStatus { try operation("add") }
  func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus {
    try operation("update")
  }
  func delete(_ query: [String: Any]) throws -> OSStatus { try operation("delete") }
}

@main
struct MacOSKeychainInteractionTest {
  private static let operations = ["read", "add", "update", "delete"]

  static func main() {
    do {
      try normalAndOperationFailure()
      try getAndDisableFailure()
      try restoreFailureAndRecovery()
      try sharedBoundary()
      print("legacy 交互包装器通过：原值 true/false、四类操作、策略失败、异常恢复和跨实例共享边界；未调用系统策略或 Keychain")
    } catch let failure as TestFailure {
      print("行为断言失败：\(failure.message)")
      exit(1)
    } catch {
      print("行为断言失败：出现未归约异常")
      exit(1)
    }
  }

  private static func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(message: message) }
  }

  private static func expectFailure(_ expected: CredentialStoreFailure, _ body: () throws -> Void) throws {
    do {
      try body()
    } catch let failure as CredentialStoreFailure {
      try check(failure == expected, "必须返回稳定的策略失败类别")
      return
    } catch {
      throw TestFailure(message: "系统包装器不能泄露原始异常")
    }
    throw TestFailure(message: "策略失败不能虚报操作成功")
  }

  private static func invoke(_ operation: String, _ api: SystemCredentialKeychainAPI) throws -> OSStatus {
    switch operation {
    case "read": return try api.copyMatching([:]).0
    case "add": return try api.add([:])
    case "update": return try api.update([:], attributes: [:])
    default: return try api.delete([:])
    }
  }

  private static func normalAndOperationFailure() throws {
    for initial in [true, false] {
      for operation in operations {
        for status in [errSecSuccess, errSecAuthFailed, errSecItemNotFound] {
          let raw = RecordingLegacyKeychain(allowed: initial)
          raw.operationStatus = status
          let actual = try invoke(operation, SystemCredentialKeychainAPI(api: raw))
          try check(actual == status, "SecItem 返回值不能被策略包装器改成成功")
          try check(raw.events == ["get", "set:false", operation, "set:\(initial)"],
                    "系统操作必须先 get/禁止交互，再执行并恢复原值")
          try check(raw.allowed == initial, "成功和系统失败都必须恢复原始策略")
        }
        let raw = RecordingLegacyKeychain(allowed: initial)
        raw.throwsOperation = true
        try expectFailure(.storageFailure) { _ = try invoke(operation, SystemCredentialKeychainAPI(api: raw)) }
        try check(raw.events == ["get", "set:false", operation, "set:\(initial)"], "Swift 异常也必须恢复策略")
        try check(raw.allowed == initial, "异常路径不能残留临时禁用状态")
      }
    }
  }

  private static func getAndDisableFailure() throws {
    let statuses: [(OSStatus, CredentialStoreFailure)] = [
      (errSecAuthFailed, .unavailable), (errSecParam, .storageFailure),
      (errSecItemNotFound, .storageFailure),
    ]
    for initial in [true, false] {
      for (status, expected) in statuses {
        for operation in operations {
          let getFailed = RecordingLegacyKeychain(allowed: initial)
          getFailed.getStatus = status
          try expectFailure(expected) { _ = try invoke(operation, SystemCredentialKeychainAPI(api: getFailed)) }
          try check(getFailed.events == ["get"] && getFailed.allowed == initial,
                    "读取策略失败时不得改变策略或调用 SecItem")

          let disableFailed = RecordingLegacyKeychain(allowed: initial)
          disableFailed.setStatuses = [status, errSecSuccess]
          disableFailed.mutateFailedSet = true
          try expectFailure(expected) { _ = try invoke(operation, SystemCredentialKeychainAPI(api: disableFailed)) }
          try check(disableFailed.events == ["get", "set:false", "set:\(initial)"],
                    "关闭交互失败时必须恢复已知原值并跳过 SecItem")
          try check(disableFailed.allowed == initial, "关闭失败即使改变了状态也要恢复")
        }
      }
    }
  }

  private static func restoreFailureAndRecovery() throws {
    for initial in [true, false] {
      for operation in operations {
        let raw = RecordingLegacyKeychain(allowed: initial)
        raw.setStatuses = [errSecSuccess, errSecParam, errSecSuccess]
        try expectFailure(.storageFailure) { _ = try invoke(operation, SystemCredentialKeychainAPI(api: raw)) }
        try check(raw.events == ["get", "set:false", operation, "set:\(initial)", "set:\(initial)"],
                  "恢复失败必须有界补偿且仍报告失败")
        try check(raw.allowed == initial, "有界补偿成功时必须恢复原值")
      }

      let raw = RecordingLegacyKeychain(allowed: initial)
      raw.setStatuses = [errSecSuccess, errSecParam, errSecParam]
      let first = SystemCredentialKeychainAPI(api: raw)
      try expectFailure(.storageFailure) { _ = try first.delete([:]) }
      let beforeBlocked = raw.events.count
      raw.setStatuses = [errSecParam, errSecParam]
      let second = SystemCredentialKeychainAPI(api: raw)
      try expectFailure(.storageFailure) { _ = try second.copyMatching([:]) }
      try check(Array(raw.events.dropFirst(beforeBlocked)) == ["set:\(initial)", "set:\(initial)"],
                "待恢复策略失败时新实例不得读取新基线或进入存储")
      let beforeRecovery = raw.events.count
      raw.setStatuses = []
      _ = try second.delete([:])
      try check(Array(raw.events.dropFirst(beforeRecovery)) ==
                ["set:\(initial)", "get", "set:false", "delete", "set:\(initial)"],
                "新实例必须先恢复旧原值，不能永久沿用临时 false")
      try check(raw.allowed == initial, "跨实例恢复后应回到原始策略")
    }
  }

  private static func sharedBoundary() throws {
    let raw = RecordingLegacyKeychain(allowed: true)
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let secondAttempted = DispatchSemaphore(value: 0)
    let secondGotPolicy = DispatchSemaphore(value: 0)
    let complete = DispatchGroup()
    let failures = FailureCount()
    raw.onGet = { if $0 == 2 { secondGotPolicy.signal() } }
    raw.onOperation = { count in
      if count == 1 {
        entered.signal()
        _ = release.wait(timeout: .now() + 2)
      }
    }
    let first = SystemCredentialKeychainAPI(api: raw)
    let second = SystemCredentialKeychainAPI(api: raw)
    complete.enter()
    DispatchQueue.global().async {
      do { _ = try first.add([:]) } catch { failures.increment() }
      complete.leave()
    }
    try check(entered.wait(timeout: .now() + 2) == .success, "首个系统操作应进入测试边界")
    complete.enter()
    DispatchQueue.global().async {
      secondAttempted.signal()
      do { _ = try second.delete([:]) } catch { failures.increment() }
      complete.leave()
    }
    let attempted = secondAttempted.wait(timeout: .now() + 2)
    let premature = secondGotPolicy.wait(timeout: .now() + 0.1)
    release.signal()
    try check(complete.wait(timeout: .now() + 2) == .success, "共享边界不能死锁")
    try check(attempted == .success && premature == .timedOut, "两个适配器必须共享同步边界")
    try check(failures.count == 0 && raw.allowed, "并发操作完成后必须保留原始策略")
    try check(raw.events == ["get", "set:false", "add", "set:true", "get", "set:false", "delete", "set:true"],
              "共享锁必须覆盖读取策略至恢复完成的整个过程")
  }
}
