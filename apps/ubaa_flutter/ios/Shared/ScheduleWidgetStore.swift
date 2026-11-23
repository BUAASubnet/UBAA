import CryptoKit
import Foundation
import Security

/// 与 Android `WidgetStore.kt` 同合同的组件安全存储。
/// 只存 AES-256-GCM 密文（`[版本] + nonce + 密文 + 标签`）；密钥在 Keychain
/// （此设备专用、解锁后可读），副本本身不含解密材料且排除备份，
/// 随机账号别名与课表投影处于同一完整性边界。
/// Runner 与 ScheduleWidget 扩展通过 App Group 容器共享这一副本。
/// 周次翻页偏移是低敏感展示状态，独立存于容器明文，不在此边界内。
enum ScheduleWidgetStore {
    static let appGroupID = "group.cn.edu.ubaa"
    static let alias = "ubaa.schedule.widgets.v1"
    private static let limit = 4 * 1024 * 1024
    private static let queue = DispatchQueue(label: "cn.edu.ubaa.schedule-widget-store")

    enum StoreError: Error {
        case unavailable
        case corrupt
    }

    // MARK: - 容器与密钥

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("schedule-widgets.enc")
    }

    private static var keyURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("schedule-widgets.key")
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

    private static func loadKey(create: Bool) throws -> SymmetricKey {
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
        let query = try keychainQuery()
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

    // MARK: - 读写

    private static func readLocked() throws -> [String: Any]? {
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

    private static func writeLocked(_ value: [String: Any]) throws {
        guard let fileURL else { throw StoreError.unavailable }
        let plain = try JSONSerialization.data(withJSONObject: value)
        guard plain.count <= limit else { throw StoreError.corrupt }
        let key = try loadKey(create: !FileManager.default.fileExists(atPath: fileURL.path))
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

    /// 立即更换发布代次；`owner` 为空时撤销并清空组件副本。
    static func begin(owner: String?) throws -> String {
        try queue.sync {
            guard let fileURL else { throw StoreError.unavailable }
            let scope = UUID().uuidString.lowercased()
            guard let owner else {
                try? FileManager.default.removeItem(at: fileURL)
                guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw StoreError.unavailable
                }
                return scope
            }
            guard !owner.isEmpty, owner.count <= 128 else { throw StoreError.corrupt }
            let old = try readLocked()
            var state: [String: Any] =
                (old?["owner"] as? String) == owner
                ? old ?? [:]
                : ["owner": owner]
            state["scope"] = scope
            try writeLocked(state)
            return scope
        }
    }

    /// 校验发布代次与账号后替换课表投影；代次失效返回 `false`。
    @discardableResult
    static func publish(scope: String, snapshotJSON: [String: Any]) throws -> Bool {
        try queue.sync {
            let parsed = try ScheduleWidgetParser.parseSnapshot(snapshotJSON)
            guard var state = try readLocked(),
                  state["scope"] as? String == scope,
                  state["owner"] as? String == parsed.owner
            else { return false }
            state["snapshot"] = snapshotJSON
            try writeLocked(state)
            return true
        }
    }

    /// 读取 `{owner, snapshot?}`；快照校验失败按无快照处理。
    static func readState() -> (owner: String?, snapshot: WidgetSnapshot?) {
        queue.sync {
            guard let state = try? readLocked() else { return (nil, nil) }
            let owner = state["owner"] as? String
            let snapshot =
                (state["snapshot"] as? [String: Any]).flatMap {
                    try? ScheduleWidgetParser.parseSnapshot($0)
                }
            return (owner, snapshot)
        }
    }
}
