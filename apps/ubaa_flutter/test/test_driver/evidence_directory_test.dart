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
        reason: path,
      );
    }
  });
  test('拒绝任务目录之外的仓库路径且不写入文件', () {
    for (final path in [
      repo.path,
      '${repo.path}/new/shots',
      '${repo.path}/../repo/shots',
      '${repo.path}/.ubaa_local',
      '${repo.path}/.ubaa_local_backup/shots',
      '${repo.path}/.ubaa_local/../shots',
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
  test('允许项目本地任务子目录且校验时不创建目录', () {
    final destination = '${repo.path}/.ubaa_local/evidence/run';
    for (final createParent in [false, true]) {
      if (createParent) Directory('${repo.path}/.ubaa_local').createSync();
      final result = checkedEvidenceDirectory(destination, repoRoot: repo);
      expect(
        result.uri,
        Directory(
          '${repo.resolveSymbolicLinksSync()}/.ubaa_local/evidence/run',
        ).uri,
      );
      expect(result.existsSync(), isFalse);
    }
  });
  test('拒绝仓库外目录与名称同前缀的兄弟目录', () {
    for (final destination in [temporary.path, '${repo.path}_private/run']) {
      expect(
        () => checkedEvidenceDirectory(destination, repoRoot: repo),
        throwsArgumentError,
      );
    }
  });
  test(
    '拒绝项目本地目录中的链接指向其他源码目录',
    () {
      Directory('${repo.path}/.ubaa_local').createSync();
      final tracked = Directory('${repo.path}/docs')..createSync();
      Link('${repo.path}/.ubaa_local/alias').createSync(tracked.path);
      expect(
        () => checkedEvidenceDirectory(
          '${repo.path}/.ubaa_local/alias/new/shots',
          repoRoot: repo,
        ),
        throwsArgumentError,
      );
    },
    skip: Platform.isWindows ? 'Windows 创建符号链接需要额外系统权限' : false,
  );
  test(
    '拒绝项目本地目录本身通过链接移到仓库外',
    () {
      final outside = Directory('${temporary.path}/private')..createSync();
      Link('${repo.path}/.ubaa_local').createSync(outside.path);
      expect(
        () => checkedEvidenceDirectory(
          '${repo.path}/.ubaa_local/run',
          repoRoot: repo,
        ),
        throwsArgumentError,
      );
    },
    skip: Platform.isWindows ? 'Windows 创建符号链接需要额外系统权限' : false,
  );
}
