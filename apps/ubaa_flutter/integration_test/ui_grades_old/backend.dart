import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_academic_old/backend.dart';

/// 成绩旧版验收仅使用合成课程与学期，不访问学校服务。
class GradesOldBackend extends AcademicOldBackend {
  GradesOldBackend({super.state});
  final gradeReads = <FeatureQuery>[];
  bool failGrades = false, failOtherTerm = false;
  Completer<void>? gradesPending, aggregatePending;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      return const FeatureResult.success(
        resolvedRoute: ConnectionMode.direct,
        details: [
          FeatureDetail(
            title: '合成当前学期',
            presentation: TermPresentation(
              code: '2026-2027-1',
              selected: true,
              index: 1,
            ),
          ),
          FeatureDetail(
            title: '合成上一学期',
            presentation: TermPresentation(
              code: '2025-2026-2',
              selected: false,
              index: 2,
            ),
          ),
        ],
      );
    }
    if (feature != FeatureId.grades) {
      return super.loadFeatureQuery(feature, query);
    }
    gradeReads.add(query);
    if (gradesPending case final gate?) await gate.future;
    final term = query.term ?? '2026-2027-1';
    final other = term == '2025-2026-2';
    if (other && aggregatePending != null) await aggregatePending!.future;
    if (failGrades ||
        (other && (state == 'partial' || failOtherTerm)) ||
        (state == 'first-error' && gradeReads.length == 1)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    final grades = state == 'empty'
        ? <GradePresentation>[]
        : [
            GradePresentation(
              courseName: title(other ? '合成往期课程' : '合成数学课程'),
              courseCode: 'GRADE-SAFE',
              score: state == 'long'
                  ? '上游提供的完整较长非数值成绩待核实'
                  : other
                  ? '100'
                  : '80',
              gradePoint: 'RAW-KEEP',
              credit: 2,
              courseType: title('必修'),
              scoreType: title('正常'),
              termCode: term,
            ),
            if (!other)
              GradePresentation(
                courseName: title('合成待出课程'),
                courseCode: 'MISSING-SAFE',
                credit: 1,
                termCode: term,
              ),
            if (state == 'many')
              for (var i = 1; i <= 42; i++)
                GradePresentation(
                  courseName: '合成更多课程 $i',
                  courseCode: 'MORE-$i',
                  score: '优秀',
                  credit: 1,
                  termCode: term,
                ),
          ];
    final overview = GradesTermOverview(
      requestTerm: term,
      termCode: term,
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
          (grade) => FeatureDetail(
            title: grade.courseName!,
            presentation: grade,
            fields: const [FeatureField(label: '合成补充字段', value: '仍可查看')],
          ),
        )
        .toList();
    final route = other ? ConnectionMode.webvpn : ConnectionMode.direct;
    return details.isEmpty
        ? FeatureResult.empty(overview: overview, resolvedRoute: route)
        : FeatureResult.success(
            overview: overview,
            details: details,
            resolvedRoute: route,
          );
  }
}
