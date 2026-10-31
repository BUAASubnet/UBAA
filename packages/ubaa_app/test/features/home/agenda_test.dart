import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/bridge/agenda/backend.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_app/src/bridge/home/agenda.dart';
import 'package:ubaa_app/src/bridge/features/signin/reader.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/controller/fakes.dart';

const alias = '00000000000000000000000000000001';
HomeTodoRequest request({
  Map<FeatureId, FeatureSnapshot> sources = const {},
  String? account,
}) => HomeTodoRequest(
  snapshots: sources,
  accountId: account,
  now: DateTime.parse('2026-03-24T04:00:00Z'),
);
void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.calls = 0;
    api.values = null;
    api.handle = _Handle();
  });
  test('在线投影不等待未完成的日程打开或缓存密钥，打开后才使用覆盖', () async {
    final backend = BridgeAgendaBackend(
      BridgeContext(_Client(), configDirectory: '/synthetic'),
    );
    final opened = backend.openAccount(alias);
    await Future<void>.delayed(Duration.zero);
    await backend.projectHomeTodos(request(account: alias));
    expect(api.calls, 1);
    expect(api.handle.calls, 0);
    api.handle.activation.complete();
    await opened;
    await backend.projectHomeTodos(request(account: alias));
    expect(api.handle.calls, 1);
    await backend.projectHomeTodos(
      request(account: '00000000000000000000000000000002'),
    );
    expect(api.handle.calls, 1);
    expect(api.calls, 2);
  });
  test('日程覆盖损坏单独报告，缓存写入失败仍交付已取得学校结果', () async {
    api.handle.activation.complete();
    final backend = BridgeAgendaBackend(
      BridgeContext(_Client(), configDirectory: '/synthetic'),
    );
    await backend.openAccount(alias);
    api.handle.failure = true;
    final snapshot = FeatureSnapshot(
      feature: FeatureId.spoc,
      status: FeatureLoadStatus.success,
      updatedAt: DateTime.parse('2026-03-24T04:00:00Z'),
      evidence: DataEvidence(
        accountId: alias,
        origin: DataOrigin.online,
        fetchedAt: DateTime.parse('2026-03-24T04:00:00Z'),
        complete: true,
        savedForOffline: false,
      ),
      details: const [
        FeatureDetail(
          title: '在线作业',
          presentation: SpocAssignmentPresentation(
            courseId: 'c',
            courseName: '课',
            assignmentId: 'a',
            dueTime: '2026-03-25 12:00',
            status: AssignmentSubmissionStatus.unsubmitted,
            statusText: '未提交',
          ),
        ),
      ],
    );
    final result = await backend.projectHomeTodos(
      request(
        account: alias,
        sources: {
          FeatureId.spoc: snapshot,
          FeatureId.judge: const FeatureSnapshot(
            feature: FeatureId.judge,
            status: FeatureLoadStatus.failure,
          ),
        },
      ),
    );
    expect(result.overlayFailure, isNotNull);
    expect(api.values!.spoc.single.assignmentId, 'a');
    expect(api.values!.judge, isEmpty);
    expect(snapshot.evidence!.savedForOffline, isFalse);
    expect(api.context!.now.rfc3339, '2026-03-24T12:00:00+08:00');
  });
  test('逐组投影拒绝先发后到结果，退出后拒绝迟到错误且不额外读取学校', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final first = controller.projectHomeTodos(request());
    final second = controller.projectHomeTodos(request());
    final firstCheck = expectLater(
      first,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '旧输入',
          AgendaFailure.superseded,
        ),
      ),
    );
    backend.pending[1].complete(HomeTodoProjection(const []));
    await second;
    backend.pending[0].complete(HomeTodoProjection(const []));
    await firstCheck;
    final last = controller.projectHomeTodos(request());
    final lastCheck = expectLater(
      last,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '退出',
          AgendaFailure.superseded,
        ),
      ),
    );
    await controller.logout();
    backend.pending.last.completeError(
      const AgendaException(AgendaFailure.corrupt),
    );
    await lastCheck;
  });
  test('路线切换撤销在途投影，阳光只使用同路线教学周', () async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    addTearDown(controller.dispose);
    await controller.initialize();
    final pending = controller.projectHomeTodos(request());
    final checked = expectLater(
      pending,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '旧路线',
          AgendaFailure.superseded,
        ),
      ),
    );
    await controller.setRoutePolicy(RoutePolicy.webvpn);
    backend.pending.single.complete(HomeTodoProjection(const []));
    await checked;
    final ctx = bridgeHomeAgendaContext(
      HomeTodoRequest(
        snapshots: const {
          FeatureId.ygdk: FeatureSnapshot(
            feature: FeatureId.ygdk,
            status: FeatureLoadStatus.success,
            resolvedRoute: ConnectionMode.direct,
          ),
        },
        now: request().now,
        currentWeek: const WeekPresentation(
          requestTerm: 'term',
          responseTerm: 'term',
          number: 11,
          current: true,
          startDate: '2026-03-23',
          endDate: '2026-03-29',
        ),
        currentWeekRoute: ConnectionMode.webvpn,
      ),
    );
    expect(ctx.currentWeek, isNull);
  });
  test('首页页面未指定学期时保留考试真实读取范围', () {
    final values = bridgeHomeAgendaInputs(
      request(
        sources: {
          FeatureId.exam: const FeatureSnapshot(
            feature: FeatureId.exam,
            status: FeatureLoadStatus.success,
            resolvedRoute: ConnectionMode.direct,
            details: [
              FeatureDetail(
                title: '合成考试',
                presentation: ExamPresentation(
                  arranged: true,
                  requestTerm: 'resolved-term',
                  taskId: 't',
                  date: '2026-03-25',
                  startTime: '12:00',
                ),
              ),
            ],
          ),
        },
      ),
    );
    expect(values.exam.single.term, 'resolved-term');
  });
  test('无缓存签到读取跨校园午夜时拒绝结果，不能恢复昨日动作', () async {
    final times = [
      DateTime.parse('2026-03-24T15:59:59Z'),
      DateTime.parse('2026-03-24T16:00:00Z'),
    ];
    await expectLater(
      bridgeLoadSigninHome(
        BridgeContext(_SigninClient()),
        const FeatureQuery(),
        useCache: false,
        currentTime: () => times.removeAt(0),
      ),
      throwsA(
        isA<BackendException>().having(
          (e) => e.code,
          '跨日',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
  });
  test('签到输入保留观察日期，陈旧与离线不能获得 fresh 标签', () {
    final input = bridgeHomeAgendaInputs(
      request(
        sources: {
          FeatureId.signin: FeatureSnapshot(
            feature: FeatureId.signin,
            status: FeatureLoadStatus.stale,
            updatedAt: DateTime.parse('2026-03-23T15:00:00Z'),
            details: const [
              FeatureDetail(
                title: '合成签到',
                presentation: SigninPresentation(
                  courseId: 'course',
                  classBeginTime: '12:00',
                  classEndTime: '13:00',
                  signStatus: 0,
                ),
              ),
            ],
          ),
        },
      ),
    );
    expect(input.signin.single.date, '2026-03-23');
    expect(input.signin.single.fresh, isFalse);
  });
}

class _Api extends RustLibApi {
  int calls = 0;
  BridgeHomeAgendaInput? values;
  BridgeHomeAgendaContext? context;
  _Handle handle = _Handle();
  @override
  Future<BridgeAgendaStore> crateApiAgendaBridgeAgendaStoreOpen({
    required String configDir,
    required String accountId,
  }) async => handle;
  @override
  Future<List<BridgeAgendaEntry>> crateApiAgendaHomeAgendaProjectHome({
    required BridgeHomeAgendaInput values,
    required BridgeHomeAgendaContext context,
  }) async {
    calls++;
    this.values = values;
    this.context = context;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Handle implements BridgeAgendaStore {
  final activation = Completer<void>();
  int calls = 0;
  bool failure = false;
  @override
  Future<void> activate() => activation.future;
  @override
  Future<List<BridgeAgendaEntry>> projectHome({
    required BridgeHomeAgendaInput values,
    required BridgeHomeAgendaContext context,
  }) async {
    calls++;
    if (failure)
      throw const BridgeAgendaError(failure: BridgeAgendaFailure.corrupt);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Client implements BridgeClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Backend extends FixtureQueryBackend implements HomeTodoBackend {
  _Backend() : super(onQuery: (_, _) => const FeatureResult.empty());
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic');
  final pending = <Completer<HomeTodoProjection>>[];
  @override
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) {
    final gate = Completer<HomeTodoProjection>();
    pending.add(gate);
    return gate.future;
  }
}

class _SigninClient extends _Client {
  @override
  Future<BridgeRoutedSigninClasses> signinToday() async =>
      const BridgeRoutedSigninClasses(
        data: [],
        route: BridgeRouteDecision(
          policy: BridgeRoutePolicy.direct,
          resolvedRoute: BridgeConnectionMode.direct,
          network: BridgeNetworkState.unknown,
          initialRoute: BridgeConnectionMode.direct,
          usedFallback: false,
        ),
      );
}
