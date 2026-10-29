import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../recovery/startup_test.dart' as support;
import 'progressive_test.dart' show until;

void main() {
  test('课表在途时其他首页业务开始，教务考试等待同组课表', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    addTearDown(backend.release);
    await controller.initialize();
    await until(() => backend.started.contains(FeatureId.schedule));
    await until(
      () => backend.started.containsAll([
        FeatureId.signin,
        FeatureId.spoc,
        FeatureId.judge,
      ]),
    );
    expect(backend.started, isNot(contains(FeatureId.exam)));
    expect(backend.maximumActive, greaterThan(1));
    backend.release();
    await until(() => backend.started.contains(FeatureId.exam));
  });

  test('并行在途读取在退出后不能回填首页', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    addTearDown(backend.release);
    await controller.initialize();
    await until(() => backend.started.length > 1);
    final logout = controller.logout();
    backend.release();
    await logout;
    expect(controller.phase, AppPhase.login);
    expect(
      controller.homeSnapshots.values.every(
        (snapshot) => snapshot.details.isEmpty,
      ),
      isTrue,
    );
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements ProgressiveReadBackend, ConcurrentReadBackend {
  final readGate = Completer<void>();
  final started = <FeatureId>{};
  int active = 0;
  int maximumActive = 0;
  void release() {
    if (!readGate.isCompleted) readGate.complete();
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    started.add(feature);
    active++;
    if (active > maximumActive) maximumActive = active;
    await readGate.future;
    active--;
    return const FeatureResult.success(details: [FeatureDetail(title: '合成结果')]);
  }
}
