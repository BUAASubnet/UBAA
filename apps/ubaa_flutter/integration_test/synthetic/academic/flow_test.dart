import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../../navigation.dart';
import '../app/flow_test.dart' show createInspectionApp;

part 'flow/support.dart';
part 'flow/b2.dart';

const _academicFeatures = [
  FeatureId.schedule,
  FeatureId.exam,
  FeatureId.grades,
  FeatureId.classroom,
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('原生学业页内选择器与状态筛选：${brightness.name}', (tester) async {
      await _loginAcademic(tester, brightness, 'normal');
      await _openAcademic(tester, FeatureId.schedule);
      // 课表自动定位：学期列表 → 教学周 → 本周课表，不经手填。
      _expectScheduleWeek(tester, '2026-2027-1', 2);
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-current-week',
        FeatureId.schedule,
        '进入课表后自动定位当前学期本周，读取typed周课表',
      );
      await _tapAcademic(tester, find.byTooltip('下一周'));
      _expectScheduleWeek(tester, '2026-2027-1', 3);
      await _tapAcademic(tester, find.text('第 3 周'));
      expect(find.text('选择教学周'), findsOneWidget);
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-week-picker',
        FeatureId.schedule,
        '课表自身的教学周选择器列出合成周次并标出本周',
      );
      await _tapAcademic(tester, find.widgetWithText(ListTile, '第 1 周'));
      _expectScheduleWeek(tester, '2026-2027-1', 1);
      await _tapAcademic(tester, find.byTooltip('上一周'));
      _expectScheduleWeek(tester, '2026-2027-1', 1);
      await _selectAcademicTerm(tester, '2025-2026-2');
      _expectScheduleWeek(tester, '2025-2026-2', 2);
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-other-term',
        FeatureId.schedule,
        '顶栏学期选择换学期后重新定位该学期本周',
      );
      await _horizontalAcademic(
        binding,
        tester,
        brightness,
        FeatureId.schedule,
        'normal-schedule-week-horizontal',
      );

      for (final (feature, options) in [
        (
          FeatureId.exam,
          <(String, FeatureQueryView)>[
            ('已安排', FeatureQueryView.examArranged),
            ('未安排', FeatureQueryView.examNotArranged),
            ('全部', FeatureQueryView.summary),
          ],
        ),
        (
          FeatureId.grades,
          <(String, FeatureQueryView)>[
            ('已出成绩', FeatureQueryView.gradesScored),
            ('待出成绩', FeatureQueryView.gradesMissing),
            ('全部', FeatureQueryView.summary),
          ],
        ),
      ]) {
        await _openAcademic(tester, feature);
        if (feature == FeatureId.exam) {
          await _openAcademicFilter(tester);
          await _tapAcademic(tester, find.widgetWithText(ActionChip, '当前学期'));
          await _tapAcademic(
            tester,
            find.widgetWithText(ListTile, '2026-2027-1'),
          );
          expect(
            _academicSnapshot(tester, feature).readContext!.query!.term,
            '2026-2027-1',
          );
          expect(
            find.widgetWithText(ActionChip, '2026-2027-1'),
            findsOneWidget,
          );
        }
        for (final (label, view) in options) {
          await _chooseAcademicStatus(tester, feature, label, view);
          final result = _academicSnapshot(tester, feature);
          if (feature == FeatureId.exam) {
            expect(result.readContext!.query!.term, '2026-2027-1');
            expect(
              result.details.every(
                (item) => item.presentation is ExamPresentation,
              ),
              isTrue,
            );
            if (view != FeatureQueryView.summary) {
              expect(
                result.details.every(
                  (item) =>
                      (item.presentation! as ExamPresentation).arranged ==
                      (view == FeatureQueryView.examArranged),
                ),
                isTrue,
              );
            }
          } else {
            expect(
              result.details.every(
                (item) => item.presentation is GradePresentation,
              ),
              isTrue,
            );
            if (view != FeatureQueryView.summary) {
              expect(
                result.details.every(
                  (item) =>
                      ((item.presentation! as GradePresentation).score
                              ?.trim()
                              .isNotEmpty ??
                          false) ==
                      (view == FeatureQueryView.gradesScored),
                ),
                isTrue,
              );
            }
          }
          await _academicCapture(
            binding,
            tester,
            brightness,
            'normal-${feature.name}-${view.name.toLowerCase()}',
            feature,
            '点选$label即读取；从snapshot.readContext核对视图，校验typed结果分类',
          );
          if (view == FeatureQueryView.summary) {
            await _closeAcademicFilter(tester);
            await _checkAcademicDetails(binding, tester, brightness, feature);
          }
        }
        await _closeAcademicFilter(tester);
      }

      await _openAcademic(tester, FeatureId.classroom);
      await _selectClassroomInputs(binding, tester, brightness);
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-classroom-matched',
        FeatureId.classroom,
        '正文切换日期与校区；typed上下文精确匹配',
      );
    });

    for (final state in [
      'empty',
      'first-error',
      'stale',
      'long',
      'many',
      'loading',
    ]) {
      testWidgets(
        '原生学业四领域状态$state：${brightness.name}',
        (tester) async {
          final failingReads = <FeatureId>{};
          Completer<void>? pendingRead;
          addTearDown(() {
            if (pendingRead != null && !pendingRead.isCompleted) {
              pendingRead.complete();
            }
          });
          await _loginAcademic(
            tester,
            brightness,
            state,
            scale: state == 'long' ? 1.3 : 1.0,
            failingReads: state == 'stale' ? failingReads : null,
            beforeRead: state == 'loading'
                ? () async {
                    await pendingRead?.future;
                  }
                : null,
          );
          for (final feature in _academicFeatures) {
            await _openAcademic(tester, feature);
            final schedule = feature == FeatureId.schedule;
            if (state == 'first-error') {
              final before = _academicSnapshot(tester, feature);
              expect(before.status, FeatureLoadStatus.failure);
              await _academicCapture(
                binding,
                tester,
                brightness,
                '$state-${feature.name}-before',
                feature,
                '首次合成读取失败，未回退演示成功',
              );
              // 课表自动定位逐级读取学期、教学周和周课表，每级首读都会失败一次。
              for (
                var attempt = 0;
                attempt < 3 &&
                    _academicSnapshot(tester, feature).status ==
                        FeatureLoadStatus.failure;
                attempt++
              ) {
                await _tapAcademic(tester, find.text('重试').last);
              }
              final after = _academicSnapshot(tester, feature);
              expect(after.status, FeatureLoadStatus.success);
              expect(
                after.readContext!.requestRevision,
                greaterThan(before.readContext!.requestRevision),
              );
              if (schedule) {
                _expectScheduleWeek(tester, '2026-2027-1', 2);
              } else {
                expect(
                  after.readContext!.hasSameQuery(before.readContext!.query),
                  isTrue,
                );
              }
            } else if (state == 'loading') {
              pendingRead = Completer<void>();
              await tester.tap(_academicRefresh);
              await tester.pump(const Duration(milliseconds: 200));
              expect(
                _academicSnapshot(tester, feature).status,
                FeatureLoadStatus.loading,
              );
              await _academicCapture(
                binding,
                tester,
                brightness,
                '$state-${feature.name}-pending',
                feature,
                '观察实际合成backend延迟中的加载态',
                settle: false,
              );
              pendingRead.complete();
              pendingRead = null;
              await _waitAcademicStatus(
                tester,
                feature,
                FeatureLoadStatus.success,
              );
            } else if (state == 'stale') {
              final beforeRefresh = _academicSnapshot(tester, feature);
              expect(
                beforeRefresh.status,
                FeatureLoadStatus.success,
                reason: feature.name,
              );
              failingReads.add(feature);
              // 课表不提供搜索；其余列表的常驻搜索在刷新失败后保留。
              if (!schedule) {
                await _academicSearch(tester, _searchFor(feature));
              }
              await _tapAcademic(tester, _academicRefresh);
              final failed = _academicSnapshot(tester, feature);
              expect(
                failed.status,
                FeatureLoadStatus.stale,
                reason:
                    '${feature.name}: ${beforeRefresh.readContext?.query} -> ${failed.readContext?.query}',
              );
              expect(find.widgetWithText(TextButton, '重试'), findsWidgets);
              if (!schedule) {
                expect(
                  failed.readContext!.query,
                  isNull,
                  reason: '默认读取刷新必须保持null上下文，不能换为显式summary',
                );
                expect(_academicSearchText(tester), _searchFor(feature));
              }
              await _academicCapture(
                binding,
                tester,
                brightness,
                '$state-${feature.name}-before-retry',
                feature,
                '同视图刷新失败后保留旧结果和本地搜索',
              );
              await _tapAcademic(tester, find.widgetWithText(TextButton, '重试'));
              final retried = _academicSnapshot(tester, feature);
              expect(retried.status, FeatureLoadStatus.stale);
              expect(find.widgetWithText(TextButton, '重试'), findsWidgets);
              expect(
                retried.readContext!.hasSameQuery(failed.readContext!.query),
                isTrue,
              );
              expect(
                retried.readContext!.requestRevision,
                greaterThan(failed.readContext!.requestRevision),
              );
              if (!schedule) {
                expect(_academicSearchText(tester), _searchFor(feature));
              }
            } else if (schedule && (state == 'empty' || state == 'many')) {
              // 学期列表为空或编号重复时不静默挑选，停在选择学期提示。
              expect(find.text('请选择学期'), findsOneWidget);
              expect(
                _academicSnapshot(tester, feature).readContext?.query?.view,
                FeatureQueryView.scheduleTerms,
              );
            } else {
              final snapshot = _academicSnapshot(tester, feature);
              expect(
                snapshot.status,
                state == 'empty'
                    ? FeatureLoadStatus.empty
                    : FeatureLoadStatus.success,
              );
              if (schedule) _expectScheduleWeek(tester, '2026-2027-1', 2);
              if (state == 'empty') expect(snapshot.details, isEmpty);
              if (state == 'many') {
                expect(snapshot.details, hasLength(40));
                expect(
                  snapshot.pagination,
                  isNull,
                  reason: '学业合成many只用现有本地分页，不能冒称服务端页',
                );
                await _academicCapture(
                  binding,
                  tester,
                  brightness,
                  '$state-${feature.name}-page-one',
                  feature,
                  '40条合成数据的本地第一页',
                );
                await tester.drag(
                  find.byType(Scrollable).hitTestable().last,
                  const Offset(0, -2000),
                );
                await tester.pumpAndSettle();
                expect(
                  _academicSnapshot(
                    tester,
                    feature,
                  ).readContext?.requestRevision,
                  snapshot.readContext?.requestRevision,
                );
              }
            }
            await _academicCapture(
              binding,
              tester,
              brightness,
              '$state-${feature.name}-result',
              feature,
              '记录$state最终可见状态及当前真实snapshot上下文',
            );
            if (state == 'long') {
              await _horizontalAcademic(
                binding,
                tester,
                brightness,
                feature,
                '$state-${feature.name}-horizontal',
              );
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 6)),
      );
    }
  }
}
