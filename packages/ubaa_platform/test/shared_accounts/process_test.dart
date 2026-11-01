import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:test/test.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import '../support/shared_account_worker.dart'
    show syntheticWindowsMaterials, SyntheticMaterialCodec;

void main() {
  late Directory root;
  late SecureMaterialStore materials;
  late SecureLocalAccountStore accounts;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ubaa_synthetic_process_');
    materials = SecureMaterialStore(
      transport: syntheticWindowsMaterials(root),
      coordinator: MaterialCoordinator(
        directory: Directory('${root.path}/coordination'),
      ),
    );
    await materials.probe();
    accounts = SecureLocalAccountStore(materials);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<Process> start(
    String command, [
    String value = '',
    String? lockPath,
  ]) => Process.start(
    'just',
    [
      'dart',
      'run',
      'packages/ubaa_platform/test/support/shared_account_worker.dart',
      root.path,
      command,
      value,
      if (lockPath != null) lockPath,
    ],
    workingDirectory: _repository(),
    environment: {'UBAA_CONFIG_DIR': '${root.path}/config-$command-$value'},
  );
  Future<String> run(
    String command, [
    String value = '',
    String? lockPath,
  ]) async {
    final child = await start(command, value, lockPath);
    final out = utf8.decoder.bind(child.stdout).join();
    final err = utf8.decoder.bind(child.stderr).join();
    expect(await child.exitCode, 0, reason: await err);
    return (await out).trim();
  }

  test('同一系统用户修改 HOME、USERPROFILE 和 XDG 后默认锁域仍相同', () async {
    Future<String> resolve(String suffix) async {
      final result = await Process.run(
        'just',
        [
          'dart',
          'run',
          'packages/ubaa_platform/test/support/shared_account_worker.dart',
          root.path,
          'defaultDirectory',
        ],
        workingDirectory: _repository(),
        environment: {
          'HOME': '${root.path}/home-$suffix',
          'USERPROFILE': '${root.path}/profile-$suffix',
          'XDG_DATA_HOME': '${root.path}/xdg-$suffix',
          'UBAA_CONFIG_DIR': '${root.path}/config-$suffix',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      return result.stdout.toString().trim();
    }

    expect(await resolve('one'), await resolve('two'));
  });

  test('两个真实进程在不同config目录保留同账号：别名和密钥唯一、代次推进', () async {
    final results = await Future.wait([
      run('retain', 'fixture-a'),
      run('retain', 'fixture-a'),
    ]);
    final values = results
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
    expect(values[0]['id'], values[1]['id']);
    expect(values[0]['key'], values[1]['key']);
    expect((await accounts.read())!.generation, 2);
  });
  test('两个真实进程保留不同账号：账号与密钥均不丢失', () async {
    final results = await Future.wait([
      run('retain', 'fixture-a'),
      run('retain', 'fixture-b'),
    ]);
    final values = results
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
    for (var i = 0; i < 2; i++) {
      final state = await accounts.retain(
        'fixture-${i == 0 ? 'a' : 'b'}',
        retainSession: true,
      );
      expect(state.account!.id, values[i]['id']);
      expect(
        base64Encode(await accounts.cacheKey(state.account!)),
        values[i]['key'],
      );
    }
    expect((await accounts.read())!.generation, 4);
  });
  for (final operation in ['signOut', 'switch', 'disable', 'remove']) {
    test('另一个进程$operation后旧快照拒绝条件更新', () async {
      await accounts.retain('fixture-a', retainSession: true);
      final old = (await accounts.capture())!;
      expect(await run(operation), 'OK');
      expect(await accounts.validate(old), isFalse);
      await expectLater(
        accounts.refreshIfCurrent(old),
        throwsA(isA<LocalAccountConflict>()),
      );
      final current = await accounts.read();
      if (operation != 'switch') expect(current!.canRestore, isFalse);
    });
  }
  test('并发probe与账号写入覆盖整map后端，探测不删除业务材料', () async {
    final results = await Future.wait([
      run('retain', 'fixture-a'),
      run('probe'),
      run('probe'),
    ]);
    expect(results.skip(1), everyElement('OK'));
    final saved = jsonDecode(results.first) as Map<String, dynamic>;
    final state = (await accounts.read())!;
    expect(state.account!.id, saved['id']);
    expect(base64Encode(await accounts.cacheKey(state.account!)), saved['key']);
  });
  test('有界锁等待、路径别名、进程终止释放及普通句柄结束不退出', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    final path = Directory('${root.path}/coordination');
    final alias = Link('${root.path}/alias');
    await alias.create(path.path);
    final holder = await start('hold', '', alias.path);
    final lines = StreamIterator(
      utf8.decoder.bind(holder.stdout).transform(const LineSplitter()),
    );
    expect(await lines.moveNext(), isTrue);
    expect(lines.current, startsWith('LOCKED:'));
    final holderPid = int.parse(lines.current.split(':').last);
    try {
      final time = Stopwatch()..start();
      expect(await run('probe'), 'BLOCKED');
      expect(time.elapsed, lessThan(const Duration(seconds: 10)));
    } finally {
      Process.killPid(holderPid, ProcessSignal.sigkill);
      await holder.exitCode;
      await lines.cancel();
    }
    expect(await run('probe'), 'OK');
    expect((await accounts.read())!.generation, state.generation);
    expect((await accounts.read())!.canRestore, isTrue);
  });
  test('持锁进程在密钥写入后被终止：后续明确阻断，旧alias与key保留', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    final child = await start('crash');
    final lines = StreamIterator(
      utf8.decoder.bind(child.stdout).transform(const LineSplitter()),
    );
    expect(await lines.moveNext(), isTrue);
    expect(lines.current, startsWith('MUTATION_PENDING:'));
    final childPid = int.parse(lines.current.split(':').last);
    Process.killPid(childPid, ProcessSignal.sigkill);
    await child.exitCode;
    await lines.cancel();
    expect(await run('probe'), 'BLOCKED');
    await expectLater(accounts.read(), throwsA(isA<SecureMaterialException>()));
    final raw =
        jsonDecode(
              utf8.decode(
                const SyntheticMaterialCodec().decrypt(
                  await File(
                    '${root.path}/synthetic_materials.dat',
                  ).readAsBytes(),
                ),
              ),
            )
            as Map<String, dynamic>;
    expect(raw['ubaa.material.v2.cache-key.${state.account!.id}'], isNotNull);
    expect(
      raw['ubaa.material.v2.account-index.v1'],
      contains(state.account!.id),
    );
  });
  test('同进程独立isolate也受fd锁保护', () async {
    final path = Directory('${root.path}/isolate_lock');
    final port = ReceivePort();
    await Isolate.spawn(_holdIsolate, (path.path, port.sendPort));
    final release = await port.first as SendPort;
    try {
      final lock = MaterialCoordinator(
        directory: path,
        waitLimit: const Duration(milliseconds: 100),
      );
      await expectLater(
        lock.run(() async => true),
        throwsA(isA<MaterialCoordinationException>()),
      );
    } finally {
      release.send(null);
      port.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      await MaterialCoordinator(directory: path).run(() async => true),
      isTrue,
    );
  });
}

Future<void> _holdIsolate((String, SendPort) data) async {
  await MaterialCoordinator(directory: Directory(data.$1)).run(() async {
    final release = ReceivePort();
    data.$2.send(release.sendPort);
    await release.first;
    release.close();
  });
}

String _repository() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/justfile').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('缺少仓库入口');
    dir = parent;
  }
  return dir.path;
}
