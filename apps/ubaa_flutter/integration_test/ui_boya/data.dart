part of 'backend.dart';

FeatureResult boyaData(FeatureQuery query, String state, {bool empty = false}) {
  final suffix = state == 'long' ? ' 与跨学科创新实践及大学生活专题研讨的较长名称' * 3 : '';
  if (empty && query.view != FeatureQueryView.bykcStatistics) {
    return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
  }
  switch (query.view) {
    case FeatureQueryView.summary:
      final count = state == 'many' ? 42 : 7;
      final page = query.page <= 0 ? 1 : query.page;
      final size = query.size.clamp(1, 100);
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (var i = (page - 1) * size; i < count && i < page * size; i++)
            _course(i, suffix),
        ],
        pagination: FeaturePagination(
          page: page,
          size: size,
          total: count,
          totalPages: (count / size).ceil(),
          hasMore: page * size < count,
        ),
      );
    case FeatureQueryView.bykcDetail:
      final id = int.tryParse(query.courseId ?? '') ?? 0;
      if (id < 101 || id > 142) {
        throw const BackendException(UbaaErrorCode.invalidInput);
      }
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [_course(id - 101, suffix, isDetail: true)],
      );
    case FeatureQueryView.bykcChosenCourses:
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          for (var i = 0; i < (state == 'many' ? 42 : 3); i++)
            FeatureDetail(
              title: '合成已选课 ${i + 1}$suffix',
              presentation: BykcChosenPresentation(
                recordId: 9001 + i,
                courseId: 101 + i,
                courseName: '合成已选课 ${i + 1}$suffix',
                courseTeacher: '合成教师$suffix',
                coursePosition: '合成教学楼$suffix',
                courseStartDate: '2026-09-09 08:00:00',
                courseEndDate: '2026-09-09 10:00:00',
                courseCancelEndDate: '2026-09-08 18:00:00',
                selectDate: '2026-09-01 08:00:00',
                category: '博雅课程',
                subCategory: '美育',
                checkin: i == 0
                    ? 5
                    : i == 1
                    ? 1
                    : null,
                pass: i == 1 ? 1 : null,
                score: i == 0
                    ? 0
                    : i == 1
                    ? 95
                    : null,
                signStartDate: '2026-09-09 07:50:00',
                signEndDate: '2026-09-09 08:10:00',
                signOutStartDate: '2026-09-09 09:50:00',
                signOutEndDate: '2026-09-09 10:10:00',
                signPointCount: i == 2 ? null : 1,
                courseSignType: 3,
              ),
              fields: const [FeatureField(label: '课程 ID', value: '999')],
              actions: [
                BykcDeselectAction(
                  courseId: 101 + i,
                  eligibility: i == 0
                      ? ActionEligibility.allowed
                      : i == 1
                      ? ActionEligibility.denied
                      : ActionEligibility.unknown,
                ),
                BykcSignAction(
                  courseId: 101 + i,
                  kind: BykcSignKind.signIn,
                  eligibility: i == 0
                      ? ActionEligibility.allowed
                      : ActionEligibility.denied,
                  requiresCoordinates: false,
                ),
                BykcSignAction(
                  courseId: 101 + i,
                  kind: BykcSignKind.signOut,
                  eligibility: i == 0
                      ? ActionEligibility.allowed
                      : ActionEligibility.unknown,
                  requiresCoordinates: false,
                ),
              ],
            ),
        ],
      );
    case FeatureQueryView.bykcStatistics:
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '总体净有效次数',
            presentation: BykcStatisticsPresentation(
              totalValidCount: empty ? null : 0,
            ),
          ),
          if (!empty)
            for (var i = 0; i < (state == 'many' ? 42 : 5); i++)
              FeatureDetail(
                title: '分类 ${i + 1}$suffix',
                presentation: BykcCategoryPresentation(
                  categoryName: '博雅课程$suffix',
                  subCategoryName: '分类 ${i + 1}$suffix',
                  requiredCount: i == 4 ? null : 1,
                  passedCount: i == 4 ? null : 9,
                  qualified: i == 4 ? null : i.isOdd,
                ),
              ),
        ],
      );
    case FeatureQueryView.bykcProfile:
      return FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成博雅同学$suffix',
            presentation: BykcProfilePresentation(
              id: 1,
              realName: '合成博雅同学$suffix',
              studentNo: 'synthetic-student',
              collegeName: '合成学院$suffix',
            ),
            fields: [
              const FeatureField(label: '学号', value: 'synthetic-student'),
              FeatureField(label: '学院', value: '合成学院$suffix'),
            ],
          ),
        ],
      );
    default:
      throw const BackendException(UbaaErrorCode.invalidInput);
  }
}

FeatureDetail _course(int index, String suffix, {bool isDetail = false}) {
  final id = 101 + index;
  final status = const [
    BykcCourseStatus.available,
    BykcCourseStatus.full,
    BykcCourseStatus.selected,
    BykcCourseStatus.preview,
    BykcCourseStatus.available,
    BykcCourseStatus.ended,
    BykcCourseStatus.expired,
  ][index % 7];
  return FeatureDetail(
    title: '合成课程 ${index + 1}$suffix',
    presentation: BykcCoursePresentation(
      id: id,
      courseName: '合成课程 ${index + 1}$suffix',
      status: status,
      courseTeacher: '合成教师$suffix',
      coursePosition: '合成教室$suffix',
      courseStartDate: '2026-09-09 08:00:00',
      courseEndDate: '2026-09-09 10:00:00',
      courseSelectStartDate: '2026-09-01 08:00:00',
      courseSelectEndDate: '2026-09-08 18:00:00',
      courseCancelEndDate: '2026-09-08 18:00:00',
      selected: index % 7 == 4 ? null : status == BykcCourseStatus.selected,
      courseCurrentCount: index % 7 == 4
          ? null
          : status == BykcCourseStatus.full
          ? 3
          : 1,
      courseMaxCount: 3,
      isDetail: isDetail,
    ),
    fields: const [FeatureField(label: '课程 ID', value: '999')],
    readNavigation: isDetail
        ? null
        : FeatureReadNavigation(
            feature: FeatureId.bykc,
            query: FeatureQuery(
              view: FeatureQueryView.bykcDetail,
              courseId: '$id',
            ),
          ),
    actions: [
      BykcSelectAction(
        courseId: id,
        eligibility: index % 7 == 0
            ? ActionEligibility.allowed
            : index % 7 == 4
            ? ActionEligibility.unknown
            : ActionEligibility.denied,
      ),
      BykcDeselectAction(
        courseId: id,
        eligibility: status == BykcCourseStatus.selected
            ? ActionEligibility.allowed
            : ActionEligibility.denied,
      ),
    ],
  );
}
