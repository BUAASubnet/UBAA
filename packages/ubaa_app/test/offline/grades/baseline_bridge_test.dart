import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

const account = LocalAccount(id: 'synthetic-account', username: 'synthetic');
const latest = GradeScoreBaseline(
  termCode: '2026-2027-1',
  termName: '合成学期',
  scores: [
    GradeScoreEntry(
      key: 'code:safe',
      courseCode: 'safe',
      courseName: '合成课程',
      score: '90',
    ),
  ],
);
void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  late BridgeBackend backend;
  setUp(() async {
    api.cache = _Cache();
    backend = BridgeBackend(_Client(), configDirectory: '/synthetic');
    await backend.openOfflineAccount(account, List.filled(32, 19));
  });
  Future<GradeScoreBaseline?> update({String id = 'synthetic-account'}) =>
      backend.updateGradeScoreBaseline(
        accountId: id,
        route: ConnectionMode.webvpn,
        latest: latest,
        legacy: latest,
      );
  test('成绩基线完整映射实际路线和字段，不打开网络客户端', () async {
    final previous = await update();
    expect(api.cache.route, BridgeConnectionMode.webVpn);
    expect(api.cache.latest!.termCode, latest.termCode);
    expect(api.cache.latest!.scores.single.key, 'code:safe');
    expect(api.cache.legacy!.scores.single.courseName, '合成课程');
    expect(previous!.scores.single.score, '90');
    expect(previous.termName, '合成学期');
  });
  test('错误账号被拒绝，Bridge缓存失败字段原样映射', () async {
    await expectLater(
      update(id: 'other'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '账号隔离',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    expect(api.cache.calls, 0);
    api.cache.failure = true;
    await expectLater(
      update(),
      throwsA(
        isA<BackendException>().having(
          (e) => e.cacheFailure,
          '本机错误',
          CacheMaintenanceFailure.capacity,
        ),
      ),
    );
  });
  test('退出期间迟到基线不能作为当前观察交付', () async {
    api.cache.gate = Completer<void>();
    final pending = update();
    final checked = expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    await api.cache.started.future;
    await backend.deactivateOfflineAccount();
    api.cache.gate!.complete();
    await checked;
  });
}

class _Api implements RustLibApi {
  late _Cache cache;
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => cache;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  @override
  int contractVersion() => 37;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  int calls = 0;
  bool failure = false;
  BridgeConnectionMode? route;
  BridgeGradeScoreBaseline? latest, legacy;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<BridgeGradeScoreBaseline?> updateGradeScoreBaseline({
    required BridgeConnectionMode route,
    required BridgeGradeScoreBaseline latest,
    BridgeGradeScoreBaseline? legacy,
  }) async {
    calls++;
    this.route = route;
    this.latest = latest;
    this.legacy = legacy;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    if (failure)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        message: '合成容量不足',
        kind: BridgeErrorKind.internal,
        retryable: false,
        cacheFailure: BridgeCacheFailure.capacity,
      );
    return legacy;
  }

  @override
  Future<void> activate() async {}
  @override
  Future<void> deactivate() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
