import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'bridge_test.dart' as fixture;

void main() {
  setUpAll(() => RustLib.initMock(api: fixture.Api()));
  test('无持久仓库创建在线计划时退出，迟到句柄立即取消', () async {
    final client = GateClient();
    final backend = BridgeBackend(client);
    final pending = backend.beginFeatureRead(FeatureId.judge, null);
    await client.started.future;
    await backend.deactivateOfflineAccount();
    final rejected = expectLater(pending, throwsA(isA<BackendException>()));
    client.onlineGate.complete(client.task);
    await rejected;
    expect(client.task.cancelled, isTrue);
    expect(client.calls, 0);
  });
  for (final succeed in [true, false]) {
    test('回退创建期间取消，迟到${succeed ? '成功' : '失败'}不复活任务', () async {
      final client = GateClient();
      final backend = await fixture.open(client);
      final task = (await backend.beginFeatureRead(FeatureId.judge, null))!;
      final pending = task.next();
      await client.started.future;
      task.cancel();
      final rejected = expectLater(
        pending,
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            '取消优先',
            UbaaErrorCode.operationConflict,
          ),
        ),
      );
      if (succeed) {
        client.onlineGate.complete(client.task);
      } else {
        client.onlineGate.completeError(
          const BridgeError(
            code: BridgeErrorCode.authenticationRequired,
            kind: BridgeErrorKind.authentication,
            retryable: false,
            message: '合成旧认证失败',
          ),
        );
      }
      await rejected;
      expect(client.calls, 0);
      if (succeed) expect(client.task.cancelled, isTrue);
    });
  }
  test('单详情回退仍精确核对目标且不授予动作', () async {
    final client = fixture.Client();
    final backend = await fixture.open(client);
    final task = (await backend.beginFeatureRead(
      FeatureId.judge,
      const FeatureQuery(
        view: FeatureQueryView.judgeDetail,
        courseId: '12',
        assignmentId: '101',
      ),
    ))!;
    FeatureReadBatch batch;
    do {
      batch = await task.next();
    } while (!batch.finished);
    expect(client.options!.keys!.single.assignmentId, '101');
    expect(batch.result.details.single.actions, isEmpty);
    expect(batch.result.evidence!.savedForOffline, isFalse);
    task.cancel();
  });
}

class GateClient extends fixture.Client {
  final started = Completer<void>();
  final onlineGate = Completer<BridgeJudgeOnlineTask>();
  @override
  Future<BridgeJudgeOnlineTask> beginJudgeOnline({
    required BridgeJudgeOnlineOptions options,
  }) {
    this.options = options;
    started.complete();
    return onlineGate.future;
  }
}
