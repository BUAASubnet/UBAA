import 'package:ubaa_ui/ubaa_ui.dart' show UiDestination;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/navigation.dart';
import '../../support/write_harness.dart';

void main() {
  testWidgets('博雅三维筛选交集维度内并集，关闭往返刷新保留且重置清三维', (tester) async {
    final state = await _mount(tester);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    expect(find.widgetWithText(FilterChip, '美育'), findsOneWidget);
    for (final name in ['德育', '美育', '劳动教育', '安全健康', '其他方面']) {
      expect(find.widgetWithText(FilterChip, name), findsOneWidget);
    }
    expect(find.widgetWithText(FilterChip, '未知类型'), findsNothing);
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成美育沙河'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成德育沙河'), findsNothing);
    expect(find.widgetWithText(Card, '合成美育学院路'), findsNothing);
    expect(state.queries, isEmpty);
    await openQueryPanel(tester);
    await _chip(tester, '德育');
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成德育沙河'), findsOneWidget);
    await tester.tap(find.widgetWithText(Card, '合成美育沙河'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await openQueryPanel(tester);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '美育')).selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '沙河校区'))
          .selected,
      isTrue,
    );
    await closeQueryPanel(tester);
    state.catalog = [
      _catalog(73, '刷新学院路', BykcCourseSubCategory.aesthetic, ['学院路校区']),
    ];
    await tester.tap(find.byTooltip('刷新当前查询'));
    await tester.pumpAndSettle();
    expect(find.text('已加载内容中没有匹配项'), findsOneWidget);
    await openQueryPanel(tester);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '沙河校区'))
          .selected,
      isTrue,
    );
    await tester.ensureVisible(find.widgetWithText(TextButton, '恢复默认'));
    await tester.tap(find.widgetWithText(TextButton, '恢复默认'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '美育')).selected,
      isFalse,
    );
    expect(find.widgetWithText(FilterChip, '沙河校区'), findsNothing);
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '刷新学院路'), findsOneWidget);
  });

  testWidgets('博雅状态与校区各自并集且保持人数已满和未知类别语义', (tester) async {
    final state = await _mount(tester);
    state.update(() {
      state.catalog = [
        const FeatureDetail(
          title: '合成人数已满',
          presentation: BykcCoursePresentation(
            id: 81,
            courseName: '合成人数已满',
            status: BykcCourseStatus.available,
            selected: false,
            courseCurrentCount: 3,
            courseMaxCount: 3,
            category: BykcCourseCategory.boya,
            subCategory: BykcCourseSubCategory.aesthetic,
            audienceCampuses: ['沙河校区'],
          ),
        ),
        _catalog(82, '合成可选学院路', BykcCourseSubCategory.aesthetic, ['学院路校区']),
        const FeatureDetail(
          title: '合成一级回退',
          presentation: BykcCoursePresentation(
            id: 83,
            courseName: '合成一级回退',
            status: BykcCourseStatus.available,
            category: BykcCourseCategory.boya,
          ),
        ),
        _catalog(84, '合成未知类型', BykcCourseSubCategory.unknown, ['沙河校区']),
      ];
      state.snapshot = state.make(const FeatureQuery());
    });
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await tester.ensureVisible(find.widgetWithText(TextButton, '状态不限'));
    await tester.tap(find.widgetWithText(TextButton, '状态不限'));
    await tester.pumpAndSettle();
    await _chip(tester, '可选');
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    await closeQueryPanel(tester);
    expect(find.text('已加载内容中没有匹配项'), findsOneWidget);
    await openQueryPanel(tester);
    await _chip(tester, '学院路校区');
    await _chip(tester, '人数已满');
    await closeQueryPanel(tester);
    expect(find.widgetWithText(Card, '合成人数已满'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成可选学院路'), findsOneWidget);
    expect(find.widgetWithText(Card, '合成未知类型'), findsNothing);
    expect(find.widgetWithText(Card, '合成一级回退'), findsNothing);
  });

  testWidgets('博雅已选类别校区在切账号后清除', (tester) async {
    final state = await _mount(tester);
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    await _chip(tester, '美育');
    await _chip(tester, '沙河校区');
    await closeQueryPanel(tester);
    state.update(() => state.username = 'synthetic-b');
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '美育')).selected,
      isFalse,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '沙河校区'))
          .selected,
      isFalse,
    );
  });

  testWidgets('普通详情展示完整字段且签到路径必须经过独立已选读取', (tester) async {
    final state = await _mount(tester);
    await openFeature(tester, FeatureId.bykc);
    await tester.tap(find.widgetWithText(Card, '合成美育沙河'));
    await tester.pumpAndSettle();
    expect(find.text('合成联系人'), findsOneWidget);
    expect(find.text('000-TEST-01'), findsOneWidget);
    expect(find.text('合成开课单位'), findsOneWidget);
    await _show(tester, find.text('适用范围'));
    expect(find.text('合成学院'), findsOneWidget);
    expect(find.text('合成年级'), findsOneWidget);
    expect(find.text('合成人群'), findsOneWidget);
    await _show(tester, find.text('查看签到与签退'));
    expect(find.text('准备博雅签到'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, '查看签到与签退'));
    await tester.pumpAndSettle();
    expect(state.queries.last.view, FeatureQueryView.bykcChosenCourses);
    await tester.tap(find.widgetWithText(Card, '合成已选记录'));
    await tester.pumpAndSettle();
    await _show(tester, find.text('准备博雅签到'));
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '准备博雅签到'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '准备博雅签到'));
    await tester.pumpAndSettle();
    expect(state.prepared.single.courseId, 71);
    expect(state.prepared.single.kind, BykcSignKind.signIn);
  });

  testWidgets('已选完整详情保留具体记录考勤并在父刷新失配或重复后清除动作', (tester) async {
    for (final duplicate in [false, true]) {
      final state = await _mount(tester);
      await _openChosen(tester);
      await tester.tap(find.widgetWithText(Card, '合成已选记录'));
      await tester.pumpAndSettle();
      expect(state.queries.last.view, FeatureQueryView.bykcChosenCourses);
      expect(state.queries.last.courseId, '71');
      expect(find.text('7002'), findsOneWidget);
      expect(find.text('合成联系人'), findsOneWidget);
      await _show(tester, find.text('签到信息'));
      expect(find.text('已签到、未签退'), findsOneWidget);
      expect(find.text('考勤通过'), findsNothing);
      state.chosen = duplicate ? [_chosen, _chosen] : const [];
      await tester.tap(find.byTooltip('刷新当前查询'));
      await tester.pumpAndSettle();
      expect(find.text('准备博雅签到'), findsNothing);
      expect(find.text('准备退选'), findsNothing);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('准备博雅签到'), findsNothing);
    }
  });

  testWidgets('完整详情补查失败明确显示失败并禁止复用旧记录动作', (tester) async {
    final state = await _mount(tester);
    state.failFull = true;
    await _openChosen(tester);
    await tester.tap(find.widgetWithText(Card, '合成已选记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('合成完整详情读取失败'), findsWidgets);
    expect(find.text('准备博雅签到'), findsNothing);
    expect(find.text('准备退选'), findsNothing);
  });

  testWidgets('返回和切账号后迟到详情不能复活旧子帧及筛选', (tester) async {
    final state = await _mount(tester);
    await _openChosen(tester);
    state.pendingFull = Completer<void>();
    await tester.tap(find.widgetWithText(Card, '合成已选记录'));
    await tester.pump();
    expect(state.queries.last.courseId, '71');
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    state.pendingFull!.complete();
    await tester.pumpAndSettle();
    expect(find.text('合成联系人'), findsNothing);
    expect(find.text('准备博雅签到'), findsNothing);
    state.update(() => state.username = 'synthetic-b');
    await tester.pumpAndSettle();
    await openFeature(tester, FeatureId.bykc);
    await openQueryPanel(tester);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, '美育')).selected,
      isFalse,
    );
  });

  testWidgets('普通完整详情刷新失效后不能用旧动作掩盖失败', (tester) async {
    final state = await _mount(tester);
    await openFeature(tester, FeatureId.bykc);
    await tester.tap(find.widgetWithText(Card, '合成美育沙河'));
    await tester.pumpAndSettle();
    state.update(
      () => state.snapshot = state.snapshot.copyWith(
        status: FeatureLoadStatus.stale,
        error: const UiError(
          code: UbaaErrorCode.authenticationRequired,
          title: '会话失效',
          message: '合成会话失效',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('准备退选'), findsNothing);
    expect(find.text('查看签到与签退'), findsNothing);
    expect(find.textContaining('合成会话失效'), findsWidgets);
  });

  testWidgets('首页博雅待办进入同一完整详情读取', (tester) async {
    final state = await _mount(tester, home: true);
    final todo = find.text('合成已选记录');
    await _show(tester, todo);
    await tester.tap(todo);
    await tester.pumpAndSettle();
    expect(state.queries.last.view, FeatureQueryView.bykcDetail);
    expect(state.queries.last.courseId, '71');
    expect(find.text('合成联系人'), findsOneWidget);
  });
}

Future<void> _chip(WidgetTester tester, String name) async {
  final chip = find.widgetWithText(FilterChip, name);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).hitTestable().last,
      maxScrolls: 30,
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _openChosen(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Card, FeatureId.bykc.title));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Card, '我的课程'));
  await tester.pumpAndSettle();
}

FeatureDetail _catalog(
  int id,
  String name,
  BykcCourseSubCategory sub,
  List<String> campuses,
) => FeatureDetail(
  title: name,
  presentation: BykcCoursePresentation(
    id: id,
    courseName: name,
    status: BykcCourseStatus.available,
    category: BykcCourseCategory.boya,
    subCategory: sub,
    audienceCampuses: campuses,
    selected: true,
  ),
  readNavigation: FeatureReadNavigation(
    feature: FeatureId.bykc,
    query: FeatureQuery(view: FeatureQueryView.bykcDetail, courseId: '$id'),
  ),
);

const _chosen = FeatureDetail(
  title: '合成已选记录',
  presentation: BykcChosenPresentation(
    recordId: 7002,
    courseId: 71,
    courseName: '合成已选记录',
    courseStartDate: '2999-01-01 08:00:00',
    courseEndDate: '2999-01-01 10:00:00',
    checkin: 5,
    pass: 0,
  ),
  actions: [
    BykcSignAction(
      courseId: 71,
      kind: BykcSignKind.signIn,
      eligibility: ActionEligibility.allowed,
      requiresCoordinates: false,
    ),
    BykcSignAction(
      courseId: 71,
      kind: BykcSignKind.signOut,
      eligibility: ActionEligibility.unknown,
      requiresCoordinates: false,
    ),
    BykcDeselectAction(courseId: 71, eligibility: ActionEligibility.allowed),
  ],
);

FeatureDetail _full(String id) => FeatureDetail(
  title: '合成详情课程',
  actions: const [
    BykcDeselectAction(courseId: 71, eligibility: ActionEligibility.allowed),
  ],
  presentation: BykcCoursePresentation(
    id: int.parse(id),
    courseName: '合成详情课程',
    status: BykcCourseStatus.selected,
    selected: true,
    isDetail: true,
    audienceCampuses: const ['沙河校区'],
    hasSignPoints: true,
    supplement: const BykcCourseSupplement(
      courseContact: '合成联系人',
      courseContactMobile: '000-TEST-01',
      organizerCollegeName: '合成开课单位',
      descriptionPlainText: '第一行\n\n第二行',
      audienceColleges: ['合成学院'],
      audienceTerms: ['合成年级'],
      audienceGroups: ['合成人群'],
      signConfig: BykcSignDisplayConfig(
        signStartDate: '2026-09-16T08:00:00',
        signPointCount: 2,
      ),
      attendance: BykcAttendanceDisplay(
        recordId: 7001,
        courseId: 71,
        checkin: 1,
        pass: 1,
      ),
    ),
  ),
  readNavigation: const FeatureReadNavigation(
    feature: FeatureId.bykc,
    query: FeatureQuery(view: FeatureQueryView.bykcChosenCourses),
  ),
);

class _Scenario {
  late StateSetter update;
  late FeatureSnapshot snapshot;
  final queries = <FeatureQuery>[];
  final prepared = <BykcSignAction>[];
  String username = 'synthetic-a';
  int revision = 1;
  bool failFull = false;
  Completer<void>? pendingFull;
  List<FeatureDetail> catalog = [
    _catalog(71, '合成美育沙河', BykcCourseSubCategory.aesthetic, ['沙河校区']),
    _catalog(72, '合成德育沙河', BykcCourseSubCategory.moral, ['沙河校区']),
    _catalog(73, '合成美育学院路', BykcCourseSubCategory.aesthetic, ['学院路校区']),
    _catalog(74, '合成未知类别', BykcCourseSubCategory.unknown, []),
  ];
  List<FeatureDetail> chosen = [_chosen];
  bool isFull(FeatureQuery query) =>
      query.view == FeatureQueryView.bykcDetail ||
      query.view == FeatureQueryView.bykcChosenCourses &&
          query.courseId != null;
  List<FeatureDetail> chosenDetails(FeatureQuery query) =>
      query.courseId == null
      ? chosen
      : [
          for (final detail in chosen)
            FeatureDetail(
              title: detail.title,
              actions: detail.actions,
              presentation: (detail.presentation! as BykcChosenPresentation)
                  .withFullDetail(
                    _full(query.courseId!).presentation!
                        as BykcCoursePresentation,
                  ),
            ),
        ];
  FeatureSnapshot make(FeatureQuery query, {bool loading = false}) =>
      FeatureSnapshot(
        feature: FeatureId.bykc,
        status: loading
            ? FeatureLoadStatus.loading
            : failFull && isFull(query)
            ? FeatureLoadStatus.failure
            : FeatureLoadStatus.success,
        summary: '合成博雅数据',
        updatedAt: DateTime(2026, 9, 15),
        error: failFull && isFull(query)
            ? const UiError(
                code: UbaaErrorCode.upstreamChanged,
                title: '详情读取失败',
                message: '合成完整详情读取失败',
                retryable: true,
              )
            : null,
        details: loading || failFull && isFull(query)
            ? const []
            : query.view == FeatureQueryView.bykcDetail
            ? [_full(query.courseId!)]
            : query.view == FeatureQueryView.bykcChosenCourses
            ? chosenDetails(query)
            : catalog,
        readContext: FeatureReadContext(
          query: query,
          requestRevision: revision,
        ),
        pagination: query.view == FeatureQueryView.summary
            ? FeaturePagination(
                page: 1,
                size: 20,
                total: catalog.length,
                totalPages: 1,
              )
            : null,
      );
  Future<void> load(FeatureQuery query) async {
    queries.add(query);
    final current = ++revision;
    update(() => snapshot = make(query, loading: true));
    if (isFull(query) && pendingFull != null) await pendingFull!.future;
    if (current == revision) update(() => snapshot = make(query));
  }
}

Future<_Scenario> _mount(WidgetTester tester, {bool home = false}) async {
  await tester.pumpWidget(const SizedBox());
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(980, 1080);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final state = _Scenario();
  state.snapshot = state.make(
    FeatureQuery(
      view: home
          ? FeatureQueryView.bykcChosenCourses
          : FeatureQueryView.summary,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, update) {
          state.update = update;
          return coordinatedShell(
            initialDestination: home
                ? UiDestination.home
                : UiDestination.coursework,
            onLoadHomeSupplement: home
                ? (source, _) async => FeatureResult.success(
                    summary: '合成首页来源',
                    details: source == HomeSupplement.bykcChosen
                        ? state.chosen
                        : const [],
                  )
                : null,
            user: UserSummary(username: state.username),
            snapshots: {
              for (final feature in FeatureId.values)
                feature: feature == FeatureId.bykc
                    ? state.snapshot
                    : FeatureSnapshot(
                        feature: feature,
                        status: FeatureLoadStatus.success,
                      ),
            },
            routePolicy: RoutePolicy.direct,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onFeatureQuery: (_, query) => state.load(query),
            onPrepareBykcWrite: (_, __) async => throw StateError('合成场景未提交'),
            onPrepareBykcSignWrite: (action) async {
              state.prepared.add(action);
              throw StateError('仅观察准备入口');
            },
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}
