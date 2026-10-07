import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/backend.dart';
import 'package:ubaa_app/src/presentation/grades.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../../cache/lifecycle.dart' show bridgeAwaitOfflineScope;
import 'projection.dart'
    show
        AcademicCacheMiss,
        AcademicValue,
        bridgeAcademicEvidence,
        bridgeMapExamDetail,
        bridgeMapGradePresentation,
        bridgeMapScheduleCourseDetail,
        bridgeMatchesClassroomFloor,
        bridgeMatchesClassroomSection;
import '../schedule/projection.dart' show bridgeScheduleOverview;
import '../schedule/reader.dart' show bridgeLoadTodayWithCache;
import '../../support/mapping.dart'
    show
        bridgeCacheTime,
        bridgeCompactFields,
        bridgeCountResult,
        bridgeField,
        bridgeRequiredQueryValue,
        bridgeToConnectionMode;
part 'cache_read.dart';

Future<FeatureResult> bridgeLoadAcademicFeature(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query,
  String today,
) async {
  final reader = _AcademicReader(backend);
  final result = await _projectAcademicFeature(
    backend,
    reader,
    feature,
    query,
    today,
  );
  return bridgeAcademicEvidence(result, reader.evidence);
}

Future<FeatureResult> _projectAcademicFeature(
  BridgeContext backend,
  _AcademicReader client,
  FeatureId feature,
  FeatureQuery query,
  String today,
) async {
  switch (feature) {
    case FeatureId.schedule:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.scheduleToday:
          if (query.view == FeatureQueryView.summary &&
              query.term != null &&
              query.week != null) {
            final result = await client.scheduleWeek(
              term: query.term!,
              week: query.week!,
            );
            final details = result.data.arrangedList
                .map(bridgeMapScheduleCourseDetail)
                .toList(growable: false);
            return bridgeCountResult(
              details.length,
              '第 ${query.week} 周课表',
              overview: bridgeScheduleOverview(result.data, details),
              details: details,
              resolvedRoute: result.route,
            );
          }
          return bridgeLoadTodayWithCache(backend);
        case FeatureQueryView.scheduleTerms:
          final result = await client.scheduleTerms();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.itemName,
                  presentation: TermPresentation(
                    code: item.itemCode,
                    selected: item.selected,
                    index: item.itemIndex,
                  ),
                  readNavigation: item.itemCode.trim().isEmpty
                      ? null
                      : FeatureReadNavigation(
                          feature: FeatureId.schedule,
                          query: FeatureQuery(
                            view: FeatureQueryView.scheduleWeeks,
                            term: item.itemCode,
                          ),
                        ),
                  fields: <FeatureField>[
                    FeatureField(label: '学期编码', value: item.itemCode),
                    FeatureField(
                      label: '当前学期',
                      value: item.selected ? '是' : '否',
                    ),
                  ],
                ),
              )
              .toList(growable: false);
          return bridgeCountResult(
            details.length,
            '个学期',
            details: details,
            resolvedRoute: result.route,
          );
        case FeatureQueryView.scheduleWeeks:
          final term = bridgeRequiredQueryValue(query.term, '学期编码');
          final result = await client.scheduleWeeks(term: term);
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  subtitle: '${item.startDate}–${item.endDate}',
                  presentation: WeekPresentation(
                    requestTerm: term,
                    responseTerm: item.term,
                    number: item.serialNumber,
                    current: item.curWeek,
                    startDate: item.startDate,
                    endDate: item.endDate,
                  ),
                  readNavigation: item.serialNumber <= 0
                      ? null
                      : FeatureReadNavigation(
                          feature: FeatureId.schedule,
                          query: FeatureQuery(
                            view: FeatureQueryView.scheduleWeek,
                            term: term,
                            week: item.serialNumber,
                          ),
                        ),
                  fields: <FeatureField>[
                    FeatureField(label: '周次', value: '${item.serialNumber}'),
                    FeatureField(label: '当前周', value: item.curWeek ? '是' : '否'),
                  ],
                ),
              )
              .toList(growable: false);
          return bridgeCountResult(
            details.length,
            '个周次',
            details: details,
            resolvedRoute: result.route,
          );
        case FeatureQueryView.scheduleWeek:
          final term = bridgeRequiredQueryValue(query.term, '学期编码');
          final week = query.week;
          if (week == null || week <= 0) {
            throw const BackendException(UbaaErrorCode.invalidInput);
          }
          final result = await client.scheduleWeek(term: term, week: week);
          final details = result.data.arrangedList
              .map(bridgeMapScheduleCourseDetail)
              .toList(growable: false);
          return bridgeCountResult(
            details.length,
            '第 $week 周课表',
            overview: bridgeScheduleOverview(result.data, details),
            details: details,
            resolvedRoute: result.route,
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.exam:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.examArranged:
        case FeatureQueryView.examNotArranged:
          final term = query.term ?? await _selectedTerm(client);
          if (term == null) return const FeatureResult.empty();
          final result = await client.examArrangement(term: term);
          final exams = <({BridgeExam item, bool arranged})>[
            if (query.view != FeatureQueryView.examNotArranged)
              for (final item in result.data.arranged)
                (item: item, arranged: true),
            if (query.view != FeatureQueryView.examArranged)
              for (final item in result.data.notArranged)
                (item: item, arranged: false),
          ];
          final details = exams
              .map(
                (entry) =>
                    bridgeMapExamDetail(entry.item, arranged: entry.arranged),
              )
              .toList(growable: false);
          final label = switch (query.view) {
            FeatureQueryView.examArranged => '已安排考试',
            FeatureQueryView.examNotArranged => '未安排考试',
            _ => '考试安排',
          };
          return bridgeCountResult(
            exams.length,
            label,
            details: details,
            resolvedRoute: result.route,
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.grades:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.gradesScored:
        case FeatureQueryView.gradesMissing:
          final term = query.term ?? await _selectedTerm(client);
          if (term == null) return const FeatureResult.empty();
          final result = await client.grades(term: term);
          final allGrades = result.data.grades
              .map(bridgeMapGradePresentation)
              .toList(growable: false);
          return projectGrades(
            GradesTermOverview(
              requestTerm: term,
              termCode: result.data.termCode,
              grades: List.unmodifiable(allGrades),
            ),
            query.view,
            result.route,
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.classroom:
      final campus = query.campus ?? 1;
      final queryDate = today;
      final result = await client.classroomSearch(
        campus: campus,
        date: queryDate,
      );
      final floorFilter = query.floorId?.trim();
      final sectionFilter = query.section?.trim();
      final details = <FeatureDetail>[
        for (final floor in result.data.floors)
          for (final room in floor.rooms)
            if (bridgeMatchesClassroomFloor(room, floor.name, floorFilter) &&
                bridgeMatchesClassroomSection(
                  room.availableSections,
                  sectionFilter,
                ))
              FeatureDetail(
                title: room.name,
                subtitle: floor.name,
                presentation: ClassroomPresentation(
                  roomId: room.id,
                  floorId: room.floorId,
                  floorName: floor.name,
                  availableSections: room.availableSections,
                  queryDate: queryDate,
                  campus: campus,
                ),
                fields: bridgeCompactFields(<FeatureField?>[
                  bridgeField('可用节次', room.availableSections),
                ]),
              ),
      ];
      return bridgeCountResult(
        details.length,
        '间可用教室',
        details: details,
        resolvedRoute: result.route,
      );
    default:
      throw StateError('unexpected feature: $feature');
  }
}

Future<String?> _selectedTerm(_AcademicReader client) async {
  final result = await client.scheduleTerms();
  if (client.localRoute != null) {
    final selected = result.data
        .where((term) => term.selected && term.itemCode.trim().isNotEmpty)
        .toList();
    if (selected.length != 1) throw const AcademicCacheMiss();
    return selected.single.itemCode;
  }
  for (final term in result.data) {
    if (term.selected && term.itemCode.trim().isNotEmpty) return term.itemCode;
  }
  for (final term in result.data) {
    if (term.itemCode.trim().isNotEmpty) return term.itemCode;
  }
  return null;
}
