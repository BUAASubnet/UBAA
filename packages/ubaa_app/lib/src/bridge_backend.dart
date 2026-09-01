import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

import 'backend.dart';

/// 基于 FRB opaque client 的生产后端。
///
/// 该适配器只负责把 bridge 的 typed 结果投影到应用层；请求 URL、Cookie、
/// Session 和路线选择仍由 Rust Core 管理。测试可以继续显式注入 [DemoBackend]，
/// 生产宿主不得把 Demo 作为默认实现。
class BridgeBackend implements UbaaBackend, BackendLifecycle {
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
      await client.setDefaultRoutePolicy(policy: _toBridgePolicy(policy));
      await client.prepareLogin();
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
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    try {
      final today = _dateOnly(DateTime.now());
      switch (feature) {
        case FeatureId.schedule:
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
          return _countResult(result.data.length, '今日课程', details: details);
        case FeatureId.exam:
          final term = await _selectedTerm();
          if (term == null) return const FeatureResult.empty();
          final result = await client.examArrangement(term: term);
          final exams = <BridgeExam>[
            ...result.data.arranged,
            ...result.data.notArranged,
          ];
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
          return _countResult(exams.length, '考试安排', details: details);
        case FeatureId.grades:
          final term = await _selectedTerm();
          if (term == null) return const FeatureResult.empty();
          final result = await client.grades(term: term);
          final details = result.data.grades
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
          return _countResult(
            result.data.grades.length,
            '门课程成绩',
            details: details,
          );
        case FeatureId.bykc:
          final result = await client.bykcCourses(page: 0, size: 20, all: true);
          final details = result.data.content
              .map(
                (item) => FeatureDetail(
                  title: item.courseName,
                  subtitle: item.courseTeacher,
                  fields: _compactFields(<FeatureField?>[
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
          );
        case FeatureId.classroom:
          final result = await client.classroomSearch(campus: 1, date: today);
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
          return _countResult(rooms, '间可用教室', details: details);
        case FeatureId.spoc:
          final result = await client.spocAssignments();
          final details = result.data.assignments
              .map(
                (item) => FeatureDetail(
                  title: item.title,
                  subtitle: item.courseName,
                  fields: _compactFields(<FeatureField?>[
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
          );
        case FeatureId.judge:
          final result = await client.judgeAssignments(includeExpired: false);
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.title,
                  subtitle: item.courseName,
                  fields: _compactFields(<FeatureField?>[
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
          return _countResult(result.data.length, '项希冀作业', details: details);
        case FeatureId.libbook:
          final result = await client.libbookLibraries(day: today);
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.name,
                  fields: _compactFields(<FeatureField?>[
                    _field('空闲座位', '${item.freeNum}'),
                    _field('总座位', '${item.totalNum}'),
                    _field('楼层数', '${item.storeys.length}'),
                  ]),
                ),
              )
              .toList(growable: false);
          return _countResult(result.data.length, '所图书馆', details: details);
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
          return _countResult(result.data.length, '门今日签到课程', details: details);
        case FeatureId.cgyy:
          final result = await client.cgyySites();
          final details = result.data
              .map(
                (item) => FeatureDetail(
                  title: item.siteName,
                  subtitle: item.venueName,
                  fields: _compactFields(<FeatureField?>[
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
          return _countResult(result.data.length, '个可预约场馆', details: details);
        case FeatureId.ygdk:
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
          return FeatureResult.success(summary: summary, details: details);
        case FeatureId.evaluation:
          final result = await client.evaluationAll();
          final details = result.data.courses
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
          final summary =
              '已评 ${progress.evaluatedCourses}/${progress.totalCourses} 门';
          return FeatureResult.success(summary: summary, details: details);
      }
    } on BridgeError catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> dispose() => client.dispose();

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
  }) => count == 0
      ? const FeatureResult.empty()
      : FeatureResult.success(summary: '$count$unit', details: details);

  static FeatureField? _field(String label, String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty
        ? null
        : FeatureField(label: label, value: trimmed);
  }

  static List<FeatureField> _compactFields(Iterable<FeatureField?> fields) =>
      List<FeatureField>.unmodifiable(fields.whereType<FeatureField>());

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
