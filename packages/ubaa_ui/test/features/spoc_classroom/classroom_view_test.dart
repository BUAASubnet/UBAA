import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/player_page.dart';

import 'fixture.dart';

void main() {
  testWidgets('直播卡位于最新教学周之前，点击进入该节次', (tester) async {
    final fixture = await ClassroomFixture.load();
    final live = fixture.period(ClassroomStatus.live);
    setViewport(tester);
    await pumpClassroom(tester, fixture.view());

    final liveCard = find.ancestor(
      of: find.text('正在直播'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: liveCard, matching: find.text(live.title)),
      findsOneWidget,
    );
    final newestWeek = find.text('第 4 周 · 1 节');
    expect(
      tester.getBottomLeft(liveCard).dy,
      lessThan(tester.getTopLeft(newestWeek).dy),
    );
    expect(find.text('第 2 周 · 1 节'), findsNothing);

    await tapAndSettle(tester, find.text(live.title));
    expect(find.byType(ClassroomPlayerPage), findsOneWidget);
    expect(fixture.sessionCalls, [(fixture.data.courseId, live.subId)]);
  });

  testWidgets('显示各状态文字，四种不可播放节次不打开播放器', (tester) async {
    final fixture = await ClassroomFixture.load();
    final replay = fixture.period(ClassroomStatus.replay);
    final additional = [
      for (final (status, title) in [
        (ClassroomStatus.tencentMeeting, '演示腾讯会议节次'),
        (ClassroomStatus.other, '演示不可播放节次'),
      ])
        ClassroomSessionSummary(
          subId: status.name,
          title: title,
          week: replay.week,
          startSecs: replay.startSecs + status.index * 7200,
          endSecs: replay.endSecs + status.index * 7200,
          room: replay.room,
          lecturer: replay.lecturer,
          status: status,
        ),
    ];
    fixture.readCatalog = (_) async =>
        fixture.withPeriods([...fixture.data.sessions, ...additional]);
    setViewport(tester, height: 960);
    await pumpClassroom(tester, fixture.view());

    expect(find.text('正在直播'), findsOneWidget);
    expect(find.text('回放'), findsOneWidget);
    for (final (title, label) in [
      (fixture.period(ClassroomStatus.upcoming).title, '未开始'),
      (fixture.period(ClassroomStatus.noReplay).title, '无回放'),
      (additional.first.title, '腾讯会议'),
      (additional.last.title, '不可播放'),
    ]) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: row, matching: find.text(label)),
        findsOneWidget,
      );
      expect(tester.widget<InkWell>(row).onTap, isNull);
      await tapAndSettle(tester, find.text(title));
      expect(find.byType(ClassroomPlayerPage), findsNothing);
    }
    expect(fixture.sessionCalls, isEmpty);
  });

  testWidgets('成功读到空目录时显示空态', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (_) async => fixture.withPeriods([]);
    await pumpClassroom(tester, fixture.view());

    expect(find.text('还没有课堂记录'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('首次读取失败显示错误，重试后显示目录', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (_) async {
      if (fixture.catalogCalls.length == 1) throw catalogFailure;
      return fixture.demoCatalog;
    };
    setViewport(tester);
    await pumpClassroom(tester, fixture.view());

    expect(find.text('课堂读取失败'), findsOneWidget);
    expect(find.text(catalogFailure.message), findsOneWidget);
    expect(find.text('正在直播'), findsNothing);
    await tapAndSettle(tester, find.text('重试'));
    expect(find.text('课堂读取失败'), findsNothing);
    expect(find.text('正在直播'), findsOneWidget);
    expect(fixture.catalogCalls, [fixture.kcid, fixture.kcid]);
  });

  testWidgets('刷新失败保留旧目录并展示横幅，重试成功后替换数据', (tester) async {
    final fixture = await ClassroomFixture.load();
    fixture.readCatalog = (_) async => switch (fixture.catalogCalls.length) {
      1 => fixture.demoCatalog,
      2 => throw catalogFailure,
      _ => fixture.withPeriods([]),
    };
    setViewport(tester);
    await pumpClassroom(tester, fixture.view());

    final banner = find.text('刷新失败，显示的是上次读取的内容');
    await tapAndSettle(tester, find.byTooltip('刷新'));
    expect(banner, findsOneWidget);
    expect(
      find.text(fixture.period(ClassroomStatus.replay).title),
      findsOneWidget,
    );
    expect(find.text('课堂读取失败'), findsNothing);

    await tapAndSettle(tester, find.text('重试'));
    expect(banner, findsNothing);
    expect(find.text('还没有课堂记录'), findsOneWidget);
    expect(
      find.text(fixture.period(ClassroomStatus.replay).title),
      findsNothing,
    );
    expect(fixture.catalogCalls, List.filled(3, fixture.kcid));
  });
}
