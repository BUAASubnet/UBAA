import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/navigation.dart';
import '../support/write_harness.dart';

void main() {
  testWidgets('阳光首页搜索保留原记录编号和图片数量等低频字段能力', (tester) async {
    await _open(tester);
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '101');
    await tester.pumpAndSettle();
    await closeQueryPanel(tester);
    expect(find.text('合成历史运动'), findsOneWidget);
    await openQueryPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选详情'), '图片数量');
    await tester.pumpAndSettle();
    await closeQueryPanel(tester);
    expect(find.text('合成历史运动'), findsOneWidget);
  });
  testWidgets('阳光旧首页先概要再记录，项目只在新增入口打开后出现', (tester) async {
    await _open(tester);
    expect(find.text('本学期认定次数 0 次'), findsOneWidget);
    expect(find.text('本周打卡 0 / 3'), findsOneWidget);
    expect(find.text('打卡记录'), findsOneWidget);
    expect(find.text('合成历史运动'), findsOneWidget);
    expect(find.text('合成运动项目'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('2 张图片'), findsOneWidget);
    expect(find.textContaining('未分享'), findsOneWidget);
    await tester.tap(find.byTooltip('新增打卡'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '填写阳光打卡信息'), findsOneWidget);
    await tester.tap(find.text('选择运动项目'));
    await tester.pumpAndSettle();
    expect(find.text('合成运动项目'), findsOneWidget);
    await tester.tap(find.text('合成运动项目'));
    await tester.pumpAndSettle();
    expect(find.text('填写阳光打卡信息'), findsOneWidget);
    expect(find.widgetWithText(TextField, '开始时间'), findsOneWidget);
  });
  testWidgets('阳光记录局部失败保留概要并显示重试，不伪装没有记录', (tester) async {
    await _open(
      tester,
      records: const YgdkHomeRecords(
        page: 1,
        size: 20,
        errorCode: UbaaErrorCode.networkError,
      ),
    );
    expect(find.text('本学期认定次数 0 次'), findsOneWidget);
    expect(find.text('打卡记录加载失败，请重试。'), findsOneWidget);
    expect(find.text('暂时还没有打卡记录'), findsNothing);
    expect(find.text('重试记录'), findsOneWidget);
  });
  testWidgets('阳光记录低频编号与未知状态进详情，跨天结束日期不丢失', (tester) async {
    await _open(tester);
    expect(find.textContaining('2026-09-10 00:30'), findsOneWidget);
    expect(find.text('记录编号'), findsNothing);
    await tester.tap(find.widgetWithText(Card, '合成历史运动'));
    await tester.pumpAndSettle();
    expect(find.text('记录详情'), findsOneWidget);
    expect(find.text('记录编号'), findsOneWidget);
    expect(find.text('999'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

const _records = YgdkHomeRecords(
  page: 1,
  size: 20,
  total: 1,
  hasMore: false,
  content: [
    YgdkRecordPresentation(
      recordId: 101,
      itemId: 7,
      itemName: '合成历史运动',
      startTime: '2026-09-09 23:30',
      endTime: '2026-09-10 00:30',
      place: '合成操场',
      imageCount: 2,
      isOpen: false,
      state: 999,
      createdAtLabel: '合成提交时间',
    ),
  ],
);
Future<void> _open(
  WidgetTester tester, {
  YgdkHomeRecords records = _records,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(402, 874);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: coordinatedShell(
        initialTab: 2,
        user: const UserSummary(username: 'synthetic'),
        snapshots: {
          for (final id in FeatureId.values)
            id: FeatureSnapshot(
              feature: id,
              status: FeatureLoadStatus.success,
              overview: id == FeatureId.ygdk
                  ? YgdkOverview(
                      termCount: 0,
                      weekCount: 0,
                      weekTarget: 3,
                      classifyId: 31,
                      classifyName: '合成体育',
                      defaultItemId: 7,
                      defaultItemName: '合成运动项目',
                      records: records,
                    )
                  : null,
              details: id == FeatureId.ygdk
                  ? const [
                      FeatureDetail(
                        title: '合成运动项目',
                        presentation: YgdkItemPresentation(
                          itemId: 7,
                          name: '合成运动项目',
                        ),
                        actions: [
                          YgdkSubmitAction(
                            classifyId: 31,
                            itemId: 7,
                            eligibility: ActionEligibility.allowed,
                          ),
                        ],
                      ),
                    ]
                  : const [],
              readContext: FeatureReadContext(
                query: const FeatureQuery(),
                requestRevision: 1,
              ),
              resolvedRoute: ConnectionMode.direct,
            ),
        },
        routePolicy: RoutePolicy.direct,
        telemetryEnabled: false,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onFeatureQuery: (_, __) async {},
        onPrepareBykcWrite: (_, __) async => throw StateError('禁止写入'),
        onPrepareYgdkSubmitWrite: (_) async => throw StateError('禁止写入'),
        onPickYgdkPhoto: () async => null,
        onRefreshYgdkAfterWrite: ({required expectedRoute}) async {},
        onDiscardWriteIntent: (_) async {},
        onCommitWrite: (_) async => throw StateError('禁止提交'),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.ygdk);
}
