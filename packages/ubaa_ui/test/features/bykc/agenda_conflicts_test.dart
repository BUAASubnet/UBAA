import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/common/feature_detail.dart';
import 'package:ubaa_ui/src/features/agenda/format.dart';
import 'package:ubaa_ui/src/features/bykc/agenda_conflicts.dart';
import '../../agenda/support.dart';
import 'direct_actions_test.dart' as direct;

void main() {
  testWidgets('主界面接入日程检查，用户继续后才准备并提交选课', (tester) async {
    final backend = _Agenda();
    final service = AgendaService(backend);
    await service.openAccount('synthetic');
    addTearDown(() async {
      final closing = service.dispose();
      await tester.pump();
      await closing;
    });
    final h = await direct.mount(
      tester,
      agenda: AgendaAccess(service: service, term: '2026-2027-1'),
      commit: () async => direct.result(WriteOperation.bykcSelectCourse),
    );
    await tester.tap(direct.actionButton('选课'));
    await tester.pumpAndSettle();
    expect(find.text('与日程时间冲突'), findsOneWidget);
    expect(h.targets, isEmpty);
    expect(h.commits, 0);
    await tester.tap(find.text('继续选课'));
    await tester.pumpAndSettle();
    expect(h.targets, [(WriteOperation.bykcSelectCourse, 71)]);
    expect(h.commits, 1);
  });
  for (final detail in [false, true]) {
    testWidgets('列表与详情选课前检查日程，取消不提交，继续只提交一次：详情=$detail', (tester) async {
      final h = Harness(detail: detail);
      await h.mount(tester);
      await tester.tap(find.text('选课').first);
      await tester.pumpAndSettle();
      expect(find.text('与日程时间冲突'), findsOneWidget);
      expect(find.textContaining('合成会议'), findsOneWidget);
      expect(find.textContaining('14:30'), findsOneWidget);
      expect(h.writes, isEmpty);
      expect(h.backend.lastQuery!.from, '2026-11-18');
      expect(h.backend.lastQuery!.to, '2026-11-19');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.writes, isEmpty);
      h.backend.gate = Completer<AgendaQueryResult>();
      await tester.tap(find.text('选课').first);
      await tester.pump();
      await tester.tap(find.text('选课').first);
      await tester.pump();
      expect(h.backend.reads, 2);
      h.backend.gate!.complete(h.backend.result());
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续选课'));
      await tester.pumpAndSettle();
      expect(h.writes, [(WriteOperation.bykcSelectCourse, 1)]);
    });
  }
  testWidgets('筛选只隐藏相交课程，日程变更重新计算，关闭恢复原顺序', (tester) async {
    final h = Harness()..hide = true;
    await h.mount(tester);
    expect(find.text('合成博雅1'), findsNothing);
    expect(find.text('合成博雅2'), findsOneWidget);
    expect(find.text('时间未知课程'), findsOneWidget);
    expect(h.backend.reads, 1);
    h.backend.entries = [];
    h.update(() => h.epoch++);
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsOneWidget);
    h.backend.entries = [meeting()];
    h.update(() => h.epoch++);
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsNothing);
    h.update(() => h.hide = false);
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('合成博雅1')).dy,
      lessThan(tester.getTopLeft(find.text('合成博雅2')).dy),
    );
  });
  testWidgets('前页全部与日程冲突时继续加载后页，课程保留原始分页范围', (tester) async {
    final h = Harness()
      ..hide = true
      ..paged = true;
    await h.mount(tester);
    expect(h.moreReads, 1);
    expect(find.text('合成博雅1'), findsNothing);
    expect(find.text('合成博雅2'), findsOneWidget);
    expect(h.backend.reads, 2);
  });
  testWidgets('追加课程检查期间不重新显示已确认冲突的前页课程', (tester) async {
    final h = Harness()..hide = true;
    await h.mount(tester);
    h.backend.gate = Completer<AgendaQueryResult>();
    h.update(() => h.count = 4);
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsNothing);
    expect(find.text('正在检查日程冲突…'), findsOneWidget);
    h.backend.gate!.complete(h.backend.result());
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsNothing);
  });
  testWidgets('账号切换后旧筛选结果不能隐藏新账号课程', (tester) async {
    final h = Harness()..hide = true;
    final old = Completer<AgendaQueryResult>();
    h.backend.gate = old;
    await h.mount(tester);
    h.backend.gate = null;
    h.backend.entries = [];
    await h.service.openAccount('synthetic-new');
    h.update(() => h.epoch++);
    await tester.pumpAndSettle();
    old.complete(AgendaQueryResult(entries: [meeting()], sources: []));
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsOneWidget);
    expect(find.text('日程读取失败，尚未隐藏冲突课程'), findsNothing);
  });
  testWidgets('筛选结果不会复用到选课确认，点击时重新读取最新日程', (tester) async {
    final h = Harness()..hide = true;
    h.backend.entries = [];
    await h.mount(tester);
    h.backend.entries = [meeting()];
    await tester.tap(find.text('选课').first);
    await tester.pumpAndSettle();
    expect(h.backend.reads, 2);
    expect(find.text('与日程时间冲突'), findsOneWidget);
    expect(h.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  testWidgets('日程失败保留课程并提示，重试成功后筛选生效', (tester) async {
    final h = Harness()..hide = true;
    h.backend.fail = true;
    await h.mount(tester);
    expect(find.text('合成博雅1'), findsOneWidget);
    expect(find.text('日程读取失败，尚未隐藏冲突课程'), findsOneWidget);
    await tester.tap(find.text('选课').first);
    await tester.pumpAndSettle();
    expect(find.text('日程冲突检查未完成'), findsOneWidget);
    expect(h.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    h.backend.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('合成博雅1'), findsNothing);
  });
  testWidgets('学校日程没有同步记录时说明检查范围，已知冲突仍可筛除', (tester) async {
    final h = Harness()..hide = true;
    h.backend.sources.add(
      AgendaSource(
        feature: AgendaFeature.schedule,
        observations: [],
        missingScopes: [],
        semesterImported: false,
        unprojectableCount: 0,
      ),
    );
    await h.mount(tester);
    expect(find.text('合成博雅1'), findsNothing);
    expect(find.text('合成博雅2'), findsOneWidget);
    expect(find.text('日程信息不完整，只隐藏已确认冲突的课程'), findsOneWidget);
    await tester.tap(find.text('选课').first);
    await tester.pumpAndSettle();
    expect(find.text('日程冲突检查未完成'), findsOneWidget);
    expect(h.writes, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  for (final whileDialog in [false, true]) {
    testWidgets('离开页面后迟到检查或确认均不能提交：弹窗已显示=$whileDialog', (tester) async {
      final h = Harness();
      await h.mount(tester);
      if (!whileDialog) h.backend.gate = Completer<AgendaQueryResult>();
      await tester.tap(find.text('选课').first);
      await tester.pumpAndSettle();
      h.update(() => h.visible = false);
      await tester.pumpAndSettle();
      h.backend.gate?.complete(h.backend.result());
      await tester.pumpAndSettle();
      expect(find.text('继续选课'), findsNothing);
      expect(h.writes, isEmpty);
    });
  }
  testWidgets('无冲突直接提交，缺时间需明确继续，退选不进行日程检查', (tester) async {
    final h = Harness();
    h.backend.entries = [];
    await h.mount(tester);
    await tester.tap(find.text('选课').first);
    await tester.pumpAndSettle();
    expect(h.writes, [(WriteOperation.bykcSelectCourse, 1)]);
    await tester.tap(find.text('选课').last);
    await tester.pumpAndSettle();
    expect(find.text('日程冲突检查未完成'), findsOneWidget);
    await tester.tap(find.text('继续选课'));
    await tester.pumpAndSettle();
    expect(h.writes.last, (WriteOperation.bykcSelectCourse, 3));
    h.update(() => h.selected = true);
    await tester.pumpAndSettle();
    final reads = h.backend.reads;
    await tester.tap(find.text('退选').first);
    await tester.pumpAndSettle();
    expect(h.backend.reads, reads);
    expect(h.writes.last, (WriteOperation.bykcDeselectCourse, 1));
  });
}

class Harness {
  Harness({this.detail = false});
  final bool detail;
  final backend = _Agenda();
  late AgendaService service;
  late StateSetter update;
  bool hide = false, visible = true, selected = false;
  int epoch = 0, moreReads = 0;
  bool paged = false;
  int pages = 1, count = 3;
  final writes = <(WriteOperation, int)>[];
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    service = AgendaService(backend);
    await service.openAccount('synthetic');
    addTearDown(() async {
      final closing = service.dispose();
      await tester.pump();
      await closing;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, change) {
              update = change;
              return FeatureDetailView(
                feature: FeatureId.bykc,
                visible: visible,
                hasMore: paged && pages == 1,
                onLoadMore: paged
                    ? () async {
                        moreReads++;
                        update(() => pages = 2);
                      }
                    : null,
                snapshot: FeatureSnapshot(
                  feature: FeatureId.bykc,
                  status: FeatureLoadStatus.success,
                  details: [
                    for (
                      var id = 1;
                      id <=
                          (detail
                              ? 1
                              : paged
                              ? pages
                              : count);
                      id++
                    )
                      FeatureDetail(
                        title: id == 3 ? '时间未知课程' : '合成博雅$id',
                        presentation: BykcCoursePresentation(
                          id: id,
                          courseName: id == 3 ? '时间未知课程' : '合成博雅$id',
                          courseStartDate: id == 3
                              ? null
                              : '2026-11-18 ${id == 1 ? '14' : '16'}:00:00',
                          courseEndDate: id == 3
                              ? null
                              : '2026-11-18 ${id == 1 ? '16' : '18'}:00:00',
                          status: BykcCourseStatus.available,
                          isDetail: detail,
                          selected: selected,
                        ),
                        actions: [
                          BykcSelectAction(
                            courseId: id,
                            eligibility: ActionEligibility.allowed,
                          ),
                          BykcDeselectAction(
                            courseId: id,
                            eligibility: ActionEligibility.allowed,
                          ),
                        ],
                      ),
                  ],
                ),
                query: FeatureQuery(
                  view: detail
                      ? FeatureQueryView.bykcDetail
                      : FeatureQueryView.summary,
                ),
                bykcAgenda: BykcAgendaContext(
                  access: AgendaAccess(service: service, term: '2026-2027-1'),
                  route: ConnectionMode.direct,
                  epoch: epoch,
                ),
                bykcFilters: BykcCourseFilters(hideAgendaConflicts: hide),
                onBykcFiltersChanged: (_) {},
                onBack: () {},
                onRetry: () async {},
                onBykcWrite: (operation, id) async {
                  writes.add((operation, id));
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

class _Agenda extends MemoryAgenda {
  List<AgendaEntry> entries = [meeting()];
  int reads = 0;
  bool fail = false;
  AgendaQueryResult result() =>
      AgendaQueryResult(entries: entries, sources: sources);
  @override
  Future<AgendaQueryResult> query(AgendaQuery query) async {
    lastQuery = query;
    reads++;
    if (fail) throw const AgendaException(AgendaFailure.unavailable);
    return gate == null ? result() : await gate!.future;
  }
}

AgendaEntry meeting() {
  final start = AgendaTime(
    rfc3339: '2026-11-18T14:30:00+08:00',
    timezone: 'Asia/Shanghai',
  );
  final end = AgendaTime(
    rfc3339: '2026-11-18T16:00:00+08:00',
    timezone: 'Asia/Shanghai',
  );
  return AgendaEntry(
    local: AgendaOccurrence(
      itemId: 'meeting',
      recurrenceId: start.rfc3339,
      content: AgendaContent(
        kind: AgendaKind.event,
        title: '合成会议',
        start: start,
        end: end,
        allDay: false,
      ),
      overridden: false,
    ),
    timing: AgendaTiming(kind: AgendaTimingKind.period, start: start, end: end),
    soon: false,
    completed: false,
    hidden: false,
  );
}
