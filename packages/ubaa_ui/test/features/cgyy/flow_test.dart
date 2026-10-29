import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';
import 'package:ubaa_ui/src/features/cgyy/reservation_flow.dart';
import 'package:ubaa_ui/src/write/cgyy/draft.dart';
import 'package:ubaa_ui/src/shared/loading.dart';

void main() {
  testWidgets('只看可预约隐藏无可用房间和时段，关闭后恢复', (tester) async {
    await _open(tester, _dayDetails, []);
    expect(find.text('合成研讨室'), findsOneWidget);
    expect(_slot('无时段房间', '09:00–10:00'), findsNothing);
    expect(_slot('合成研讨室', '09:00–10:00'), findsNothing);
    await tester.tap(find.text('只看可预约'));
    await tester.pumpAndSettle();
    expect(_slot('无时段房间', '09:00–10:00'), findsOneWidget);
    expect(_slot('合成研讨室', '09:00–10:00'), findsOneWidget);
  });
  testWidgets('整页无可用时段提示并允许恢复全部表格', (tester) async {
    await _open(tester, [_dayDetails.first, _dayDetails.last], []);
    expect(find.text('这一天该楼层没有可预约时段'), findsOneWidget);
    await tester.tap(find.text('显示全部时段'));
    await tester.pumpAndSettle();
    expect(_slot('合成研讨室', '09:00–10:00'), findsOneWidget);
    expect(_slot('无时段房间', '09:00–10:00'), findsOneWidget);
  });
  testWidgets('缓存楼层先到且网络仍在加载时不闪通用列表', (tester) async {
    final draft = CgyyFormDraft();
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CgyyReservationFlow(
            snapshot: FeatureSnapshot(
              feature: FeatureId.cgyy,
              status: FeatureLoadStatus.loading,
              evidence: DataEvidence(
                accountId: 'synthetic',
                origin: DataOrigin.persisted,
                fetchedAt: DateTime(2026, 10, 28),
                complete: true,
                savedForOffline: true,
              ),
              details: const [
                FeatureDetail(
                  title: '缓存楼层',
                  presentation: CgyySitePresentation(
                    id: 7,
                    siteName: '一层',
                    venueName: '合成楼',
                    campusName: '沙河',
                  ),
                ),
              ],
            ),
            query: const FeatureQuery(view: FeatureQueryView.summary),
            cacheEpoch: 0,
            fallback: const Text('通用楼层列表'),
            onQuery: (_) async {},
            onRetry: () async {},
            formContext: CgyyFormContext(draft: draft),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LoadingPlaceholder), findsOneWidget);
    expect(find.text('通用楼层列表'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('宽屏时段铺满内容宽度，选中汇总随取消更新', (tester) async {
    await _open(tester, _dayDetails, [], width: 1400);
    final header = find.byKey(const ValueKey('cgyy-time-header-scroll'));
    await tester.tap(find.text('只看可预约'));
    await tester.pumpAndSettle();
    final lastCell = _slot('无时段房间', '09:00–10:00');
    expect(
      tester.getRect(lastCell).right,
      closeTo(tester.getRect(header).right, 1),
      reason: '宽屏最后一列应与内容区右边缘对齐',
    );
    await tester.tap(_slot('合成研讨室', '08:00–09:00'));
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('cgyy-selection-summary'));
    expect(
      find.descendant(of: summary, matching: find.textContaining('合成研讨室')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.textContaining('2026-09-04')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.textContaining('08:00–09:00'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('清空选择'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsNothing);
  });

  testWidgets('窄屏大字时段表头同步滚动且汇总不遮挡下一步', (tester) async {
    await _open(tester, _dayDetails, [], scale: 2);
    await tester.tap(find.text('只看可预约'));
    await tester.pumpAndSettle();
    final head = find.byKey(const ValueKey('cgyy-time-header-scroll'));
    final body = find.byKey(const ValueKey('cgyy-time-body-scroll'));
    await tester.drag(body, const Offset(-220, 0));
    await tester.pumpAndSettle();
    final a = tester.widget<SingleChildScrollView>(head).controller!;
    final b = tester.widget<SingleChildScrollView>(body).controller!;
    expect(a.offset, greaterThan(0));
    expect(a.offset, closeTo(b.offset, .01));
    a.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(_slot('合成研讨室', '08:00–09:00'));
    await tester.pumpAndSettle();
    expect(find.text('下一步').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cgyy-selection-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏直接点选长楼栋，查询保持原始站点编号', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(
      tester,
      const [
        FeatureDetail(
          title: '忽略展示编号',
          presentation: CgyySitePresentation(
            id: 7,
            venueName: '合成楼',
            siteName: '合成楼',
            campusName: '学院路校区',
          ),
        ),
        FeatureDetail(
          title: '另一个展示编号',
          presentation: CgyySitePresentation(
            id: 17,
            venueName: '合成长楼栋名称',
            siteName: '合成长楼层名称',
            campusName: '学院路校区',
          ),
        ),
      ],
      queries,
      width: 402,
    );
    final choice = find.byKey(const ValueKey('cgyy-site-17'));
    await tester.ensureVisible(choice);
    await tester.pumpAndSettle();
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(queries.last.siteId, 17);
    expect(queries.last.view, FeatureQueryView.cgyyDayInfo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('活动类型首次读取失败可重试且保留已填草稿', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _dayDetails,
      [],
      loadPurposes: (_) async => ++calls == 1
          ? const FeatureResult.failure(
              UiError(
                code: UbaaErrorCode.networkError,
                title: '活动类型加载失败',
                message: '合成错误',
                retryable: true,
              ),
            )
          : _purposes,
    );
    await _form(tester);
    final phone = find.widgetWithText(TextField, '联系电话');
    await tester.enterText(phone, 'synthetic-phone');
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('合成研讨甲'), findsOneWidget);
    expect(tester.widget<TextField>(phone).controller!.text, 'synthetic-phone');
    expect(calls, 2);
  });
  testWidgets('已保存用途仍可选择原始编号', (tester) async {
    await _open(
      tester,
      _dayDetails,
      [],
      loadPurposes: (_) async => FeatureResult.success(
        details: _purposes.details,
        resolvedRoute: ConnectionMode.direct,
        evidence: DataEvidence(
          accountId: 'synthetic',
          origin: DataOrigin.persisted,
          fetchedAt: DateTime(2026, 9, 22),
          complete: false,
          savedForOffline: true,
        ),
      ),
    );
    await _form(tester);
    expect(find.text('合成研讨甲'), findsOneWidget);
  });

  testWidgets('已保存研讨室时段无错误码也可阅读且没有预约下一步', (tester) async {
    await _open(tester, _dayDetails, [], cached: true);
    await tester.tap(find.text('显示全部时段'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('合成研讨室'), findsWidgets);
    expect(find.text('下一步'), findsNothing);
  });

  testWidgets('研讨室用途按原key选择且返回保留选择', (tester) async {
    var calls = 0;
    CgyySubmitInput? input;
    await _open(
      tester,
      _dayDetails,
      [],
      loadPurposes: (_) async {
        calls++;
        return _purposes;
      },
      prepare: (value) async {
        input = value;
        throw StateError('仅捕获准备参数');
      },
    );
    await _form(tester);

    await tester.ensureVisible(find.text('合成研讨甲'));
    await tester.tap(find.text('合成研讨甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成研讨乙'));
    await tester.pumpAndSettle();
    for (final entry in {
      '联系电话': 'synthetic-phone',
      '预约主题': '合成主题',
      '活动内容': '合成讨论',
      '参与人说明': '合成人员',
    }.entries) {
      final field = find.widgetWithText(TextField, entry.key);
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('返回修改时段'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('合成研讨乙'), findsOneWidget);
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(input?.purposeType, 37);
    expect(input?.phone, 'synthetic-phone');
    expect(calls, 2);
  });
  testWidgets('研讨室空用途不猜编号，重试后可选', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _dayDetails,
      [],
      loadPurposes: (_) async =>
          ++calls == 1 ? const FeatureResult.empty() : _purposes,
    );
    await _form(tester);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('合成研讨甲'), findsOneWidget);
    expect(calls, 2);
  });
  testWidgets('研讨室读取代次变化关闭旧表单且拒绝迟到用途', (tester) async {
    final epoch = ValueNotifier(0);
    addTearDown(epoch.dispose);
    final gate = Completer<FeatureResult>();
    await _open(
      tester,
      _dayDetails,
      [],
      epoch: epoch,
      loadPurposes: (_) => gate.future,
    );
    await tester.tap(_slot('合成研讨室', '08:00–09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.widgetWithText(TextField, '联系电话'),
      'synthetic-private-draft',
    );
    epoch.value++;
    await tester.pump(const Duration(milliseconds: 400));
    gate.complete(_purposes);
    await tester.pumpAndSettle();
    expect(find.text('填写预约信息'), findsNothing);
    expect(find.text('synthetic-private-draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('研讨室预约使用独立表单，返回修改时段保留草稿', (tester) async {
    await _open(tester, _dayDetails, []);
    await tester.tap(_slot('合成研讨室', '08:00–09:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('已选时段'), findsOneWidget);
    final phone = find.widgetWithText(TextField, '联系电话');
    await tester.enterText(phone, 'synthetic-phone');
    await tester.tap(find.text('返回修改时段'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(phone).controller!.text, 'synthetic-phone');
  });

  testWidgets('研讨室移动端直接显示原始站点选择，默认读取不采用展示编号', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, const [
      FeatureDetail(
        title: '假标题',
        fields: [FeatureField(label: '站点 ID', value: '999')],
        presentation: CgyySitePresentation(
          id: 7,
          siteName: '一层',
          venueName: '合成研讨楼',
          campusName: '沙河校区',
        ),
      ),
    ], queries);
    final site = find.byKey(const ValueKey('cgyy-site-7'));
    await tester.ensureVisible(site);
    expect(tester.widget<FilterChip>(site).selected, isTrue);
    expect(queries, hasLength(1));
    expect(queries.single.siteId, 7);
    expect(queries.single.view, FeatureQueryView.cgyyDayInfo);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('研讨室房间时段表保留未知状态并在选中后才有下一步', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, _dayDetails, queries);
    expect(find.text('合成研讨室'), findsOneWidget);
    await tester.tap(find.text('只看可预约'));
    await tester.pumpAndSettle();
    expect(find.text('无时段房间'), findsOneWidget);
    expect(find.text('资格未知'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
    await tester.tap(_slot('合成研讨室', '08:00–09:00'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '填写预约信息'), findsOneWidget);
    expect(queries, isEmpty);
  });
}

const _dayDetails = [
  FeatureDetail(
    title: '预约时间',
    presentation: CgyyDayPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      availableDates: ['2026-09-04'],
      timeSlots: [
        CgyyTimePresentation(
          id: 9,
          beginTime: '08:00',
          endTime: '09:00',
          label: '上午',
        ),
        CgyyTimePresentation(
          id: 3,
          beginTime: '09:00',
          endTime: '10:00',
          label: '上午',
        ),
      ],
      spaces: [
        CgyySpacePresentation(spaceId: 4, spaceName: '合成研讨室', venueSiteId: 7),
        CgyySpacePresentation(spaceId: 5, spaceName: '无时段房间', venueSiteId: 7),
      ],
    ),
  ),
  FeatureDetail(
    title: '合成研讨室 上午',
    presentation: CgyySlotPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      spaceId: 4,
      spaceName: '合成研讨室',
      timeId: 9,
      beginTime: '08:00',
      endTime: '09:00',
      reservationStatus: 1,
    ),
    actions: [
      CgyyReserveAction(
        venueSiteId: 7,
        reservationDate: '2026-09-04',
        spaceId: 4,
        timeId: 9,
        timeOrdinal: 0,
        venueSpaceGroupId: null,
        eligibility: ActionEligibility.allowed,
      ),
    ],
  ),
  FeatureDetail(
    title: '合成研讨室 上午',
    presentation: CgyySlotPresentation(
      venueSiteId: 7,
      reservationDate: '2026-09-04',
      spaceId: 4,
      spaceName: '合成研讨室',
      timeId: 3,
      beginTime: '09:00',
      endTime: '10:00',
    ),
  ),
];

Future<void> _open(
  WidgetTester tester,
  List<FeatureDetail> details,
  List<FeatureQuery> queries, {
  Future<FeatureResult> Function(bool)? loadPurposes,
  bool cached = false,
  double width = 402,
  double scale = 1,
  ValueNotifier<int>? epoch,
  Future<WriteIntent> Function(CgyySubmitInput)? prepare,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final revision = epoch ?? ValueNotifier(0);
  if (epoch == null) addTearDown(revision.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (context, value, _) => UbaaMainShell(
          readCacheEpoch: value,
          onLoadCgyyPurposes: loadPurposes,
          initialDestination: UiDestination.campus,
          user: const UserSummary(username: 'synthetic'),
          snapshots: {
            for (final id in FeatureId.values)
              id: cached && id == FeatureId.cgyy
                  ? CachedFeatureProjection(
                      feature: id,
                      accountId: 'synthetic',
                      route: ConnectionMode.direct,
                      fetchedAt: DateTime(2026, 9, 22),
                      complete: true,
                      details: details,
                    ).toSnapshot()
                  : FeatureSnapshot(
                      feature: id,
                      status: FeatureLoadStatus.success,
                      resolvedRoute: ConnectionMode.direct,
                      details: id == FeatureId.cgyy ? details : const [],
                    ),
          },
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onFeatureQuery: (_, query) async {
            queries.add(query);
          },
          onPrepareCgyySubmitWrite:
              prepare ?? (_) async => throw StateError('本用例禁止写准备'),
          onRunWritePrepare: (prepare, {required expectedOperation}) async =>
              prepare(),
          onCancelWrite: () async {},
          onConfirmWrite: () async => null,
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.cgyy);
}

Future<void> _form(WidgetTester tester) async {
  await tester.tap(_slot('合成研讨室', '08:00–09:00'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下一步'));
  await tester.pumpAndSettle();
}

const _purposes = FeatureResult.success(
  resolvedRoute: ConnectionMode.webvpn,
  details: [
    FeatureDetail(
      title: '假编号999',
      presentation: CgyyPurposePresentation(
        key: 9,
        name: '合成研讨甲',
        isStaticFallback: true,
      ),
    ),
    FeatureDetail(
      title: '假编号888',
      presentation: CgyyPurposePresentation(
        key: 37,
        name: '合成研讨乙',
        isStaticFallback: true,
      ),
    ),
  ],
);

Finder _slot(String room, String time) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label?.startsWith('$room ') ?? false) &&
      (widget.properties.label?.contains(' $time ') ?? false),
);
