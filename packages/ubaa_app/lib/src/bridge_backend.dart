import 'dart:typed_data';

import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'backend.dart';

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以继续显式注入 [DemoBackend]，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        BackendLifecycle {
  BridgeBackend(this.client);

  /// 从平台已经解析好的应用私有目录打开 Core。
  factory BridgeBackend.open(String configDirectory) =>
      BridgeBackend(BridgeClient.open(configDir: configDirectory));

  final BridgeClient client;

  @override
  Future<AuthStatus> authStatus() async {
    try {
      final outcome = await client.authStatus();
      return outcome.readiness == BridgeLoginReadiness.noneReady
          ? AuthStatus.signedOut
          : AuthStatus.signedIn;
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<UserSummary?> userInfo() async {
    try {
      final result = await client.userInfo();
      final profile = result.data;
      final username = profile.username?.trim();
      if (username == null || username.isEmpty) return null;
      return UserSummary(
        username: username,
        displayName: _nonBlank(profile.name),
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {
    try {
      await setDefaultRoutePolicy(policy);
      await client.prepareLogin();
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  Future<BackendRouteSettings> setDefaultRoutePolicy(RoutePolicy policy) async {
    try {
      final settings = await client.setDefaultRoutePolicy(
        policy: _toBridgePolicy(policy),
      );
      return BackendRouteSettings(
        defaultPolicy: _toRoutePolicy(settings.defaultPolicy),
        activeRoutes: List<ConnectionMode>.unmodifiable(
          settings.activeRoutes.map(_toConnectionMode),
        ),
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<BackendRouteSettings> routeSettings() async {
    try {
      final settings = await client.routeSettings();
      return BackendRouteSettings(
        defaultPolicy: _toRoutePolicy(settings.defaultPolicy),
        activeRoutes: List<ConnectionMode>.unmodifiable(
          settings.activeRoutes.map(_toConnectionMode),
        ),
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> login(LoginInput input) async {
    try {
      await client.setDefaultRoutePolicy(
        policy: _toBridgePolicy(input.routePolicy),
      );
      final outcome = await client.login(
        username: input.username.trim(),
        password: input.password,
      );
      if (outcome.readiness == BridgeLoginReadiness.noneReady) {
        final failed = outcome.routes
            .map((route) => route.error)
            .whereType<BridgeSafeError>()
            .firstOrNull;
        throw BackendException(_errorCode(failed?.code));
      }
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await client.logout();
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    try {
      final today = _dateOnly(query.date ?? DateTime.now());
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
                        FeatureField(
                          label: '周次',
                          value: '${item.serialNumber}',
                        ),
                        FeatureField(
                          label: '当前周',
                          value: item.curWeek ? '是' : '否',
                        ),
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
              final term = query.term ?? await _selectedTerm();
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
              final term = query.term ?? await _selectedTerm();
              if (term == null) return const FeatureResult.empty();
              final result = await client.grades(term: term);
              final grades = switch (query.view) {
                FeatureQueryView.gradesScored =>
                  result.data.grades
                      .where((item) => item.score?.trim().isNotEmpty ?? false)
                      .toList(growable: false),
                FeatureQueryView.gradesMissing =>
                  result.data.grades
                      .where(
                        (item) => !(item.score?.trim().isNotEmpty ?? false),
                      )
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
                        item.credit == null
                            ? null
                            : _field('学分', '${item.credit}'),
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
        case FeatureId.bykc:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.bykcCourses(
                // Core 的分页合同为 1-based；UI 的通用查询默认从 0 开始，
                // 因此这里在 bridge 边界显式收敛为首个有效页。
                page: query.page <= 0 ? 1 : query.page,
                size: query.size.clamp(1, 100),
                all: true,
              );
              final details = result.data.content
                  .map(
                    (item) => FeatureDetail(
                      title: item.courseName,
                      subtitle: item.courseTeacher,
                      fields: _compactFields(<FeatureField?>[
                        _field('课程 ID', item.id.toString()),
                        _field('地点', item.coursePosition),
                        _field('状态', item.status.name),
                        item.courseCurrentCount == null
                            ? null
                            : _field('已选人数', '${item.courseCurrentCount}'),
                        item.courseMaxCount == null
                            ? null
                            : _field('容量', '${item.courseMaxCount}'),
                        _field('选课截止', item.courseSelectEndDate),
                        _field('退选截止', item.courseCancelEndDate),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.content.length,
                '门博雅课程',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.bykcDetail:
              final id = _requiredPositiveQueryInt(query.courseId, '课程 ID');
              final result = await client.bykcCourseDetail(id: id);
              final item = result.data;
              return FeatureResult.success(
                summary: '博雅课程详情',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: item.courseName,
                    subtitle: item.courseTeacher,
                    fields: _compactFields(<FeatureField?>[
                      _field('课程 ID', item.id.toString()),
                      _field('地点', item.coursePosition),
                      _field('状态', item.status.name),
                      item.courseCurrentCount == null
                          ? null
                          : _field('已选人数', '${item.courseCurrentCount}'),
                      item.courseMaxCount == null
                          ? null
                          : _field('容量', '${item.courseMaxCount}'),
                      _field('开始', item.courseStartDate),
                      _field('结束', item.courseEndDate),
                      _field('选课开始', item.courseSelectStartDate),
                      _field('选课截止', item.courseSelectEndDate),
                      _field('退选截止', item.courseCancelEndDate),
                      _field(
                        '已选',
                        item.selected == null
                            ? null
                            : item.selected!
                            ? '是'
                            : '否',
                      ),
                    ]),
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.bykcProfile:
              final result = await client.bykcProfile();
              final item = result.data;
              return FeatureResult.success(
                summary: '博雅个人资料',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: item.realName ?? '博雅个人资料',
                    fields: _compactFields(<FeatureField?>[
                      _field('用户 ID', item.id.toString()),
                      _field('姓名', item.realName),
                      _field('学号', item.studentNo),
                      _field('学院', item.collegeName),
                    ]),
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.bykcChosenCourses:
              final result = await client.bykcChosenCourses();
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.courseName,
                      subtitle: item.courseTeacher,
                      fields: _compactFields(<FeatureField?>[
                        _field('课程 ID', item.courseId.toString()),
                        _field('地点', item.coursePosition),
                        _field('开始', item.courseStartDate),
                        _field('结束', item.courseEndDate),
                        _field('签到状态', '${item.checkin}'),
                        _field('成绩', item.score?.toString()),
                        _field(
                          '通过',
                          item.pass == null
                              ? null
                              : item.pass! > 0
                              ? '是'
                              : '否',
                        ),
                        _field('可签到', item.canSign ? '是' : '否'),
                        _field('可签退', item.canSignOut ? '是' : '否'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                details.length,
                '门已选博雅课程',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.bykcStatistics:
              final result = await client.bykcStatistics();
              final details = result.data.categories
                  .map(
                    (item) => FeatureDetail(
                      title: item.categoryName ?? item.subCategoryName ?? '分类',
                      subtitle: item.subCategoryName,
                      fields: _compactFields(<FeatureField?>[
                        _field('要求数量', item.requiredCount?.toString()),
                        _field('通过数量', item.passedCount?.toString()),
                        _field(
                          '达标',
                          item.qualified == null
                              ? null
                              : item.qualified!
                              ? '是'
                              : '否',
                        ),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                details.length,
                result.data.totalValidCount == null
                    ? '博雅修读统计'
                    : '有效课程 ${result.data.totalValidCount}',
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
          final rooms = result.data.floors.fold<int>(
            0,
            (total, floor) => total + floor.rooms.length,
          );
          final details = <FeatureDetail>[
            for (final floor in result.data.floors)
              for (final room in floor.rooms)
                FeatureDetail(
                  title: room.name,
                  subtitle: floor.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('可用节次', room.availableSections),
                  ]),
                ),
          ];
          return _countResult(
            rooms,
            '间可用教室',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureId.spoc:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.spocAssignments();
              final details = result.data.assignments
                  .map(
                    (item) => FeatureDetail(
                      title: item.title,
                      subtitle: item.courseName,
                      fields: _compactFields(<FeatureField?>[
                        _field('作业编号', item.assignmentId),
                        _field('教师', item.teacherName),
                        _field('开始', item.startTime),
                        _field('截止', item.dueTime),
                        _field('状态', item.submissionStatusText),
                        _field('得分', item.score),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.assignments.length,
                '项 SPOC 作业',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.spocDetail:
              final assignmentId = _requiredQueryValue(
                query.assignmentId,
                '作业编号',
              );
              final result = await client.spocAssignment(
                assignmentId: assignmentId,
              );
              final item = result.data;
              return FeatureResult.success(
                summary: 'SPOC 作业详情',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: item.title,
                    subtitle: item.courseName,
                    fields: _compactFields(<FeatureField?>[
                      _field('作业编号', item.assignmentId),
                      _field('课程编号', item.courseId),
                      _field('教师', item.teacherName),
                      _field('开始', item.startTime),
                      _field('截止', item.dueTime),
                      _field('状态', item.submissionStatusText),
                      _field('得分', item.score),
                      _field('提交时间', item.submittedAt),
                      _field('作业内容', item.contentPlainText),
                    ]),
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            default:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
        case FeatureId.judge:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.judgeAssignments(
                includeExpired: query.includeExpired,
              );
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.title,
                      subtitle: item.courseName,
                      fields: _compactFields(<FeatureField?>[
                        _field('课程编号', item.courseId),
                        _field('作业编号', item.assignmentId),
                        _field('开始', item.startTime),
                        _field('截止', item.dueTime),
                        _field('状态', item.submissionStatusText),
                        _field(
                          '进度',
                          '${item.submittedCount}/${item.totalProblems}',
                        ),
                        _field('我的得分', item.myScore),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.length,
                '项希冀作业',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.judgeDetail:
              final courseId = _requiredQueryValue(query.courseId, '课程编号');
              final assignmentId = _requiredQueryValue(
                query.assignmentId,
                '作业编号',
              );
              final result = await client.judgeAssignment(
                courseId: courseId,
                assignmentId: assignmentId,
              );
              final item = result.data;
              final problems = item.problems
                  .map(
                    (problem) => FeatureDetail(
                      title: problem.name,
                      fields: _compactFields(<FeatureField?>[
                        _field('状态', problem.statusText),
                        _field('得分', problem.score),
                        _field('满分', problem.maxScore),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              final details = <FeatureDetail>[
                FeatureDetail(
                  title: item.title,
                  subtitle: item.courseName,
                  fields: _compactFields(<FeatureField?>[
                    _field('课程编号', item.courseId),
                    _field('作业编号', item.assignmentId),
                    _field('开始', item.startTime),
                    _field('截止', item.dueTime),
                    _field('状态', item.submissionStatusText),
                    _field(
                      '进度',
                      '${item.submittedCount}/${item.totalProblems}',
                    ),
                    _field('我的得分', item.myScore),
                    _field('作业内容', item.contentPlainText),
                  ]),
                ),
                ...problems,
              ];
              return FeatureResult.success(
                summary: '希冀作业详情',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            default:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
        case FeatureId.libbook:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.libbookLibraries(day: today);
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.name,
                      fields: _compactFields(<FeatureField?>[
                        _field('馆 ID', item.id),
                        _field('空闲座位', '${item.freeNum}'),
                        _field('总座位', '${item.totalNum}'),
                        _field('楼层数', '${item.storeys.length}'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.length,
                '所图书馆',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookAreas:
              final premisesId = _requiredQueryValue(query.premisesId, '馆区 ID');
              final result = await client.libbookAreas(
                premisesId: premisesId,
                storeyId: query.storeyId,
                day: today,
              );
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.name,
                      subtitle: item.areaName,
                      fields: _compactFields(<FeatureField?>[
                        _field('分区 ID', item.id),
                        _field('楼层 ID', item.storeyId),
                        _field('空闲座位', '${item.freeNum}'),
                        _field('总座位', '${item.totalNum}'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.length,
                '个图书馆分区',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookAreaDetail:
              final areaId = _requiredQueryValue(query.areaId, '分区 ID');
              final result = await client.libbookAreaDetail(areaId: areaId);
              final detail = result.data;
              return FeatureResult.success(
                summary: '可用日期 ${detail.availableDates.length} 天',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: detail.name,
                    fields: _compactFields(<FeatureField?>[
                      _field('分区 ID', detail.id),
                      _field(
                        '可用日期',
                        detail.availableDates.isEmpty
                            ? null
                            : detail.availableDates.join('、'),
                      ),
                      _field(
                        '时段',
                        detail.timeSlots.isEmpty
                            ? null
                            : detail.timeSlots
                                  .map((slot) => slot.label)
                                  .join('、'),
                      ),
                    ]),
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookSeats:
              final areaId = _requiredQueryValue(query.areaId, '分区 ID');
              final startTime = _requiredQueryValue(query.startTime, '开始时间');
              final endTime = _requiredQueryValue(query.endTime, '结束时间');
              final result = await client.libbookSeats(
                areaId: areaId,
                day: today,
                startTime: startTime,
                endTime: endTime,
              );
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.name,
                      subtitle: item.no,
                      fields: _compactFields(<FeatureField?>[
                        _field('座位 ID', item.id),
                        _field('状态', item.statusName),
                        _field('可预约', item.isAvailable ? '是' : '否'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.length,
                '个座位',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookBookings:
              final page = query.page <= 0 ? 1 : query.page;
              final limit = query.size.clamp(1, 100);
              final result = await client.libbookBookings(
                page: page,
                limit: limit,
              );
              final details = result.data.bookings
                  .map(
                    (item) => FeatureDetail(
                      title: item.nameMerge,
                      subtitle: item.areaName,
                      fields: _compactFields(<FeatureField?>[
                        _field('预约 ID', item.id),
                        _field('座位', item.seatNo),
                        _field('日期', item.day),
                        _field('时段', '${item.beginTime}–${item.endTime}'),
                        _field('状态', item.statusName),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.bookings.length,
                '条预约记录',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.ygdkRecords:
            case FeatureQueryView.bykcDetail:
            case FeatureQueryView.bykcProfile:
            case FeatureQueryView.bykcChosenCourses:
            case FeatureQueryView.bykcStatistics:
            case FeatureQueryView.scheduleToday:
            case FeatureQueryView.scheduleTerms:
            case FeatureQueryView.scheduleWeeks:
            case FeatureQueryView.scheduleWeek:
            case FeatureQueryView.examArranged:
            case FeatureQueryView.examNotArranged:
            case FeatureQueryView.gradesScored:
            case FeatureQueryView.gradesMissing:
            case FeatureQueryView.evaluationPending:
            case FeatureQueryView.cgyyPurposeTypes:
            case FeatureQueryView.cgyyDayInfo:
            case FeatureQueryView.cgyyOrders:
            case FeatureQueryView.cgyyOrderDetail:
            case FeatureQueryView.cgyyLockCode:
            case FeatureQueryView.spocDetail:
            case FeatureQueryView.judgeDetail:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
        case FeatureId.signin:
          final result = await client.signinToday();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: '${item.classBeginTime}–${item.classEndTime}',
                  fields: <FeatureField>[
                    FeatureField(label: '签到状态', value: '${item.signStatus}'),
                  ],
                ),
              )
              .toList(growable: false);
          return _countResult(
            result.data.length,
            '门今日签到课程',
            details: details,
            resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
          );
        case FeatureId.cgyy:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.cgyySites();
              final details = result.data
                  .map(
                    (item) => FeatureDetail(
                      title: item.siteName,
                      subtitle: item.venueName,
                      fields: _compactFields(<FeatureField?>[
                        _field('站点 ID', '${item.id}'),
                        _field('校区', item.campusName),
                        item.seatCount == null
                            ? null
                            : _field('座位数', '${item.seatCount}'),
                        item.reservationSpaceCount == null
                            ? null
                            : _field('空间数', '${item.reservationSpaceCount}'),
                        _field('开放开始', item.openStartDate),
                        _field('开放结束', item.openEndDate),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.length,
                '个可预约场馆',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.cgyyPurposeTypes:
              final result = await client.cgyyPurposeTypes();
              final source =
                  result.data.source == BridgeCgyyPurposeSource.upstream
                  ? '上游'
                  : '本地冻结回退';
              final details = result.data.items
                  .map(
                    (item) => FeatureDetail(
                      title: item.name,
                      fields: <FeatureField>[
                        FeatureField(label: '用途编号', value: '${item.key}'),
                        FeatureField(label: '来源', value: source),
                      ],
                    ),
                  )
                  .toList(growable: false);
              return FeatureResult.success(
                summary: '用途类型（来源：$source）',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.cgyyDayInfo:
              final siteId = _requiredPositiveInt(query.siteId, '站点 ID');
              final result = await client.cgyyDayInfo(
                siteId: siteId,
                date: today,
              );
              final details = result.data.spaces
                  .map(
                    (space) => FeatureDetail(
                      title: space.spaceName,
                      fields: _compactFields(<FeatureField?>[
                        _field('空间编号', '${space.spaceId}'),
                        _field('时段数', '${space.slots.length}'),
                        _field(
                          '可预约时段',
                          '${space.slots.where((slot) => slot.isReservable).length}',
                        ),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.spaces.length,
                '个可预约空间',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.cgyyOrders:
              final page = query.page <= 0 ? 1 : query.page;
              final size = query.size.clamp(1, 100);
              final result = await client.cgyyOrders(page: page, size: size);
              final details = result.data.content
                  .map(
                    (item) => FeatureDetail(
                      title: item.theme ?? item.siteName ?? '场馆订单 ${item.id}',
                      subtitle: item.venueSpaceName ?? item.venueName,
                      fields: _compactFields(<FeatureField?>[
                        _field('订单编号', '${item.id}'),
                        _field(
                          '日期',
                          item.reservationDateDetail ?? item.reservationDate,
                        ),
                        _field('开始', item.reservationStartDate),
                        _field('结束', item.reservationEndDate),
                        _field('用途', item.purposeTypeName),
                        item.joinerNum == null
                            ? null
                            : _field('参与人数', '${item.joinerNum}'),
                        _field('订单状态', item.orderStatus?.toString()),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.content.length,
                '条场馆订单',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.cgyyOrderDetail:
              final orderId = _requiredPositiveInt(query.orderId, '订单 ID');
              final result = await client.cgyyOrderDetail(id: orderId);
              final item = result.data;
              return FeatureResult.success(
                summary: '订单详情',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: item.theme ?? item.siteName ?? '场馆订单 ${item.id}',
                    subtitle: item.venueSpaceName ?? item.venueName,
                    fields: _compactFields(<FeatureField?>[
                      _field('订单编号', '${item.id}'),
                      _field('校区', item.campusName),
                      _field(
                        '日期',
                        item.reservationDateDetail ?? item.reservationDate,
                      ),
                      _field('开始', item.reservationStartDate),
                      _field('结束', item.reservationEndDate),
                      _field('用途', item.purposeTypeName),
                      item.joinerNum == null
                          ? null
                          : _field('参与人数', '${item.joinerNum}'),
                      _field('订单状态', item.orderStatus?.toString()),
                      _field('审核状态', item.checkStatus?.toString()),
                    ]),
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.cgyyLockCode:
              final result = await client.cgyyLockCode();
              return FeatureResult.success(
                summary: result.data.available ? '门锁可用' : '门锁不可用',
                details: <FeatureDetail>[
                  FeatureDetail(
                    title: '门锁状态',
                    fields: <FeatureField>[
                      FeatureField(
                        label: '可用',
                        value: result.data.available ? '是' : '否',
                      ),
                    ],
                  ),
                ],
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookAreas:
            case FeatureQueryView.bykcDetail:
            case FeatureQueryView.bykcProfile:
            case FeatureQueryView.bykcChosenCourses:
            case FeatureQueryView.bykcStatistics:
            case FeatureQueryView.scheduleToday:
            case FeatureQueryView.scheduleTerms:
            case FeatureQueryView.scheduleWeeks:
            case FeatureQueryView.scheduleWeek:
            case FeatureQueryView.examArranged:
            case FeatureQueryView.examNotArranged:
            case FeatureQueryView.gradesScored:
            case FeatureQueryView.gradesMissing:
            case FeatureQueryView.evaluationPending:
            case FeatureQueryView.libbookAreaDetail:
            case FeatureQueryView.libbookSeats:
            case FeatureQueryView.libbookBookings:
            case FeatureQueryView.ygdkRecords:
            case FeatureQueryView.spocDetail:
            case FeatureQueryView.judgeDetail:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
        case FeatureId.ygdk:
          switch (query.view) {
            case FeatureQueryView.summary:
              final result = await client.ygdkOverview();
              final details = result.data.items
                  .map(
                    (item) => FeatureDetail(
                      title: item.name,
                      fields: _compactFields(<FeatureField?>[
                        _field('项目编号', '${item.itemId}'),
                        item.kind == null ? null : _field('类型', '${item.kind}'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              final summary = result.data.summary.termTarget == null
                  ? '已打卡 ${result.data.summary.termCount} 次'
                  : '学期进度 ${result.data.summary.termCount}/${result.data.summary.termTarget}';
              return FeatureResult.success(
                summary: summary,
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.ygdkRecords:
              final page = query.page <= 0 ? 1 : query.page;
              final size = query.size.clamp(1, 100);
              final result = await client.ygdkRecords(page: page, size: size);
              final details = result.data.content
                  .map(
                    (item) => FeatureDetail(
                      title: item.itemName ?? '打卡记录 ${item.recordId}',
                      subtitle: item.createdAtLabel ?? item.createdAt,
                      fields: _compactFields(<FeatureField?>[
                        _field('记录编号', '${item.recordId}'),
                        _field('开始时间', item.startTime),
                        _field('结束时间', item.endTime),
                        _field('地点', item.place),
                        _field('公开状态', item.isOpen ? '公开' : '不公开'),
                        _field('图片数量', '${item.images.length}'),
                      ]),
                    ),
                  )
                  .toList(growable: false);
              return _countResult(
                result.data.content.length,
                '条打卡记录',
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            case FeatureQueryView.libbookAreas:
            case FeatureQueryView.bykcDetail:
            case FeatureQueryView.bykcProfile:
            case FeatureQueryView.bykcChosenCourses:
            case FeatureQueryView.bykcStatistics:
            case FeatureQueryView.scheduleToday:
            case FeatureQueryView.scheduleTerms:
            case FeatureQueryView.scheduleWeeks:
            case FeatureQueryView.scheduleWeek:
            case FeatureQueryView.examArranged:
            case FeatureQueryView.examNotArranged:
            case FeatureQueryView.gradesScored:
            case FeatureQueryView.gradesMissing:
            case FeatureQueryView.evaluationPending:
            case FeatureQueryView.libbookAreaDetail:
            case FeatureQueryView.libbookSeats:
            case FeatureQueryView.libbookBookings:
            case FeatureQueryView.cgyyPurposeTypes:
            case FeatureQueryView.cgyyDayInfo:
            case FeatureQueryView.cgyyOrders:
            case FeatureQueryView.cgyyOrderDetail:
            case FeatureQueryView.cgyyLockCode:
            case FeatureQueryView.spocDetail:
            case FeatureQueryView.judgeDetail:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
        case FeatureId.evaluation:
          switch (query.view) {
            case FeatureQueryView.summary:
            case FeatureQueryView.evaluationPending:
              final result = await client.evaluationAll();
              final courses = query.view == FeatureQueryView.evaluationPending
                  ? result.data.courses
                        .where((item) => !item.isEvaluated)
                        .toList(growable: false)
                  : result.data.courses;
              final details = courses
                  .map(
                    (item) => FeatureDetail(
                      title: item.kcmc,
                      subtitle: item.bpmc,
                      fields: <FeatureField>[
                        FeatureField(
                          label: '状态',
                          value: item.isEvaluated ? '已评' : '待评',
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false);
              final progress = result.data.progress;
              final summary = query.view == FeatureQueryView.evaluationPending
                  ? '待评 ${progress.pendingCourses} 门'
                  : '已评 ${progress.evaluatedCourses}/${progress.totalCourses} 门';
              return FeatureResult.success(
                summary: summary,
                details: details,
                resolvedRoute: _toConnectionMode(result.route.resolvedRoute),
              );
            default:
              throw const BackendException(UbaaErrorCode.invalidInput);
          }
      }
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> dispose() => client.dispose();

  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) async =>
      _prepareIntent(
        client.prepareBykcSelectCourse(
          request: BridgeBykcCourseRequest(courseId: courseId),
        ),
      );

  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepareIntent(
        client.prepareBykcDeselectCourse(
          request: BridgeBykcCourseRequest(courseId: courseId),
        ),
      );

  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => _prepareIntent(
    client.prepareBykcSignCourse(
      request: BridgeBykcSignCourseRequest(
        courseId: courseId,
        lat: lat,
        lng: lng,
        signType: signType,
      ),
    ),
  );

  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      _prepareIntent(
        client.prepareSigninPerform(
          request: BridgeSigninPerformRequest(courseId: courseId),
        ),
      );

  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => _prepareIntent(
    client.prepareLibbookReserve(
      request: BridgeLibbookReserveRequest(
        areaId: areaId,
        seatId: seatId,
        day: day,
        segment: segment,
        startTime: startTime,
        endTime: endTime,
      ),
    ),
  );

  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) =>
      _prepareIntent(
        client.prepareLibbookCancelBooking(
          request: BridgeLibbookCancelBookingRequest(id: id),
        ),
      );

  /// 准备阳光打卡。照片字节只在本次调用构造 typed DTO，不写入配置或日志。
  Future<WriteIntent> prepareYgdkSubmit({
    int? itemId,
    String? startTime,
    String? endTime,
    String? place,
    bool? shareToSquare,
    List<int>? photoBytes,
    String photoFileName = 'upload.jpg',
    String photoMimeType = 'image/jpeg',
  }) => _prepareIntent(
    client.prepareYgdkSubmit(
      request: BridgeYgdkSubmitRequest(
        itemId: itemId,
        startTime: startTime,
        endTime: endTime,
        place: place,
        shareToSquare: shareToSquare,
        photo: photoBytes == null
            ? null
            : BridgePhotoUpload(
                bytes: Uint8List.fromList(photoBytes),
                fileName: photoFileName,
                mimeType: photoMimeType,
              ),
      ),
    ),
  );

  /// 准备场馆预约；selection 只包含经过 UI 选择的 ID，不接受 raw JSON。
  Future<WriteIntent> prepareCgyySubmitReservation({
    required int venueSiteId,
    required String reservationDate,
    required List<({int spaceId, int timeId, int? venueSpaceGroupId})>
    selections,
    required String phone,
    required String theme,
    required int purposeType,
    required int joinerNum,
    required String activityContent,
    required String joiners,
    required bool isPhilosophySocialSciences,
    required bool isOffSchoolJoiner,
  }) => _prepareIntent(
    client.prepareCgyySubmitReservation(
      request: BridgeCgyySubmitReservationRequest(
        venueSiteId: venueSiteId,
        reservationDate: reservationDate,
        selections: selections
            .map(
              (selection) => BridgeCgyyReservationSelection(
                spaceId: selection.spaceId,
                timeId: selection.timeId,
                venueSpaceGroupId: selection.venueSpaceGroupId,
              ),
            )
            .toList(growable: false),
        phone: phone,
        theme: theme,
        purposeType: purposeType,
        joinerNum: joinerNum,
        activityContent: activityContent,
        joiners: joiners,
        isPhilosophySocialSciences: isPhilosophySocialSciences,
        isOffSchoolJoiner: isOffSchoolJoiner,
      ),
    ),
  );

  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      _prepareIntent(
        client.prepareCgyyCancelOrder(
          request: BridgeCgyyCancelOrderRequest(id: id),
        ),
      );

  /// 评教只接收 bridge 白名单课程 DTO，并在 commit 后由页面重新读取进度。
  Future<WriteIntent> prepareEvaluationSubmitCourses({
    required List<BridgeEvaluationCourse> courses,
  }) => _prepareIntent(
    client.prepareEvaluationSubmitCourses(
      request: BridgeEvaluationSubmitCoursesRequest(
        courses: List<BridgeEvaluationCourse>.unmodifiable(courses),
      ),
    ),
  );

  Future<WriteIntent> _prepareIntent(Future<BridgeWriteIntent> pending) async {
    try {
      return _mapIntent(await pending);
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  Future<WriteCommitResult> commitWrite(String intentId) async {
    try {
      final result = await client.commitWrite(intentId: intentId);
      return WriteCommitResult(
        operation: _toWriteOperation(result.operation),
        success: result.success,
        message: result.message,
        outcomeUnknown: result.outcomeUnknown,
        resolvedRoute: result.resolvedRoute == null
            ? null
            : _toConnectionMode(result.resolvedRoute!),
      );
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  static WriteIntent _mapIntent(BridgeWriteIntent intent) => WriteIntent(
    intentId: intent.intentId,
    operation: _toWriteOperation(intent.operation),
    targetSummary: intent.targetSummary,
    resolvedRoute: _toConnectionMode(intent.resolvedRoute),
    warnings: List<String>.unmodifiable(intent.warnings),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      int.parse(intent.expiresAt.toString()) * 1000,
    ),
    requestDigest: intent.requestDigest,
  );

  static WriteOperation _toWriteOperation(BridgeWriteOperation operation) =>
      switch (operation) {
        BridgeWriteOperation.bykcSelectCourse =>
          WriteOperation.bykcSelectCourse,
        BridgeWriteOperation.bykcDeselectCourse =>
          WriteOperation.bykcDeselectCourse,
        BridgeWriteOperation.bykcSignCourse => WriteOperation.bykcSignCourse,
        BridgeWriteOperation.signinPerform => WriteOperation.signinPerform,
        BridgeWriteOperation.libbookReserve => WriteOperation.libbookReserve,
        BridgeWriteOperation.libbookCancelBooking =>
          WriteOperation.libbookCancelBooking,
        BridgeWriteOperation.ygdkSubmit => WriteOperation.ygdkSubmit,
        BridgeWriteOperation.cgyySubmitReservation =>
          WriteOperation.cgyySubmitReservation,
        BridgeWriteOperation.cgyyCancelOrder => WriteOperation.cgyyCancelOrder,
        BridgeWriteOperation.evaluationSubmitCourses =>
          WriteOperation.evaluationSubmitCourses,
      };

  static ConnectionMode _toConnectionMode(BridgeConnectionMode mode) =>
      switch (mode) {
        BridgeConnectionMode.direct => ConnectionMode.direct,
        BridgeConnectionMode.webVpn => ConnectionMode.webvpn,
      };

  static RoutePolicy _toRoutePolicy(BridgeRoutePolicy policy) =>
      switch (policy) {
        BridgeRoutePolicy.auto => RoutePolicy.auto,
        BridgeRoutePolicy.direct => RoutePolicy.direct,
        BridgeRoutePolicy.webVpn => RoutePolicy.webvpn,
      };

  Future<String?> _selectedTerm() async {
    final result = await client.scheduleTerms();
    for (final term in result.data) {
      if (term.selected && term.itemCode.trim().isNotEmpty)
        return term.itemCode;
    }
    for (final term in result.data) {
      if (term.itemCode.trim().isNotEmpty) return term.itemCode;
    }
    return null;
  }

  static FeatureResult _countResult(
    int count,
    String unit, {
    List<FeatureDetail> details = const <FeatureDetail>[],
    ConnectionMode? resolvedRoute,
  }) => count == 0
      ? FeatureResult.empty(resolvedRoute: resolvedRoute)
      : FeatureResult.success(
          summary: '$count$unit',
          details: details,
          resolvedRoute: resolvedRoute,
        );

  static FeatureField? _field(String label, String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty
        ? null
        : FeatureField(label: label, value: trimmed);
  }

  static List<FeatureField> _compactFields(Iterable<FeatureField?> fields) =>
      List<FeatureField>.unmodifiable(fields.whereType<FeatureField>());

  static String _requiredQueryValue(String? value, String label) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw BackendException(UbaaErrorCode.invalidInput, detail: '$label 不能为空');
    }
    return trimmed;
  }

  static int _requiredPositiveInt(int? value, String label) {
    if (value == null || value <= 0) {
      throw BackendException(
        UbaaErrorCode.invalidInput,
        detail: '$label 必须为正整数',
      );
    }
    return value;
  }

  static int _requiredPositiveQueryInt(String? value, String label) {
    final trimmed = value?.trim();
    final parsed = trimmed == null ? null : int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) {
      throw BackendException(
        UbaaErrorCode.invalidInput,
        detail: '$label 必须为正整数',
      );
    }
    return parsed;
  }

  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static BridgeRoutePolicy _toBridgePolicy(RoutePolicy policy) =>
      switch (policy) {
        RoutePolicy.auto => BridgeRoutePolicy.auto,
        RoutePolicy.direct => BridgeRoutePolicy.direct,
        RoutePolicy.webvpn => BridgeRoutePolicy.webVpn,
      };

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static BackendException _mapError(BridgeError error) =>
      BackendException(_errorCode(error.code.name), detail: _safeDetail(error));

  static UbaaErrorCode _errorCode(String? code) => switch (code) {
    'invalidInput' || 'invalid_input' => UbaaErrorCode.invalidInput,
    'authenticationRequired' ||
    'authentication_required' => UbaaErrorCode.authenticationRequired,
    'invalidCredentials' ||
    'invalid_credentials' => UbaaErrorCode.invalidCredentials,
    'passwordRiskConfirmationFailed' || 'password_risk_confirmation_failed' =>
      UbaaErrorCode.passwordRiskConfirmationFailed,
    'permissionDenied' || 'permission_denied' => UbaaErrorCode.permissionDenied,
    'networkError' || 'network_error' => UbaaErrorCode.networkError,
    'timeout' => UbaaErrorCode.timeout,
    'upstreamUnavailable' ||
    'upstream_unavailable' => UbaaErrorCode.upstreamUnavailable,
    'upstreamChanged' || 'upstream_changed' => UbaaErrorCode.upstreamChanged,
    'parseError' || 'parse_error' => UbaaErrorCode.parseError,
    'clientDisposed' || 'client_disposed' => UbaaErrorCode.internalError,
    'confirmationRequired' ||
    'confirmation_required' => UbaaErrorCode.confirmationRequired,
    'intentExpired' || 'intent_expired' => UbaaErrorCode.intentExpired,
    'operationConflict' ||
    'operation_conflict' => UbaaErrorCode.operationConflict,
    'outcomeUnknown' || 'outcome_unknown' => UbaaErrorCode.outcomeUnknown,
    _ => UbaaErrorCode.internalError,
  };

  static String? _safeDetail(BridgeError error) {
    final value = error.message.trim();
    if (value.isEmpty || value.length > 160) return null;
    if (value.contains(
      RegExp(r'(?i)(password|cookie|token|authorization|https?://)'),
    )) {
      return null;
    }
    return value;
  }
}

/// 创建生产后端；任何初始化失败都保持明确的不可用状态，不回退到 Demo。
UbaaBackend createProductionBackend() {
  try {
    return BridgeBackend.open(defaultConfigDirectory());
  } on Object {
    return const UnavailableBackend();
  }
}

extension on Iterable<BridgeSafeError?> {
  BridgeSafeError? get firstOrNull {
    for (final value in this) {
      if (value != null) return value;
    }
    return null;
  }
}
