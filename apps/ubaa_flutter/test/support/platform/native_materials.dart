import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubaa_platform/shared_accounts.dart'
    show
        WindowsFileMaterials,
        WindowsMaterialCodec,
        WindowsDpapiCodec,
        replaceWindowsMaterial;
import 'package:ubaa_platform/ubaa_platform.dart';

/// 原生合成测试的数据与协调目录共用私有域，Linux仅接受专用隔离入口。
Future<SecureMaterialStore> createNativeTestMaterials({
  required Directory domain,
  String? operatingSystem,
  SecureMaterialTransport Function()? nativeTransport,
  WindowsMaterialCodec? windowsCodec,
  Future<void> Function(File, File)? windowsReplace,
}) async {
  final os = operatingSystem ?? Platform.operatingSystem;
  late SecureMaterialTransport transport;
  if (os == 'windows') {
    transport = WindowsFileMaterials(
      file: () async => File('${domain.path}/synthetic-materials.dat'),
      codec: windowsCodec ?? const WindowsDpapiCodec(),
      replace: windowsReplace ?? replaceWindowsMaterial,
    );
  } else if (os == 'linux') {
    const isolated = bool.fromEnvironment('UBAA_SYNTHETIC_SECRET_SERVICE');
    final root = Platform.environment['UBAA_SYNTHETIC_SECRET_SERVICE_ROOT'];
    if (!isolated ||
        root == null ||
        !Directory(root).isAbsolute ||
        Platform.environment['XDG_DATA_HOME'] != '$root/data' ||
        Platform.environment['XDG_CONFIG_HOME'] != '$root/config' ||
        Platform.environment['XDG_RUNTIME_DIR'] != '$root/runtime' ||
        (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) {
      throw StateError('Linux原生材料测试必须通过linux-secure-storage.sh隔离会话运行');
    }
    transport =
        nativeTransport?.call() ??
        _PluginTransport(const FlutterSecureStorage());
  } else if (os == 'macos' || os == 'ios' || os == 'android') {
    if (os == 'android') {
      // 插件还使用固定配置、包装key和Keystore，必须先核对真实应用沙箱。
      final info = await PackageInfo.fromPlatform();
      if (info.packageName != 'cn.edu.ubaa.synthetic.materials') {
        throw StateError('Android原生材料测试必须通过android_materials.py独立Debug包运行');
      }
    }
    final name =
        'ubaa.synthetic.${domain.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    transport = _PluginTransport(
      FlutterSecureStorage(
        mOptions: _MacSyntheticOptions(name),
        iOptions: IOSOptions(
          accountName: name,
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        aOptions: AndroidOptions(
          sharedPreferencesName: name,
          resetOnError: true,
          migrateOnAlgorithmChange: true,
        ),
      ),
    );
  } else {
    throw StateError('此平台尚无隔离原生材料测试适配');
  }
  return SecureMaterialStore(
    coordinator: MaterialCoordinator(
      directory: Directory('${domain.path}/coordination'),
    ),
    transport: _NativeDiagnostics(transport),
  );
}

class _MacSyntheticOptions extends MacOsOptions {
  _MacSyntheticOptions(String name)
    : super(
        accountName: name,
        usesDataProtectionKeychain: false,
        accessibility: null,
      );
  @override
  Map<String, String> toMap() => {
    ...super.toMap(),
    'useDataProtectionKeyChain': 'false',
  };
}

class _PluginTransport implements SecureMaterialTransport {
  _PluginTransport(this.storage);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

// 仅输出操作与整数状态，不输出路径、平台异常正文或材料键值。
class _NativeDiagnostics implements SecureMaterialTransport {
  _NativeDiagnostics(this.native);
  final SecureMaterialTransport native;
  Future<T> call<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      final status = error.details;
      debugPrint('安全材料原生探测：$operation，状态=${status is int ? status : '未提供'}');
      rethrow;
    }
  }

  @override
  Future<String?> read(String key) => call('read', () => native.read(key));
  @override
  Future<void> write(String key, String value) =>
      call('write', () => native.write(key, value));
  @override
  Future<void> delete(String key) => call('delete', () => native.delete(key));
}
