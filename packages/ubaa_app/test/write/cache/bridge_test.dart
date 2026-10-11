import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  test('结果成功投影后才确认持久提示，投影异常保留提示', () async {
    for (final broken in [false, true]) {
      final client = _Client()
        ..value = BridgeCachedWriteCommit(
          result: broken ? _BrokenResult() : _success(),
          readbackHintId: 'synthetic-hint',
        );
      final backend = await _backend(client);
      final pending = backend.commitWriteWithCache(
        'intent',
        accountId: 'synthetic',
      );
      if (broken) {
        await expectLater(
          pending,
          throwsA(
            isA<BackendException>().having(
              (e) => e.code,
              '不确定结果',
              UbaaErrorCode.outcomeUnknown,
            ),
          ),
        );
        expect(api.cache.acknowledged, isEmpty);
      } else {
        expect((await pending).success, isTrue);
        expect(api.cache.acknowledged, ['synthetic-hint']);
      }
      expect(client.cached, 1);
    }
  });
  test('提示确认失败不覆盖已经确定的学校成功', () async {
    final client = _Client()
      ..value = BridgeCachedWriteCommit(
        result: _success(),
        readbackHintId: 'synthetic-hint',
      );
    final backend = await _backend(client);
    api.cache.failAcknowledgement = true;
    final result = await backend.commitWriteWithCache(
      'intent',
      accountId: 'synthetic',
    );
    expect(result.success, isTrue);
    expect(result.outcomeUnknown, isFalse);
    expect(result.cacheFailure, CacheMaintenanceFailure.unavailable);
    expect(api.cache.acknowledged, isEmpty);
  });
  test('学校成功与本地失败分列，同一缓存入口只调用一次', () async {
    final client = _Client()
      ..value = BridgeCachedWriteCommit(
        result: _success(),
        cacheError: BridgeCacheFailure.capacity,
      );
    final backend = await _backend(client);
    final result = await backend.commitWriteWithCache(
      'intent',
      accountId: 'synthetic',
    );
    expect(result.success, isTrue);
    expect(result.cacheFailure, CacheMaintenanceFailure.capacity);
    expect(client.cached, 1);
    expect(client.ordinary, 0);
  });
  test('未知提交和本地故障同时保留，不重试学校写入', () async {
    final client = _Client()
      ..value = const BridgeCachedWriteCommit(
        error: _unknown,
        cacheError: BridgeCacheFailure.corrupt,
      );
    final backend = await _backend(client);
    await expectLater(
      backend.commitWriteWithCache('intent', accountId: 'synthetic'),
      throwsA(
        isA<BackendException>()
            .having((e) => e.code, '学校未知', UbaaErrorCode.outcomeUnknown)
            .having((e) => e.resolvedRoute, '实际路线', ConnectionMode.webvpn)
            .having(
              (e) => e.cacheFailure,
              '本地故障',
              CacheMaintenanceFailure.corrupt,
            ),
      ),
    );
    expect(client.cached, 1);
    expect(client.ordinary, 0);
  });
  test('无本机句柄或账号不匹配时不借另一账号的库，原写结果仍保留', () async {
    final client = _Client();
    final backend = await _backend(client);
    final result = await backend.commitWriteWithCache(
      'intent',
      accountId: 'different',
    );
    expect(result.success, isTrue);
    expect(result.cacheFailure, CacheMaintenanceFailure.unavailable);
    expect(client.cached, 0);
    expect(client.ordinary, 1);
    final ordinary = await backend.commitWrite('old-interface');
    expect(ordinary.cacheFailure, isNull);
    expect(client.ordinary, 2);
  });
  test('退出期间学校提交迟到成功不被本地代次错误替换', () async {
    final client = _Client()..pending = Completer();
    final backend = await _backend(client);
    final result = backend.commitWriteWithCache(
      'intent',
      accountId: 'synthetic',
    );
    await Future<void>.delayed(Duration.zero);
    await backend.deactivateOfflineAccount();
    client.pending!.complete(
      BridgeCachedWriteCommit(
        result: _success(),
        cacheError: BridgeCacheFailure.inactive,
      ),
    );
    expect((await result).success, isTrue);
    expect(client.cached, 1);
  });
  test('矛盾或空结果不推断提交成功', () async {
    for (final value in [
      const BridgeCachedWriteCommit(),
      BridgeCachedWriteCommit(result: _success(), error: _unknown),
    ]) {
      final client = _Client()..value = value;
      final backend = await _backend(client);
      await expectLater(
        backend.commitWriteWithCache('intent', accountId: 'synthetic'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            '未知结果',
            UbaaErrorCode.outcomeUnknown,
          ),
        ),
      );
      expect(client.cached, 1);
    }
  });
}

Future<BridgeBackend> _backend(_Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'fixture'),
    List.filled(32, 8),
  );
  return backend;
}

class _Api implements RustLibApi {
  late _Cache cache;
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => cache = _Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  final acknowledged = <String>[];
  bool failAcknowledgement = false;
  @override
  Future<void> dismissWriteReadback({required String id}) async {
    if (failAcknowledgement) throw StateError('合成本地确认失败');
    acknowledged.add(id);
  }

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BrokenResult implements BridgeWriteCommitResult {
  @override
  BridgeWriteOperation get operation => throw StateError('/private/synthetic');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  int cached = 0, ordinary = 0;
  BridgeCachedWriteCommit value = BridgeCachedWriteCommit(result: _success());
  Completer<BridgeCachedWriteCommit>? pending;
  @override
  int contractVersion() => 41;
  @override
  Future<BridgeCachedWriteCommit> commitWriteCached({
    required BridgeOfflineCache cache,
    required String intentId,
  }) async {
    cached++;
    return pending?.future ?? value;
  }

  @override
  Future<BridgeWriteCommitResult> commitWrite({
    required String intentId,
  }) async {
    ordinary++;
    return _success();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _unknown = BridgeError(
  code: BridgeErrorCode.outcomeUnknown,
  kind: BridgeErrorKind.network,
  retryable: false,
  message: '合成未知结果',
  resolvedRoute: BridgeConnectionMode.webVpn,
);
BridgeWriteCommitResult _success() => const BridgeWriteCommitResult(
  operation: BridgeWriteOperation.bykcSelectCourse,
  success: true,
  message: '合成学校成功',
  outcomeUnknown: false,
  resolvedRoute: BridgeConnectionMode.direct,
);
