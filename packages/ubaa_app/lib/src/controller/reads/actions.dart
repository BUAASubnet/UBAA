import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/state.dart' show ControllerState;
import '../agenda/school_refresh.dart' show controllerRefreshSchoolAgenda;

mixin ControllerReadActions on ControllerState {
  Future<void> saveScheduleSemester(String term) =>
      internalUserSchoolAction(() => internalSaveScheduleSemester(term));

  void cancelScheduleImport(String term) => internalCancelScheduleImport(term);

  /// 用户明确请求学期选项，不占用全局课表快照。
  Future<FeatureResult> loadAcademicTerms({
    bool forceRefresh = false,
    FeatureId feature = FeatureId.schedule,
  }) => internalUserSchoolAction(
    () => feature != FeatureId.schedule
        ? internalLoadAcademicTerms(
            forceRefresh: forceRefresh,
            feature: feature,
          )
        : internalLocalFirstOptions(
            const FeatureQuery(view: FeatureQueryView.scheduleTerms),
            forceRefresh,
            () => internalLoadAcademicTerms(forceRefresh: forceRefresh),
          ),
  );

  /// 教学周选项按原学期独立读取，不覆盖当前课表或查询草稿。
  Future<FeatureResult> loadAcademicWeeks(
    String term, {
    bool forceRefresh = false,
  }) => internalUserSchoolAction(
    () => internalLocalFirstOptions(
      FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
      forceRefresh,
      () => internalLoadAcademicWeeks(term, forceRefresh: forceRefresh),
    ),
  );

  /// 活动类型独立读取，不覆盖研讨室日时段和已选目标。
  Future<FeatureResult> loadCgyyPurposes({bool forceRefresh = false}) =>
      internalUserSchoolAction(
        () => internalLocalFirstOptions(
          const FeatureQuery(view: FeatureQueryView.cgyyPurposeTypes),
          forceRefresh,
          () => internalLoadCgyyPurposes(forceRefresh: forceRefresh),
          feature: FeatureId.cgyy,
        ),
      );

  /// 成绩统计的独立读取，不改变当前页面的查询或详情帧。
  Future<FeatureResult> loadGradeTerm(
    String term, {
    bool forceRefresh = false,
  }) => internalUserSchoolAction(
    () => internalLoadGradeTerm(term, forceRefresh: forceRefresh),
  );

  Future<GradesAggregate> loadAllGrades({
    bool forceRefresh = false,
    void Function(GradesAggregate)? onProgress,
  }) => internalUserSchoolAction(
    () => internalLoadGradesWithCache(
      forceRefresh: forceRefresh,
      onProgress: onProgress,
    ),
  );

  /// 首页变化检查只读取唯一标为当前的学期；缺失时不猜第一项。
  Future<GradeTermRead?> loadCurrentGrades({
    bool forceRefresh = false,
    bool background = false,
  }) => background
      ? internalAutomaticSchoolAction(
          () => internalLoadCurrentGrades(
            forceRefresh: forceRefresh,
            priority: ReadPriority.background,
          ),
        )
      : internalUserSchoolAction(
          () => internalLoadCurrentGrades(
            forceRefresh: forceRefresh,
            priority: ReadPriority.interactive,
          ),
        );

  Future<FeatureResult> loadHomeDaySchedule(
    String date, {
    bool forceRefresh = false,
  }) => internalUserSchoolAction(
    () => internalLoadHomeDaySchedule(date, forceRefresh: forceRefresh),
  );

  Future<FeatureResult> loadHomeSupplement(
    HomeSupplement source, {
    bool forceRefresh = false,
  }) => internalUserSchoolAction(
    () => internalLoadHomeSupplement(source, forceRefresh: forceRefresh),
  );

  Future<void> refreshHome({Iterable<FeatureId>? only}) =>
      internalUserSchoolAction(() => internalRefreshHome(only: only));

  /// 刷新日程学校来源，不依赖首页是否仍挂在界面中。
  Future<void> refreshSchoolAgenda() =>
      internalUserSchoolAction(() => controllerRefreshSchoolAgenda(this));

  Future<void> retryFeature(FeatureId feature) {
    final query = internalSnapshots[feature]?.readContext?.query;
    return query == null
        ? refreshHome(only: <FeatureId>[feature])
        : refreshFeatureQuery(feature, query);
  }

  /// 对支持 [FeatureQueryBackend] 的生产实现执行单领域筛选读取。
  Future<void> refreshFeatureQuery(FeatureId feature, FeatureQuery query) =>
      internalUserSchoolAction(
        () => internalRefreshFeatureQuery(feature, query),
      );
}
