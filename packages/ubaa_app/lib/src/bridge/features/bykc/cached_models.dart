part of 'projection.dart';

bool bridgeIsBykcCacheQuery(FeatureId feature, FeatureQuery query) =>
    feature == FeatureId.bykc &&
    {
      FeatureQueryView.summary,
      FeatureQueryView.bykcDetail,
      FeatureQueryView.bykcProfile,
      FeatureQueryView.bykcChosenCourses,
      FeatureQueryView.bykcStatistics,
    }.contains(query.view);

BridgeBykcCourse bridgeCachedBykcCourse(BridgeCachedBykcCourse v) =>
    BridgeBykcCourse(
      id: v.id,
      courseName: v.courseName,
      coursePosition: v.coursePosition,
      courseTeacher: v.courseTeacher,
      courseStartDate: v.courseStartDate,
      courseEndDate: v.courseEndDate,
      courseSelectStartDate: v.courseSelectStartDate,
      courseSelectEndDate: v.courseSelectEndDate,
      courseCancelEndDate: v.courseCancelEndDate,
      courseMaxCount: v.courseMaxCount,
      courseCurrentCount: v.courseCurrentCount,
      status: v.status,
      selected: v.selected,
      selectEligibility: BridgeActionEligibility.unknown,
      deselectEligibility: BridgeActionEligibility.unknown,
    );

BridgeBykcChosenCourse bridgeCachedBykcChosen(BridgeCachedBykcChosenCourse v) =>
    BridgeBykcChosenCourse(
      id: v.id,
      courseId: v.courseId,
      courseName: v.courseName,
      coursePosition: v.coursePosition,
      courseTeacher: v.courseTeacher,
      courseStartDate: v.courseStartDate,
      courseEndDate: v.courseEndDate,
      selectDate: v.selectDate,
      courseCancelEndDate: v.courseCancelEndDate,
      category: v.category,
      subCategory: v.subCategory,
      checkin: v.checkin,
      score: v.score,
      pass: v.pass,
      signEligibility: BridgeActionEligibility.unknown,
      signOutEligibility: BridgeActionEligibility.unknown,
      deselectEligibility: BridgeActionEligibility.unknown,
      signConfig: v.signWindow == null
          ? null
          : BridgeBykcSignConfig(
              signStartDate: v.signWindow!.signStartDate,
              signEndDate: v.signWindow!.signEndDate,
              signOutStartDate: v.signWindow!.signOutStartDate,
              signOutEndDate: v.signWindow!.signOutEndDate,
              signPoints: const [],
            ),
      courseSignType: v.courseSignType,
    );

BridgeBykcCoursePage bridgeCachedBykcPage(BridgeCachedBykcCoursePage v) =>
    BridgeBykcCoursePage(
      content: v.content.map(bridgeCachedBykcCourse).toList(),
      number: v.number,
      size: v.size,
      totalElements: v.totalElements,
      totalPages: v.totalPages,
    );

BridgeBykcCourseCatalogItem bridgeCachedBykcCatalog(
  BridgeCachedBykcCourse value,
) => BridgeBykcCourseCatalogItem(
  course: bridgeCachedBykcCourse(value),
  category: value.category,
  subCategory: value.subCategory,
  audienceCampuses: value.audienceCampuses ?? const [],
  hasSignPoints: value.hasSignPoints ?? false,
);
