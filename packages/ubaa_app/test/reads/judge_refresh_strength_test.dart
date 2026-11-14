import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart' as support;
import 'progressive_test.dart' show until;

void main() {
  test('退出后取消等待中的主动核验，不启动后续学校读取', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    await controller.initialize();
    backend.gated = true;
    final automatic = controller.internalAutomaticSchoolAction(
      () => controller.internalRefreshHome(only: [FeatureId.judge]),
    );
    await until(() => backend.queries.length == 1);
    final manual = controller.refreshHome(only: [FeatureId.judge]);
    controller.dispose();
    backend.gates[0].complete();
    await Future.wait([automatic, manual]);
    expect(backend.queries.length, 1);
  });
  test('自动计划结束后合并执行一次主动核验，所有主动调用等待新结果', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    backend.gated = true;
    final automatic = controller.internalAutomaticSchoolAction(
      () => controller.internalRefreshHome(only: [FeatureId.judge]),
    );
    await until(() => backend.queries.length == 1);
    var completed = 0;
    final first = controller
        .refreshHome(only: [FeatureId.judge])
        .then((_) => completed++);
    final second = controller
        .refreshHome(only: [FeatureId.judge])
        .then((_) => completed++);
    expect(backend.queries.single?.refreshActiveDetails ?? false, isFalse);
    backend.gates[0].complete();
    await automatic;
    await until(() => backend.queries.length == 2 || completed > 0);
    expect(backend.queries.length, 2);
    expect(backend.queries.last!.refreshActiveDetails, isTrue);
    expect(completed, 0);
    backend.gates[1].complete();
    await Future.wait([first, second]);
    expect(completed, 2);
    expect(backend.queries.length, 2);
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements ProgressiveReadBackend, ConcurrentReadBackend {
  bool gated = false;
  final queries = <FeatureQuery?>[];
  final gates = List.generate(2, (_) => Completer<void>());
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (!gated || feature != FeatureId.judge) return null;
    final index = queries.length;
    queries.add(query);
    return _Task(gates[index].future);
  }
}

class _Task implements FeatureReadTask {
  _Task(this.gate);
  final Future<void> gate;
  @override
  Future<FeatureReadBatch> next() async {
    await gate;
    return const FeatureReadBatch(FeatureResult.empty(), finished: true);
  }

  @override
  void cancel() {}
}
