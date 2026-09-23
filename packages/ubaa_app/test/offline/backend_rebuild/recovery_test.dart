import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../startup_test.dart' as support;
import 'fakes.dart';

void main() {
  test('明确已释放句柄只重建一次，恢复期间缓存首页和时间不消失', () async {
    final first = Backend()..dead = true;
    final next = Backend();
    var created = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        created++;
        return next;
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    final phases = <AppPhase>[];
    final content = <String?>[];
    controller.addListener(() {
      phases.add(controller.phase);
      content.add(
        controller
            .homeSnapshots[FeatureId.schedule]!
            .details
            .firstOrNull
            ?.title,
      );
    });
    final one = controller.resumeSession();
    final two = controller.resumeSession();
    expect(identical(one, two), isTrue);
    await Future.wait([one, two]);
    expect(created, 1);
    expect(first.disposed, 1);
    expect(next.authCalls, 1);
    expect(next.opens, 1);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.ready);
    expect(phases, everyElement(AppPhase.home));
    expect(content, everyElement('合成缓存课程'));
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.updatedAt,
      first.fetched,
    );
  });

  for (final code in [
    UbaaErrorCode.networkError,
    UbaaErrorCode.internalError,
  ]) {
    test('普通${code.name}不触发客户端重建', () async {
      final first = Backend()..authError = BackendException(code);
      var created = 0;
      final controller = AppController(
        backend: first,
        backendFactory: () {
          created++;
          return Backend();
        },
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await cachedHome(controller, first);
      await controller.resumeSession();
      expect(created, 0);
      expect(first.disposed, 0);
      expect(controller.error?.code, code);
      expect(controller.phase, AppPhase.home);
    });
  }

  test('继任句柄仍失效时原位报错，不循环重建', () async {
    final first = Backend()..dead = true;
    var created = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        created++;
        return Backend()..dead = true;
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    await controller.resumeSession();
    expect(created, 1);
    expect(controller.sessionRecoveryStatus, SessionRecoveryStatus.unavailable);
    expect(controller.phase, AppPhase.home);
    expect(
      controller.homeSnapshots[FeatureId.schedule]!.details.single.title,
      '合成缓存课程',
    );
  });

  test('写意图未结束时不检查或重建，取消后恢复一次且不提交', () async {
    final first = Backend();
    var created = 0;
    final controller = AppController(
      backend: first,
      backendFactory: () {
        created++;
        return Backend();
      },
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await cachedHome(controller, first);
    await controller.recoverSession(refreshHomeAfter: false);
    controller.writeCoordinator.setIntent(intent());
    first.dead = true;
    final recovery = controller.resumeSession();
    expect(created, 0);
    expect(controller.writeCoordinator.intent, isNotNull);
    await controller.writeCoordinator.cancelForUi();
    await recovery;
    expect(created, 1);
    expect(controller.writeCoordinator.intent, isNull);
  });

  for (final destroy in [false, true]) {
    test('旧实例释放挂起时${destroy ? "销毁" : "退出"}拒绝继任实例与迟到缓存', () async {
      final first = Backend()
        ..dead = true
        ..disposeGate = Completer<void>();
      final next = Backend();
      final controller = AppController(
        backend: first,
        backendFactory: () => next,
        localAccountStore: await support.savedAccounts(),
      );
      addTearDown(controller.dispose);
      await cachedHome(controller, first);
      final recovering = controller.resumeSession();
      await Future<void>.delayed(Duration.zero);
      try {
        expect(first.disposed, 1);
        if (destroy) {
          controller.dispose();
        } else {
          await controller.logout();
        }
      } finally {
        first.disposeGate!.complete();
        await recovering;
      }
      expect(next.disposed, 1);
      expect(next.authCalls, 0);
      expect(next.opens, 0);
      if (!destroy) {
        expect(controller.phase, AppPhase.login);
        expect(controller.homeSnapshots[FeatureId.schedule]!.details, isEmpty);
      }
    });
  }
}
