import 'dart:io';

/// 在写入截图前确认目标位于项目本地的任务子目录。
Directory checkedEvidenceDirectory(String? destination, {Directory? repoRoot}) {
  if (destination == null || !Directory(destination).isAbsolute) {
    throw ArgumentError('UBAA_UI_EVIDENCE_DIR 必须是 .ubaa_local 下的私有绝对路径');
  }
  if (destination.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError('证据目录不能包含父目录跳转');
  }
  final root = _resolvedDirectory(repoRoot ?? _findRepoRoot());
  final directory = _resolvedDirectory(Directory(destination));
  final localRoot = root.uri.resolve('.ubaa_local/');
  if (directory.uri == localRoot ||
      !directory.uri.toString().startsWith(localRoot.toString())) {
    throw ArgumentError('UBAA_UI_EVIDENCE_DIR 必须位于仓库 .ubaa_local 的任务子目录');
  }
  return directory;
}

Directory _findRepoRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/justfile').existsSync() &&
        FileSystemEntity.typeSync('${directory.path}/.git') !=
            FileSystemEntityType.notFound) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('无法定位仓库根目录，请从 UBAA2 工作树内运行驱动');
    }
    directory = parent;
  }
}

Directory _resolvedDirectory(Directory directory) {
  var ancestor = directory.absolute;
  final missing = <String>[];
  while (!ancestor.existsSync()) {
    // 断开的链接及普通文件都不能作为尚未创建的证据目录。
    if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ArgumentError('证据目录包含不可用的路径节点');
    }
    missing.insert(
      0,
      ancestor.uri.pathSegments.where((s) => s.isNotEmpty).last,
    );
    ancestor = ancestor.parent;
  }
  var resolved = Directory(ancestor.resolveSymbolicLinksSync());
  for (final segment in missing) {
    resolved = Directory.fromUri(
      resolved.uri.resolve('${Uri.encodeComponent(segment)}/'),
    );
  }
  return resolved;
}
