import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../synthetic/assignments/backend.dart';
import '../../synthetic/bykc/backend.dart';
import '../../synthetic/cgyy/backend.dart';
import '../../synthetic/libbook/backend.dart';
import '../../synthetic/ygdk/backend.dart';
import 'preview_academic.dart';
import 'preview_ihome.dart';
part 'preview_services.dart';

/// 人工预览专用内存后端。生命周期与自动化写操作矩阵完全独立。
class PreviewBackend extends CourseworkBackend
    implements
        BykcWriteBackend,
        CgyyWriteBackend,
        CancellationWriteBackend,
        LibbookWriteBackend,
        YgdkWriteBackend,
        CgyyLockDisplayBackend,
        BykcReadbackBackend,
        SigninReadbackBackend,
        CgyyReservationReadbackBackend,
        CgyyCancellationReadbackBackend,
        LibbookReadbackBackend,
        YgdkSubmissionReadbackBackend,
        IhomeBackend,
        ScheduleImportBackend,
        ProfileCacheBackend {
  PreviewBackend({super.state}) {
    signedIn = false;
  }
  final selections = <int, bool>{};
  final signedCourses = <int, int>{};
  final completedSignin = <String>{};
  final evaluated = <String>{};
  final cancelledRooms = <int>{};
  final cancelledSeats = <String>{};
  final roomOrders = <CgyyOrderPresentation>[];
  final seatBookings = <LibbookBookingPresentation>[];
  final _counts = <String, int>{};
  final _pending = <String, (WriteIntent, void Function())>{};
  int _serial = 0;
  int version = 1;
  @override
  late final IhomeService ihome = PreviewIhome(state);
  @override
  Future<UserSummary?> userInfo() async => signedIn
      ? const UserSummary(
          username: 'preview-student',
          displayName: '合成预览同学',
          schoolId: 'SYNTHETIC-001',
          department: '合成学院',
          email: 'preview@example.invalid',
          phone: '合成电话未设置',
        )
      : null;
  @override
  Future<OfflineProfileRead> readCachedProfile(RoutePolicy policy) async =>
      const OfflineProfileRead(null);
  @override
  Future<ProfileRefresh> refreshProfile({
    required LocalAccount account,
  }) async => ProfileRefresh(
    profile: (await userInfo())!,
    route: ConnectionMode.direct,
    evidence: DataEvidence(
      accountId: account.id,
      origin: DataOrigin.online,
      fetchedAt: DateTime.now(),
      complete: true,
      savedForOffline: false,
    ),
  );
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) =>
      loadFeatureQuery(feature, const FeatureQuery());
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (!signedIn) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    // 作业后端自己维护失败次数，避免叠加两次首错。
    if (feature == FeatureId.spoc || feature == FeatureId.judge) {
      if (state == 'loading') {
        await Future<void>.delayed(const Duration(seconds: 8));
      }
      return super.loadFeatureQuery(feature, query);
    }
    final key =
        '${feature.name}/${query.view.name}/${query.term}/${query.date}/${query.campus}';
    final count = _counts.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (state == 'loading') {
      await Future<void>.delayed(const Duration(seconds: 8));
    }
    if (state == 'first-error' && count == 1 || state == 'stale' && count > 1) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (feature == FeatureId.schedule ||
        feature == FeatureId.exam ||
        feature == FeatureId.grades ||
        feature == FeatureId.classroom) {
      return previewAcademic(feature, query, state);
    }
    if (state == 'empty') {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    switch (feature) {
      case FeatureId.bykc:
        return _boya(query);
      case FeatureId.cgyy:
        return _rooms(query);
      case FeatureId.libbook:
        return _library(query);
      case FeatureId.ygdk:
        return sportsData(query, state, version: version);
      case FeatureId.signin:
      case FeatureId.evaluation:
        // 读取全部 authority 后按提交后的内存状态筛选。
        final source = CourseworkBackend(
          state: state == 'many' || state == 'long' ? state : 'normal',
        )..signedIn = true;
        final base = await source.loadFeature(feature);
        final rows = <FeatureDetail>[];
        for (final d in base.details) {
          var p = d.presentation;
          var actions = d.actions;
          if (p is SigninPresentation) {
            final done =
                completedSignin.contains(p.courseId) || p.signStatus == 1;
            if (completedSignin.contains(p.courseId)) {
              p = SigninPresentation(
                courseId: p.courseId,
                classBeginTime: p.classBeginTime,
                classEndTime: p.classEndTime,
                signStatus: 1,
              );
              actions = [];
            }
            if (query.view == FeatureQueryView.signinPending && done ||
                query.view == FeatureQueryView.signinCompleted && !done) {
              continue;
            }
          }
          if (p is EvaluationCoursePresentation) {
            final done = p.isEvaluated || evaluated.contains(p.courseId);
            p = EvaluationCoursePresentation(
              courseId: p.courseId,
              isEvaluated: done,
            );
            if (done) actions = [];
            if (query.view == FeatureQueryView.evaluationPending && done) {
              continue;
            }
          }
          rows.add(
            FeatureDetail(
              title: d.title,
              subtitle: d.subtitle,
              fields: d.fields,
              presentation: p,
              actions: actions,
            ),
          );
        }
        final allDone = base.details.where((d) {
          final p = d.presentation;
          return p is EvaluationCoursePresentation &&
              (p.isEvaluated || evaluated.contains(p.courseId));
        }).length;
        return FeatureResult.success(
          details: rows,
          overview: feature == FeatureId.evaluation
              ? EvaluationProgressOverview(
                  totalCourses: base.details.length,
                  evaluatedCourses: allDone,
                  pendingCourses: base.details.length - allDone,
                )
              : null,
          resolvedRoute: ConnectionMode.direct,
        );
      default:
        return super.loadFeatureQuery(feature, query);
    }
  }

  Future<WriteIntent> _prepare(
    WriteOperation operation,
    void Function() change, {
    FeatureQuery? readbackQuery,
  }) async {
    final id = 'preview-${++_serial}';
    final intent = WriteIntent(
      intentId: id,
      operation: operation,
      targetSummary: '合成本地操作',
      resolvedRoute: ConnectionMode.direct,
      warnings: const ['仅修改本次预览的内存数据'],
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      requestDigest: 'synthetic-$id',
      readbackQuery: readbackQuery,
    );
    _pending[id] = (intent, change);
    return intent;
  }

  @override
  Future<void> discardWriteIntent(String intentId) async {
    _pending.remove(intentId);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    final pending = _pending.remove(intentId);
    if (pending == null || pending.$1.expiresAt.isBefore(DateTime.now())) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    pending.$2();
    return WriteCommitResult(
      operation: pending.$1.operation,
      success: true,
      outcomeUnknown: false,
      message: '合成操作成功',
      resolvedRoute: ConnectionMode.direct,
    );
  }

  @override
  Future<WriteIntent> prepareBykcSelectCourse({required int courseId}) =>
      _prepare(
        WriteOperation.bykcSelectCourse,
        () => selections[courseId] = true,
      );
  @override
  Future<WriteIntent> prepareBykcDeselectCourse({required int courseId}) =>
      _prepare(
        WriteOperation.bykcDeselectCourse,
        () => selections[courseId] = false,
      );
  @override
  Future<WriteIntent> prepareBykcSignCourse({
    required int courseId,
    double? lat,
    double? lng,
    required int signType,
  }) => _prepare(WriteOperation.bykcSignCourse, () {
    signedCourses[courseId] = signType;
  });
  @override
  Future<WriteIntent> prepareSigninPerform({required String courseId}) =>
      _prepare(
        WriteOperation.signinPerform,
        () => completedSignin.add(courseId),
      );
  @override
  Future<WriteIntent> prepareEvaluationSubmitCourses(
    List<EvaluationSubmitTarget> targets,
  ) => _prepare(WriteOperation.evaluationSubmitCourses, () {
    for (final t in targets) {
      evaluated.add('${t.rwid}_${t.wjid}_${t.kcdm}_${t.bpdm}');
    }
  });
  @override
  Future<WriteIntent> prepareYgdkSubmit(YgdkSubmitInput input) =>
      _prepare(WriteOperation.ygdkSubmit, () => version++);
  @override
  Future<WriteIntent> prepareCgyyCancelOrder({required int id}) => _prepare(
    WriteOperation.cgyyCancelOrder,
    () => cancelledRooms.add(id),
    readbackQuery: FeatureQuery(
      view: FeatureQueryView.cgyyOrderDetail,
      orderId: id,
    ),
  );
  @override
  Future<WriteIntent> prepareLibbookCancelBooking({
    required String id,
    required int page,
    required int limit,
  }) => _prepare(
    WriteOperation.libbookCancelBooking,
    () => cancelledSeats.add(id),
    readbackQuery: FeatureQuery(
      view: FeatureQueryView.libbookBookings,
      page: page,
      size: limit,
    ),
  );
  @override
  Future<WriteIntent> prepareCgyySubmitReservation(CgyySubmitInput input) =>
      _prepare(WriteOperation.cgyySubmitReservation, () {
        final a = input.actions.first;
        roomOrders.insert(
          0,
          CgyyOrderPresentation(
            id: 1000 + _serial,
            venueSiteId: a.venueSiteId,
            reservationDate: a.reservationDate,
            venueName: '合成研讨楼',
            venueSpaceName: '合成研讨室 ${a.spaceId}',
            theme: input.theme,
            orderStatus: 1,
            checkStatus: 1,
            statusText: '预约成功',
          ),
        );
      });
  @override
  Future<WriteIntent> prepareLibbookReserve({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) => _prepare(WriteOperation.libbookReserve, () {
    seatBookings.insert(
      0,
      LibbookBookingPresentation(
        id: 'preview-booking-$_serial',
        name: '合成图书馆',
        areaName: areaId,
        seatNumber: seatId,
        day: day,
        beginTime: startTime,
        endTime: endTime,
        status: 1,
        statusName: '有效',
      ),
    );
  });
  @override
  Future<CgyyLockDisplaySession> openLockDisplay() =>
      RoomBackend().openLockDisplay();
  @override
  Future<ScheduleImportTask> beginScheduleImport(String term) async =>
      PreviewImport(term);
  @override
  Future<FeatureResult> readBykcAfterWrite(FeatureQuery query) =>
      loadFeatureQuery(FeatureId.bykc, query);
  @override
  Future<FeatureResult> readCgyyAfterWrite(FeatureQuery query) =>
      loadFeatureQuery(FeatureId.cgyy, query);
  @override
  Future<FeatureResult> readLibbookAfterWrite(FeatureQuery query) =>
      loadFeatureQuery(FeatureId.libbook, query);

  @override
  Future<FeatureResult> readSigninAfterWrite() => loadFeature(FeatureId.signin);
  @override
  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => loadFeatureQuery(
    FeatureId.cgyy,
    FeatureQuery(view: FeatureQueryView.cgyyOrders, page: page, size: size),
  );
  @override
  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) => loadFeatureQuery(
    FeatureId.cgyy,
    FeatureQuery(view: FeatureQueryView.cgyyOrderDetail, orderId: orderId),
  );
  @override
  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) => loadFeature(FeatureId.ygdk);
  @override
  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => loadFeatureQuery(
    FeatureId.ygdk,
    FeatureQuery(view: FeatureQueryView.ygdkRecords, page: page, size: size),
  );
}

/// 同步仅模拟进度，本地预览数据始终由相同生成函数提供。
class PreviewImport implements ScheduleImportTask {
  PreviewImport(this.term);
  final String term;
  int weeks = 0;
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<ScheduleImportProgress> next() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (cancelled) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    weeks = (weeks + 1).clamp(0, 18);
    return ScheduleImportProgress(
      term: term,
      completedWeeks: weeks,
      totalWeeks: 18,
      finished: weeks == 18,
      route: ConnectionMode.direct,
    );
  }
}
