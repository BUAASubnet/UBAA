import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

class Backend extends support.FakeRecoveryBackend
    implements OfflineCacheBackend, BackendLifecycle, WriteCommitBackend {
  bool dead = false;
  int disposed = 0, opens = 0;
  Completer<void>? disposeGate;
  final disposeStarted = Completer<void>();
  final cached = Completer<void>();
  LocalAccount? account;
  final fetched = DateTime.utc(2026, 9, 21);
  @override
  Future<AuthStatus> authStatus() {
    if (dead) return BridgeBackend(DisposedClient()).authStatus();
    return super.authStatus();
  }

  @override
  Future<void> dispose() async {
    disposed++;
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    await disposeGate?.future;
  }

  @override
  Future<void> openOfflineAccount(LocalAccount account, List<int> key) async {
    this.account = account;
    opens++;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async {
    if (!cached.isCompleted) cached.complete();
    return OfflineHomeRead([
      CachedFeatureProjection(
        feature: FeatureId.schedule,
        accountId: account!.id,
        route: ConnectionMode.direct,
        fetchedAt: fetched,
        complete: true,
        details: const [FeatureDetail(title: '合成缓存课程')],
      ),
    ]);
  }

  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> clearOfflineAccount() async {}
  @override
  Future<void> discardWriteIntent(String intentId) async {}
  @override
  Future<WriteCommitResult> commitWrite(String intentId) =>
      throw StateError('句柄恢复测试禁止学校提交');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      throw const BackendException(UbaaErrorCode.networkError);
}

class DisposedClient implements BridgeClient {
  @override
  int contractVersion() => 43;
  @override
  Future<BridgeLoginOutcome> authStatus() async => throw const BridgeError(
    code: BridgeErrorCode.clientDisposed,
    kind: BridgeErrorKind.internal,
    retryable: false,
    message: '合成已释放客户端',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QueryBackend extends Backend
    implements FeatureQueryBackend, ProgressiveReadBackend {
  Completer<FeatureResult>? queryGate;
  final queries = <FeatureQuery>[];
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    queries.add(query);
    if (queryGate case final gate?) return gate.future;
    if (dead)
      throw const BackendException(
        UbaaErrorCode.internalError,
        clientDisposed: true,
      );
    return const FeatureResult.success(
      details: [FeatureDetail(title: '继任实例的新查询')],
    );
  }
}

Future<void> cachedHome(AppController controller, Backend backend) async {
  await controller.initialize();
  await backend.cached.future;
  await Future<void>.delayed(Duration.zero);
}

WriteIntent intent() => WriteIntent(
  intentId: 'synthetic',
  operation: WriteOperation.bykcSelectCourse,
  targetSummary: '合成目标',
  resolvedRoute: ConnectionMode.direct,
  warnings: const [],
  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  requestDigest: 'synthetic',
);
