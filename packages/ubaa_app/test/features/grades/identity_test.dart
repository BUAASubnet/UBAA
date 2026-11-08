import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'aggregate_test.dart' as fixtures;
import 'package:ubaa_test_support/recovery.dart' as startup;

void main() {
  test('未保留本机账号的宿主遇身份冲突后也不能准备学校写入', () async {
    final controller = AppController(backend: _LegacyBackend());
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.loadAllGrades();
    expect(controller.phase, AppPhase.login);
    var prepares = 0;
    await controller.writeCoordinator
        .prepare(() async {
          prepares++;
          throw const BackendException(UbaaErrorCode.internalError);
        })
        .catchError((Object _) => null);
    expect(prepares, 0);
  });

  for (final target in [FeatureId.schedule, FeatureId.grades]) {
    test('辅助$target读取确认账号不一致后隐藏旧缓存并禁止准备', () async {
      final accounts = await startup.savedAccounts();
      final backend = _Backend(target)..online = true;
      final controller = AppController(
        backend: backend,
        localAccountStore: accounts,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.recoverSession(refreshHomeAfter: false);
      final result = await controller.loadAllGrades();
      expect(controller.phase, AppPhase.login);
      expect(result.terms, isEmpty);
      expect((await accounts.read())!.canRestore, isFalse);
      expect(backend.closed, 1);
      var prepares = 0;
      await controller.writeCoordinator.prepare(() async {
        prepares++;
        throw const BackendException(UbaaErrorCode.internalError);
      });
      expect(prepares, 0);
    });
  }
  test('旧路线迟到的账号不一致错误不关闭当前路线账号', () async {
    final accounts = await startup.savedAccounts();
    final backend = _Backend(FeatureId.grades)
      ..online = true
      ..gate = Completer<void>();
    final controller = AppController(
      backend: backend,
      localAccountStore: accounts,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession(refreshHomeAfter: false);
    final pending = controller.loadGradeTerm('a');
    try {
      await backend.started.future.timeout(const Duration(seconds: 5));
      await controller.setRoutePolicy(RoutePolicy.webvpn);
    } finally {
      backend.gate!.complete();
    }
    await pending;
    expect(controller.phase, AppPhase.home);
    expect((await accounts.read())!.canRestore, isTrue);
    expect(backend.closed, 0);
  });
}

class _Backend extends fixtures.GradesBackend {
  _Backend(this.target);
  final FeatureId target;
  Completer<void>? gate;
  final started = Completer<void>();
  int closed = 0;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.gradesOverview &&
        target == FeatureId.schedule)
      return const FeatureResult.empty();
    if (feature == target) {
      if (!started.isCompleted) started.complete();
      await gate?.future;
      throw const BackendException(
        UbaaErrorCode.authenticationRequired,
        accountMismatch: true,
        kind: UbaaErrorKind.authentication,
      );
    }
    return super.loadFeatureQuery(feature, query);
  }

  @override
  Future<void> deactivateOfflineAccount() async {
    closed++;
  }
}

class _LegacyBackend extends startup.FakeRecoveryBackend
    implements FeatureQueryBackend {
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => throw const BackendException(
    UbaaErrorCode.authenticationRequired,
    accountMismatch: true,
    kind: UbaaErrorKind.authentication,
  );
}
