import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'progressive_test.dart' as fixtures;
import 'package:ubaa_test_support/recovery.dart' as startup;

void main() {
  test('当前评教读取在课程批次之间优先让位紧急签到', () async {
    final events = <String>[];
    final client = _Client(events);
    final controller = AppController(
      backend: _Backend(BridgeBackend(client), events),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    var requested = false;
    Future<void>? signin;
    controller.addListener(() {
      if (!requested &&
          controller.snapshots[FeatureId.evaluation]!.details.isNotEmpty) {
        requested = true;
        signin = controller.refreshFeatureQuery(
          FeatureId.signin,
          const FeatureQuery(view: FeatureQueryView.signinPending),
        );
      }
    });
    await controller.refreshFeatureQuery(
      FeatureId.evaluation,
      const FeatureQuery(),
    );
    await signin;
    expect(events, ['课程1', '签到', '课程2']);
  });
}

class _Client extends fixtures.EvaluationClient {
  _Client(this.events);
  final List<String> events;
  @override
  Future<BridgeEvaluationScanBatch> nextEvaluationScan({
    required BridgeEvaluationScan task,
  }) async {
    if (calls > 0) events.add(calls == 1 ? '课程1' : '课程2');
    return super.nextEvaluationScan(task: task);
  }
}

class _Backend extends startup.FakeRecoveryBackend
    implements ProgressiveReadBackend, FeatureQueryBackend {
  _Backend(this.bridge, this.events);
  final BridgeBackend bridge;
  final List<String> events;
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) => feature == FeatureId.evaluation
      ? bridge.beginFeatureRead(feature, query)
      : Future.value();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    expect(feature, FeatureId.signin);
    events.add('签到');
    return const FeatureResult.empty();
  }
}
