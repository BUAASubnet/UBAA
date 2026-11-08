import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../support/bridge/recording_client.dart';

const stats = BridgeGradeStatistics(
  gpa: 3.2,
  averageScore: 75,
  gpaCredits: 2,
  averageCredits: 4,
);

class GraduateClient extends FixtureCharacterizationBridgeClient {
  @override
  Future<BridgeRoutedTerms> scheduleTerms() async =>
      throw StateError('研究生成绩和考试不得访问课表学期');
  @override
  Future<BridgeRoutedGrades> grades({required String term}) async =>
      throw StateError('完整历史成绩只需一次读取');
  @override
  Future<BridgeRoutedGradeOverview> gradesOverview() async =>
      const BridgeRoutedGradeOverview(
        route: fixtureWebVpnRoute,
        data: BridgeGradeOverview(
          graduate: true,
          statistics: stats,
          grades: [
            BridgeGrade(
              courseName: '合成课程',
              termCode: '20251',
              score: '90',
              credit: 2,
            ),
            BridgeGrade(courseName: '待出课程', termCode: '20251', credit: 2),
          ],
          terms: [
            BridgeGradeTermStatistics(
              termCode: '20251',
              termName: '历史学期',
              statistics: stats,
            ),
          ],
        ),
      );
  @override
  Future<BridgeRoutedTerms> examTerms() async => const BridgeRoutedTerms(
    data: [
      BridgeTerm(
        itemCode: '20261',
        itemName: '考试学期',
        selected: true,
        itemIndex: 0,
      ),
    ],
    route: fixtureWebVpnRoute,
  );
  @override
  Future<BridgeRoutedExamArrangement> examArrangement({
    required String term,
  }) async {
    expect(term, '20261');
    return const BridgeRoutedExamArrangement(
      data: BridgeExamArrangement(arranged: [], notArranged: []),
      route: fixtureWebVpnRoute,
    );
  }
}

void main() {
  test('研究生历史成绩保留Core统计和完整集合，筛选不重新计算绩点', () async {
    final backend = BridgeBackend(GraduateClient());
    final result = await backend.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(view: FeatureQueryView.gradesMissing),
    );
    final overview = result.overview! as GradesTermOverview;
    expect(result.details.single.title, '待出课程');
    expect(overview.termCode, '20251');
    expect(overview.grades, hasLength(2));
    expect(overview.statistics!.gpa, 3.2);
    expect(
      GradeStatistics.fromGraduate(
        overview.statistics!,
        overview.grades,
      ).weightedAverage,
      75,
    );
    final all = await backend.loadFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(view: FeatureQueryView.gradesOverview),
    );
    expect(
      (all.overview! as GraduateGradesOverview).terms.single.code,
      '20251',
    );
  });
  test('考试默认学期来自独立考试接口', () async {
    final result = await BridgeBackend(
      GraduateClient(),
    ).loadFeatureQuery(FeatureId.exam, const FeatureQuery());
    expect(result.isEmpty, isTrue);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
  });
}
