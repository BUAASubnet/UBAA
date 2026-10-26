import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/controller/write/pinned_readback.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/controller/fakes.dart';

void main() {
  test('签到原路线回读同步首页数据并暂停旧资格', () async {
    final backend = Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final future = controllerPinnedWriteReadback(
      controller,
      WriteOperation.signinPerform,
      null,
      ConnectionMode.direct,
    );
    expect(
      controller.homeSnapshots[FeatureId.signin]!.status,
      FeatureLoadStatus.loading,
    );
    backend.gate.complete(
      const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '已签到',
            presentation: SigninPresentation(
              courseId: '1',
              classBeginTime: '14:00',
              classEndTime: '17:00',
              signStatus: 1,
            ),
          ),
        ],
      ),
    );
    await future;
    expect(
      controller.homeSnapshots[FeatureId.signin]!.details.single.title,
      '已签到',
    );
    expect(
      controller.homeSnapshots[FeatureId.signin]!.status,
      FeatureLoadStatus.success,
    );
    expect(backend.reads, 1);
  });
  test('签到回读异常同步首页错误且不保留可签到资格', () async {
    final backend = Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    final pending = controllerPinnedWriteReadback(
      controller,
      WriteOperation.signinPerform,
      null,
      ConnectionMode.direct,
    );
    backend.gate.completeError(
      const BackendException(UbaaErrorCode.networkError),
    );
    await pending;
    expect(
      controller.homeSnapshots[FeatureId.signin]!.error?.code,
      UbaaErrorCode.networkError,
    );
    expect(
      controller.homeSnapshots[FeatureId.signin]!.status,
      FeatureLoadStatus.failure,
    );
    expect(backend.reads, 1);
  });
}

class Backend extends FixtureQueryBackend
    implements PinnedWriteReadbackBackend {
  Backend() : super(onQuery: (_, _) => const FeatureResult.empty());
  final gate = Completer<FeatureResult>();
  int reads = 0;
  @override
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) {
    expect(operation, WriteOperation.signinPerform);
    expect(route, ConnectionMode.direct);
    reads++;
    return gate.future;
  }
}
