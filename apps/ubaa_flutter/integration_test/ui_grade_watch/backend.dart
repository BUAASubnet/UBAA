import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_grades_old/backend.dart';

/// 成绩变化验收的显式内存backend；score由测试动作改变，不访问学校。
class GradeWatchBackend extends GradesOldBackend {
  GradeWatchBackend({super.state, this.multiple = false});
  String score = '80';
  String account = 'grade-watch-fixture';
  ConnectionMode gradeRoute = ConnectionMode.direct;
  bool emptyCurrent = false;
  final bool multiple;
  @override
  Future<UserSummary?> userInfo() async =>
      signedIn ? UserSummary(username: account, displayName: '合成成绩同学') : null;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature == FeatureId.schedule &&
        {
          FeatureQueryView.summary,
          FeatureQueryView.scheduleToday,
        }.contains(query.view)) {
      return const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成今日课程',
            presentation: TodayCoursePresentation(
              time: '09:00–10:40',
              place: '合成教学楼 A101',
            ),
          ),
        ],
      );
    }
    final result = await super.loadFeatureQuery(feature, query);
    if (feature != FeatureId.grades ||
        result.overview is! GradesTermOverview ||
        result.error != null) {
      return result;
    }
    final original = result.overview! as GradesTermOverview;
    final current = original.termCode == '2026-2027-1';
    final grades = current && emptyCurrent
        ? <GradePresentation>[]
        : [
            for (final grade in original.grades)
              GradePresentation(
                courseName: grade.courseName,
                courseCode: grade.courseCode,
                score: current && grade.courseCode == 'GRADE-SAFE'
                    ? score
                    : grade.score,
                gradePoint: grade.gradePoint,
                credit: grade.credit,
                courseType: grade.courseType,
                scoreType: grade.scoreType,
                termCode: grade.termCode,
              ),
            if (current && multiple)
              for (var i = 1; i <= 2; i++)
                GradePresentation(
                  courseCode: 'EXTRA-$i',
                  courseName: '合成更多课程$i',
                  score: score,
                  credit: 1,
                  termCode: original.termCode,
                ),
          ];
    final overview = GradesTermOverview(
      requestTerm: original.requestTerm,
      termCode: original.termCode,
      grades: grades,
    );
    final selected = grades.where(
      (grade) => switch (query.view) {
        FeatureQueryView.gradesScored => grade.score?.trim().isNotEmpty == true,
        FeatureQueryView.gradesMissing =>
          grade.score?.trim().isNotEmpty != true,
        _ => true,
      },
    );
    final details = selected
        .map(
          (grade) =>
              FeatureDetail(title: grade.courseName!, presentation: grade),
        )
        .toList();
    final route = current ? gradeRoute : result.resolvedRoute;
    return details.isEmpty
        ? FeatureResult.empty(overview: overview, resolvedRoute: route)
        : FeatureResult.success(
            overview: overview,
            details: details,
            resolvedRoute: route,
          );
  }
}
