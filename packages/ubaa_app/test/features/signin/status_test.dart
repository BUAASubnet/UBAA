import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../support/controller/fakes.dart';

void main() {
  test('每次在线检查读取新状态并更新签到快照', () async {
    final (controller, backend) = await _start();
    expect(await controller.checkSigninSigned('课次'), isFalse);
    backend.next = () async => _result(1);
    expect(await controller.checkSigninSigned('课次'), isTrue);
    expect(_status(controller), 1);
    expect(backend.onlineReads, 2);
  });

  test('找不到排课或在线请求失败时抛错', () async {
    final (controller, backend) = await _start();
    expect(await controller.checkSigninSigned('课次'), isFalse);
    await expectLater(
      controller.checkSigninSigned('不存在'),
      throwsA(isA<BackendException>()),
    );
    backend.next = () async =>
        throw const BackendException(UbaaErrorCode.networkError);
    await expectLater(
      controller.checkSigninSigned('课次'),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '错误码',
          UbaaErrorCode.networkError,
        ),
      ),
    );
  });

  test('多个排课同时检查时合用一次今日列表读取', () async {
    final (controller, backend) = await _start();
    final pending = Completer<FeatureResult>();
    backend.next = () => pending.future;
    final first = controller.checkSigninSigned('课次');
    final second = controller.checkSigninSigned('另一排课');
    pending.complete(_result(1));
    await Future.wait<void>([
      expectLater(first, completion(isTrue)),
      expectLater(second, throwsA(isA<BackendException>())),
    ]);
    expect(backend.onlineReads, 1);
  });

  test('签到提交成功仍通过原路线回读更新卡片数据', () async {
    final (controller, backend) = await _start();
    final coordinator = controller.writeCoordinator;
    final intent = await coordinator.prepareForUi(
      () => controller.prepareSigninWrite(
        const SigninPerformAction(
          scheduleId: '课次',
          eligibility: ActionEligibility.allowed,
        ),
      ),
      expectedOperation: WriteOperation.signinPerform,
    );
    expect(intent, isNotNull);
    await coordinator.confirmForUi();
    expect(backend.commitCalls, 1);
    expect(backend.pinnedRoutes, [ConnectionMode.direct]);
    expect(_status(controller), 1);
  });
}

int? _status(AppController controller) =>
    (controller.snapshots[FeatureId.signin]!.details.single.presentation
            as SigninPresentation)
        .signStatus;

Future<(AppController, _Backend)> _start() async {
  final backend = _Backend();
  final controller = AppController(backend: backend);
  addTearDown(controller.dispose);
  await controller.initialize();
  await controller.refreshHome(only: [FeatureId.signin]);
  await Future<void>.delayed(Duration.zero);
  return (controller, backend);
}

FeatureResult _result(int status) => FeatureResult.success(
  resolvedRoute: ConnectionMode.direct,
  details: [
    FeatureDetail(
      title: '课程',
      presentation: SigninPresentation(
        courseId: '展示课程',
        actionTarget: '课次',
        classBeginTime: '08:00',
        classEndTime: '09:40',
        signStatus: status,
      ),
    ),
  ],
);

final class _Backend extends FixtureSigninWriteBackend
    implements SigninReadbackBackend, PinnedWriteReadbackBackend {
  int onlineReads = 0;
  final pinnedRoutes = <ConnectionMode>[];
  Future<FeatureResult> Function() next = () async => _result(0);

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.signin
      ? _result(commitCalls == 0 ? 0 : 1)
      : const FeatureResult.empty();

  @override
  Future<FeatureResult> readSigninAfterWrite() {
    onlineReads++;
    return next();
  }

  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) async {
    pinnedRoutes.add(route);
    return _result(1);
  }
}
