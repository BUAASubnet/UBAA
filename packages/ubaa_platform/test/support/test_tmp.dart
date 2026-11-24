import 'dart:io';

Directory createTestTempDirectory(String suite, {Directory? fallbackRoot}) {
  final override = Platform.environment['UBAA_TEST_TMP'];
  final root = override == null || override.isEmpty
      ? _workspaceTestTempRoot() ?? fallbackRoot
      : Directory(override).absolute;
  if (root == null) throw StateError('找不到测试所在的 UBAA 工作区');
  final parent = Directory.fromUri(root.uri.resolve('$suite/'))
    ..createSync(recursive: true);
  return parent.createTempSync('run_');
}

Directory? _workspaceTestTempRoot() {
  var directory = Directory.current.absolute;
  while (!File.fromUri(directory.uri.resolve('justfile')).existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
  return Directory.fromUri(directory.uri.resolve('target/test_tmp/'));
}
