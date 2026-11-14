import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  test('关闭客户端后批次收尾不产生未捕获错误', () async {
    final backend = _Backend()..failEnd = true;
    final controller = AppController(backend: backend);
    await controller.initialize();
    await backend.started.future;
    controller.dispose();
    backend.detail.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.ends, 1);
  });

  test('首页首批完成后返回，身份复用批次在后台详情结束后关闭', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    addTearDown(() {
      if (!backend.detail.isCompleted) backend.detail.complete();
    });
    await controller.initialize();
    await backend.started.future;
    await controller.internalAutomaticSchoolAction(
      () => controller.internalRefreshHome(firstBatch: true),
    );
    expect(controller.homeSnapshots[FeatureId.judge]!.refining, isTrue);
    expect(backend.ends, 0);
    expect(backend.begins, 1);
    backend.detail.complete();
    await backend.ended.future;
    expect(backend.ends, 1);
    expect(
      controller.homeSnapshots[FeatureId.judge]!.details.single.title,
      '完整结果',
    );
  });
}

class _Backend extends FakeRecoveryBackend
    implements
        ProgressiveReadBackend,
        ConcurrentReadBackend,
        HomeRecoveryBatchBackend {
  final started = Completer<void>(), detail = Completer<void>();
  final ended = Completer<void>();
  int begins = 0, ends = 0;
  bool failEnd = false;
  @override
  Future<int> beginHomeRecoveryBatch() async => ++begins;
  @override
  Future<void> endHomeRecoveryBatch(int batch) async {
    ends++;
    if (failEnd)
      throw const BackendException(
        UbaaErrorCode.operationConflict,
        clientDisposed: true,
      );
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<void> invalidateHomeRecoveryBatch() async {}
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => feature == FeatureId.judge ? _Task(this) : null;
}

class _Task implements FeatureReadTask {
  _Task(this.backend);
  final _Backend backend;
  bool first = true;
  @override
  Future<FeatureReadBatch> next() async {
    if (first) {
      first = false;
      if (!backend.started.isCompleted) backend.started.complete();
      return const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批结果')]),
        finished: false,
      );
    }
    await backend.detail.future;
    return const FeatureReadBatch(
      FeatureResult.success(details: [FeatureDetail(title: '完整结果')]),
      finished: true,
    );
  }

  @override
  void cancel() {}
}
