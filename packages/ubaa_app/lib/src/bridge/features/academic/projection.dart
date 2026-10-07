import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/mapping.dart' show bridgeCompactFields, bridgeField;
part 'cached_models.dart';

bool bridgeMatchesClassroomFloor(
  BridgeClassroomInfo room,
  String floorName,
  String? filter,
) {
  if (filter == null || filter.isEmpty) return true;
  final normalized = filter.toLowerCase();
  return room.floorId.trim().toLowerCase() == normalized ||
      floorName.trim().toLowerCase() == normalized;
}

/// 冻结 `kxsds`/`availableSections` 是逗号分隔的节次序号；只匹配完整令牌，
/// 避免把第 3 节误命中为第 13 节。
bool bridgeMatchesClassroomSection(String available, String? filter) {
  if (filter == null || filter.isEmpty) return true;
  return available
      .split(',')
      .map((item) => item.trim())
      .any((item) => item == filter);
}

/// 两个周课表入口共用纯展示投影，不读取或推断新的查询字段。
FeatureDetail bridgeMapScheduleCourseDetail(BridgeCourseClass item) =>
    FeatureDetail(
      title: item.courseName,
      subtitle: item.courseCode,
      presentation: ScheduleCoursePresentation(
        courseCode: item.courseCode,
        courseSerialNo: item.courseSerialNo,
        credit: item.credit,
        beginTime: item.beginTime,
        endTime: item.endTime,
        beginSection: item.beginSection,
        endSection: item.endSection,
        dayOfWeek: item.dayOfWeek,
        place: item.placeName,
        weeksAndTeachers: item.weeksAndTeachers,
        teachingTarget: item.teachingTarget,
        color: item.color,
      ),
      fields: bridgeCompactFields(<FeatureField?>[
        bridgeField('时间', item.beginTime),
        bridgeField('地点', item.placeName),
        bridgeField('周次', item.weeksAndTeachers),
      ]),
    );

FeatureDetail bridgeMapExamDetail(BridgeExam item, {required bool arranged}) =>
    FeatureDetail(
      title: item.courseName,
      subtitle: item.examTimeDescription ?? item.examDate,
      presentation: ExamPresentation(
        arranged: arranged,
        courseNo: item.courseNo,
        date: item.examDate,
        description: item.examTimeDescription,
        startTime: item.startTime,
        endTime: item.endTime,
        place: item.examPlace,
        seat: item.examSeatNo,
        week: item.week,
        status: item.examStatus,
        type: item.examType,
        taskId: item.taskId,
      ),
      fields: bridgeCompactFields(<FeatureField?>[
        bridgeField(
          '时间',
          item.startTime == null || item.endTime == null
              ? null
              : '${item.startTime}–${item.endTime}',
        ),
        bridgeField('地点', item.examPlace),
        bridgeField('座位', item.examSeatNo),
        bridgeField('类型', item.examType),
      ]),
    );

GradePresentation bridgeMapGradePresentation(BridgeGrade item) =>
    GradePresentation(
      courseName: item.courseName,
      courseCode: item.courseCode,
      score: item.score,
      gradePoint: item.gradePoint,
      credit: item.credit,
      courseType: item.courseType,
      scoreType: item.scoreType,
      termCode: item.termCode,
    );
