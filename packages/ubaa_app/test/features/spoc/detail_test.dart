import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'progressive_test.dart' as fixtures;

const query = FeatureQuery(
  view: FeatureQueryView.spocDetail,
  assignmentId: 'a1',
);
void main() {
  final api = fixtures.SpocCacheApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() => api.cache = fixtures.SpocCache());
  test('SPOC 单详情也建立逐页任务，前置不能把列表作为详情发布', () async {
    final client = fixtures.SpocClient();
    final backend = BridgeBackend(client);
    final task = await backend.beginAccountFeatureRead(
      FeatureId.spoc,
      query,
      fixtures.account,
    );
    expect(task, isNotNull);
    expect(client.requestedAssignment, 'a1');
    expect(client.expectedIdentity, fixtures.account.username);
    expect((await task!.next()).publish, isFalse);
    final last = await task.next();
    expect(last.finished, isTrue);
    expect(last.result.details.single.title, '新详情');
    expect(last.result.details.single.actions, isEmpty);
    expect(last.result.evidence!.savedForOffline, isFalse);
    expect(last.result.evidence!.complete, isTrue);
    task.cancel();
    expect(client.detailTask.cancelled, isTrue);
  });
  test('单详情补充部分失败保留同目标旧完整正文和取得时间', () async {
    api.cache.detailValue = BridgeCachedHomeSpocDetail(
      data: fixtures.detailData('a1', '旧详情'),
      sourceRoute: BridgeConnectionMode.direct,
      fetchedAt: 50,
      complete: true,
    );
    final client = fixtures.SpocClient()..partial = true;
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(fixtures.account, List.filled(32, 7));
    final task = (await backend.beginFeatureRead(FeatureId.spoc, query))!;
    await task.next();
    final last = await task.next();
    expect(client.persistent, isTrue);
    expect(last.result.details.single.title, '旧详情');
    expect(last.result.evidence!.fetchedAt.millisecondsSinceEpoch, 50000);
    expect(last.result.evidence!.complete, isFalse);
  });
  test('错目标不能发布，退出期间迟到的合法正文也丢弃', () async {
    final client = fixtures.SpocClient()..wrongDetail = true;
    final backend = BridgeBackend(client);
    final wrong = (await backend.beginFeatureRead(FeatureId.spoc, query))!;
    await wrong.next();
    await expectLater(
      wrong.next(),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '错目标',
          UbaaErrorCode.upstreamChanged,
        ),
      ),
    );
    client.wrongDetail = false;
    final task = (await backend.beginFeatureRead(FeatureId.spoc, query))!;
    client.detailGate = Completer<BridgeSpocDetailScanBatch>();
    final pending = task.next();
    await backend.deactivateOfflineAccount();
    client.detailGate!.complete(client.detailBatch(true));
    await expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '旧代次',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
  });
}
