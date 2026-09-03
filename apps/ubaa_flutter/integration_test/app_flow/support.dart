part of '../app_flow_test.dart';

/// 仅供宿主集成测试使用的脱敏 typed backend；不访问网络或真实账号。
final class _IntegrationBackend
    implements UbaaBackend, FeatureQueryBackend, RouteSettingsBackend {
  bool _signedIn = false;
  bool get signedIn => _signedIn;
  FeatureQuery? lastQuery;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000000') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (feature == FeatureId.schedule) {
      return const FeatureResult.success(
        summary: '今日课程',
        details: <FeatureDetail>[
          FeatureDetail(
            title: '集成测试课程',
            fields: <FeatureField>[
              FeatureField(label: '时间', value: '周一 08:00'),
            ],
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    final fields = switch (feature) {
      FeatureId.bykc => const <FeatureField>[
        FeatureField(label: '课程 ID', value: '42'),
      ],
      FeatureId.spoc => const <FeatureField>[
        FeatureField(label: '作业编号', value: 'assignment-1'),
      ],
      FeatureId.judge => const <FeatureField>[
        FeatureField(label: '课程编号', value: 'course-1'),
        FeatureField(label: '作业编号', value: 'assignment-1'),
      ],
      FeatureId.cgyy => const <FeatureField>[
        FeatureField(label: '站点 ID', value: '7'),
      ],
      _ => const <FeatureField>[],
    };
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[
        FeatureDetail(title: feature.title, fields: fields),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    lastQuery = query;
    return const FeatureResult.success(
      summary: '指定周课表',
      details: <FeatureDetail>[
        FeatureDetail(
          title: '查询后的课程',
          fields: <FeatureField>[FeatureField(label: '周次', value: '3')],
        ),
      ],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );
}

/// 仅供宿主写入组合测试使用的脱敏 backend；提交后模拟只读状态变化。
final class _WriteIntegrationBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        SigninWriteBackend {
  _WriteIntegrationBackend({this.throwOnCommit = false});

  final bool throwOnCommit;
  bool _signedIn = false;
  bool _completed = false;
  int signinLoads = 0;
  int commitCalls = 0;
  String? preparedCourse;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000001') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
    _completed = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (feature == FeatureId.signin) {
      signinLoads++;
      return FeatureResult.success(
        summary: _completed ? '今日签到已完成' : '今日有待签到课程',
        details: <FeatureDetail>[
          FeatureDetail(
            title: '宿主集成签到课程',
            fields: <FeatureField>[
              const FeatureField(label: '课程 ID', value: 'course-integration'),
              FeatureField(label: '签到状态', value: _completed ? '已签到' : '未签到'),
            ],
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    return FeatureResult.success(
      summary: feature.title,
      details: <FeatureDetail>[FeatureDetail(title: feature.title)],
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) async {
    preparedCourse = courseId;
    return WriteIntent(
      intentId: 'signin-integration',
      operation: WriteOperation.signinPerform,
      targetSummary: '宿主集成签到课程',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['提交后请刷新今日签到状态确认结果'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'integration-digest',
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commitCalls++;
    if (intentId != 'signin-integration') {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    if (throwOnCommit) {
      throw Exception('测试提交传输失败');
    }
    _completed = true;
    return const WriteCommitResult(
      operation: WriteOperation.signinPerform,
      success: true,
      message: '签到结果已提交，请刷新确认',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}

/// 覆盖全部写入口的脱敏宿主后端；只记录操作枚举，不保存请求正文。
final class _AllWritesIntegrationBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        RouteSettingsBackend,
        BykcWriteBackend,
        SigninWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyWriteBackend,
        EvaluationWriteBackend {
  bool _signedIn = false;
  bool _bykcSelected = false;
  int _nextIntent = 0;
  final Map<String, WriteOperation> _pending = <String, WriteOperation>{};
  final List<WriteOperation> committedOperations = <WriteOperation>[];
  final Map<FeatureId, int> featureLoads = <FeatureId, int>{};
  int commitCalls = 0;

  @override
  Future<AuthStatus> authStatus() async =>
      _signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;

  @override
  Future<UserSummary?> userInfo() async =>
      _signedIn ? const UserSummary(username: '2020000099') : null;

  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}

  @override
  Future<void> login(LoginInput input) async {
    _signedIn = true;
  }

  @override
  Future<void> logout() async {
    _signedIn = false;
    _pending.clear();
  }

  @override
  Future<BackendRouteSettings> routeSettings() async => BackendRouteSettings(
    defaultPolicy: RoutePolicy.auto,
    activeRoutes: _signedIn
        ? const <ConnectionMode>[ConnectionMode.direct]
        : const <ConnectionMode>[],
  );

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    featureLoads.update(feature, (count) => count + 1, ifAbsent: () => 1);
    final details = switch (feature) {
      FeatureId.bykc => <FeatureDetail>[
        FeatureDetail(
          title: '集成课程',
          fields: <FeatureField>[
            const FeatureField(label: '课程 ID', value: '42'),
            FeatureField(label: '已选', value: _bykcSelected ? '是' : '否'),
            FeatureField(label: '状态', value: _bykcSelected ? '已选' : '可选'),
            const FeatureField(label: '可签到', value: '是'),
            const FeatureField(label: '可签退', value: '是'),
          ],
        ),
      ],
      FeatureId.signin => const <FeatureDetail>[
        FeatureDetail(
          title: '课堂集成课程',
          fields: <FeatureField>[
            FeatureField(label: '课程 ID', value: 'signin-course'),
            FeatureField(label: '签到状态', value: '未签到'),
          ],
        ),
      ],
      FeatureId.libbook => const <FeatureDetail>[
        FeatureDetail(
          title: '集成座位',
          fields: <FeatureField>[
            FeatureField(label: '分区 ID', value: 'area-1'),
            FeatureField(label: '座位 ID', value: 'seat-1'),
            FeatureField(label: '日期', value: '2026-09-02'),
            FeatureField(label: '时段', value: '3'),
            FeatureField(label: '开始时间', value: '10:00'),
            FeatureField(label: '结束时间', value: '12:00'),
            FeatureField(label: '可预约', value: '是'),
            FeatureField(label: '预约 ID', value: 'booking-1'),
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
        ),
      ],
      FeatureId.cgyy => const <FeatureDetail>[
        FeatureDetail(
          title: '集成场馆时段',
          fields: <FeatureField>[
            FeatureField(label: '站点 ID', value: '3'),
            FeatureField(label: '日期', value: '2026-09-03'),
            FeatureField(label: '空间 ID', value: '4'),
            FeatureField(label: '空间组 ID', value: '9'),
            FeatureField(label: '时段 ID', value: '5'),
            FeatureField(label: '可预约', value: '是'),
          ],
        ),
        FeatureDetail(
          title: '集成场馆订单',
          fields: <FeatureField>[
            FeatureField(label: '订单编号', value: '17'),
            FeatureField(label: '订单状态', value: '1'),
            FeatureField(label: '审核状态', value: '1'),
            FeatureField(label: '开始', value: '2099-01-01 10:00:00'),
            FeatureField(label: '结束', value: '2099-01-01 11:00:00'),
          ],
        ),
      ],
      FeatureId.ygdk => const <FeatureDetail>[
        FeatureDetail(
          title: '集成跑步项目',
          fields: <FeatureField>[FeatureField(label: '项目编号', value: '7')],
        ),
      ],
      FeatureId.evaluation => const <FeatureDetail>[
        FeatureDetail(
          title: '集成评教课程',
          fields: <FeatureField>[
            FeatureField(label: '状态', value: '待评'),
            FeatureField(label: '课程 ID', value: 'course-evaluation'),
            FeatureField(label: '任务 ID', value: 'task-evaluation'),
            FeatureField(label: '问卷 ID', value: 'questionnaire-evaluation'),
            FeatureField(label: '课程代码', value: 'K-EVAL'),
            FeatureField(label: '模型 ID', value: 'M-EVAL'),
          ],
        ),
      ],
      _ => <FeatureDetail>[FeatureDetail(title: feature.title)],
    };
    return FeatureResult.success(
      summary: feature.title,
      details: details,
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => loadFeature(feature);

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcSelectCourse);

  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepare(WriteOperation.bykcDeselectCourse);

  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => _prepare(WriteOperation.bykcSignCourse);

  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      _prepare(WriteOperation.signinPerform);

  @override
  Future<WriteIntent> prepareLibbookCancelBooking({required String id}) =>
      _prepare(WriteOperation.libbookCancelBooking);

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) =>
      _prepare(WriteOperation.cgyyCancelOrder);

  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => _prepare(WriteOperation.libbookReserve);

  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      _prepare(WriteOperation.ygdkSubmit);

  @override
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      _prepare(WriteOperation.cgyySubmitReservation);

  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationCourseInput> courses,
  ) => _prepare(WriteOperation.evaluationSubmitCourses);

  Future<WriteIntent> _prepare(WriteOperation operation) {
    final intentId = 'all-writes-${_nextIntent++}';
    _pending[intentId] = operation;
    return Future<WriteIntent>.value(
      WriteIntent(
        intentId: intentId,
        operation: operation,
        targetSummary: '脱敏集成测试目标',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>['集成测试不访问真实账号'],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'all-writes-digest',
      ),
    );
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    final operation = _pending.remove(intentId);
    if (operation == null) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    commitCalls++;
    committedOperations.add(operation);
    if (operation == WriteOperation.bykcSelectCourse) _bykcSelected = true;
    if (operation == WriteOperation.bykcDeselectCourse) _bykcSelected = false;
    return WriteCommitResult(
      operation: operation,
      success: true,
      message: '${operation.title}结果已提交，请刷新确认',
      outcomeUnknown: false,
      resolvedRoute: ConnectionMode.direct,
    );
  }
}
