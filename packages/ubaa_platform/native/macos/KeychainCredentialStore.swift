import Foundation
import Security

/// 平台错误只携带稳定类别，不包含系统错误正文或凭据内容。
enum CredentialStoreFailure: String, Error {
  case invalidInput = "credentials_invalid_input"
  case unavailable = "credentials_unavailable"
  case storageFailure = "credentials_storage_failure"

  var message: String {
    switch self {
    case .invalidInput: return "凭据输入无效"
    case .unavailable: return "安全凭据存储暂不可用"
    case .storageFailure: return "安全凭据存储操作失败"
    }
  }

  static func check(_ status: OSStatus) throws {
    switch status {
    case errSecSuccess: return
    case errSecNotAvailable, errSecInteractionNotAllowed, errSecAuthFailed,
         errSecUserCanceled, errSecMissingEntitlement:
      throw CredentialStoreFailure.unavailable
    default:
      throw CredentialStoreFailure.storageFailure
    }
  }
}

/// 测试可注入系统返回值，不必访问用户的任何 Keychain 条目。
protocol CredentialKeychainAPI {
  func copyMatching(_ query: [String: Any]) throws -> (OSStatus, CFTypeRef?)
  func add(_ attributes: [String: Any]) throws -> OSStatus
  func update(_ query: [String: Any], attributes: [String: Any]) throws -> OSStatus
  func delete(_ query: [String: Any]) throws -> OSStatus
}

/// macOS 登录 Keychain 适配；只查询本应用服务和明确 namespace 对应的单条凭据。
///
/// 不导入旧存储、不缓存明文、不启用同步。调用方负责在同一串行队列中执行操作。
final class KeychainCredentialStore {
  private let api: CredentialKeychainAPI
  private static let service = "cn.edu.buaa.ubaa.credentials"
  private static let whitespace = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "\u{FEFF}"))

  init(api: CredentialKeychainAPI = SystemCredentialKeychainAPI()) {
    self.api = api
  }

  func read(_ namespace: Any?) throws -> [String: Any]? {
    var query = try itemQuery(namespace)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, result) = try api.copyMatching(query)
    if status == errSecItemNotFound { return nil }
    try CredentialStoreFailure.check(status)
    guard let data = result as? Data,
          let value = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
      throw CredentialStoreFailure.storageFailure
    }
    return try credential(value, failure: .storageFailure)
  }

  func write(_ arguments: Any?) throws {
    guard let arguments = arguments as? [String: Any] else {
      throw CredentialStoreFailure.invalidInput
    }
    let query = try itemQuery(arguments["namespace"])
    let value = try credential(arguments, failure: .invalidInput)
    guard let data = try? PropertyListSerialization.data(
      fromPropertyList: value, format: .binary, options: 0
    ) else {
      throw CredentialStoreFailure.storageFailure
    }
    let changes = [kSecValueData as String: data]
    var status = try api.update(query, attributes: changes)
    if status == errSecItemNotFound {
      var attributes = query
      attributes[kSecValueData as String] = data
      status = try api.add(attributes)
      // 其他进程可能在更新与新增之间写入同一条目，最多补一次精确更新。
      if status == errSecDuplicateItem {
        status = try api.update(query, attributes: changes)
      }
    }
    try CredentialStoreFailure.check(status)
  }

  func clear(_ namespace: Any?) throws {
    let status = try api.delete(itemQuery(namespace))
    if status != errSecItemNotFound { try CredentialStoreFailure.check(status) }
  }

  private func itemQuery(_ rawNamespace: Any?) throws -> [String: Any] {
    guard let namespace = rawNamespace as? String,
          !namespace.trimmingCharacters(in: Self.whitespace).isEmpty else {
      throw CredentialStoreFailure.invalidInput
    }
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: namespace,
      kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: false,
    ]
  }

  private func credential(
    _ value: Any?, failure: CredentialStoreFailure
  ) throws -> [String: Any] {
    guard let fields = value as? [String: Any],
          let username = fields["username"] as? String,
          !username.trimmingCharacters(in: Self.whitespace).isEmpty,
          let password = fields["password"] as? String,
          !password.isEmpty,
          let autoLogin = fields["autoLogin"] as? NSNumber,
          CFGetTypeID(autoLogin) == CFBooleanGetTypeID() else {
      throw failure
    }
    return ["username": username, "password": password, "autoLogin": autoLogin.boolValue]
  }
}
