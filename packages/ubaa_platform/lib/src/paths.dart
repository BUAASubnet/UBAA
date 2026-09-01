import 'dart:io';

/// 解析 Core Session 使用的应用私有配置目录。
///
/// 宿主只把该目录传给 bridge，绝不读取其中的 Session 内容。移动端的 `HOME`
/// 由系统沙箱提供；若平台没有可验证的私有目录则直接失败，禁止退回程序目录
/// 或公共临时目录。
String defaultConfigDirectory() {
  final configured = Platform.environment['UBAA_CONFIG_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) {
    final path = Directory(configured);
    if (!path.isAbsolute)
      throw const FileSystemException('config directory must be absolute');
    return path.path;
  }

  final environment = Platform.environment;
  final home = environment['HOME']?.trim();
  String? base;
  if (Platform.isWindows) {
    base = environment['APPDATA']?.trim() ?? home;
  } else if (Platform.isMacOS || Platform.isIOS) {
    base = home == null || home.isEmpty
        ? null
        : '$home/Library/Application Support';
  } else if (Platform.isLinux || Platform.isAndroid) {
    base = environment['XDG_STATE_HOME']?.trim();
    base ??= home == null || home.isEmpty ? null : '$home/.local/state';
  } else {
    base = home;
  }
  if (base == null || base.isEmpty) {
    throw const FileSystemException(
      'private application directory is unavailable',
    );
  }
  final path = Directory('$base/UBAA');
  if (!path.isAbsolute)
    throw const FileSystemException(
      'private application directory is not absolute',
    );
  return path.path;
}
