import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../runtime/shared_recovery_probe.dart' as probe;
import '../runtime/session_recovery_probe.dart' show profile;

void main() {
  for (final entry in probe.cases.entries) {
    test(entry.key, entry.value);
  }
  late Directory root;
  setUp(() async {
    root = await probe.fixture();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('真实双进程同时恢复：继任客户端复用已发布会话，只提交一次密码', () async {
    final a = await Child.start(root, 'hold'),
        b = await Child.start(root, 'normal');
    try {
      a.send('GO');
      await a.next('LOGIN');
      b.send('GO');
      a.send('RELEASE');
      await a.next('DONE');
      await b.next('DONE');
      await a.finished();
      await b.finished();
      expect(submissions(root), 1);
    } finally {
      await a.dispose();
      await b.dispose();
    }
  });
  for (final action in ['退出', '切号', '退出重登', '撤销许可']) {
    test('真实双进程恢复中$action：旧任务不能交付', () async {
      final a = await Child.start(root, 'hold');
      try {
        a.send('GO');
        await a.next('LOGIN');
        final accounts = await probe.openAccounts(root);
        if (action == '撤销许可') {
          await accounts.revokeIfCurrent((await accounts.capture())!);
        } else {
          await accounts.signOut();
        }
        if (action == '切号')
          await accounts.retain('synthetic-other', retainSession: true);
        if (action == '退出重登')
          await accounts.retain(profile.username, retainSession: true);
        await File(
          '${root.path}/session',
        ).writeAsString('外部操作-$action', flush: true);
        a.send('RELEASE');
        await a.next('STOP');
        await a.finished();
        expect(
          await File('${root.path}/session').readAsString(),
          '外部操作-$action',
        );
        expect(submissions(root), 1);
      } finally {
        await a.dispose();
      }
    });
  }
  test('真实恢复进程中途被 SIGKILL，等待者获得 OS 锁并完成恢复', () async {
    final a = await Child.start(root, 'hold'),
        b = await Child.start(root, 'normal');
    try {
      a.send('GO');
      await a.next('LOGIN');
      b.send('GO');
      Process.killPid(a.pid, ProcessSignal.sigkill);
      await a.process.exitCode;
      await b.next('LOGIN');
      await b.next('DONE');
      await b.finished();
      expect(submissions(root), 2);
      expect(
        (await (await probe.openAccounts(root)).read())!.canRestore,
        isTrue,
      );
    } finally {
      await a.dispose();
      await b.dispose();
    }
  });
  test('会话已写入但发布前崩溃：新客户端先复用会话，不再次提交密码', () async {
    final a = await Child.start(root, 'hold');
    Child? b;
    try {
      a.send('GO');
      await a.next('LOGIN');
      // 合成恢复中断于 Core 已持久化、账号发布前的边界。
      await File('${root.path}/session').writeAsString('合成已提交会话', flush: true);
      Process.killPid(a.pid, ProcessSignal.sigkill);
      await a.process.exitCode;
      b = await Child.start(root, 'normal');
      b.send('GO');
      await b.next('DONE');
      await b.finished();
      expect(submissions(root), 1);
    } finally {
      await a.dispose();
      await b?.dispose();
    }
  });
}

int submissions(Directory root) => root
    .listSync()
    .whereType<File>()
    .where((file) => file.uri.pathSegments.last.startsWith('submission-'))
    .length;

class Child {
  Child(this.process, this.lines, this.pid, this.errors) {
    unawaited(
      process.exitCode.then((_) {
        exited = true;
      }),
    );
  }
  bool exited = false;
  final Process process;
  final StreamIterator<String> lines;
  final int pid;
  final Future<String> errors;
  static Future<Child> start(Directory root, String mode) async {
    var repo = Directory.current.absolute;
    while (!File('${repo.path}/justfile').existsSync()) {
      repo = repo.parent;
    }
    final process = await Process.start('just', [
      'dart',
      'run',
      'packages/ubaa_app/test/runtime/shared_recovery_worker.dart',
      root.path,
      mode,
    ], workingDirectory: repo.path);
    final lines = StreamIterator(
      utf8.decoder.bind(process.stdout).transform(const LineSplitter()),
    );
    final errors = utf8.decoder.bind(process.stderr).join();
    expect(await lines.moveNext(), isTrue);
    expect(lines.current, startsWith('READY:'));
    return Child(
      process,
      lines,
      int.parse(lines.current.split(':').last),
      errors,
    );
  }

  void send(String message) => process.stdin.writeln(message);
  Future<void> next(String expected) async {
    expect(await lines.moveNext().timeout(const Duration(seconds: 20)), isTrue);
    expect(lines.current, expected);
  }

  Future<void> finished() async {
    expect(await process.exitCode, 0, reason: await errors);
  }

  Future<void> dispose() async {
    Process.killPid(pid, ProcessSignal.sigkill);
    await process.exitCode;
    await lines.cancel();
  }
}
