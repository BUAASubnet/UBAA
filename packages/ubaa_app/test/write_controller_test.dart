import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
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
    expect(controller.intent, isNull);
    controller.dispose();
  });

  test('prepare 只建立确认意图，不提交写请求且失败映射安全错误', () async {
    var prepareCalls = 0;
    var commitCalls = 0;
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
    );
    final prepared = await controller.prepare(() async {
      prepareCalls++;
      return intent();
    });
    expect(prepared?.intentId, 'intent-1');
    expect(controller.intent?.intentId, 'intent-1');
    expect(prepareCalls, 1);
    expect(commitCalls, 0);

    controller.cancel();
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
}
