import 'dart:io';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'material/windows_materials.dart';
import 'material/windows_dpapi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'material/secure_material_core.dart' as core;
import 'material/secure_material_core.dart' show SecureMaterialTransport;
import 'material/material_coordination.dart';
import 'paths.dart';
export 'material/secure_material_core.dart' hide SecureMaterialStore;
export 'material/material_credentials.dart';
export 'material/material_coordination.dart';

/// Flutter 生产适配；纯 Dart 消费者从 shared_accounts.dart 注入安全传输。
final class SecureMaterialStore extends core.SecureMaterialStore {
  SecureMaterialStore({
    SecureMaterialTransport? transport,
    MaterialCoordinator? coordinator,
  }) : super(
         transport: transport ?? const PlatformSecureMaterialTransport(),
         coordinator:
             coordinator ??
             MaterialCoordinator.resolving(
               () async => Platform.isLinux || Platform.isWindows
                   ? MaterialCoordinator.desktopDirectory()
                   : mobileMaterialCoordinationDirectory(),
             ),
       );
}

/// 全平台均使用flutter_secure_storage插件合同；OHOS由宿主注册对应插件。
final class PlatformSecureMaterialTransport implements SecureMaterialTransport {
  const PlatformSecureMaterialTransport({
    this.operatingSystem,
    this.windowsTransport,
  });
  final SecureMaterialTransport? windowsTransport;
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
  bool get _isWindows =>
      (operatingSystem ?? Platform.operatingSystem) == 'windows';
  static final _windows = WindowsFileMaterials(
    file: () async => File(
      paths.canonicalize(
        paths.join(
          (await getApplicationSupportDirectory()).path,
          'flutter_secure_storage.dat',
        ),
      ),
    ),
    codec: const WindowsDpapiCodec(),
    replace: replaceWindowsMaterial,
  );

  @override
  Future<String?> read(String key) => _isWindows
      ? (windowsTransport ?? _windows).read(key)
      : _isOhos
      ? FlutterSecureStoragePlatform.instance.read(
          key: key,
          options: _ohosOptions,
        )
      : _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _isWindows
      ? (windowsTransport ?? _windows).write(key, value)
      : _isOhos
      ? FlutterSecureStoragePlatform.instance.write(
          key: key,
          value: value,
          options: _ohosOptions,
        )
      : _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _isWindows
      ? (windowsTransport ?? _windows).delete(key)
      : _isOhos
      ? FlutterSecureStoragePlatform.instance.delete(
          key: key,
          options: _ohosOptions,
        )
      : _storage.delete(key: key);
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
