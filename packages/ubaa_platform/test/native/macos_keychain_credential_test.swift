import Foundation
import Security

/// 注入全部 Security 调用；本套确定性测试从不访问系统 Keychain。
private final class FakeKeychain: CredentialKeychainAPI {
  var copyResult: (OSStatus, CFTypeRef?) = (errSecItemNotFound, nil)
  var updateStatuses = [errSecSuccess]
  var addStatus = errSecSuccess
  var deleteStatus = errSecSuccess
  var calls: [(String, [String: Any])] = []
  var changes: [[String: Any]] = []

  func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
    calls.append(("read", query))
    return copyResult
  }

  func add(_ attributes: [String: Any]) -> OSStatus {
    calls.append(("add", attributes))
    return addStatus
  }

  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    calls.append(("update", query))
    changes.append(attributes)
    return updateStatuses.removeFirst()
  }

  func delete(_ query: [String: Any]) -> OSStatus {
    calls.append(("delete", query))
    return deleteStatus
  }
}

@main
struct MacOSKeychainCredentialTest {
  private static let namespace = "com.buaa.ubaa.credentials.test.\(UUID().uuidString)"
  private static let values: [String: Any] = [
    "username": "synthetic-student", "password": "synthetic-secret", "autoLogin": false,
  ]
  private static var arguments: [String: Any] {
    values.merging(["namespace": namespace]) { first, _ in first }
  }

  static func main() throws {
    try exactQueriesAndUpdate()
    try insertAndRace()
    try nullableAndTypedReads()
    try invalidInputNeverTouchesKeychain()
    try errorMapping()
    print("原生凭据确定性检查通过：精确寻址、禁止同步、严格类型、更新/新增竞争、无记录和错误归约；未访问系统 Keychain")
  }

  private static func checkQuery(_ query: [String: Any]) {
    precondition(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    precondition(query[kSecAttrService as String] as? String == "cn.edu.buaa.ubaa.credentials")
    precondition(query[kSecAttrAccount as String] as? String == namespace, "不能替换或扩大 namespace")
    let sync = query[kSecAttrSynchronizable as String] as? NSNumber
    precondition(sync != nil && CFGetTypeID(sync!) == CFBooleanGetTypeID() && !sync!.boolValue)
    let dataProtection = query[kSecUseDataProtectionKeychain as String] as? NSNumber
    precondition(
      dataProtection != nil && CFGetTypeID(dataProtection!) == CFBooleanGetTypeID()
        && !dataProtection!.boolValue,
      "所有操作必须明确限定 legacy Keychain，不能依赖默认路由"
    )
    precondition(query[kSecAttrAccessGroup as String] == nil, "不能请求其他应用访问组")
  }

  private static func expectFailure(_ expected: CredentialStoreFailure, _ body: () throws -> Void) {
    do {
      try body()
      preconditionFailure("应拒绝此操作")
    } catch let failure as CredentialStoreFailure {
      precondition(failure == expected, "错误必须归约为稳定类别")
    } catch {
      preconditionFailure("不允许抛出系统或解析器的原始错误")
    }
  }

  private static func exactQueriesAndUpdate() throws {
    let api = FakeKeychain()
    let store = KeychainCredentialStore(api: api)
    try store.write(arguments)
    precondition(api.calls.map { $0.0 } == ["update"])
    precondition(api.changes.count == 1 && api.changes[0].count == 1)
    let data = api.changes[0][kSecValueData as String] as! Data
    let encoded = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    precondition(encoded.count == 3, "namespace 与用户名不得进入 Keychain 可检索个人属性")
    precondition(encoded["username"] as? String == values["username"] as? String)
    precondition(encoded["password"] as? String == values["password"] as? String)
    precondition(CFGetTypeID(encoded["autoLogin"] as! NSNumber) == CFBooleanGetTypeID())
    try store.clear(namespace)
    api.deleteStatus = errSecItemNotFound
    try store.clear(namespace)
    precondition(api.calls.map { $0.0 } == ["update", "delete", "delete"])
    for (_, query) in api.calls { checkQuery(query) }
  }

  private static func insertAndRace() throws {
    for raced in [false, true] {
      let api = FakeKeychain()
      api.updateStatuses = raced ? [errSecItemNotFound, errSecSuccess] : [errSecItemNotFound]
      api.addStatus = raced ? errSecDuplicateItem : errSecSuccess
      try KeychainCredentialStore(api: api).write(arguments)
      precondition(api.calls.map { $0.0 } == (raced ? ["update", "add", "update"] : ["update", "add"]))
      for (_, query) in api.calls { checkQuery(query) }
    }
  }

  private static func nullableAndTypedReads() throws {
    let api = FakeKeychain()
    let store = KeychainCredentialStore(api: api)
    let missing = try store.read(namespace)
    precondition(missing == nil)
    for autoLogin in [false, true] {
      var saved = values
      saved["autoLogin"] = autoLogin
      api.copyResult = (errSecSuccess, try PropertyListSerialization.data(fromPropertyList: saved, format: .binary, options: 0) as CFData)
      let read = try store.read(namespace)!
      precondition(read["username"] as? String == values["username"] as? String)
      precondition(read["password"] as? String == values["password"] as? String)
      let result = read["autoLogin"] as! NSNumber
      precondition(CFGetTypeID(result) == CFBooleanGetTypeID() && result.boolValue == autoLogin)
    }
    for bad in [Data(), Data("合成损坏数据".utf8)] {
      api.copyResult = (errSecSuccess, bad as CFData)
      expectFailure(.storageFailure) { _ = try store.read(namespace) }
    }
    api.copyResult = (errSecSuccess, nil)
    expectFailure(.storageFailure) { _ = try store.read(namespace) }
    var numeric = values
    numeric["autoLogin"] = 1
    api.copyResult = (errSecSuccess, try PropertyListSerialization.data(fromPropertyList: numeric, format: .binary, options: 0) as CFData)
    expectFailure(.storageFailure) { _ = try store.read(namespace) }
    for (_, query) in api.calls {
      checkQuery(query)
      precondition(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
      precondition(query[kSecReturnData as String] as? Bool == true)
    }
  }

  private static func invalidInputNeverTouchesKeychain() throws {
    let api = FakeKeychain()
    let store = KeychainCredentialStore(api: api)
    for key in arguments.keys {
      var missing = arguments
      missing.removeValue(forKey: key)
      expectFailure(.invalidInput) { try store.write(missing) }
    }
    let invalid: [(String, Any)] = [
      ("namespace", ""), ("namespace", NSNull()), ("namespace", 1),
      ("username", " \n\t\u{FEFF}"), ("username", 1),
      ("password", ""), ("password", 1),
      ("autoLogin", 0), ("autoLogin", 1), ("autoLogin", 0.0),
      ("autoLogin", 1.0), ("autoLogin", "true"), ("autoLogin", NSNull()),
    ]
    for (key, value) in invalid {
      var bad = arguments
      bad[key] = value
      expectFailure(.invalidInput) { try store.write(bad) }
    }
    for invalid in [nil, "", " \n", NSNull(), 1, [String: Any]()] as [Any?] {
      expectFailure(.invalidInput) { _ = try store.read(invalid) }
      expectFailure(.invalidInput) { try store.clear(invalid) }
      expectFailure(.invalidInput) { try store.write(invalid) }
    }
    precondition(api.calls.isEmpty, "非法输入不能触发系统存储调用")
    // Dart 的现有约束仅要求密码非空，不擅自裁剪密码或用户名原值。
    var spaces = arguments
    spaces["username"] = " synthetic-student "
    spaces["password"] = " "
    try store.write(spaces)
  }

  private static func errorMapping() throws {
    let failures: [(OSStatus, CredentialStoreFailure)] = [
      (errSecNotAvailable, .unavailable), (errSecInteractionNotAllowed, .unavailable),
      (errSecAuthFailed, .unavailable), (errSecUserCanceled, .unavailable),
      (errSecMissingEntitlement, .unavailable), (errSecDecode, .storageFailure),
      (errSecParam, .storageFailure), (errSecInternalError, .storageFailure),
    ]
    for (status, expected) in failures {
      let api = FakeKeychain()
      let store = KeychainCredentialStore(api: api)
      api.copyResult = (status, nil)
      expectFailure(expected) { _ = try store.read(namespace) }
      api.deleteStatus = status
      expectFailure(expected) { try store.clear(namespace) }
      api.updateStatuses = [status]
      expectFailure(expected) { try store.write(arguments) }
      precondition(!api.calls.contains { $0.0 == "add" }, "更新失败不能当成不存在而新增")
      api.updateStatuses = [errSecItemNotFound]
      api.addStatus = status
      expectFailure(expected) { try store.write(arguments) }
      api.updateStatuses = [errSecItemNotFound, status]
      api.addStatus = errSecDuplicateItem
      expectFailure(expected) { try store.write(arguments) }
    }
  }
}
