import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_test_support/ubaa_test_support.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

const _homeSources = [
  FeatureId.schedule,
  FeatureId.signin,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.ygdk,
  FeatureId.exam,
];

void main() {
  test('恢复首页只读取展示所需来源，未访问功能保持待加载', () async {
    final backend = _HomeLoadingBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(backend.reads, _homeSources);
    for (final feature in FeatureId.values) {
      expect(
        controller.snapshots[feature]!.status,
        _homeSources.contains(feature)
            ? FeatureLoadStatus.success
            : FeatureLoadStatus.idle,
      );
    }
  });

  test('刷新首页不重读无关功能，显式打开仍能单独加载', () async {
    final backend = _HomeLoadingBackend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await Future<void>.delayed(Duration.zero);
    await controller.retryFeature(FeatureId.classroom);
    final classroom = controller.snapshots[FeatureId.classroom];
    backend.reads.clear();

    await controller.refreshHome();
    expect(backend.reads, _homeSources);
    expect(controller.snapshots[FeatureId.classroom], same(classroom));

    backend.reads.clear();
    await controller.retryFeature(FeatureId.evaluation);
    expect(backend.reads, [FeatureId.evaluation]);
    expect(
      controller.snapshots[FeatureId.evaluation]!.status,
      FeatureLoadStatus.success,
    );
  });

  test('串行网络下签到在第二次读取后显示，不排在无关功能之后', () async {
    final schedule = Completer<void>();
    final signin = Completer<void>();
    final remaining = Completer<void>();
    final backend = _HomeLoadingBackend(
      waitBeforeRead: (feature) => switch (feature) {
        FeatureId.schedule => schedule.future,
        FeatureId.signin => signin.future,
        _ => remaining.future,
      },
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    try {
      await controller.initialize();
      schedule.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.homeSnapshots[FeatureId.schedule]!.status,
        FeatureLoadStatus.success,
      );
      signin.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.homeSnapshots[FeatureId.signin]!.status,
        FeatureLoadStatus.success,
      );
      expect(
        controller.homeSnapshots[FeatureId.spoc]!.status,
        FeatureLoadStatus.loading,
      );
    } finally {
      for (final gate in [schedule, signin, remaining]) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
  });
}

class _HomeLoadingBackend extends DemoBackend {
  _HomeLoadingBackend({this.waitBeforeRead});

  final Future<void> Function(FeatureId feature)? waitBeforeRead;
  final reads = <FeatureId>[];
  Future<void> _tail = Future.value();

  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-home-loading');

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) {
    reads.add(feature);
    final pending = _tail.then((_) async {
      await waitBeforeRead?.call(feature);
      return FeatureResult.success(
        details: [FeatureDetail(title: '合成${feature.title}')],
        resolvedRoute: ConnectionMode.direct,
      );
    });
    _tail = pending.then((_) {});
    return pending;
  }
}
