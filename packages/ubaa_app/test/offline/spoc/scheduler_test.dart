import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'progressive_test.dart' as fixtures;
import '../startup_test.dart' as startup;
import '../progressive_controller_test.dart' show until;

void main() {
  test('生产 SPOC 逐页投影在两页间让位紧急签到读取', () async {
    final events = <String>[];
    final client = _Client(events);
    final backend = _Backend(BridgeBackend(client), events);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    var requested = false;
    Future<void>? signin;
    controller.addListener(() {
      if (!requested &&
          controller.homeSnapshots[FeatureId.spoc]!.details.isNotEmpty) {
        requested = true;
        signin = controller.refreshFeatureQuery(
          FeatureId.signin,
          const FeatureQuery(view: FeatureQueryView.signinPending),
        );
      }
    });
    await controller.initialize();
    await until(() => events.contains('第2页') && signin != null);
    await signin;
    expect(events, ['第1页', '签到', '第2页']);
    expect(controller.homeSnapshots[FeatureId.spoc]!.details.length, 2);
  });
  test('打开 SPOC 详情会取消首页剩余页并保留已呈现摘要', () async {
    final events = <String>[];
    final backend = _Backend(BridgeBackend(_Client(events)), events);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    Future<void>? detail;
    var requested = false;
    controller.addListener(() {
      if (!requested &&
          controller.homeSnapshots[FeatureId.spoc]!.details.isNotEmpty) {
        requested = true;
        detail = controller.refreshFeatureQuery(
          FeatureId.spoc,
          const FeatureQuery(
            view: FeatureQueryView.spocDetail,
            assignmentId: 'a1',
          ),
        );
      }
    });
    await controller.initialize();
    await until(
      () =>
          detail != null &&
          controller.homeSnapshots[FeatureId.spoc]!.status !=
              FeatureLoadStatus.loading,
    );
    await detail;
    expect(events, ['第1页', '详情']);
    expect(
      controller.homeSnapshots[FeatureId.spoc]!.details.single.title,
      '合成 a1',
    );
  });
}

class _Client extends fixtures.SpocClient {
  _Client(this.events);
  final List<String> events;
  @override
  Future<BridgeSpocScanBatch> nextSpocScan({
    required BridgeSpocScan task,
  }) async {
    if (calls >= 2) events.add(calls == 2 ? '第1页' : '第2页');
    return super.nextSpocScan(task: task);
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
  ) => feature == FeatureId.spoc
      ? bridge.beginFeatureRead(feature, query)
      : Future.value();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    expect([FeatureId.signin, FeatureId.spoc], contains(feature));
    events.add(feature == FeatureId.signin ? '签到' : '详情');
    return const FeatureResult.empty();
  }
}
