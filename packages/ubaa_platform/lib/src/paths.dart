import 'dart:io';
import 'package:flutter/services.dart';

final _privateDirectory = PrivateConfigDirectory();

String defaultConfigDirectory() => _privateDirectory.resolve();

/// 生产宿主在创建 Core 会话之前取得原生私有目录。
Future<void> initializePrivateDirectory() => _privateDirectory.initialize();

/// 可注入的平台目录解析器；不读取账号、会话或业务文件。
final class PrivateConfigDirectory {
  PrivateConfigDirectory({
    Map<String, String>? environment,
    String? operatingSystem,
    MethodChannel? channel,
  }) : environment = environment ?? Platform.environment,
       operatingSystem = operatingSystem ?? Platform.operatingSystem,
       channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/platform');
  final Map<String, String> environment;
  final String operatingSystem;
  final MethodChannel channel;
  String? _native;
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final configured = environment['UBAA_CONFIG_DIR']?.trim();
    if (configured != null && configured.isNotEmpty) {
      resolve();
      return;
    }
    if (operatingSystem != 'ios' && operatingSystem != 'android') return;
    String? path;
    try {
      path = await channel.invokeMethod<String>('paths.config');
    } on Object {
      throw const FileSystemException('应用私有目录暂不可用');
    }
    if (path == null || path.isEmpty || !Directory(path).isAbsolute) {
      throw const FileSystemException('应用私有目录暂不可用');
    }
    _native = path;
  }

  String resolve() {
    final configured = environment['UBAA_CONFIG_DIR']?.trim();
    if (configured != null && configured.isNotEmpty) {
      final path = Directory(configured);
      if (!path.isAbsolute) throw const FileSystemException('配置目录必须为绝对路径');
      return path.path;
    }
    if (_native != null) return _native!;

    final home = environment['HOME']?.trim();
    String? base;
    if (operatingSystem == 'windows') {
      base = environment['APPDATA']?.trim() ?? home;
    } else if (operatingSystem == 'macos' || operatingSystem == 'ios') {
      base = home == null || home.isEmpty
          ? null
          : '$home/Library/Application Support';
    } else if (operatingSystem == 'linux' || operatingSystem == 'android') {
      base = environment['XDG_STATE_HOME']?.trim();
      base ??= home == null || home.isEmpty ? null : '$home/.local/state';
    } else {
      base = home;
    }
    if (base == null || base.isEmpty) {
      throw const FileSystemException('应用私有目录暂不可用');
    }
    final path = Directory('$base/UBAA');
    if (!path.isAbsolute) throw const FileSystemException('应用私有目录必须为绝对路径');
    return path.path;
  }
}
