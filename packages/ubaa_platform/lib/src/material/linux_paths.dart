import 'dart:io';
import 'user_directory.dart';

/// 复用 path_provider_linux 的 applicationId 与固定 GUI 旧名称，不采用 AOT 文件名。
Future<String> linuxCommandDirectory({Map<String, String>? environment}) async {
  final values = environment ?? Platform.environment;
  final configured = values['UBAA_CONFIG_DIR']?.trim();
  if (configured != null && configured.isNotEmpty) {
    if (!Directory(configured).isAbsolute)
      throw const FileSystemException('应用目录必须为绝对路径');
    return configured;
  }
  final home = systemMaterialDirectory().parent.parent.parent.parent.path;
  final xdg = values['XDG_DATA_HOME'];
  final data = xdg != null && xdg.isNotEmpty ? xdg : '$home/.local/share';
  if (!Directory(data).isAbsolute)
    throw const FileSystemException('应用目录必须为绝对路径');
  final current = Directory('$data/cn.edu.ubaa');
  final legacy = Directory('$data/ubaa_flutter');
  return '${await current.exists()
      ? current.path
      : await legacy.exists()
      ? legacy.path
      : current.path}/UBAA';
}
