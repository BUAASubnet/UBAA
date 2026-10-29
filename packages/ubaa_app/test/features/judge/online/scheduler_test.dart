import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'bridge_test.dart' as fixtures;
import 'package:ubaa_test_support/recovery.dart' as startup;
import '../../../reads/progressive_test.dart' show until;

void main() {
  test('无缓存生产Bridge投影首批后让位签到，后续详情才继续', () async {
    final events = <String>[];
    final client = _Client(events);
    final backend = _Backend(BridgeBackend(client), events);
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    var requested = false;
    Future<void>? signin;
    controller.addListener(() {
      if (!requested &&
          controller.homeSnapshots[FeatureId.judge]!.details.isNotEmpty) {
        requested = true;
        signin = controller.refreshFeatureQuery(
          FeatureId.signin,
          const FeatureQuery(view: FeatureQueryView.signinPending),
        );
      }
    });
    await controller.initialize();
    await until(() => events.contains('详情') && signin != null);
    await signin;
    expect(events, ['索引', '签到', '详情']);
    expect(client.legacyCalls, 0);
    expect(
      controller.homeSnapshots[FeatureId.judge]!.details.single.title,
      '合成作业',
    );
  });
}

class _Client extends fixtures.OnlineClient {
  _Client(this.events);
  final List<String> events;
  @override
  Future<BridgeJudgeOnlineProgress> nextJudgeOnline({
    required BridgeJudgeOnlineTask task,
  }) async {
    events.add(calls == 0 ? '索引' : '详情');
    return super.nextJudgeOnline(task: task);
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
  ) => bridge.beginFeatureRead(feature, query);
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
