import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_academic_old/backend.dart';

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
            beginTime: '08:00',
            endTime: '09:40',
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
