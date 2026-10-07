import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'credentials.dart';

/// 系统安全存储传输；测试注入不改变生产实现的安全边界。
abstract interface class SecureMaterialTransport {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 全平台均使用flutter_secure_storage插件合同；OHOS由宿主注册对应插件。
final class PlatformSecureMaterialTransport implements SecureMaterialTransport {
  const PlatformSecureMaterialTransport({this.operatingSystem});
  final String? operatingSystem;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: _MacLoginKeychainOptions(),
  );
  // 官方门面尚未识别OHOS；沿其公开平台接口调用同一插件通道，不自建通道。
  static const _ohosOptions = <String, String>{
    'resetOnError': 'false',
    'ohosKeyCipherAlgorithm': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
    'ohosStorageCipherAlgorithm': 'AES_GCM_NoPadding',
  };
  bool get _isOhos => (operatingSystem ?? Platform.operatingSystem) == 'ohos';

  @override
  Future<String?> read(String key) => _isOhos
      ? FlutterSecureStoragePlatform.instance.read(
          key: key,
          options: _ohosOptions,
        )
      : _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _isOhos
      ? FlutterSecureStoragePlatform.instance.write(
          key: key,
          value: value,
          options: _ohosOptions,
        )
      : _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _isOhos
      ? FlutterSecureStoragePlatform.instance.delete(
          key: key,
          options: _ohosOptions,
        )
      : _storage.delete(key: key);
}

/// 原生异常只归约为稳定类别，不暴露密钥、凭据、平台路径或正文。
class SecureMaterialException implements Exception {
  const SecureMaterialException();
  @override
  String toString() => '系统安全存储暂不可用';
}

/// 不提供内存、文件或明文降级；材料只在调用期经过 Dart 内存。
final class SecureMaterialStore {
  SecureMaterialStore({SecureMaterialTransport? transport})
    : _transport = transport ?? const PlatformSecureMaterialTransport();
  final SecureMaterialTransport _transport;
  bool _available = false;
  bool get isAvailable => _available;
  static const _prefix = 'ubaa.material.v2.';
  static const _capabilityKey = '${_prefix}capability';
  static const _capabilityValue = 'probe-ok';

  /// 用专用非敏感键闭环验证写入、读回和删除，不枚举或读取用户凭据。
  Future<void> probe() async {
    try {
      await _transport.write(_capabilityKey, _capabilityValue);
      if (await _transport.read(_capabilityKey) != _capabilityValue) {
        throw const SecureMaterialException();
      }
      await _transport.delete(_capabilityKey);
      if (await _transport.read(_capabilityKey) != null) {
        throw const SecureMaterialException();
      }
      _available = true;
    } on Object {
      _available = false;
      try {
        await _transport.delete(_capabilityKey);
      } on Object {
        // 探测清理失败仍只归类为不可用，不暴露原生错误。
      }
    }
  }

  Future<String?> read(String key) async {
    _validateKey(key);
    try {
      final value = await _transport.read('$_prefix$key');
      if (value != null && value.length > 65536) {
        throw const SecureMaterialException();
      }
      return value;
    } on Object {
      throw const SecureMaterialException();
    }
  }

  Future<void> write(String key, String value) async {
    _validateKey(key);
    if (value.length > 65536) throw const SecureMaterialException();
    try {
      await _transport.write('$_prefix$key', value);
      // 原生 API 无错误返回仍需确认实际可读，防止权限/签名问题静默丢失。
      if (await _transport.read('$_prefix$key') != value) {
        throw const SecureMaterialException();
      }
    } on Object {
      throw const SecureMaterialException();
    }
  }

  Future<void> delete(String key) async {
    _validateKey(key);
    try {
      await _transport.delete('$_prefix$key');
      if (await _transport.read('$_prefix$key') != null) {
        throw const SecureMaterialException();
      }
    } on Object {
      throw const SecureMaterialException();
    }
  }

  void _validateKey(String key) {
    if (!_available ||
        key.isEmpty ||
        key.length > 256 ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(key)) {
      throw const SecureMaterialException();
    }
  }
}

/// 保留旧 autoLogin 授权值；升级不会将关闭状态改为允许提交密码。
final class MaterialCredentialStore implements PlatformSecureCredentialStore {
  MaterialCredentialStore(this.materials);
  final SecureMaterialStore materials;
  @override
  bool get isAvailable => materials.isAvailable;

  @override
  Future<Credential?> read(String namespace) async {
    try {
      final raw = await materials.read('credentials.$namespace');
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['username'] is! String ||
          value['password'] is! String ||
          value['autoLogin'] is! bool) {
        throw const CredentialVaultException(
          CredentialVaultErrorCode.storageFailure,
        );
      }
      final credential = Credential(
        username: value['username'] as String,
        password: value['password'] as String,
        autoLogin: value['autoLogin'] as bool,
      );
      CredentialVault.validate(credential);
      return credential;
    } on Object {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> write(String namespace, Credential credential) async {
    CredentialVault.validate(credential);
    try {
      await materials.write(
        'credentials.$namespace',
        jsonEncode({
          'username': credential.username,
          'password': credential.password,
          'autoLogin': credential.autoLogin,
        }),
      );
    } on Object {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }

  @override
  Future<void> clear(String namespace) async {
    try {
      await materials.delete('credentials.$namespace');
    } on Object {
      throw const CredentialVaultException(
        CredentialVaultErrorCode.storageFailure,
      );
    }
  }
}

/// 固定 darwin 0.2.0 的原生参数拼写与 Dart 参数不同；显式传递真实读取键。
/// 登录钥匙串使用自身锁定与访问控制，不设置仅适用于数据保护钥匙串的属性。
class _MacLoginKeychainOptions extends MacOsOptions {
  const _MacLoginKeychainOptions()
    : super(usesDataProtectionKeychain: false, accessibility: null);
  @override
  Map<String, String> toMap() => {
    ...super.toMap(),
    'useDataProtectionKeyChain': 'false',
  };
}
