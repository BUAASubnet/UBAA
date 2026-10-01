import Foundation
import Security

/// legacy 交互策略与 SecItem 一同注入，测试不调用真实系统策略。
protocol LegacyKeychainAPI: CredentialKeychainAPI {
  func getUserInteractionAllowed() -> (OSStatus, Bool)
  func setUserInteractionAllowed(_ allowed: Bool) -> OSStatus
}

/// 保留登录 Keychain 与当前 Debug 签名条件；deprecated 调用仅集中在此兼容边界。
struct SecurityLegacyKeychainAPI: LegacyKeychainAPI {
  func getUserInteractionAllowed() -> (OSStatus, Bool) {
    var allowed: DarwinBoolean = false
    let status = SecKeychainGetUserInteractionAllowed(&allowed)
    return (status, allowed.boolValue)
  }

  func setUserInteractionAllowed(_ allowed: Bool) -> OSStatus {
    SecKeychainSetUserInteractionAllowed(allowed)
  }

  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    return (status, value)
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    SecItemAdd(attributes as CFDictionary, nil)
  }

  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    SecItemDelete(query as CFDictionary)
  }
}

struct SystemCredentialKeychainAPI: CredentialKeychainAPI {
  private let api: LegacyKeychainAPI

  init(api: LegacyKeychainAPI = SecurityLegacyKeychainAPI()) {
    self.api = api
  }

  func copyMatching(_ query: [String: Any]) throws -> (OSStatus, CFTypeRef?) {
    try LegacyKeychainInteraction.shared.perform(using: api) { try api.copyMatching(query) }
  }

  func add(_ attributes: [String: Any]) throws -> OSStatus {
    try LegacyKeychainInteraction.shared.perform(using: api) { try api.add(attributes) }
  }

  func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus {
    try LegacyKeychainInteraction.shared.perform(using: api) { try api.update(query, attributes: attributes) }
  }

  func delete(_ query: [String: Any]) throws -> OSStatus {
    try LegacyKeychainInteraction.shared.perform(using: api) { try api.delete(query) }
  }
}

/// legacy 策略属于进程，锁和待恢复原值必须由所有适配器共用，不能按 handler 分配。
private final class LegacyKeychainInteraction {
  static let shared = LegacyKeychainInteraction()
  private let lock = NSLock()
  private var pendingAllowed: Bool?

  func perform<T>(using api: LegacyKeychainAPI, operation: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    // 之前的恢复失败时，先修复原策略；绝不能把临时 false 当作新的原值。
    try restore(using: api)
    let (status, original) = api.getUserInteractionAllowed()
    try CredentialStoreFailure.check(status)
    pendingAllowed = original

    let outcome: Result<T, Error>
    do {
      try CredentialStoreFailure.check(api.setUserInteractionAllowed(false))
      outcome = .success(try operation())
    } catch {
      outcome = .failure(error as? CredentialStoreFailure ?? CredentialStoreFailure.storageFailure)
    }
    // 关闭失败和 Swift 异常同样经过恢复；恢复错误优先报告，不能返回已取得的凭据。
    try restore(using: api)
    return try outcome.get()
  }

  private func restore(using api: LegacyKeychainAPI) throws {
    guard let original = pendingAllowed else { return }
    let status = api.setUserInteractionAllowed(original)
    if status == errSecSuccess {
      pendingAllowed = nil
      return
    }
    // 只做一次有界补偿；仍失败则保留原值并阻止后续存储，不无限等待或永久关闭交互。
    if api.setUserInteractionAllowed(original) == errSecSuccess { pendingAllowed = nil }
    try CredentialStoreFailure.check(status)
  }
}
