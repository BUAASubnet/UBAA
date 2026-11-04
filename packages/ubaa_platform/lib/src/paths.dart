import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'material/user_directory.dart';

final _privateDirectory = PrivateConfigDirectory();
String defaultConfigDirectory() => _privateDirectory.resolve();
Future<void> initializePrivateDirectory() => _privateDirectory.initialize();

/// 系统插件取得目录；Android 独立薄通道仅补 noBackupFilesDir。
final class PrivateConfigDirectory {
  PrivateConfigDirectory({
    Map<String, String>? environment,
    String? operatingSystem,
    MethodChannel? channel,
    Future<Directory> Function()? supportDirectory,
  }) : environment = environment ?? Platform.environment,
       operatingSystem = operatingSystem ?? Platform.operatingSystem,
       channel =
           channel ?? const MethodChannel('cn.edu.buaa.ubaa/private-paths'),
       _supportDirectory = supportDirectory ?? _platformSupportDirectory;
  final Map<String, String> environment;
  final String operatingSystem;
  final MethodChannel channel;
  final Future<Directory> Function() _supportDirectory;
  String? _native;
  Future<void>? _initializing;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (_configured != null) {
      resolve();
      return;
    }
    try {
      final path = operatingSystem == 'android'
          ? await channel.invokeMethod<String>('configDirectory')
          : paths.join((await _supportDirectory()).path, 'UBAA');
      if (path == null || path.isEmpty || !paths.isAbsolute(path))
        throw const FileSystemException();
      _native = path;
    } on Object {
      throw const FileSystemException('应用私有目录暂不可用');
    }
  }

  String? get _configured {
    final value = environment['UBAA_CONFIG_DIR']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String resolve() {
    final path = _configured ?? _native;
    if (path == null || !paths.isAbsolute(path))
      throw const FileSystemException('请先初始化应用私有目录');
    return path;
  }
}

Future<Directory> _platformSupportDirectory() async {
  if (!Platform.isMacOS) return getApplicationSupportDirectory();
  final home = systemMaterialDirectory().parent.parent.parent.parent.path;
  final legacy = Directory(
    '$home/Library/Containers/cn.edu.ubaa/Data/Library/Application Support/cn.edu.ubaa',
  );
  final current = Directory('$home/Library/Application Support/cn.edu.ubaa');
  final oldExists = await Directory('${legacy.path}/UBAA').exists();
  final currentExists = await Directory('${current.path}/UBAA').exists();
  if (oldExists && currentExists)
    throw const FileSystemException('发现两份应用资料，请先确定使用的资料目录');
  // 保留已安装版本的资料原位使用，不复制会话、SQLite WAL 或安全材料。
  return currentExists ? current : legacy;
}

/// 材料协调独立于业务数据目录覆盖；移动端采用原生应用私有目录。
Future<Directory> mobileMaterialCoordinationDirectory() async {
  final native = PrivateConfigDirectory(environment: const {});
  await native.initialize();
  return Directory('${native.resolve()}/material_coordination_v1');
}
