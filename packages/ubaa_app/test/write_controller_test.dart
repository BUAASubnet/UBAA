import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  WriteIntent intent({Duration age = Duration.zero}) => WriteIntent(
    intentId: 'intent-1',
    operation: WriteOperation.bykcSelectCourse,
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
}
