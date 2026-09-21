import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'startup_test.dart' as support;

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue);
}

void main() {
  test('首批立即呈现，通知中进入签到时先读当前任务再发后台下一批', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    Future<void>? query;
    var requested = false;
    controller.addListener(() {
      if (!requested &&
          controller.homeSnapshots[FeatureId.judge]!.details.isNotEmpty) {
        requested = true;
        expect(
          controller.homeSnapshots[FeatureId.judge]!.status,
          FeatureLoadStatus.loading,
        );
        query = controller.refreshFeatureQuery(
          FeatureId.signin,
          const FeatureQuery(view: FeatureQueryView.signinPending),
        );
      }
    });
    await controller.initialize();
    await until(() => backend.task.calls == 1);
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批已到')]),
        finished: false,
      ),
    );
    await until(() => backend.task.calls == 2 && query != null);
    await query;
    expect(
      backend.events.indexOf('签到'),
      lessThan(backend.events.indexOf('希冀第2批')),
    );
    expect(
      controller.homeSnapshots[FeatureId.judge]!.details.single.title,
      '全部已到',
    );
    expect(backend.legacyJudgeReads, 0);
  });
  test('同首页批次与相同显式查询在途时合并，不重复开始学校读取', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(() => backend.task.calls == 1);
    final joinedHome = controller.refreshHome(only: [FeatureId.judge]);
    final firstQuery = controller.refreshFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
    );
    final secondQuery = controller.refreshFeatureQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
    );
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批已到')]),
        finished: false,
      ),
    );
    await Future.wait([joinedHome, firstQuery, secondQuery]);
    expect(backend.beginCalls, 1);
    expect(backend.events.where((event) => event == '签到').length, 1);
  });
  test('写意图存在时既定回读不触发恢复，也不被后台批次阻塞', () async {
    final backend = _Backend();
    final controller = AppController(
      backend: backend,
      localAccountStore: await support.savedAccounts(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.recoverSession();
    await until(() => backend.task.calls == 1);
    final authCalls = backend.authCalls;
    final signinReads = backend.signinReads;
    controller.writeCoordinator.setIntent(
      WriteIntent(
        intentId: 'synthetic',
        operation: WriteOperation.signinPerform,
        targetSummary: '合成目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const [],
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        requestDigest: 'synthetic',
      ),
    );
    final readback = controller.refreshAfterWrite(WriteOperation.signinPerform);
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批已到')]),
        finished: false,
      ),
    );
    await readback;
    expect(backend.signinReads, signinReads + 1);
    expect(backend.authCalls, authCalls);
    expect(controller.writeCoordinator.intent, isNotNull);
    expect(backend.task.calls, 1);
    controller.writeCoordinator.invalidate();
    await until(() => backend.task.calls == 2);
  });
  test('部分失败最后一批保留新旧合法内容并显示局部错误', () async {
    final backend = _Backend();
    backend.task.second = FeatureReadBatch(
      FeatureResult.partial(
        error: UbaaErrorMapper.fromCode(UbaaErrorCode.networkError),
        details: const [
          FeatureDetail(title: '旧内容保留'),
          FeatureDetail(title: '本轮新内容'),
        ],
      ),
      finished: true,
    );
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(() => backend.task.calls == 1);
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批已到')]),
        finished: false,
      ),
    );
    await until(
      () =>
          controller.homeSnapshots[FeatureId.judge]!.status ==
          FeatureLoadStatus.stale,
    );
    final result = controller.homeSnapshots[FeatureId.judge]!;
    expect(result.details.map((item) => item.title), ['旧内容保留', '本轮新内容']);
    expect(result.error?.code, UbaaErrorCode.networkError);
  });
  test('详情准备步骤不把占位结果发布成当前目标内容', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    var placeholderPublished = false;
    controller.addListener(() {
      if (controller.homeSnapshots[FeatureId.judge]!.details.any(
        (item) => item.title == '不可发布的准备数据',
      ))
        placeholderPublished = true;
    });
    await controller.initialize();
    await until(() => backend.task.calls == 1);
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '不可发布的准备数据')]),
        finished: false,
        publish: false,
      ),
    );
    await until(() => backend.task.calls == 2);
    expect(placeholderPublished, isFalse);
  });
  test('转后台停止后续批次，返回前台继续；退出丢弃在途结果并取消句柄', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    await until(() => backend.task.calls == 1);
    controller.setAppForeground(false);
    backend.task.first.complete(
      const FeatureReadBatch(
        FeatureResult.success(details: [FeatureDetail(title: '首批已到')]),
        finished: false,
      ),
    );
    await until(
      () => controller.homeSnapshots[FeatureId.judge]!.details.isNotEmpty,
    );
    expect(backend.task.calls, 1);
    controller.setAppForeground(true);
    await until(() => backend.task.calls == 2);
    await controller.logout();
    expect(controller.homeSnapshots[FeatureId.judge]!.details, isEmpty);
    expect(backend.task.cancelled, isTrue);
  });
}

class _Backend
    implements UbaaBackend, FeatureQueryBackend, ProgressiveReadBackend {
  final events = <String>[];
  late final task = _Task(events);
  int legacyJudgeReads = 0;
  int beginCalls = 0;
  int authCalls = 0;
  int signinReads = 0;
  @override
  Future<AuthStatus> authStatus() async {
    authCalls++;
    return AuthStatus.signedIn;
  }

  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-user');
  @override
  Future<void> logout() async {}
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async {
    if (feature != FeatureId.judge) return null;
    beginCalls++;
    return task;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (feature == FeatureId.judge) legacyJudgeReads++;
    if (feature == FeatureId.signin) signinReads++;
    return const FeatureResult.empty();
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.signin) events.add('签到');
    return const FeatureResult.success(details: [FeatureDetail(title: '当前任务')]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements FeatureReadTask {
  _Task(this.events);
  final List<String> events;
  final first = Completer<FeatureReadBatch>();
  int calls = 0;
  bool cancelled = false;
  FeatureReadBatch second = const FeatureReadBatch(
    FeatureResult.success(details: [FeatureDetail(title: '全部已到')]),
    finished: true,
  );
  @override
  Future<FeatureReadBatch> next() async {
    events.add('希冀第${++calls}批');
    if (calls == 1) return first.future;
    return second;
  }

  @override
  void cancel() {
    cancelled = true;
  }
}
