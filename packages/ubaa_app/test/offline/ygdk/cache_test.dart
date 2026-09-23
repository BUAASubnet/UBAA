import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  setUp(() {
    local.calls.clear();
    local.failRead = false;
  });
  test('清理前概览的迟到返回不能用新句柄请求下一步记录', () async {
    final client = _Client()..homeGate = Completer<void>();
    final backend = await _backend(client);
    final pending = backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
    );
    final check = expectLater(
      pending,
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '旧调用链',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    await client.homeStarted.future;
    await backend.clearBusinessCache(accountId: 'synthetic');
    client.homeGate!.complete();
    await check;
    expect(client.matched, isEmpty);
    expect(client.cachedCalls, 0);
  });
  test('记录视图按分类索引读取精确页并使用页的保存时间', () async {
    final backend = await _backend(_Client());
    final result = await backend.readCachedQuery(
      FeatureId.ygdk,
      query,
      RoutePolicy.direct,
    );
    expect(result.projection, isNotNull);
    expect(local.calls, ['2/2/5']);
    expect(result.projection!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(result.projection!.details.single.title, '已保存分类2');
    expect(result.projection!.pagination!.page, 2);
  });
  test('部分刷新只保留实际返回分类的旧页且首次部分保持线上来源', () async {
    final client = _Client();
    final backend = await _backend(client);
    final value = await backend.loadFeatureQuery(FeatureId.ygdk, query);
    expect(value.details.single.title, '已保存分类3');
    expect(value.evidence!.origin, DataOrigin.persisted);
    expect(value.evidence!.fetchedAt.millisecondsSinceEpoch, 100000);
    expect(value.evidence!.complete, isFalse);
    expect(local.calls, ['3/2/5']);
    client.firstPartial = true;
    final first = await backend.loadFeatureQuery(FeatureId.ygdk, query);
    expect(first.details.single.title, '线上分类3');
    expect(first.evidence!.origin, DataOrigin.online);
    expect(first.evidence!.complete, isFalse);
  });
  test('本地概览按自己的分类附带记录且时间不借用概览', () async {
    final backend = await _backend(_Client());
    final result = await backend.readCachedQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
      RoutePolicy.direct,
    );
    final overview = result.projection!.overview as YgdkOverview;
    expect(local.calls, ['3/1/20']);
    expect(result.projection!.fetchedAt.millisecondsSinceEpoch, 300000);
    expect(overview.records!.classifyId, 3);
    expect(
      overview.records!.evidence!.fetchedAt.millisecondsSinceEpoch,
      100000,
    );
    expect(overview.records!.content.single.itemName, '已保存分类3');
  });
  test('线上概览记录使用明确匹配合同且失败保留同分类页', () async {
    final client = _Client();
    final backend = await _backend(client);
    var result = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
    );
    var records = (result.overview as YgdkOverview).records!;
    expect(client.matched, ['direct/3/1/20']);
    expect(records.content.single.itemName, '已保存分类3');
    expect(records.evidence!.complete, isFalse);
    client.failRecords = true;
    result = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
    );
    records = (result.overview as YgdkOverview).records!;
    expect(records.errorCode, UbaaErrorCode.networkError);
    expect(records.content.single.itemName, '已保存分类3');
    expect(records.evidence!.origin, DataOrigin.persisted);
  });
  test('本地记录损坏不抹去概览且保留独立失败提示', () async {
    local.failRead = true;
    final backend = await _backend(_Client());
    final value = await backend.readCachedQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
      RoutePolicy.direct,
    );
    expect(value.projection, isNotNull);
    final overview = value.projection!.overview as YgdkOverview;
    expect(overview.termCount, 4);
    expect(overview.records!.errorCode, UbaaErrorCode.internalError);
  });
  test('写后固定路线记录回读绕过缓存恢复', () async {
    final client = _Client();
    final backend = await _backend(client);
    await (backend as YgdkSubmissionReadbackBackend).loadYgdkRecordsOnRoute(
      route: ConnectionMode.webvpn,
      page: 1,
      size: 20,
    );
    expect(client.pinned, [BridgeConnectionMode.webVpn]);
    expect(client.cachedCalls, 0);
  });
}

const query = FeatureQuery(
  view: FeatureQueryView.ygdkRecords,
  page: 2,
  size: 5,
);
final local = _Cache();
Future<BridgeBackend> _backend(_Client client) async {
  final backend = BridgeBackend(client, configDirectory: '/synthetic');
  await backend.openOfflineAccount(
    const LocalAccount(id: 'synthetic', username: 'synthetic'),
    List.filled(32, 1),
  );
  return backend;
}

BridgeYgdkRecordsPage _page(String title, int page, int size) =>
    BridgeYgdkRecordsPage(
      content: [
        BridgeYgdkRecord(
          recordId: 1,
          itemName: title,
          imageCount: 2,
          isOpen: false,
        ),
      ],
      total: 11,
      page: page,
      size: size,
      hasMore: true,
    );
const decision = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);

class _Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => local;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const overview = BridgeYgdkOverview(
  summary: BridgeYgdkTermSummary(termCount: 4),
  classifyId: 3,
  classifyName: '分类3',
  defaultItemId: 1,
  defaultItemName: '合成运动',
  items: [],
);

class _Cache implements BridgeOfflineCache {
  bool failRead = false;
  @override
  Future<BridgeCacheReset> clearAndReopen() async => BridgeCacheReset(
    cache: _Cache(),
    report: const BridgeCacheClearReport(compacted: true),
  );
  @override
  Future<BridgeCachedHomeYgdk?> readHomeYgdk({
    required BridgeConnectionMode route,
  }) async => BridgeCachedHomeYgdk(
    data: const BridgeCachedYgdkOverview(
      summary: BridgeYgdkTermSummary(termCount: 4),
      classifyId: 3,
      classifyName: '分类3',
      defaultItemId: 1,
      defaultItemName: '合成运动',
      items: [],
    ),
    sourceRoute: route,
    fetchedAt: 300,
    complete: true,
  );
  final calls = <String>[];
  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedYgdkSelection?> readYgdkRecordsSelection({
    required BridgeConnectionMode route,
  }) async => BridgeCachedYgdkSelection(
    data: const BridgeYgdkRecordsSelection(classifyId: 2, classifyName: '分类2'),
    sourceRoute: route,
  );
  @override
  Future<BridgeCachedYgdkRecords?> readYgdkRecords({
    required BridgeConnectionMode route,
    required int classifyId,
    required int page,
    required int size,
  }) async {
    if (failRead)
      throw const BridgeError(
        code: BridgeErrorCode.internalError,
        kind: BridgeErrorKind.internal,
        retryable: false,
        message: '合成缓存损坏',
      );
    calls.add('$classifyId/$page/$size');
    return BridgeCachedYgdkRecords(
      data: _page('已保存分类$classifyId', page, size),
      classifyId: classifyId,
      sourceRoute: route,
      fetchedAt: 100,
      complete: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  bool failRecords = false;
  Completer<void>? homeGate;
  final homeStarted = Completer<void>();
  final matched = <String>[];
  @override
  Future<BridgeHomeYgdkRefresh> homeYgdkCached({
    required BridgeOfflineCache cache,
  }) async {
    if (!homeStarted.isCompleted) homeStarted.complete();
    await homeGate?.future;
    return const BridgeHomeYgdkRefresh(
      result: BridgeRoutedYgdkOverview(data: overview, route: decision),
      state: BridgeHomeRefreshState(
        fetchedAt: 400,
        complete: true,
        savedForOffline: true,
        preservedPrevious: false,
      ),
    );
  }

  @override
  Future<BridgeYgdkRecordsRefresh> ygdkRecordsForOverviewCached({
    required BridgeOfflineCache cache,
    required BridgeConnectionMode route,
    required int classifyId,
    required int page,
    required int size,
  }) async {
    matched.add('${route.name}/$classifyId/$page/$size');
    if (failRecords)
      throw const BridgeError(
        code: BridgeErrorCode.networkError,
        kind: BridgeErrorKind.network,
        retryable: true,
        message: '合成失败',
      );
    return ygdkRecordsCached(cache: cache, page: page, size: size);
  }

  bool firstPartial = false;
  int cachedCalls = 0;
  final pinned = <BridgeConnectionMode>[];
  @override
  int contractVersion() => 33;
  @override
  Future<BridgeYgdkRecordsRefresh> ygdkRecordsCached({
    required BridgeOfflineCache cache,
    required int page,
    required int size,
  }) async {
    cachedCalls++;
    return BridgeYgdkRecordsRefresh(
      data: _page('线上分类3', page, size),
      selection: const BridgeYgdkRecordsSelection(
        classifyId: 3,
        classifyName: '分类3',
      ),
      route: decision,
      fetchedAt: 200,
      complete: false,
      savedForOffline: firstPartial,
      preservedPrevious: !firstPartial,
    );
  }

  @override
  Future<BridgeCallerPinnedYgdkRecords> ygdkRecordsOnRoute({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async {
    pinned.add(route);
    return BridgeCallerPinnedYgdkRecords(
      data: _page('固定路线', page, size),
      pinnedRoute: route,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
