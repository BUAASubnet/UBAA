import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/write_controller.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  WriteIntent intent({
    Duration age = Duration.zero,
    String id = 'intent-1',
    WriteOperation operation = WriteOperation.bykcSelectCourse,
  }) => WriteIntent(
    intentId: id,
    operation: operation,
    targetSummary: '选择一门博雅课程',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>['提交后请刷新已选课程确认结果'],
    expiresAt: DateTime.now().add(const Duration(minutes: 2) - age),
    requestDigest: 'digest',
  );

  test('同一 intent 只提交一次并在成功后清除', () async {
    var calls = 0;
    final controller = WriteFlowController(
      commit: (id) async {
        calls++;
        expect(id, 'intent-1');
        return const WriteCommitResult(
          operation: WriteOperation.bykcSelectCourse,
          success: true,
          message: '已提交',
          outcomeUnknown: false,
        );
      },
    );
    controller.setIntent(intent());
    final result = await controller.confirm();
    expect(result?.success, isTrue);
    expect(calls, 1);
    expect(controller.intent, isNull);
    expect(await controller.confirm(), isNull);
    expect(calls, 1);
    controller.dispose();
  });

  test('十项写操作均经过一次性确认且不会自动重复提交', () async {
    for (final operation in WriteOperation.values) {
      var calls = 0;
      final id = 'intent-${operation.name}';
      final controller = WriteFlowController(
        commit: (intentId) async {
          calls++;
          expect(intentId, id);
          return WriteCommitResult(
            operation: operation,
            success: true,
            message: '${operation.title}已提交，请刷新核对',
            outcomeUnknown: false,
          );
        },
      );
      final prepared = await controller.prepare(
        () async => intent(id: id, operation: operation),
      );
      expect(prepared?.operation, operation);
      expect(calls, 0);
      final result = await controller.confirm();
      expect(result?.operation, operation);
      expect(calls, 1);
      expect(await controller.confirm(), isNull);
      expect(calls, 1);
      controller.dispose();
    }
  });

  test('过期 intent 不调用提交器', () async {
    var calls = 0;
    final controller = WriteFlowController(
      commit: (_) async {
        calls++;
        throw StateError('should not be called');
      },
    );
    controller.setIntent(intent(age: const Duration(minutes: 3)));
    expect(await controller.confirm(), isNull);
    expect(calls, 0);
    expect(controller.error?.code, UbaaErrorCode.intentExpired);
    controller.dispose();
  });

  test('结果不确定映射为禁止自动重试的安全错误', () async {
    final controller = WriteFlowController(
      commit: (_) async =>
          throw const BackendException(UbaaErrorCode.outcomeUnknown),
    );
    controller.setIntent(intent());
    await expectLater(controller.confirm(), throwsA(isA<BackendException>()));
    expect(controller.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(controller.error?.retryable, isFalse);
    expect(controller.intent, isNull);
    controller.dispose();
  });

  test('prepare 在控制器销毁后返回时 best-effort 释放晚到的 intent', () async {
    final prepared = Completer<WriteIntent>();
    final discardedIntentIds = <String>[];
    final controller = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
      discard: (intentId) async {
        discardedIntentIds.add(intentId);
        throw StateError('释放失败不应逃逸销毁边界');
      },
    );

    final preparing = controller.prepare(() => prepared.future);
    controller.dispose();
    prepared.complete(intent(id: 'intent-after-dispose'));

    expect(await preparing, isNull);
    expect(discardedIntentIds, <String>['intent-after-dispose']);
  });

  test('prepare 只建立确认意图，不提交写请求且失败映射安全错误', () async {
    var prepareCalls = 0;
    var commitCalls = 0;
    final discardedIntentIds = <String>[];
    final controller = WriteFlowController(
      commit: (_) async {
        commitCalls++;
        return const WriteCommitResult(
          operation: WriteOperation.signinPerform,
          success: true,
          message: '已提交',
          outcomeUnknown: false,
        );
      },
      discard: (intentId) async => discardedIntentIds.add(intentId),
    );
    final prepared = await controller.prepare(() async {
      prepareCalls++;
      return intent();
    });
    expect(prepared?.intentId, 'intent-1');
    expect(controller.intent?.intentId, 'intent-1');
    expect(prepareCalls, 1);
    expect(commitCalls, 0);

    await controller.cancel();
    expect(discardedIntentIds, <String>['intent-1']);
    await expectLater(
      controller.prepare(() async {
        throw const BackendException(UbaaErrorCode.permissionDenied);
      }),
      throwsA(isA<BackendException>()),
    );
    expect(controller.intent, isNull);
    expect(controller.error?.code, UbaaErrorCode.permissionDenied);
    controller.dispose();
  });

  test('取消必须等待后端释放 intent，成功后才清理本地状态', () async {
    final discardStarted = Completer<void>();
    final allowDiscard = Completer<void>();
    final controller = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
      discard: (intentId) async {
        expect(intentId, 'intent-await-discard');
        discardStarted.complete();
        await allowDiscard.future;
      },
    );
    controller.setIntent(intent(id: 'intent-await-discard'));

    final cancel = controller.cancel();
    await discardStarted.future;
    expect(controller.isSubmitting, isTrue);
    expect(controller.intent?.intentId, 'intent-await-discard');
    controller.setIntent(intent(id: 'intent-must-not-replace'));
    expect(controller.intent?.intentId, 'intent-await-discard');

    allowDiscard.complete();
    await cancel;
    expect(controller.isSubmitting, isFalse);
    expect(controller.intent, isNull);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('未消费的 intent 不能被后到的 setIntent 覆盖', () {
    final controller = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
    );
    controller.setIntent(intent(id: 'intent-original'));

    controller.setIntent(intent(id: 'intent-replacement'));

    expect(controller.intent?.intentId, 'intent-original');
    controller.dispose();
  });

  test('取消首次失败保留 intent，第二次成功后清理', () async {
    var discardCalls = 0;
    final controller = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
      discard: (_) async {
        discardCalls++;
        if (discardCalls == 1) {
          throw const BackendException(
            UbaaErrorCode.networkError,
            detail: '/private/session?token=secret',
          );
        }
      },
    );
    controller.setIntent(intent(id: 'intent-retained'));

    await expectLater(
      controller.cancel(),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', UbaaErrorCode.networkError)
            .having((error) => error.detail, 'detail', isNull),
      ),
    );
    expect(controller.intent?.intentId, 'intent-retained');
    expect(controller.error?.code, UbaaErrorCode.networkError);
    expect(controller.error.toString(), isNot(contains('secret')));

    await controller.cancel();
    expect(discardCalls, 2);
    expect(controller.intent, isNull);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('未配置释放器或未知异常均安全失败且保留 intent', () async {
    final unsupportedController = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
    );
    unsupportedController.setIntent(intent(id: 'intent-no-discarder'));
    await expectLater(
      unsupportedController.cancel(),
      throwsA(
        isA<BackendException>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.unsupported,
        ),
      ),
    );
    expect(unsupportedController.intent?.intentId, 'intent-no-discarder');
    expect(unsupportedController.error?.code, UbaaErrorCode.unsupported);
    unsupportedController.dispose();

    final internalErrorController = WriteFlowController(
      commit: (_) async => throw StateError('不应提交'),
      discard: (_) async => throw StateError('/private/token=secret'),
    );
    internalErrorController.setIntent(intent(id: 'intent-internal-error'));
    await expectLater(
      internalErrorController.cancel(),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', UbaaErrorCode.internalError)
            .having((error) => error.detail, 'detail', isNull),
      ),
    );
    expect(internalErrorController.intent?.intentId, 'intent-internal-error');
    expect(internalErrorController.error?.code, UbaaErrorCode.internalError);
    internalErrorController.dispose();
  });
}
