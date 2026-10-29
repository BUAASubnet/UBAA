import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/evidence_directory.dart';

void main() {
  late Directory temporary;
  late Directory repo;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('ubaa_evidence_');
    repo = Directory('${temporary.path}/repo')..createSync();
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test('拒绝缺失配置与相对路径', () {
    for (final path in <String?>[null, '', 'shots']) {
      expect(
        () => checkedEvidenceDirectory(path, repoRoot: repo),
        throwsArgumentError,
      );
    }
  });
  test('拒绝仓库根和未创建的子目录且不写入文件', () {
    for (final path in [
      repo.path,
      '${repo.path}/new/shots',
      '${repo.path}/../repo/shots',
    ]) {
      expect(
        () => checkedEvidenceDirectory(path, repoRoot: repo),
        throwsArgumentError,
      );
    }
    expect(Directory('${repo.path}/new').existsSync(), isFalse);
  });
  test('解析符号链接后仍拒绝指向仓库的目录', () {
    Link('${temporary.path}/alias').createSync(repo.path);
    expect(
      () => checkedEvidenceDirectory(
        '${temporary.path}/alias/new/shots',
        repoRoot: repo,
      ),
      throwsArgumentError,
    );
  }, skip: Platform.isWindows ? 'Windows 创建符号链接需要额外系统权限' : false);
  test('允许仓库外的新目录与名称同前缀的兄弟目录', () {
    final destination = '${repo.path}_private/run';
    final result = checkedEvidenceDirectory(destination, repoRoot: repo);
    expect(
      result.uri,
      Directory('${temporary.resolveSymbolicLinksSync()}/repo_private/run').uri,
    );
    expect(result.existsSync(), isFalse);
  });
}
