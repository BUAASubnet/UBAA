import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import 'app_flow_test.dart' show createInspectionApp;

part 'ui_academic/support.dart';
part 'ui_academic/b2.dart';

const _academicFeatures = [
  FeatureId.schedule,
  FeatureId.exam,
  FeatureId.grades,
  FeatureId.classroom,
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('原生学业全部子视图与typed父子返回：${brightness.name}', (tester) async {
      await _loginAcademic(tester, brightness, 'normal');
      await _openAcademic(tester, FeatureId.schedule);
      await _chooseAcademicView(tester, '按输入查询');
      await _selectAcademicTerm(tester, FeatureId.schedule);
      await _academicField(tester, '周次（可选）', '2');
      await _chooseAcademicView(tester, '按输入查询');
      await _applyAcademic(
        tester,
        FeatureId.schedule,
        FeatureQueryView.summary,
        term: '2026-2027-1',
      );
      expect(
        _academicSnapshot(tester, FeatureId.schedule).readContext!.query!.week,
        2,
      );
      expect(
        _academicSnapshot(tester, FeatureId.schedule).details.every(
          (item) => item.presentation is ScheduleCoursePresentation,
        ),
        isTrue,
      );
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-input-compatibility',
        FeatureId.schedule,
        '真实学期弹窗只更新草稿；按输入查询携带学期和周次并保持兼容',
      );
      await _chooseAcademicView(tester, '今日课程');
      await _applyAcademic(
        tester,
        FeatureId.schedule,
        FeatureQueryView.scheduleToday,
      );
      expect(
        _academicSnapshot(tester, FeatureId.schedule).readContext!.query!.term,
        isNull,
      );
      expect(
        _academicSnapshot(tester, FeatureId.schedule).readContext!.query!.week,
        isNull,
      );
      expect(
        _academicSnapshot(
          tester,
          FeatureId.schedule,
        ).details.every((item) => item.presentation is TodayCoursePresentation),
        isTrue,
      );
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-today',
        FeatureId.schedule,
        '应用今日课程，读取合成backend结果的typed上下文',
      );

      await _chooseAcademicView(tester, '学期列表');
      await _applyAcademic(
        tester,
        FeatureId.schedule,
        FeatureQueryView.scheduleTerms,
      );
      final term = _academicSnapshot(tester, FeatureId.schedule).details.first;
      final termTarget = term.readNavigation!;
      expect(term.presentation, isA<TermPresentation>());
      await _academicField(tester, '筛选详情', '秋季');
      await _academicField(tester, '学期编码（可选）', '父学期未应用草稿');
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-terms',
        FeatureId.schedule,
        '学期列表保存本地搜索和未应用草稿',
      );
      await _tapAcademic(tester, find.text('查看周次'));
      _expectAcademicQuery(tester, FeatureId.schedule, termTarget.query);
      final weeks = _academicSnapshot(tester, FeatureId.schedule);
      expect(
        weeks.details.every((item) => item.presentation is WeekPresentation),
        isTrue,
      );
      final week = weeks.details.firstWhere(
        (item) => (item.presentation! as WeekPresentation).number == 2,
      );
      final weekTarget = week.readNavigation!;
      await _academicField(tester, '筛选详情', '第 2 周');
      await _academicField(tester, '学期编码（可选）', '父周次未应用草稿');
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-weeks',
        FeatureId.schedule,
        '点击typed学期后读取周次，保留第二层草稿',
      );
      await _tapAcademic(tester, find.text('查看周课表'));
      _expectAcademicQuery(tester, FeatureId.schedule, weekTarget.query);
      expect(
        _academicSnapshot(tester, FeatureId.schedule).details.every(
          (item) => item.presentation is ScheduleCoursePresentation,
        ),
        isTrue,
      );
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-week',
        FeatureId.schedule,
        '点击第2周，参数从公开typed导航传入并在readContext核对',
      );
      await _horizontalAcademic(
        binding,
        tester,
        brightness,
        FeatureId.schedule,
        'normal-schedule-week-horizontal',
      );
      final revision = _academicSnapshot(
        tester,
        FeatureId.schedule,
      ).readContext!.requestRevision;
      await _tapAcademic(tester, find.byTooltip('返回'));
      expect(_academicFieldText(tester, '筛选详情'), '第 2 周');
      expect(_academicFieldText(tester, '学期编码（可选）'), '父周次未应用草稿');
      expect(
        _academicSnapshot(
          tester,
          FeatureId.schedule,
        ).readContext!.requestRevision,
        revision,
      );
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-back-weeks',
        FeatureId.schedule,
        '原生页面返回按钮恢复父周次搜索/草稿；readContext修订未增加，非新请求',
      );
      await _tapAcademic(tester, find.byTooltip('返回'));
      expect(_academicFieldText(tester, '筛选详情'), '秋季');
      expect(_academicFieldText(tester, '学期编码（可选）'), '父学期未应用草稿');
      expect(
        _academicSnapshot(
          tester,
          FeatureId.schedule,
        ).readContext!.requestRevision,
        revision,
      );
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-schedule-back-terms',
        FeatureId.schedule,
        '再次返回父学期，UI缓存恢复而非冒称发生父查询',
      );

      for (final (feature, options) in [
        (
          FeatureId.exam,
          <(String, FeatureQueryView)>[
            ('全部考试', FeatureQueryView.summary),
            ('已安排', FeatureQueryView.examArranged),
            ('未安排', FeatureQueryView.examNotArranged),
          ],
        ),
        (
          FeatureId.grades,
          <(String, FeatureQueryView)>[
            ('全部成绩', FeatureQueryView.summary),
            ('已出成绩', FeatureQueryView.gradesScored),
            ('待出成绩', FeatureQueryView.gradesMissing),
          ],
        ),
      ]) {
        await _openAcademic(tester, feature);
        await _selectAcademicTerm(tester, feature);
        for (final (label, view) in options) {
          await _chooseAcademicView(tester, label);
          await _applyAcademic(tester, feature, view, term: '2026-2027-1');
          final result = _academicSnapshot(tester, feature);
          if (feature == FeatureId.exam) {
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
            '应用$label；从snapshot.readContext核对学期与视图，校验typed结果分类',
          );
          if (view == FeatureQueryView.summary) {
            await _checkAcademicTable(binding, tester, brightness, feature);
          }
        }
      }

      await _openAcademic(tester, FeatureId.classroom);
      await _selectClassroomInputs(binding, tester, brightness);
      await _academicCapture(
        binding,
        tester,
        brightness,
        'normal-classroom-matched',
        FeatureId.classroom,
        '应用真实输入日期/校区/楼层/节次；typed上下文及令牌精确匹配',
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
          await _loginAcademic(
            tester,
            brightness,
            state,
            scale: state == 'long' ? 1.3 : 1.0,
          );
          for (final feature in _academicFeatures) {
            await _openAcademic(tester, feature);
            if (feature == FeatureId.schedule &&
                !['first-error', 'stale', 'long'].contains(state)) {
              await _chooseAcademicView(tester, '按输入查询');
            }
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
              await _tapAcademic(tester, find.text('重试').last);
              final after = _academicSnapshot(tester, feature);
              expect(after.status, FeatureLoadStatus.success);
              expect(
                after.readContext!.hasSameQuery(before.readContext!.query),
                isTrue,
              );
              expect(
                after.readContext!.requestRevision,
                greaterThan(before.readContext!.requestRevision),
              );
            } else if (state == 'loading') {
              final apply = find.widgetWithText(FilledButton, '应用筛选');
              await tester.ensureVisible(apply);
              await tester.tap(apply);
              await tester.pump(const Duration(milliseconds: 200));
              expect(
                _academicSnapshot(tester, feature).status,
                FeatureLoadStatus.loading,
              );
              expect(
                _academicSnapshot(tester, feature).readContext!.query!.view,
                FeatureQueryView.summary,
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
              await _waitAcademicStatus(
                tester,
                feature,
                FeatureLoadStatus.success,
              );
            } else if (state == 'stale') {
              await _academicField(tester, '筛选详情', _searchFor(feature));
              await _tapAcademic(tester, find.byTooltip('刷新当前查询'));
              final failed = _academicSnapshot(tester, feature);
              expect(failed.status, FeatureLoadStatus.stale);
              expect(find.text('以下为上次成功加载的数据。'), findsOneWidget);
              expect(
                failed.readContext!.query,
                isNull,
                reason: '默认读取刷新必须保持null上下文，不能换为显式summary',
              );
              expect(_academicFieldText(tester, '筛选详情'), _searchFor(feature));
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
              expect(find.text('以下为上次成功加载的数据。'), findsOneWidget);
              expect(
                retried.readContext!.hasSameQuery(failed.readContext!.query),
                isTrue,
              );
              expect(
                retried.readContext!.requestRevision,
                greaterThan(failed.readContext!.requestRevision),
              );
              expect(_academicFieldText(tester, '筛选详情'), _searchFor(feature));
            } else {
              if (state == 'long' && feature == FeatureId.schedule) {
                await _chooseAcademicView(tester, '周课表');
                await _academicField(tester, '学期编码（可选）', '2026-2027-1');
                await _academicField(tester, '周次（可选）', '2');
                await _applyAcademic(
                  tester,
                  feature,
                  FeatureQueryView.scheduleWeek,
                  term: '2026-2027-1',
                );
                expect(
                  _academicSnapshot(tester, feature).readContext!.query!.week,
                  2,
                );
              } else {
                if (state == 'long' && feature == FeatureId.classroom) {
                  await _academicField(tester, '日期', '2026-09-08');
                  await _captureAcademicDateField(binding, tester, brightness);
                }
                await _applyAcademic(
                  tester,
                  feature,
                  FeatureQueryView.summary,
                  status: state == 'empty'
                      ? FeatureLoadStatus.empty
                      : FeatureLoadStatus.success,
                );
              }
              if (state == 'empty') {
                expect(_academicSnapshot(tester, feature).details, isEmpty);
              }
              if (state == 'many') {
                final before = _academicSnapshot(tester, feature);
                expect(before.details, hasLength(40));
                expect(
                  before.pagination,
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
                await _tapAcademic(tester, find.byTooltip('下一页'));
                expect(find.text('2 / 2'), findsOneWidget);
                expect(
                  _academicSnapshot(
                    tester,
                    feature,
                  ).readContext!.requestRevision,
                  before.readContext!.requestRevision,
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
