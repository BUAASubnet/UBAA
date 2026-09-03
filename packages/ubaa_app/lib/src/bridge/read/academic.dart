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
                .map(
                  (item) => FeatureDetail(
                    title: item.courseName,
                    subtitle: item.courseCode,
                    fields: _compactFields(<FeatureField?>[
                      _field('时间', item.beginTime),
                      _field('地点', item.placeName),
                      _field('周次', item.weeksAndTeachers),
                    ]),
                  ),
                )
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
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: item.courseCode,
                  fields: _compactFields(<FeatureField?>[
                    _field('时间', item.beginTime),
                    _field('地点', item.placeName),
                    _field('周次', item.weeksAndTeachers),
                  ]),
                ),
              )
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
          final exams = switch (query.view) {
            FeatureQueryView.examArranged => result.data.arranged,
            FeatureQueryView.examNotArranged => result.data.notArranged,
            _ => <BridgeExam>[
              ...result.data.arranged,
              ...result.data.notArranged,
            ],
          };
          final details = exams
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: item.examTimeDescription ?? item.examDate,
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
                ),
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
          final grades = switch (query.view) {
            FeatureQueryView.gradesScored =>
              result.data.grades
                  .where((item) => item.score?.trim().isNotEmpty ?? false)
                  .toList(growable: false),
            FeatureQueryView.gradesMissing =>
              result.data.grades
                  .where((item) => !(item.score?.trim().isNotEmpty ?? false))
                  .toList(growable: false),
            _ => result.data.grades,
          };
          final details = grades
              .map(
                (item) => FeatureDetail(
                  title: item.courseName ?? item.courseCode ?? '课程',
                  subtitle: item.courseCode,
                  fields: _compactFields(<FeatureField?>[
                    _field('成绩', item.score),
                    _field('绩点', item.gradePoint),
                    item.credit == null ? null : _field('学分', '${item.credit}'),
                    _field('课程类型', item.courseType),
                  ]),
                ),
              )
              .toList(growable: false);
          final label = switch (query.view) {
            FeatureQueryView.gradesScored => '门已出成绩课程',
            FeatureQueryView.gradesMissing => '门待出成绩课程',
            _ => '门课程成绩',
          };
          return _countResult(
            grades.length,
            label,
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        default:
          throw const BackendException(UbaaErrorCode.invalidInput);
      }
    case FeatureId.classroom:
      final result = await client.classroomSearch(
        campus: query.campus ?? 1,
        date: today,
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
