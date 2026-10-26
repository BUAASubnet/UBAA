import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';

void main() {
  testWidgets('宽屏时段铺满内容宽度，选中汇总随取消更新', (tester) async {
    await _open(tester, _dayDetails, [], width: 1400);
    final header = find.byKey(const ValueKey('cgyy-time-header-scroll'));
    final lastCell = find.byTooltip('无时段房间 09:00–10:00');
    expect(
      tester.getRect(lastCell).right,
      closeTo(tester.getRect(header).right, 1),
      reason: '宽屏最后一列应与内容区右边缘对齐',
    );
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
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
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
    await tester.pumpAndSettle();
    expect(find.text('下一步').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cgyy-selection-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏长楼栋选项可展开选择，查询保持原始站点编号', (tester) async {
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
      width: 1400,
    );
    final choice = find.byKey(const ValueKey('cgyy-choice-楼栋 / 楼层'));
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('合成长楼栋名称 / 合成长楼层名称').last);
    await tester.pumpAndSettle();
    expect(queries.last.siteId, 17);
    expect(queries.last.view, FeatureQueryView.cgyyDayInfo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('活动类型刷新失败保留已显示选项和草稿选择', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _dayDetails,
      [],
      loadPurposes: (_) async => ++calls == 1
          ? _purposes
          : const FeatureResult.failure(
              UiError(
                code: UbaaErrorCode.networkError,
                title: '合成刷新失败',
                message: '保持选择',
              ),
            ),
    );
    await _form(tester);
    expect(find.widgetWithText(OutlinedButton, '合成研讨甲'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '合成研讨甲'));
    await tester.tap(find.widgetWithText(OutlinedButton, '合成研讨甲'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('刷新活动类型'));
    await tester.tap(find.text('刷新活动类型'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '合成研讨甲'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '合成研讨甲'), findsOneWidget);
    expect(find.text('保持选择'), findsOneWidget);
  });

  testWidgets('已保存用途保留选项与未完整状态', (tester) async {
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
    expect(find.widgetWithText(OutlinedButton, '合成研讨甲'), findsOneWidget);
    expect(find.text('活动类型尚未核对完整'), findsOneWidget);
  });

  testWidgets('已保存研讨室时段无错误码也可阅读且没有预约下一步', (tester) async {
    await _open(tester, _dayDetails, [], cached: true);
    expect(tester.takeException(), isNull);
    expect(find.text('合成研讨室'), findsWidgets);
    expect(find.text('下一步'), findsNothing);
  });

  testWidgets('研讨室用途按原key选择，显示来源且返回保留选择', (tester) async {
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
    expect(find.text('使用预设活动类型'), findsOneWidget);
    expect(find.byTooltip('实际路线：混合'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '合成研讨甲'));
    await tester.tap(find.widgetWithText(OutlinedButton, '合成研讨甲'));
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
    expect(find.widgetWithText(OutlinedButton, '合成研讨乙'), findsOneWidget);
    await tester.tap(find.text('继续确认'));
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
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '选择活动类型'));
    await tester.tap(find.widgetWithText(OutlinedButton, '选择活动类型'));
    await tester.pumpAndSettle();
    expect(find.text('暂无可选活动类型，可重试或手动填写已知编号。'), findsOneWidget);
    await tester.ensureVisible(find.text('刷新活动类型'));
    await tester.tap(find.text('刷新活动类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '合成研讨甲'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '合成研讨甲'), findsOneWidget);
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
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
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
    expect(find.text('填写研讨室预约信息'), findsNothing);
    expect(find.text('synthetic-private-draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('研讨室预约使用独立表单，返回修改时段保留草稿', (tester) async {
    await _open(tester, _dayDetails, []);
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
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

  testWidgets('研讨室校区和楼栋采用typed选择，默认查询面板不占正文', (tester) async {
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
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.byTooltip('搜索与筛选'));
    await tester.pumpAndSettle();
    final sites = tester.widget<DropdownButton<int>>(
      find.byKey(const ValueKey('cgyy-choice-楼栋 / 楼层')),
    );
    expect(sites.items!.single.value, 7);
    await tester.tap(find.widgetWithText(TextButton, '完成'));
    await tester.pumpAndSettle();
    expect(queries, hasLength(1));
    expect(queries.single.siteId, 7);
    expect(queries.single.view, FeatureQueryView.cgyyDayInfo);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('研讨室房间时段表保留未知状态并在选中后才有下一步', (tester) async {
    final queries = <FeatureQuery>[];
    await _open(tester, _dayDetails, queries);
    expect(find.text('合成研讨室'), findsOneWidget);
    expect(find.text('无时段房间'), findsOneWidget);
    expect(find.text('资格未知'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
    await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsOneWidget);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('填写研讨室预约信息'), findsOneWidget);
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
  await tester.tap(find.byTooltip('合成研讨室 08:00–09:00'));
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
