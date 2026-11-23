import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:ubaa_platform/shared_accounts.dart';

void main() {
  late Directory root;
  late _Materials transport;
  late SecureMaterialStore material;
  late SecureLocalAccountStore accounts;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ubaa_synthetic_failure_');
    // 协调器使用规范路径，故障注入必须匹配同一文件，包括 macOS 的 /var 别名。
    root = Directory(await root.resolveSymbolicLinks());
    transport = _Materials();
    material = SecureMaterialStore(
      transport: transport,
      coordinator: MaterialCoordinator(directory: root),
    );
    await material.probe();
    accounts = SecureLocalAccountStore(material);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('退出在首次索引写入前失败，重启撤销原账号', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    transport.failWrite = 'account-index.v1';
    await expectLater(
      accounts.signOut(),
      throwsA(isA<SecureMaterialException>()),
    );
    transport.failWrite = null;
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reset,
    );
    expect((await accounts.read())!.canRestore, isFalse);
  });

  test('删除账号在发布撤销后失败，重启补完密钥清理', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    transport.failDelete = true;
    await expectLater(
      accounts.removeAccount(state.account!.id),
      throwsA(isA<SecureMaterialException>()),
    );
    transport.failDelete = false;
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reset,
    );
    expect(
      transport.values,
      isNot(contains('ubaa.material.v2.cache-key.${state.account!.id}')),
    );
  });

  test('删密钥后、更新索引前中断，重启跳过已删除键并完成撤销', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    final key = 'ubaa.material.v2.cache-key.${state.account!.id}';
    transport.delayWrite = () async {
      if (!transport.values.containsKey(key)) throw StateError('合成索引写入中断');
    };
    await expectLater(
      accounts.removeAccount(state.account!.id),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(transport.values, isNot(contains(key)));
    transport.delayWrite = null;
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reset,
    );
    expect((await accounts.read())!.account, isNull);
    expect(await File('${root.path}/transaction.v1').readAsString(), 'UBAA1:C');
  });

  test('首次缓存密钥已落盘、索引更新中断时保留原密钥并继续恢复', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    final key = 'ubaa.material.v2.cache-key.${state.account!.id}';
    transport.failWrite = 'account-index.v1';
    await expectLater(
      accounts.cacheKey(state.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    final stored = transport.values[key];
    expect(stored, isNotNull);
    final marker = File('${root.path}/transaction.v1');
    expect(await marker.readAsString(), 'UBAA1:B:save');
    transport.failWrite = null;
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reconciled,
    );
    expect((await accounts.read())!.generation, state.generation);
    expect((await accounts.read())!.canRestore, isTrue);
    expect(base64Encode(await accounts.cacheKey(state.account!)), stored);
    expect(await marker.readAsString(), 'UBAA1:C');
  });

  test('旧格式 B 即使材料一致也撤销且清理密钥', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    final marker = File('${root.path}/transaction.v1');
    await marker.writeAsString('UBAA1:B', flush: true);
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reset,
    );
    expect(await marker.readAsString(), 'UBAA1:C');
    final reset = (await accounts.read())!;
    expect(reset.generation, state.generation + 1);
    expect(reset.account, isNull);
    expect(
      transport.values,
      isNot(contains('ubaa.material.v2.cache-key.${state.account!.id}')),
    );
  });

  test('同一事务内意图升级且较弱写入不能覆盖撤销标记', () async {
    final marker = File('${root.path}/transaction.v1');
    final coordinator = material.coordinator;
    await expectLater(
      material.coordinate(() async {
        await coordinator.beforeMutation(MaterialMutation.probe);
        expect(await marker.readAsString(), 'UBAA1:B:probe');
        await material.write('synthetic-saved', 'synthetic');
        expect(await marker.readAsString(), 'UBAA1:B:save');
        await material.delete('synthetic-saved');
        expect(await marker.readAsString(), 'UBAA1:B:remove');
        await material.write('synthetic-later', 'synthetic');
        await coordinator.beforeMutation(MaterialMutation.probe);
        expect(await marker.readAsString(), 'UBAA1:B:remove');
        throw const SecureMaterialException();
      }),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(await marker.readAsString(), 'UBAA1:B:remove');
  });

  test('首次能力探测写入失败后，启动无需索引即可对账', () async {
    transport.failAfterProbeWrite = true;
    await material.probe();
    expect(material.isAvailable, isFalse);
    expect(
      await accounts.reconcileForStartup(),
      MaterialTransactionRecovery.reconciled,
    );
  });

  for (final code in [null, 0, 3, 5, 13, 32]) {
    if (Platform.isWindows && code == 3) continue;
    test('事务标记存在查询吞掉错误后，读取错误$code仍阻断且保留原件', () async {
      final state = File('${root.path}/transaction.v1');
      final lock = File('${root.path}/materials.lock');
      await state.writeAsString('UBAA1:B', flush: true);
      final original = await state.readAsBytes();
      final values = Map<String, String>.of(transport.values);
      final mutations = transport.mutations;
      final failed = _UnreadableMarker(state, code);
      var callbacks = 0;
      Object? failure;
      await IOOverrides.runZoned(() async {
        try {
          await material.coordinator.run(() async {
            callbacks++;
            await material.write('fixture-forbidden', 'forbidden');
          });
        } on Object catch (error) {
          failure = error;
        }
      }, createFile: (path) => path == state.path ? failed : lock);
      expect(callbacks, 0);
      expect(transport.values, values);
      expect(transport.mutations, mutations);
      expect(await state.readAsBytes(), original);
      expect(failed.reads, 1);
      expect(
        failure,
        isA<MaterialCoordinationException>().having(
          (error) => error.uncertain,
          'uncertain',
          isTrue,
        ),
      );
      // 错误消失后，原 B 仍须阻断，不能自动初始化或清除。
      await expectLater(
        material.coordinator.run(() async => callbacks++),
        throwsA(isA<MaterialCoordinationException>()),
      );
      expect(callbacks, 0);
    });
  }

  test('事务标记UTF-8损坏以uncertain阻断，材料和原字节均保留', () async {
    final state = File('${root.path}/transaction.v1');
    await state.writeAsBytes([0xff, 0xfe], flush: true);
    var callbacks = 0;
    await expectLater(
      material.coordinator.run(() async => callbacks++),
      throwsA(
        isA<MaterialCoordinationException>().having(
          (error) => error.uncertain,
          'uncertain',
          isTrue,
        ),
      ),
    );
    expect(callbacks, 0);
    expect(transport.values, isEmpty);
    expect(await state.readAsBytes(), [0xff, 0xfe]);
  });

  test('探测前安全材料不可读时不留下写入标记，恢复后可读取原材料', () async {
    await material.write('fixture-business', 'synthetic-business');
    final state = File('${root.path}/transaction.v1');
    final mutations = transport.mutations;
    expect(await state.readAsString(), 'UBAA1:C');

    transport.unavailable = true;
    await material.probe();
    expect(material.isAvailable, isFalse);
    expect(await state.readAsString(), 'UBAA1:C');
    expect(transport.mutations, mutations);

    transport.unavailable = false;
    final reopened = SecureMaterialStore(
      transport: transport,
      coordinator: MaterialCoordinator(directory: root),
    );
    await reopened.probe();
    expect(reopened.isAvailable, isTrue);
    expect(await reopened.read('fixture-business'), 'synthetic-business');
  });

  test('probe写后异常仅清自身随机键，原业务材料保留且后续阻断', () async {
    await material.write('fixture-business', 'synthetic-business');
    transport.failAfterProbeWrite = true;
    await material.probe();
    expect(material.isAvailable, isFalse);
    expect(transport.values, {
      'ubaa.material.v2.fixture-business': 'synthetic-business',
    });
    expect(
      await File('${root.path}/transaction.v1').readAsString(),
      'UBAA1:B:probe',
    );
    final reopened = SecureMaterialStore(
      transport: transport,
      coordinator: MaterialCoordinator(directory: root),
    );
    transport.failAfterProbeWrite = false;
    await reopened.probe();
    expect(reopened.isAvailable, isFalse);
    expect(transport.values, {
      'ubaa.material.v2.fixture-business': 'synthetic-business',
    });
  });

  test('两个独立材料对象同时取得待建密钥，所有消费者获得同一值', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    final second = SecureMaterialStore(
      transport: transport,
      coordinator: MaterialCoordinator(directory: root),
    );
    await second.probe();
    final entered = Completer<void>();
    final creating = second.coordinate(() async {
      entered.complete();
      // 让两个消费者在待建密钥的事务期间竞争同一把锁。
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return SecureLocalAccountStore(second).cacheKey(state.account!);
    });
    await entered.future;
    final keys = await Future.wait([
      accounts.cacheKey(state.account!),
      creating,
    ]);
    expect(keys.first, keys.last);
  });
  test('密钥成功后索引回执失败保留原key和pending，后续明确阻断', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    transport.failWrite = 'account-index.v1';
    await expectLater(
      accounts.cacheKey(state.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    final raw =
        transport.values['ubaa.material.v2.cache-key.${state.account!.id}'];
    expect(base64Decode(raw!), hasLength(32));
    expect(
      transport.values['ubaa.material.v2.account-index.v1'],
      contains('"cacheKeyPending":true'),
    );
    transport.failWrite = null;
    await expectLater(
      accounts.cacheKey(state.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(
      transport.values['ubaa.material.v2.cache-key.${state.account!.id}'],
      raw,
    );
  });
  test('破坏性步骤前先撤销许可，删除失败不能悄悄恢复', () async {
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    final key =
        transport.values['ubaa.material.v2.cache-key.${state.account!.id}'];
    transport.failDelete = true;
    await expectLater(
      accounts.removeAccount(state.account!.id),
      throwsA(isA<SecureMaterialException>()),
    );
    final index =
        jsonDecode(transport.values['ubaa.material.v2.account-index.v1']!)
            as Map<String, dynamic>;
    expect(index['canRestore'], isFalse);
    expect(index['generation'], greaterThan(state.generation));
    expect(
      transport.values['ubaa.material.v2.cache-key.${state.account!.id}'],
      key,
    );
  });
  test('损坏、未知索引和损坏既有key均保留，不写空库或替代key', () async {
    for (final raw in ['{broken', '{"version":999}']) {
      transport.values['ubaa.material.v2.account-index.v1'] = raw;
      await expectLater(
        accounts.retain('fixture-a', retainSession: true),
        throwsA(isA<SecureMaterialException>()),
      );
      expect(transport.values['ubaa.material.v2.account-index.v1'], raw);
    }
    transport.values.remove('ubaa.material.v2.account-index.v1');
    final state = await accounts.retain('fixture-a', retainSession: true);
    await accounts.cacheKey(state.account!);
    transport.values['ubaa.material.v2.cache-key.${state.account!.id}'] =
        'invalid';
    await expectLater(
      accounts.cacheKey(state.account!),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(
      transport.values['ubaa.material.v2.cache-key.${state.account!.id}'],
      'invalid',
    );
  });
  test('凭据许可改变先撤销恢复，旧快照不能读自动登录密码或重新启用', () async {
    final vault = MaterialCredentialStore(material);
    await vault.write(
      'com.buaa.ubaa.credentials.v1',
      const Credential(
        username: 'fixture-a',
        password: 'fixture-only',
        autoLogin: true,
      ),
    );
    await accounts.retain('fixture-a', retainSession: true);
    final snapshot = (await accounts.capture())!;
    expect(await vault.readForRestore(snapshot), isNotNull);
    await vault.write(
      'com.buaa.ubaa.credentials.v1',
      const Credential(
        username: 'fixture-a',
        password: 'fixture-only',
        autoLogin: false,
      ),
    );
    expect((await accounts.read())!.canRestore, isFalse);
    expect(await vault.readForRestore(snapshot), isNull);
    await expectLater(
      accounts.refreshIfCurrent(snapshot),
      throwsA(isA<LocalAccountConflict>()),
    );
    final closed = (await accounts.capture())!;
    await expectLater(
      accounts.refreshIfCurrent(closed),
      throwsA(isA<LocalAccountConflict>()),
    );
  });
  test('同一外层事务内并发保留不同账号仍串行，未完成标记先于材料写入', () async {
    final second = SecureLocalAccountStore(material);
    final states = await material.coordinate(
      () => Future.wait([
        accounts.retain('fixture-a', retainSession: true),
        second.retain('fixture-b', retainSession: true),
      ]),
    );
    for (final state in states) {
      expect(await accounts.cacheKey(state.account!), hasLength(32));
    }
    expect((await accounts.read())!.generation, 2);
    transport.delayWrite = () async {
      expect(
        await File('${root.path}/transaction.v1').readAsString(),
        'UBAA1:B:save',
      );
    };
    await material.coordinate(
      () => Future.wait([
        material.write('fixture-one', 'synthetic-one'),
        material.write('fixture-two', 'synthetic-two'),
      ]),
    );
    expect(await material.read('fixture-one'), 'synthetic-one');
    expect(await material.read('fixture-two'), 'synthetic-two');
  });

  test('遗漏await的已启动写入仍收尾，事务结束后的迟到回调不能再写', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    transport.delayWrite = () async {
      entered.complete();
      await gate.future;
    };
    var finished = false;
    final pending = material
        .coordinate(() async {
          unawaited(material.write('fixture-unawaited', 'synthetic'));
        })
        .whenComplete(() {
          finished = true;
        });
    await entered.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(finished, isFalse);
    gate.complete();
    await pending;
    expect(await material.read('fixture-unawaited'), 'synthetic');
    transport.delayWrite = null;
    late Future<void> Function() lateWrite;
    await material.coordinate(() async {
      lateWrite = Zone.current.bindCallback(
        () => material.write('fixture-late', 'forbidden'),
      );
    });
    await expectLater(
      lateWrite(),
      throwsA(isA<SecureMaterialCoordinationException>()),
    );
    expect(
      transport.values.containsKey('ubaa.material.v2.fixture-late'),
      isFalse,
    );
    expect(await material.read('fixture-unawaited'), 'synthetic');
  });

  test('未await的子写落地后失败，根事务与子Future分别交付错误并保留B', () async {
    transport.failAfterWrite = 'fixture-unawaited-failure';
    final unhandled = <Object>[];
    Object? rootFailure;
    await runZonedGuarded(() async {
      try {
        await material.coordinate(() async {
          unawaited(material.write('fixture-unawaited-failure', 'synthetic'));
        });
      } on Object catch (error) {
        rootFailure = error;
      }
      await Future<void>.delayed(Duration.zero);
    }, (error, stack) => unhandled.add(error));
    expect(
      rootFailure,
      isA<SecureMaterialCoordinationException>().having(
        (error) => error.uncertain,
        'uncertain',
        isTrue,
      ),
    );
    expect(unhandled, [isA<SecureMaterialException>()]);
    expect(
      transport.values['ubaa.material.v2.fixture-unawaited-failure'],
      'synthetic',
    );
    expect(
      await File('${root.path}/transaction.v1').readAsString(),
      'UBAA1:B:save',
    );
    await expectLater(
      material.read('fixture-unawaited-failure'),
      throwsA(isA<SecureMaterialCoordinationException>()),
    );
  });

  test('上层捕获timeout仍等待迟到写，不能释放锁让新值被覆盖', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    transport.delayWrite = () async {
      entered.complete();
      await gate.future;
    };
    var finished = false;
    final first = material
        .coordinate(() async {
          try {
            await material
                .write('fixture-value', 'old')
                .timeout(const Duration(milliseconds: 10));
          } on TimeoutException {}
        })
        .whenComplete(() {
          finished = true;
        });
    await entered.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(finished, isFalse);
    final other = SecureMaterialStore(
      transport: transport,
      coordinator: MaterialCoordinator(
        directory: root,
        waitLimit: const Duration(milliseconds: 60),
      ),
    );
    await other.probe();
    expect(other.isAvailable, isFalse);
    expect(finished, isFalse);
    transport.delayWrite = null;
    gate.complete();
    await first;
    await material.write('fixture-value', 'new');
    expect(await material.read('fixture-value'), 'new');
  });
}

/// 模拟 Windows 查询错误返回 false，随后直接读取仍返回实际 OS 错误。
class _UnreadableMarker implements File {
  _UnreadableMarker(this.original, this.code);
  final File original;
  final int? code;
  int reads = 0;
  @override
  String get path => original.path;
  @override
  Future<bool> exists() async => false;
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    reads++;
    throw FileSystemException(
      '合成读取失败',
      path,
      code == null ? null : OSError('合成OS错误', code!),
    );
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      original.open(mode: mode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Materials implements SecureMaterialTransport {
  final values = <String, String>{};
  int mutations = 0;
  String? failWrite;
  String? failAfterWrite;
  bool failDelete = false;
  bool failAfterProbeWrite = false;
  bool unavailable = false;
  Future<void> Function()? delayWrite;
  @override
  Future<String?> read(String key) async {
    if (unavailable) throw const SecureMaterialException();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    mutations++;
    if (unavailable) throw const SecureMaterialException();
    if (delayWrite != null) await delayWrite!();
    if (failWrite != null && key.endsWith(failWrite!))
      throw StateError('synthetic');
    values[key] = value;
    if (failAfterWrite != null && key.endsWith(failAfterWrite!)) {
      throw StateError('合成落地后失败');
    }
    if (failAfterProbeWrite && key.contains(".capability."))
      throw StateError("synthetic");
  }

  @override
  Future<void> delete(String key) async {
    mutations++;
    if (unavailable) throw const SecureMaterialException();
    if (failDelete) throw StateError('synthetic');
    values.remove(key);
  }
}
