import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));
  setUp(() => _Cache.complete = true);
  Future<BridgeBackend> open(_Client client) async {
    final backend = BridgeBackend(client, configDirectory: '/synthetic');
    await backend.openOfflineAccount(
      const LocalAccount(id: 'synthetic', username: 'synthetic'),
      List.filled(32, 1),
    );
    return backend;
  }

  test('三个新增首页来源保留只读内容，旧未签到不生成写动作', () async {
    final backend = await open(_Client());
    final home = await backend.readCachedHome(RoutePolicy.direct);
    expect(
      home.map((item) => item.feature),
      containsAll([FeatureId.signin, FeatureId.spoc, FeatureId.ygdk]),
    );
    expect(
      home.expand((item) => item.details).expand((item) => item.actions),
      isEmpty,
    );
    final ygdk = home
        .singleWhere((item) => item.feature == FeatureId.ygdk)
        .toSnapshot();
    expect((ygdk.overview as YgdkOverview).termCount, 3);
    final pending = await backend.readCachedQuery(
      FeatureId.signin,
      const FeatureQuery(view: FeatureQueryView.signinPending),
      RoutePolicy.direct,
    );
    expect(pending.projection!.details.single.title, '旧课堂');
    expect(pending.projection!.details.single.actions, isEmpty);
  });
  test('签到在线读取保留实时动作，既定回读不进入缓存认证入口', () async {
    final client = _Client();
    final backend = await open(client);
    final online = await backend.loadFeature(FeatureId.signin);
    expect(online.details.single.actions, hasLength(1));
    expect(client.cachedSignin, 1);
    await (backend as SigninReadbackBackend).readSigninAfterWrite();
    expect(client.cachedSignin, 1);
    expect(client.plainSignin, 1);
  });
  test('同分类但已观察到学期变化时不拼接旧学期统计', () async {
    final backend = await open(_Client()..termId = 2);
    final result = await backend.loadFeature(FeatureId.ygdk);
    expect(result.evidence!.origin, DataOrigin.online);
    expect((result.overview as YgdkOverview).termCount, 0);
  });
  test('旧阳光缓存也不完整时不能将零统计标成已保存完整统计', () async {
    _Cache.complete = false;
    final backend = await open(_Client());
    final result = await backend.loadFeature(FeatureId.ygdk);
    expect(result.evidence!.origin, DataOrigin.online);
    expect(result.evidence!.complete, isFalse);
  });
  test('合并旧阳光统计时仍保留本次匹配合同读取的记录页', () async {
    final backend = await open(_Client());
    final result = await backend.loadFeatureQuery(
      FeatureId.ygdk,
      const FeatureQuery(),
    );
    final overview = result.overview as YgdkOverview;
    expect(overview.termCount, 3);
    expect(overview.records?.page, 1);
    expect(overview.records?.content, isEmpty);
    expect(overview.records?.errorCode, isNull);
  });
  test('不完整SPOC保留旧集合，阳光旧统计与本次实时动作分别取源', () async {
    final backend = await open(_Client());
    final spoc = await backend.loadFeature(FeatureId.spoc);
    expect(spoc.details.single.title, '旧作业');
    expect(spoc.evidence!.complete, isFalse);
    final ygdk = await backend.loadFeature(FeatureId.ygdk);
    expect((ygdk.overview as YgdkOverview).termCount, 3);
    expect(ygdk.details.single.actions, hasLength(1));
    expect(ygdk.evidence!.origin, DataOrigin.mixed);
    expect(ygdk.evidence!.complete, isFalse);
  });
}

const route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.unknown,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);
const oldSpoc = BridgeSpocAssignments(
  termCode: 'term',
  assignments: [
    BridgeSpocAssignmentSummary(
      assignmentId: 'a',
      courseId: 'c',
      courseName: '合成课程',
      title: '旧作业',
      submissionStatus: BridgeSpocSubmissionStatus.unsubmitted,
      submissionStatusText: '未提交',
    ),
  ],
);
const freshSignin = BridgeRoutedSigninClasses(
  data: [
    BridgeSigninClass(
      courseId: 'c',
      courseName: '新课堂',
      classBeginTime: '08:00',
      classEndTime: '09:40',
      signStatus: 0,
      signinEligibility: BridgeActionEligibility.allowed,
      signinTarget: 'c',
    ),
  ],
  route: route,
);
const partial = BridgeHomeRefreshState(
  fetchedAt: 200,
  complete: false,
  savedForOffline: false,
  preservedPrevious: true,
);

class _Api implements RustLibApi {
  @override
  Future<BridgeOfflineCache> crateApiOfflineBridgeOfflineCacheOpen({
    required String configDir,
    required String accountId,
    required String expectedIdentity,
    required List<int> key,
  }) async => _Cache();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements BridgeOfflineCache {
  @override
  Future<BridgeCachedYgdkRecords?> readYgdkRecords({
    required BridgeConnectionMode route,
    required int classifyId,
    required int page,
    required int size,
  }) async => null;

  @override
  Future<BridgeCachedCgyyOrdersRecord?> readCgyyOrders({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async => null;

  @override
  Future<BridgeCachedBykcChosenRecord?> readBykcChosen({
    required BridgeConnectionMode route,
  }) async => null;

  static bool complete = true;
  @override
  Future<void> activate() async {}
  @override
  Future<BridgeCachedToday?> readToday({
    required BridgeConnectionMode route,
  }) async => null;
  @override
  Future<BridgeCachedJudge?> readJudge({
    required BridgeConnectionMode route,
    required bool includeExpired,
  }) async => null;
  @override
  Future<BridgeCachedHomeSignin?> readHomeSignin({
    required BridgeConnectionMode route,
  }) async => BridgeCachedHomeSignin(
    data: const [
      BridgeCachedSigninClass(
        courseId: 'c',
        courseName: '旧课堂',
        classBeginTime: '08:00',
        classEndTime: '09:40',
        signStatus: 0,
      ),
    ],
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
    date: '20260922',
  );
  @override
  Future<BridgeCachedHomeSpoc?> readHomeSpoc({
    required BridgeConnectionMode route,
  }) async => BridgeCachedHomeSpoc(
    data: oldSpoc,
    sourceRoute: route,
    fetchedAt: 100,
    complete: true,
  );
  @override
  Future<BridgeCachedHomeYgdk?> readHomeYgdk({
    required BridgeConnectionMode route,
  }) async => BridgeCachedHomeYgdk(
    data: const BridgeCachedYgdkOverview(
      summary: BridgeYgdkTermSummary(termCount: 3),
      classifyId: 1,
      classifyName: '体育',
      defaultItemId: 2,
      defaultItemName: '跑步',
      items: [BridgeCachedYgdkItem(itemId: 2, name: '跑步')],
    ),
    sourceRoute: route,
    fetchedAt: 100,
    complete: complete,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements BridgeClient {
  @override
  Future<BridgeYgdkRecordsRefresh> ygdkRecordsForOverviewCached({
    required BridgeOfflineCache cache,
    required BridgeConnectionMode route,
    required int classifyId,
    required int page,
    required int size,
  }) async => BridgeYgdkRecordsRefresh(
    data: BridgeYgdkRecordsPage(
      content: [],
      total: 0,
      page: page,
      size: size,
      hasMore: false,
    ),
    selection: BridgeYgdkRecordsSelection(
      classifyId: classifyId,
      classifyName: '体育',
    ),
    route: const BridgeRouteDecision(
      policy: BridgeRoutePolicy.direct,
      resolvedRoute: BridgeConnectionMode.direct,
      network: BridgeNetworkState.unknown,
      initialRoute: BridgeConnectionMode.direct,
      usedFallback: false,
    ),
    fetchedAt: 200,
    complete: true,
    savedForOffline: true,
    preservedPrevious: false,
  );

  @override
  Future<BridgeCallerPinnedYgdkRecords> ygdkRecordsOnRoute({
    required BridgeConnectionMode route,
    required int page,
    required int size,
  }) async => BridgeCallerPinnedYgdkRecords(
    pinnedRoute: route,
    data: BridgeYgdkRecordsPage(
      content: const [],
      total: 0,
      page: page,
      size: size,
      hasMore: false,
    ),
  );

  int cachedSignin = 0, plainSignin = 0;
  int? termId;
  @override
  int contractVersion() => 24;
  @override
  Future<BridgeHomeSigninRefresh> homeSigninCached({
    required BridgeOfflineCache cache,
  }) async {
    cachedSignin++;
    return const BridgeHomeSigninRefresh(
      result: freshSignin,
      state: BridgeHomeRefreshState(
        fetchedAt: 200,
        complete: true,
        savedForOffline: true,
        preservedPrevious: false,
        scopeDate: '20260922',
      ),
    );
  }

  @override
  Future<BridgeRoutedSigninClasses> signinToday() async {
    plainSignin++;
    return freshSignin;
  }

  @override
  Future<BridgeHomeSpocRefresh> homeSpocCached({
    required BridgeOfflineCache cache,
  }) async => const BridgeHomeSpocRefresh(
    result: BridgeRoutedSpocAssignments(
      data: BridgeSpocAssignments(termCode: 'term', assignments: []),
      route: route,
    ),
    state: partial,
  );
  @override
  Future<BridgeHomeYgdkRefresh> homeYgdkCached({
    required BridgeOfflineCache cache,
  }) async => BridgeHomeYgdkRefresh(
    result: BridgeRoutedYgdkOverview(
      data: BridgeYgdkOverview(
        summary: BridgeYgdkTermSummary(termCount: 0, termId: termId),
        classifyId: 1,
        classifyName: '体育',
        defaultItemId: 2,
        defaultItemName: '跑步',
        items: [
          BridgeYgdkItem(
            itemId: 2,
            name: '跑步',
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeYgdkSubmitTarget(classifyId: 1, itemId: 2),
          ),
        ],
      ),
      route: route,
    ),
    state: partial,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
