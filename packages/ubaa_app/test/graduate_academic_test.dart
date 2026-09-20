import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

const route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.campus,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);

class GraduateClient implements BridgeClient {
  BridgeGradeOverview data = const BridgeGradeOverview(
    graduate: true,
    grades: [],
    terms: [],
    statistics: BridgeGradeStatistics(gpaCredits: 0, averageCredits: 0),
  );
  final calls = <String>[];
  @override
  int contractVersion() => 10;
  @override
  Future<BridgeRoutedGradeOverview> gradeOverview() async {
    calls.add('overview');
    return BridgeRoutedGradeOverview(route: route, data: data);
  }

  @override
  Future<BridgeRoutedTerms> examTerms() async {
    calls.add('examTerms');
    return const BridgeRoutedTerms(
      route: route,
      data: [
        BridgeTerm(
          itemCode: '20261',
          itemName: '考试学期',
          selected: true,
          itemIndex: 0,
        ),
      ],
    );
  }

  @override
  Future<BridgeRoutedExamArrangement> examArrangement({
    required String term,
  }) async {
    calls.add('exam:$term');
    return const BridgeRoutedExamArrangement(
      route: route,
      data: BridgeExamArrangement(arranged: [], notArranged: []),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected request: ${invocation.memberName}');
}

void main() {
  test(
    'graduate historical statistics remain Core values after filtering',
    () async {
      final client = GraduateClient()
        ..data = const BridgeGradeOverview(
          graduate: true,
          grades: [
            BridgeGrade(
              graduate: true,
              termCode: '20251',
              courseName: '历史课程',
              score: 'EX',
            ),
          ],
          statistics: BridgeGradeStatistics(
            gpa: 3.125,
            averageScore: 82,
            gpaCredits: 2,
            averageCredits: 4,
          ),
          terms: [
            BridgeGradeTermStatistics(
              termCode: '20251',
              termName: '历史学期',
              statistics: BridgeGradeStatistics(
                gpa: 2.75,
                averageScore: 78,
                gpaCredits: 1,
                averageCredits: 2,
              ),
            ),
          ],
        );
      final backend = BridgeBackend(client);
      final all = await backend.loadFeature(FeatureId.grades);
      expect(
        (all.overview as AcademicApplicationOverview).statistics!.gpa,
        3.125,
      );
      final term = await backend.loadFeatureQuery(
        FeatureId.grades,
        const FeatureQuery(term: '20251', view: FeatureQueryView.gradesMissing),
      );
      final overview = term.overview as AcademicApplicationOverview;
      expect(term.isEmpty, isTrue);
      expect(overview.statistics!.gpa, 2.75);
      expect(overview.statistics!.weightedAverage, 78);
      expect(overview.terms, {'20251': '历史学期'});
      expect(client.calls, ['overview', 'overview']);
    },
  );
  test('graduate empty grades do not depend on schedule terms', () async {
    final client = GraduateClient();
    final result = await BridgeBackend(client).loadFeature(FeatureId.grades);
    expect(result.error, isNull);
    expect(result.isEmpty, isTrue);
    expect(client.calls, ['overview']);
  });
  test('exam default uses exam application terms', () async {
    final client = GraduateClient();
    final result = await BridgeBackend(client).loadFeature(FeatureId.exam);
    expect(result.error, isNull);
    expect(result.isEmpty, isTrue);
    expect(client.calls, ['examTerms', 'exam:20261']);
  });
}
