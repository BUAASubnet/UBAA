import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../academic/parity/backend.dart';

/// 只用于旧课表原生验收的明确合成数据；写入继承禁止。
class ScheduleOldBackend extends AcademicOldBackend {
  ScheduleOldBackend({super.state});
  final scheduleReads = <FeatureQuery>[];
  bool fail = false;
  Completer<void>? schedulePending;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    // 课表自动定位：学期列表 → 教学周（第4周为本周）→ 周课表。
    if (feature == FeatureId.schedule &&
        query.view == FeatureQueryView.scheduleWeeks) {
      final term = query.term!;
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (final (index, week) in [3, 4, 5].indexed)
            FeatureDetail(
              title: '第 $week 周',
              presentation: WeekPresentation(
                requestTerm: term,
                responseTerm: term,
                number: week,
                current: week == 4,
                startDate: ['2026-08-31', '2026-09-07', '2026-09-14'][index],
                endDate: ['2026-09-06', '2026-09-13', '2026-09-20'][index],
              ),
            ),
        ],
      );
    }
    if (feature != FeatureId.schedule ||
        query.view != FeatureQueryView.scheduleWeek) {
      return super.loadFeatureQuery(feature, query);
    }
    scheduleReads.add(query);
    if (schedulePending case final gate?) await gate.future;
    if (fail || (state == 'first-error' && scheduleReads.length == 1)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (state == 'empty') {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    final details = <FeatureDetail>[];
    for (var i = 0; i < (state == 'many' ? 22 : 7); i++) {
      details.add(
        FeatureDetail(
          title: title('合成课程${i + 1}'),
          presentation: ScheduleCoursePresentation(
            courseCode: 'COURSE-SAFE-${i + 1}',
            dayOfWeek: state == 'many' ? 1 : i + 1,
            beginSection: state == 'many' ? 1 : [1, 3, 5, 7, 9, 11, 13][i],
            endSection: state == 'many' ? 2 : [2, 4, 6, 8, 10, 12, 13][i],
            beginTime: state == 'many'
                ? '08:00'
                : [
                    '08:00',
                    '09:50',
                    '11:30',
                    '14:50',
                    '16:40',
                    '19:00',
                    '20:40',
                  ][i],
            endTime: state == 'many'
                ? '09:35'
                : [
                    '09:35',
                    '11:25',
                    '14:45',
                    '16:35',
                    '18:15',
                    '20:35',
                    '21:25',
                  ][i],
            place: title('合成A203'),
            weeksAndTeachers: title('合成教师与周次'),
            teachingTarget: '合成教学对象',
            color: [
              '#89C8F0',
              '#AFE1AF',
              '#FFCC99',
              '#C4B0EB',
              '#E6B8CC',
              '#B2DFDB',
              '无效颜色',
            ][i % 7],
          ),
        ),
      );
    }
    details.add(
      const FeatureDetail(
        title: '合成时间待定课程',
        presentation: ScheduleCoursePresentation(
          courseCode: 'UNKNOWN-SAFE',
          dayOfWeek: 9,
          beginSection: 4,
          endSection: 2,
          weeksAndTeachers: '不因缺少学分隐藏教师',
        ),
      ),
    );
    return FeatureResult.success(
      details: details,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
