part of 'reader.dart';

FeatureResult _termOptions(List<BridgeTerm> terms, ConnectionMode route) =>
    bridgeCountResult(
      terms.length,
      '个学期',
      resolvedRoute: route,
      details: [
        for (final t in terms)
          FeatureDetail(
            title: t.itemName,
            presentation: TermPresentation(
              code: t.itemCode,
              selected: t.selected,
              index: t.itemIndex,
            ),
          ),
      ],
    );
Future<FeatureResult> _examTerms(_AcademicReader reader) async {
  final result = await reader.examTerms();
  return _termOptions(result.data, result.route);
}

Future<String?> _selectedExamTerm(
  BridgeContext backend,
  _AcademicReader reader,
) async {
  final result = await _examTerms(reader);
  final terms = result.details
      .map((d) => d.presentation)
      .whereType<TermPresentation>();
  if (reader.localRoute != null && terms.where((t) => t.selected).length != 1)
    throw const AcademicCacheMiss();
  return terms.where((t) => t.selected).firstOrNull?.code ??
      terms.firstOrNull?.code;
}

GraduateGradeStatistics _graduateStats(BridgeGradeStatistics s) =>
    GraduateGradeStatistics(
      gpa: s.gpa,
      averageScore: s.averageScore,
      gpaCredits: s.gpaCredits,
      averageCredits: s.averageCredits,
    );
Future<FeatureResult?> _graduateGrades(
  BridgeContext backend,
  FeatureQuery query,
) async {
  if (!{
    FeatureQueryView.summary,
    FeatureQueryView.gradesScored,
    FeatureQueryView.gradesMissing,
    FeatureQueryView.gradesTerms,
    FeatureQueryView.gradesOverview,
  }.contains(query.view))
    throw const BackendException(UbaaErrorCode.invalidInput);
  final result = await backend.client.gradesOverview();
  final value = result.data;
  final route = bridgeToConnectionMode(result.route.resolvedRoute);
  if (!value.graduate)
    return query.view == FeatureQueryView.gradesOverview
        ? FeatureResult.empty(resolvedRoute: route)
        : null;
  final grades = value.grades
      .map(bridgeMapGradePresentation)
      .toList(growable: false);
  final terms = value.terms
      .map(
        (t) => GraduateGradeTerm(
          code: t.termCode,
          name: t.termName,
          statistics: _graduateStats(t.statistics),
        ),
      )
      .toList(growable: false);
  if (query.view == FeatureQueryView.gradesTerms)
    return _termOptions([
      for (var i = 0; i < terms.length; i++)
        BridgeTerm(
          itemCode: terms[i].code,
          itemName: terms[i].name,
          selected: false,
          itemIndex: i,
        ),
    ], route);
  if (query.view == FeatureQueryView.gradesOverview) {
    final statistics = value.statistics;
    if (statistics == null)
      throw const BackendException(UbaaErrorCode.upstreamChanged);
    return FeatureResult.success(
      summary: '${grades.length}门课程成绩',
      resolvedRoute: route,
      overview: GraduateGradesOverview(
        grades: grades,
        terms: terms,
        statistics: _graduateStats(statistics),
      ),
    );
  }
  final term = query.term ?? terms.firstOrNull?.code;
  if (term == null) return FeatureResult.empty(resolvedRoute: route);
  final selected = terms.where((t) => t.code == term).firstOrNull;
  return projectGrades(
    GradesTermOverview(
      requestTerm: term,
      termCode: term,
      grades: grades.where((g) => g.termCode == term).toList(growable: false),
      statistics:
          selected?.statistics ??
          const GraduateGradeStatistics(gpaCredits: 0, averageCredits: 0),
    ),
    query.view,
    route,
  );
}
