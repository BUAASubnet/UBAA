part of '../bridge_backend.dart';

Future<FeatureResult> _loadAcademicFeature(
  BridgeBackend backend,
  FeatureId feature,
  FeatureQuery query,
  String today,
) async {
  final client = backend.client;
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
                .map(_mapScheduleCourseDetail)
                .toList(growable: false);
            return _countResult(
              details.length,
              '第 ${query.week} 周课表',
              details: details,
              resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
            );
          }
          final result = await client.scheduleToday();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.bizName,
                  subtitle: item.shortName,
                  presentation: TodayCoursePresentation(
                    time: item.time,
                    place: item.place,
                  ),
                  fields: _compactFields(<FeatureField?>[
                    _field('时间', item.time),
                    _field('地点', item.place),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '今日课程',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
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
          return _countResult(
            details.length,
            '个学期',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.scheduleWeeks:
          final term = _requiredQueryValue(query.term, '学期编码');
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
          return _countResult(
            details.length,
            '个周次',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureQueryView.scheduleWeek:
          final term = _requiredQueryValue(query.term, '学期编码');
          final week = query.week;
          if (week == null || week <= 0) {
            throw const BackendException(UbaaErrorCode.invalidInput);
          }
          final result = await client.scheduleWeek(term: term, week: week);
          final details = result.data.arrangedList
              .map(_mapScheduleCourseDetail)
              .toList(growable: false);
          return _countResult(
            details.length,
            '第 $week 周课表',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.exam:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.examArranged:
        case FeatureQueryView.examNotArranged:
          final term = query.term ?? await _selectedTerm(backend);
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
                (entry) => _mapExamDetail(entry.item, arranged: entry.arranged),
              )
              .toList(growable: false);
          final label = switch (query.view) {
            FeatureQueryView.examArranged => '已安排考试',
            FeatureQueryView.examNotArranged => '未安排考试',
            _ => '考试安排',
          };
          return _countResult(
            exams.length,
            label,
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.grades:
      switch (query.view) {
        case FeatureQueryView.summary:
        case FeatureQueryView.gradesScored:
        case FeatureQueryView.gradesMissing:
          final term = query.term ?? await _selectedTerm(backend);
          if (term == null) return const FeatureResult.empty();
          final result = await client.grades(term: term);
          final allGrades = result.data.grades
              .map(_mapGradePresentation)
              .toList(growable: false);
          return projectGrades(
            GradesTermOverview(
              requestTerm: term,
              termCode: result.data.termCode,
              grades: List.unmodifiable(allGrades),
            ),
            query.view,
            _toConnectionMode(result.route.resolvedRoute),
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
            if (_matchesClassroomFloor(room, floor.name, floorFilter) &&
                _matchesClassroomSection(room.availableSections, sectionFilter))
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
                fields: _compactFields(<FeatureField?>[
                  _field('可用节次', room.availableSections),
                ]),
              ),
      ];
      return _countResult(
        details.length,
        '间可用教室',
        details: details,
        resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
      );
    default:
      throw StateError('unexpected feature: $feature');
  }
}

Future<String?> _selectedTerm(BridgeBackend backend) async {
  final result = await backend.client.scheduleTerms();
  for (final term in result.data) {
    if (term.selected && term.itemCode.trim().isNotEmpty) return term.itemCode;
  }
  for (final term in result.data) {
    if (term.itemCode.trim().isNotEmpty) return term.itemCode;
  }
  return null;
}

bool _matchesClassroomFloor(
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
bool _matchesClassroomSection(String available, String? filter) {
  if (filter == null || filter.isEmpty) return true;
  return available
      .split(',')
      .map((item) => item.trim())
      .any((item) => item == filter);
}

/// 两个周课表入口共用纯展示投影，不读取或推断新的查询字段。
FeatureDetail _mapScheduleCourseDetail(BridgeCourseClass item) => FeatureDetail(
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
  ),
  fields: _compactFields(<FeatureField?>[
    _field('时间', item.beginTime),
    _field('地点', item.placeName),
    _field('周次', item.weeksAndTeachers),
  ]),
);

FeatureDetail _mapExamDetail(BridgeExam item, {required bool arranged}) =>
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
      fields: _compactFields(<FeatureField?>[
        _field(
          '时间',
          item.startTime == null || item.endTime == null
              ? null
              : '${item.startTime}–${item.endTime}',
        ),
        _field('地点', item.examPlace),
        _field('座位', item.examSeatNo),
        _field('类型', item.examType),
      ]),
    );

GradePresentation _mapGradePresentation(BridgeGrade item) => GradePresentation(
  courseName: item.courseName,
  courseCode: item.courseCode,
  score: item.score,
  gradePoint: item.gradePoint,
  credit: item.credit,
  courseType: item.courseType,
  scoreType: item.scoreType,
  termCode: item.termCode,
);
