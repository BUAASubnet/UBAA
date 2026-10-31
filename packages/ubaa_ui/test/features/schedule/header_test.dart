import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/schedule/flow.dart';

void main() {
  testWidgets('切换周次立即显示元数据日期，保留正文快照；跨学期和路线不混用', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.header?.number, 1);
    harness.query = const FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'term',
      week: 2,
    );
    harness.status = FeatureLoadStatus.loading;
    harness.route = null;
    await tester.pumpWidget(harness.build());
    await tester.pump();
    expect(harness.header?.number, 2);
    expect(harness.header?.headerDateLabels.first, '9-14');
    expect(find.text('第2周'), findsOneWidget);
    expect(find.text('原有正文'), findsOneWidget);

    harness.route = ConnectionMode.webvpn;
    await tester.pumpWidget(harness.build());
    expect(harness.header, isNull);
    harness.status = FeatureLoadStatus.success;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    expect(harness.loads, 2);
    expect(harness.header?.headerDateLabels.first, '10-5');

    harness.query = const FeatureQuery(
      view: FeatureQueryView.scheduleWeek,
      term: 'other',
      week: 2,
    );
    harness.status = FeatureLoadStatus.loading;
    await tester.pumpWidget(harness.build());
    expect(harness.header, isNull);
    expect(find.text('第2周'), findsOneWidget);
  });

  testWidgets('缺少或重复元数据只显示目标周数，账号切换丢弃旧元数据', (tester) async {
    for (final duplicate in [false, true]) {
      final harness = _Harness()
        ..metadata = duplicate ? [_week(1), _week(1)] : [];
      await tester.pumpWidget(harness.build(key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(harness.header, isNull);
      expect(find.text('第1周'), findsOneWidget);
    }
    final harness = _Harness();
    final key = UniqueKey();
    await tester.pumpWidget(harness.build(key: key));
    await tester.pumpAndSettle();
    expect(harness.header?.number, 1);
    harness.epoch++;
    harness.status = FeatureLoadStatus.loading;
    await tester.pumpWidget(harness.build(key: key));
    expect(harness.header, isNull);
  });

  testWidgets('旧路线迟到元数据不能覆盖新路线', (tester) async {
    final pending = Completer<FeatureResult>();
    final harness = _Harness()..pending = pending.future;
    await tester.pumpWidget(harness.build());
    await tester.pump();
    harness.route = ConnectionMode.webvpn;
    harness.pending = null;
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    pending.complete(
      FeatureResult.success(
        details: [_week(1)],
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.header?.headerDateLabels.first, '10-5');
  });
}

FeatureDetail _week(int n, {bool vpn = false}) => FeatureDetail(
  title: '第$n周',
  presentation: WeekPresentation(
    requestTerm: 'term',
    responseTerm: 'term',
    number: n,
    current: n == 1,
    startDate: vpn
        ? '2026-10-05'
        : n == 1
        ? '2026-09-07'
        : '2026-09-14',
    endDate: '',
  ),
);

class _Harness {
  FeatureQuery query = const FeatureQuery(
    view: FeatureQueryView.scheduleWeek,
    term: 'term',
    week: 1,
  );
  FeatureLoadStatus status = FeatureLoadStatus.success;
  ConnectionMode? route = ConnectionMode.direct;
  int epoch = 0, loads = 0;
  List<FeatureDetail>? metadata;
  Future<FeatureResult>? pending;
  WeekPresentation? header;
  Widget build({Key? key}) => MaterialApp(
    home: Scaffold(
      body: ScheduleFlow(
        key: key,
        query: query,
        visible: true,
        epoch: epoch,
        onQuery: (_) async {},
        snapshot: FeatureSnapshot(
          feature: FeatureId.schedule,
          status: status,
          resolvedRoute: route,
          readContext: FeatureReadContext(query: query, requestRevision: 1),
        ),
        loadWeeks: (_, _) async {
          loads++;
          return pending ??
              FeatureResult.success(
                details:
                    metadata ??
                    [
                      _week(1, vpn: route == ConnectionMode.webvpn),
                      _week(2, vpn: route == ConnectionMode.webvpn),
                    ],
                resolvedRoute: route,
              );
        },
        child: Builder(
          builder: (context) {
            header = ScheduleWeekScope.of(context);
            return const Text('原有正文');
          },
        ),
      ),
    ),
  );
}
