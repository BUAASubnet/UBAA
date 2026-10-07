import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'fakes.dart' show FixtureQueryBackend;

FeatureResult fixtureGradeTerm(String term, {bool empty = false}) {
  final overview = GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: empty
        ? const []
        : const [
            GradePresentation(courseName: '合成课程', score: '80', credit: 2),
            GradePresentation(courseName: '合成待出成绩', credit: 1),
          ],
  );
  return empty
      ? FeatureResult.empty(
          overview: overview,
          resolvedRoute: ConnectionMode.webvpn,
        )
      : FeatureResult.success(
          overview: overview,
          resolvedRoute: ConnectionMode.direct,
        );
}

class FixtureGradesBackend extends FixtureQueryBackend {
  FixtureGradesBackend()
    : super(onQuery: (_, _) => const FeatureResult.empty());
  final gradeCalls = <String>[];
  FeatureResult? termResult;
  FeatureResult? defaultGrades;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      feature == FeatureId.grades && defaultGrades != null
      ? defaultGrades!
      : await super.loadFeature(feature);
  Future<FeatureResult> Function(String) read = (term) async =>
      fixtureGradeTerm(term);
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'fixture-student');
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      if (termResult != null) return termResult!;
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成甲学期',
            presentation: TermPresentation(code: 'a', selected: true, index: 1),
          ),
          FeatureDetail(
            title: '合成乙学期',
            presentation: TermPresentation(
              code: 'b',
              selected: false,
              index: 2,
            ),
          ),
          FeatureDetail(
            title: '重复学期',
            presentation: TermPresentation(
              code: 'b',
              selected: false,
              index: 3,
            ),
          ),
        ],
      );
    }
    expect(feature, FeatureId.grades);
    gradeCalls.add(query.term!);
    return read(query.term!);
  }
}
