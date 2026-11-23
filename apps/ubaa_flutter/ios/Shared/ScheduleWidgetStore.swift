import CryptoKit
import Foundation
import Security

/// 与 Android `WidgetStore.kt` 同合同的组件安全存储。
/// 只存 AES-256-GCM 密文（`[版本] + nonce + 密文 + 标签`）；密钥在 Keychain
/// （此设备专用、解锁后可读），副本本身不含解密材料且排除备份，
/// 随机账号别名与课表投影处于同一完整性边界。
/// Runner 与 ScheduleWidget 扩展通过 App Group 容器共享这一副本。
/// 周次翻页偏移是低敏感展示状态，独立存于容器明文，不在此边界内。
final class ScheduleWidgetStore {
    static let appGroupID = "group.cn.edu.ubaa"
    static let shared = ScheduleWidgetStore(directory:
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID))

    private let alias = "ubaa.schedule.widgets.v1"
    private let limit = 4 * 1024 * 1024
    private let queue = DispatchQueue(label: "cn.edu.ubaa.schedule-widget-store")
    private let directory: URL?
    private let removeItem: (URL) throws -> Void
    private var publication: (owner: String, scope: String)?

    init(directory: URL?, removeItem: @escaping (URL) throws -> Void = FileManager.default.removeItem(at:)) {
        self.directory = directory
        self.removeItem = removeItem
    }

    enum StoreError: Error {
        case unavailable
        case corrupt
    }

    // MARK: - 容器与密钥

    private var fileURL: URL? {
        directory?.appendingPathComponent("schedule-widgets.enc")
    }

    private var keyURL: URL? {
        directory?.appendingPathComponent("schedule-widgets.key")
    }

    /// Keychain 条目（`AfterFirstUnlockThisDeviceOnly`：不迁移、不备份、解锁后可读）。
    private static let keychainService = "cn.edu.ubaa.schedule-widget"
    private static let keychainAccount = "aes-key"

    #if !targetEnvironment(simulator)
    private static func keychainQuery() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ScheduleWidgetKeychainAccessGroup")
            as? String, !group.hasPrefix(".") else { throw StoreError.unavailable }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: group,
        ]
    }
    #endif

    private func loadKey(create: Bool) throws -> SymmetricKey {
        #if targetEnvironment(simulator)
        // 模拟器无签名 entitlements，访问组不可用；退回容器内密钥文件（仅调试环境）。
        guard let keyURL else { throw StoreError.unavailable }
        if let data = try? Data(contentsOf: keyURL) {
            guard data.count == 32 else { throw StoreError.corrupt }
            return SymmetricKey(data: data)
        }
        guard create else { throw StoreError.unavailable }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
        else { throw StoreError.unavailable }
        try Data(bytes).write(to: keyURL, options: [.atomic])
        return SymmetricKey(data: Data(bytes))
        #else
        let query = try Self.keychainQuery()
        var lookup = query
        lookup[kSecReturnData as String] = true
        var item: CFTypeRef?
        switch SecItemCopyMatching(lookup as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else {
                throw StoreError.corrupt
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            guard create else { throw StoreError.unavailable }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
            else { throw StoreError.unavailable }
            var add = query
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecValueData as String] = Data(bytes)
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
                throw StoreError.unavailable
            }
            return SymmetricKey(data: Data(bytes))
        default:
            throw StoreError.unavailable
        }
        #endif
    }

    private func revokeLocked() throws {
        #if targetEnvironment(simulator)
        guard let keyURL else { throw StoreError.unavailable }
        do {
            try removeItem(keyURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // 密钥文件已不存在，副本无法再解密。
        }
        #else
        let status = SecItemDelete(try Self.keychainQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unavailable
        }
        #endif
        if let fileURL { try? removeItem(fileURL) }
    }

    // MARK: - 读写

    private func readLocked() throws -> [String: Any]? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path)
        else { return nil }
        let bytes = try Data(contentsOf: fileURL)
        guard bytes.count >= 29, bytes.first == 1, bytes.count <= limit + 64
        else { throw StoreError.corrupt }
        let nonce = try AES.GCM.Nonce(data: bytes[1..<13])
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: bytes[13..<(bytes.count - 16)],
            tag: bytes[(bytes.count - 16)...]
        )
        let key = try loadKey(create: false)
        let plain = try AES.GCM.open(sealed, using: key, authenticating: Data(alias.utf8))
        guard
            let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any]
        else { throw StoreError.corrupt }
        return object
    }

    private func writeLocked(_ value: [String: Any]) throws {
        guard let fileURL else { throw StoreError.unavailable }
        let plain = try JSONSerialization.data(withJSONObject: value)
        guard plain.count <= limit else { throw StoreError.corrupt }
        let key = try loadKey(create: true)
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: Data(alias.utf8))
        let encrypted =
            Data([1]) + Data(sealed.nonce) + sealed.ciphertext + sealed.tag
        try encrypted.write(to: fileURL, options: [.atomic])
        #if !targetEnvironment(simulator)
        try? (fileURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        #endif
        let roundtrip = try readLocked()
        let again = try JSONSerialization.data(
            withJSONObject: roundtrip ?? [:],
            options: [.sortedKeys]
        )
        let expected = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys]
        )
        guard again == expected else { throw StoreError.corrupt }
    }

    // MARK: - 发布协议

    /// 代次只在发布进程内有效。换账号或退出时先销毁旧密钥，直到下次发布才生成新密钥。
    func begin(owner: String?) throws -> String {
        try queue.sync {
            if let owner, owner.isEmpty || owner.count > 128 { throw StoreError.corrupt }
            let previousOwner = publication?.owner ?? ((try? readLocked())?["owner"] as? String)
            publication = nil
            if owner == nil || previousOwner != owner { try revokeLocked() }
            let scope = UUID().uuidString.lowercased()
            if let owner { publication = (owner, scope) }
            return scope
        }
    }

    /// 校验发布代次与账号后替换课表投影；代次失效返回 `false`。
    @discardableResult
    func publish(scope: String, snapshotJSON: [String: Any]) throws -> Bool {
        try queue.sync {
            let parsed = try ScheduleWidgetParser.parseSnapshot(snapshotJSON)
            guard let publication, publication.scope == scope, publication.owner == parsed.owner
            else { return false }
            try writeLocked(["owner": parsed.owner, "snapshot": snapshotJSON])
            return true
        }
    }

    /// 读取 `{owner, snapshot?}`；快照校验失败按无快照处理。
    func readState() -> (owner: String?, snapshot: WidgetSnapshot?) {
        queue.sync {
            guard let state = try? readLocked(),
                  let raw = state["snapshot"] as? [String: Any],
                  let snapshot = try? ScheduleWidgetParser.parseSnapshot(raw),
                  state["owner"] as? String == snapshot.owner
            else { return (nil, nil) }
            return (snapshot.owner, snapshot)
        }
    }
}
