import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../recovery/startup_test.dart' as support;
import 'progressive_test.dart' show until;

void main() {
  for (final feature in [FeatureId.judge, FeatureId.spoc]) {
    test('${feature.name} 首个可展示批次不等待慢考试，后续批次仍让位', () async {
      final backend = _Backend(feature, feature == FeatureId.spoc ? 2 : 0);
      final controller = AppController(backend: backend);
      addTearDown(controller.dispose);
      addTearDown(() {
        if (!backend.exam.isCompleted) backend.exam.complete();
      });
      await controller.initialize();
      await until(() => backend.events.contains('考试开始'));
      expect(
        controller.homeSnapshots[feature]!.details.map((item) => item.title),
        ['首批作业'],
        reason: '考试仍在等待时首页应已有作业内容',
      );
      expect(backend.task.calls, backend.preparations + 1);
      backend.exam.complete();
      await until(() => backend.events.contains('作业结束'));
      expect(
        backend.events.indexOf('首批作业'),
        lessThan(backend.events.indexOf('考试开始')),
      );
      expect(
        backend.events.indexOf('考试结束'),
        lessThan(backend.events.indexOf('作业结束')),
      );
    });
  }

  test('连续准备步骤受限，不能一直抢占其他首页来源', () async {
    final backend = _Backend(FeatureId.spoc, 5);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    addTearDown(() {
      if (!backend.exam.isCompleted) backend.exam.complete();
    });
    await controller.initialize();
    await until(() => backend.events.contains('考试开始'));
    expect(backend.task.calls, greaterThan(0));
    expect(backend.task.calls, lessThan(backend.preparations));
    backend.exam.complete();
    await until(() => backend.events.contains('作业结束'));
    expect(
      controller.homeSnapshots[FeatureId.spoc]!.details.single.title,
      '完整作业',
    );
  });
}

class _Backend extends support.FakeRecoveryBackend
    implements ProgressiveReadBackend {
  _Backend(this.feature, this.preparations);
  final FeatureId feature;
  final int preparations;
  final events = <String>[];
  final exam = Completer<void>();
  late final task = _Task(this);

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => feature == this.feature ? task : null;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature == FeatureId.exam) {
      events.add('考试开始');
      await exam.future;
      events.add('考试结束');
    }
    return const FeatureResult.empty();
  }
}

class _Task implements FeatureReadTask {
  _Task(this.backend);
  final _Backend backend;
  int calls = 0;
  @override
  Future<FeatureReadBatch> next() async {
    calls++;
    if (calls <= backend.preparations) {
      return const FeatureReadBatch(
        FeatureResult.empty(),
        finished: false,
        publish: false,
      );
    }
    final finished = calls > backend.preparations + 1;
    backend.events.add(finished ? '作业结束' : '首批作业');
    return FeatureReadBatch(
      FeatureResult.success(
        details: [FeatureDetail(title: finished ? '完整作业' : '首批作业')],
      ),
      finished: finished,
    );
  }

  @override
  void cancel() {}
}
