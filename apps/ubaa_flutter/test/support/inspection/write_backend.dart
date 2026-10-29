part of 'backend.dart';

final class _AllWritesIntegrationBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        CgyyCancellationReadbackBackend,
        YgdkSubmissionReadbackBackend,
        EvaluationSubmissionReadbackBackend,
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
          actions: <FeatureAction>[
            BykcSelectAction(
              courseId: 42,
              eligibility: _bykcSelected
                  ? ActionEligibility.denied
                  : ActionEligibility.allowed,
            ),
            BykcDeselectAction(
              courseId: 42,
              eligibility: _bykcSelected
                  ? ActionEligibility.allowed
                  : ActionEligibility.denied,
            ),
            const BykcSignAction(
              courseId: 42,
              kind: BykcSignKind.signIn,
              eligibility: ActionEligibility.allowed,
              requiresCoordinates: false,
            ),
            const BykcSignAction(
              courseId: 42,
              kind: BykcSignKind.signOut,
              eligibility: ActionEligibility.allowed,
              requiresCoordinates: false,
            ),
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
          actions: <FeatureAction>[
            SigninPerformAction(
              scheduleId: 'signin-course',
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
      ],
      FeatureId.libbook => const <FeatureDetail>[
        FeatureDetail(
          title: '集成座位',
          fields: <FeatureField>[
            FeatureField(label: '分区 ID', value: 'display-area-wrong'),
            FeatureField(label: '座位 ID', value: 'display-seat-wrong'),
            FeatureField(label: '日期', value: '1900-01-01'),
            FeatureField(label: '时段', value: 'display-segment-wrong'),
            FeatureField(label: '开始时间', value: '00:00'),
            FeatureField(label: '结束时间', value: '00:01'),
            FeatureField(label: '可预约', value: '否'),
            FeatureField(label: '预约 ID', value: 'booking-1'),
            FeatureField(label: '状态码', value: '1'),
            FeatureField(label: '状态', value: '有效'),
          ],
          actions: <FeatureAction>[
            LibbookReserveAction(
              areaId: 'area-1',
              seatId: 'seat-1',
              day: '2026-09-02',
              segment: '3',
              startTime: '10:00',
              endTime: '12:00',
              eligibility: ActionEligibility.allowed,
            ),
            LibbookCancelAction(
              bookingId: 'booking-1',
              page: 1,
              limit: 20,
              eligibility: ActionEligibility.allowed,
            ),
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
          actions: <FeatureAction>[
            CgyyReserveAction(
              venueSiteId: 3,
              reservationDate: '2026-09-03',
              spaceId: 4,
              timeId: 5,
              venueSpaceGroupId: 9,
              timeOrdinal: 0,
              eligibility: ActionEligibility.allowed,
            ),
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
          actions: <FeatureAction>[
            CgyyCancelAction(
              orderId: 17,
              orderStatus: 1,
              checkStatus: 1,
              targetOrderId: 17,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
      ],
      FeatureId.ygdk => const <FeatureDetail>[
        FeatureDetail(
          title: '集成跑步项目',
          fields: <FeatureField>[FeatureField(label: '展示编号已改名', value: '999')],
          actions: <FeatureAction>[
            YgdkSubmitAction(
              classifyId: 31,
              itemId: 7,
              eligibility: ActionEligibility.allowed,
            ),
          ],
        ),
      ],
      FeatureId.evaluation => const <FeatureDetail>[
        FeatureDetail(
          title: '集成评教课程',
          fields: <FeatureField>[
            FeatureField(label: '状态', value: '待评'),
            FeatureField(
              label: '课程 ID',
              value:
                  'task-evaluation_questionnaire-evaluation_K-EVAL_teacher-evaluation',
            ),
          ],
          actions: <FeatureAction>[
            EvaluationSubmitAction(
              eligibility: ActionEligibility.allowed,
              target: EvaluationSubmitTarget(
                rwid: 'task-evaluation',
                wjid: 'questionnaire-evaluation',
                kcdm: 'K-EVAL',
                bpdm: 'teacher-evaluation',
              ),
            ),
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
  ) async {
    if (feature == FeatureId.cgyy &&
        query.view == FeatureQueryView.cgyyPurposeTypes) {
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成用途',
            presentation: CgyyPurposePresentation(
              key: 2,
              name: '合成用途',
              isStaticFallback: false,
            ),
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    return loadFeature(feature);
  }

  @override
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    if (page != 0 || size != 20) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return _cgyyCancellationReadback(route: route, orderId: 17);
  }

  @override
  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) => _cgyyCancellationReadback(route: route, orderId: orderId);

  Future<FeatureResult> _cgyyCancellationReadback({
    required ConnectionMode route,
    required int orderId,
  }) async {
    if (!_signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    if (orderId <= 0) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    featureLoads.update(
      FeatureId.cgyy,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return FeatureResult.success(
      summary: '集成场馆取消回读',
      resolvedRoute: route,
      details: <FeatureDetail>[
        FeatureDetail(
          title: '已取消场馆订单',
          actions: <FeatureAction>[
            CgyyCancelAction(
              orderId: orderId,
              orderStatus: 2,
              checkStatus: 1,
              targetOrderId: null,
              cancelledTargetOrderId: orderId,
              eligibility: ActionEligibility.denied,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) async {
    featureLoads.update(
      FeatureId.ygdk,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return FeatureResult.success(summary: '集成阳光打卡概览', resolvedRoute: route);
  }

  @override
  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) async {
    if (route != ConnectionMode.direct) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return loadFeature(FeatureId.evaluation);
  }

  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) async {
    if (page != 1 || size != 20) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    featureLoads.update(
      FeatureId.ygdk,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return FeatureResult.success(
      summary: '集成阳光打卡记录',
      resolvedRoute: route,
      details: const <FeatureDetail>[FeatureDetail(title: '集成打卡记录')],
    );
  }

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
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) => _prepare(
    WriteOperation.libbookCancelBooking,
    readbackQuery: FeatureQuery(
      view: FeatureQueryView.libbookBookings,
      page: page,
      size: limit,
    ),
  );

  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) => _prepare(
    WriteOperation.cgyyCancelOrder,
    readbackQuery: FeatureQuery(
      view: FeatureQueryView.cgyyOrderDetail,
      orderId: id,
    ),
  );

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
    List<EvaluationSubmitTarget> targets,
  ) => _prepare(WriteOperation.evaluationSubmitCourses);

  Future<WriteIntent> _prepare(
    WriteOperation operation, {
    FeatureQuery? readbackQuery,
  }) {
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
        readbackQuery: readbackQuery,
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
      ygdkReceipt: operation == WriteOperation.ygdkSubmit
          ? const YgdkSubmitReceipt(recordId: 41)
          : null,
    );
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    _pending.remove(intentId);
  }
}
