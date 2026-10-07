import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../../recovery/startup_test.dart' as startup;
import 'bridge_test.dart' as fixtures;

void main() {
  test('缓存密钥不可读时控制器仍传递本机账号范围到分段读取', () async {
    final backend = _ScopedBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: _Accounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await controller.refreshFeatureQuery(FeatureId.judge, const FeatureQuery());
    expect(backend.account?.id, 'synthetic-account');
    expect(backend.account?.username, 'fixture-user');
    expect(backend.ordinary, 0);
    expect(backend.opens, 0);
    expect(controller.localCacheError, isNotNull);
  });
  test('无缓存Bridge绑定预期身份与在线原时间，不宣称持久保存', () async {
    final client = fixtures.OnlineClient();
    final backend = BridgeBackend(client);
    final task = (await backend.beginAccountFeatureRead(
      FeatureId.judge,
      null,
      const LocalAccount(id: 'synthetic-account', username: 'fixture-user'),
    ))!;
    expect(client.options!.expectedIdentity, 'fixture-user');
    await task.next();
    final last = await task.next();
    expect(last.result.evidence!.accountId, 'synthetic-account');
    expect(last.result.evidence!.origin, DataOrigin.online);
    expect(last.result.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(last.result.evidence!.savedForOffline, isFalse);
    task.cancel();
  });
  test('无缓存Bridge身份冲突保持显式账号错误', () async {
    final backend = BridgeBackend(_Mismatch());
    await expectLater(
      backend.beginAccountFeatureRead(
        FeatureId.judge,
        null,
        const LocalAccount(id: 'synthetic-account', username: 'fixture-user'),
      ),
      throwsA(
        isA<BackendException>().having(
          (error) => error.accountMismatch,
          '账号冲突',
          isTrue,
        ),
      ),
    );
  });
}

class _Accounts implements LocalAccountStore {
  @override
  Future<LocalAccountState?> read() async => const LocalAccountState(
    account: LocalAccount(id: 'synthetic-account', username: 'fixture-user'),
    canRestore: true,
    generation: 1,
  );
  @override
  Future<Uint8List> cacheKey(LocalAccount account) async =>
      throw StateError('合成密钥不可读');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScopedBackend extends startup.FakeRecoveryBackend
    implements
        AccountScopedProgressiveReadBackend,
        OfflineCacheBackend,
        FeatureQueryBackend {
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => throw StateError('必须逐批读取');
  LocalAccount? account;
  int ordinary = 0, opens = 0;
  @override
  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
  ) async {
    if (feature != FeatureId.judge) return null;
    this.account = account;
    return _Task();
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    ordinary++;
    throw StateError('已知账号必须使用账号范围入口');
  }

  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {
    opens++;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead(const []);
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount() async {}
}

class _Task implements FeatureReadTask {
  @override
  void cancel() {}
  @override
  Future<FeatureReadBatch> next() async =>
      const FeatureReadBatch(FeatureResult.empty(), finished: true);
}

class _Mismatch extends fixtures.OnlineClient {
  @override
  Future<BridgeJudgeOnlineTask> beginJudgeOnline({
    required BridgeJudgeOnlineOptions options,
  }) async => throw const BridgeError(
    code: BridgeErrorCode.cacheIdentityMismatch,
    kind: BridgeErrorKind.authentication,
    retryable: false,
    message: '合成账号不符',
    resolvedRoute: BridgeConnectionMode.direct,
  );
}
