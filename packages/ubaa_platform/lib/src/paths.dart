import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

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
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
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
