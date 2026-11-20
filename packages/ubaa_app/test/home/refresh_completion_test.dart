import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_test_support/recovery.dart';

void main() {
  test('首次加载先交付课程待办，考试到达后再补入首页', () async {
    final backend = _ExamBackend();
    final exam = backend.exam = Completer<FeatureResult>();
    final controller = _attachHome(backend);

    await controller.initialize();
    await _settleHome(controller);

    expect(backend.examReads, 1);
    expect(controller.homeState.todos.map((todo) => todo.title), ['课程待办 1']);
    expect(
      controller.homeState.sources[FeatureId.exam]!.status,
      FeatureLoadStatus.loading,
    );
    expect(controller.homeState.busy, isFalse);

    exam.complete(
      const FeatureResult.success(details: [FeatureDetail(title: '新考试')]),
    );
    await _settleHome(controller);

    expect(controller.homeState.busy, isFalse);
    expect(
      controller.homeState.todos.map((todo) => todo.title),
      unorderedEquals(['课程待办 1', '新考试']),
    );
  });

  test('下拉刷新完成时考试仍在途，再次刷新复用同一考试读取，失败保留旧待办', () async {
    final backend = _ExamBackend();
    final controller = _attachHome(backend);
    await controller.initialize();
    await _settleHome(controller);
    final exam = backend.exam = Completer<FeatureResult>();

    for (final round in [2, 3]) {
      var completed = false;
      final refresh = controller.refreshHomePage().then<void>((_) {
        completed = true;
      });
      await _settleHome(controller);

      expect(backend.examReads, 2);
      expect(
        controller.homeState.todos.map((todo) => todo.title),
        unorderedEquals(['课程待办 $round', '已有考试']),
      );
      expect(completed, isTrue);
      expect(controller.homeState.busy, isFalse);
      expect(backend.closedBatches, [1]);
      await refresh;
    }

    exam.completeError(const BackendException(UbaaErrorCode.networkError));
    await _settleHome(controller);

    final source = controller.homeState.sources[FeatureId.exam]!;
    expect(source.status, FeatureLoadStatus.stale);
    expect(source.error?.code, UbaaErrorCode.networkError);
    expect(controller.homeState.busy, isFalse);
    expect(backend.examReads, 2);
    expect(backend.closedBatches, unorderedEquals([1, 2, 3]));
    expect(
      controller.homeState.todos.map((todo) => todo.title),
      unorderedEquals(['课程待办 3', '已有考试']),
    );
  });

  test('考试单项重试和完整刷新等待在途考试', () async {
    final backend = _ExamBackend();
    final exam = backend.exam = Completer<FeatureResult>();
    final controller = _attachHome(backend);
    await controller.initialize();
    await _settleHome(controller);

    final completed = <String>[];
    final retry = controller
        .retryHomeSource(FeatureId.exam)
        .then((_) => completed.add('单项重试'));
    final full = controller.refreshHome().then((_) => completed.add('完整刷新'));
    await _settleHome(controller);

    expect(completed, isEmpty);
    expect(backend.examReads, 1);

    exam.complete(const FeatureResult.empty());
    await Future.wait([retry, full]);

    expect(completed, unorderedEquals(['单项重试', '完整刷新']));
    expect(
      controller.homeState.sources[FeatureId.exam]!.status,
      FeatureLoadStatus.empty,
    );
  });

  test('注销后迟到的考试结果不进入首页', () async {
    final backend = _ExamBackend();
    final exam = backend.exam = Completer<FeatureResult>();
    final controller = _attachHome(backend);
    await controller.initialize();
    await _settleHome(controller);
    expect(backend.examReads, 1);

    await controller.logout();
    exam.complete(
      const FeatureResult.success(details: [FeatureDetail(title: '旧会话考试')]),
    );
    await _settleHome(controller);

    expect(controller.homeState.todos, isEmpty);
    expect(controller.homeState.sources[FeatureId.exam]!.details, isEmpty);
  });

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

AppController _attachHome(_ExamBackend backend) {
  final controller = AppController(backend: backend)..attachHomePresentation();
  addTearDown(() {
    controller.dispose();
    final exam = backend.exam;
    if (exam != null && !exam.isCompleted) {
      exam.complete(const FeatureResult.empty());
    }
  });
  return controller;
}

Future<void> _settleHome(AppController controller) async {
  await Future<void>.delayed(Duration.zero);
  await controller.internalFlushHomeProjection();
}

class _ExamBackend extends FakeRecoveryBackend
    implements
        ConcurrentReadBackend,
        FeatureQueryBackend,
        HomeRecoveryBatchBackend,
        HomeTodoBackend,
        ProgressiveReadBackend {
  Completer<FeatureResult>? exam;
  int examReads = 0, spocReads = 0;
  int _batches = 0;
  final closedBatches = <int>[];

  @override
  Future<int> beginHomeRecoveryBatch() async => ++_batches;

  @override
  Future<void> endHomeRecoveryBatch(int batch) async =>
      closedBatches.add(batch);

  @override
  Future<void> invalidateHomeRecoveryBatch() async {}

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature == FeatureId.exam) {
      examReads++;
      if (exam case final pending?) return pending.future;
      return const FeatureResult.success(
        details: [FeatureDetail(title: '已有考试')],
      );
    }
    if (feature == FeatureId.spoc) {
      return FeatureResult.success(
        details: [FeatureDetail(title: '课程待办 ${++spocReads}')],
      );
    }
    return const FeatureResult.empty();
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => const FeatureResult.empty();

  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) async =>
      HomeTodoProjection([
        for (final feature in [FeatureId.spoc, FeatureId.exam])
          for (final row
              in request.snapshots[feature]?.details ?? <FeatureDetail>[])
            HomeTodo(
              id: row.title,
              feature: feature,
              title: row.title,
              subtitle: '',
              statusLabel: '',
              timeLabel: '',
              sortTime: request.now,
            ),
      ]);
}
