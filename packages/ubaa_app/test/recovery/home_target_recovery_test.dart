import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_test_support/recovery.dart' as support;

void main() {
  test('已有主会话的单项校验不发布新账号代次或重绑共享后端', () async {
    final backend = _SharedBackend();
    final accounts = await support.savedAccounts() as SecureLocalAccountStore;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    final generation = (await accounts.read())!.generation;
    final bindings = backend.sharedGeneration;
    await controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    expect((await accounts.read())!.generation, generation);
    expect(backend.sharedGeneration, bindings);
    expect(
      controller.recoveryStatusFor(FeatureId.spoc),
      SessionRecoveryStatus.ready,
    );
  });

  test('单项目标恢复期间纯本地首页待办投影仍可用', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);

    backend.gateSpoc = true;
    final recovery = controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    await backend.spocStarted.future;

    expect(controller.homeTodoProjectionBlocked, isFalse);
    final projection = await controller.projectHomeTodos(
      HomeTodoRequest(snapshots: const {}, now: DateTime(2026, 11, 7)),
    );
    expect(projection.todos, isEmpty);

    backend.releaseSpoc.complete();
    await recovery;
  });

  test('单项目标恢复中的共享账号撤销不能恢复全局 ready', () async {
    final backend = _Backend();
    final accounts = await support.savedAccounts() as SecureLocalAccountStore;
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    backend.gateSpoc = true;
    final recovery = controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    await backend.spocStarted.future;
    await accounts.revokeIfCurrent((await accounts.capture())!);
    backend.releaseSpoc.complete();
    await recovery;
    expect(
      controller.sessionRecoveryStatus,
      isNot(SessionRecoveryStatus.ready),
    );
    expect(
      controller.recoveryStatusFor(FeatureId.spoc),
      isNot(SessionRecoveryStatus.ready),
    );
  });

  test('单项读取等待自身目标恢复，其他功能可继续读取', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    backend.gateSpoc = true;
    final reading = controller.refreshHome(only: [FeatureId.spoc]);
    await backend.spocStarted.future;
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(backend.spocReads, 0);
    backend.releaseSpoc.complete();
    await reading;
    expect(backend.spocReads, 1);
  });

  for (final code in [
    UbaaErrorCode.networkError,
    UbaaErrorCode.invalidCredentials,
  ]) {
    test('单项恢复失败保留账号级状态：${code.name}', () async {
      final backend = _Backend();
      final controller = AppController(
        backend: backend,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      backend.spocError = BackendException(code);
      await controller.recoverSession(
        feature: FeatureId.spoc,
        refreshHomeAfter: false,
      );
      expect(
        controller.sessionRecoveryStatus,
        code == UbaaErrorCode.networkError
            ? SessionRecoveryStatus.ready
            : SessionRecoveryStatus.needsLogin,
      );
      expect(
        controller.recoveryStatusFor(FeatureId.spoc),
        code == UbaaErrorCode.networkError
            ? SessionRecoveryStatus.unavailable
            : SessionRecoveryStatus.needsLogin,
      );
    });
  }

  test('共享账号主会话恢复重绑后重新准备旧读取计划', () async {
    final backend = _SharedBackend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(
      feature: FeatureId.judge,
      refreshHomeAfter: false,
    );
    final reading = controller.refreshHome(only: [FeatureId.judge]);
    await backend.judgeSecondBatchStarted.future;
    await controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: true,
    );
    backend.releaseJudgeSecond.complete();
    await reading;
    expect(controller.homeSnapshots[FeatureId.judge]!.error, isNull);
    expect(
      controller.homeSnapshots[FeatureId.judge]!.details.single.title,
      '完整作业',
    );
    expect(backend.judgePlans, 2);
  });

  test('后端缓存代次变化使投影冲突时交付为被取代，首页可稍后重算', () async {
    final backend = _Backend()..projectionConflict = true;
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await expectLater(
      controller.projectHomeTodos(
        HomeTodoRequest(snapshots: const {}, now: DateTime(2026, 11, 7)),
      ),
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          'failure',
          AgendaFailure.superseded,
        ),
      ),
    );
  });

  test('目标恢复期间已在途的其他首页读取继续完成，不交付操作冲突', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(
      feature: FeatureId.judge,
      refreshHomeAfter: false,
    );

    final reading = controller.refreshHome(only: [FeatureId.judge]);
    await backend.judgeFirstBatch.future;
    backend.gateSpoc = true;
    final recovery = controller.recoverSession(
      feature: FeatureId.spoc,
      refreshHomeAfter: false,
    );
    await backend.spocStarted.future;
    backend.releaseJudgeSecond.complete();

    try {
      await reading.timeout(const Duration(milliseconds: 500));
      expect(controller.homeSnapshots[FeatureId.judge]!.error, isNull);
    } finally {
      if (!backend.releaseSpoc.isCompleted) backend.releaseSpoc.complete();
      await recovery;
    }
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements RequiredSessionBackend, ProgressiveReadBackend, HomeTodoBackend {
  final spocStarted = Completer<void>();
  final releaseSpoc = Completer<void>();
  final judgeFirstBatch = Completer<void>();
  final judgeSecondBatchStarted = Completer<void>();
  final releaseJudgeSecond = Completer<void>();
  bool gateSpoc = false;
  bool projectionConflict = false;
  int spocReads = 0;
  int sharedGeneration = 0;
  int judgePlans = 0;
  BackendException? spocError;

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    if (feature == FeatureId.spoc && gateSpoc) {
      if (!spocStarted.isCompleted) spocStarted.complete();
      await releaseSpoc.future;
    }
    if (feature == FeatureId.spoc && spocError != null) throw spocError!;
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<RecoveredRouteSession> loginRequiredRoute(
    ConnectionMode route,
    LoginInput input,
  ) async => RecoveredRouteSession(
    route: route,
    profile: const UserSummary(username: 'fixture-user'),
  );

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => feature == FeatureId.judge ? _JudgeTask(this) : null;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature == FeatureId.spoc) spocReads++;
    return const FeatureResult.empty();
  }

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async {
    if (projectionConflict) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    return HomeTodoProjection(const []);
  }
}

class _JudgeTask implements FeatureReadTask {
  _JudgeTask(this.backend) : generation = backend.sharedGeneration {
    backend.judgePlans++;
  }
  final int generation;
  final _Backend backend;
  var calls = 0;

  @override
  Future<FeatureReadBatch> next() async {
    calls++;
    if (calls == 1) {
      if (!backend.judgeFirstBatch.isCompleted) {
        backend.judgeFirstBatch.complete();
      }
      return const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批作业')]),
        finished: false,
      );
    }
    if (!backend.judgeSecondBatchStarted.isCompleted) {
      backend.judgeSecondBatchStarted.complete();
    }
    await backend.releaseJudgeSecond.future;
    if (generation != backend.sharedGeneration)
      throw const BackendException(UbaaErrorCode.operationConflict);
    return const FeatureReadBatch(
      FeatureResult.success(details: [FeatureDetail(title: '完整作业')]),
      finished: true,
    );
  }

  @override
  void cancel() {}
}

class _SharedBackend extends _Backend implements SharedAccountBackend {
  @override
  Future<void> bindSharedAccount(SharedAccountBinding binding) async {
    await binding.validate();
    sharedGeneration++;
  }
}
