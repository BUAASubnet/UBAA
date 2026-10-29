import 'dart:async';

import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

class GradesBackend
    implements
        UbaaBackend,
        FeatureQueryBackend,
        ProgressiveReadBackend,
        RequiredSessionBackend,
        OfflineCacheBackend,
        OfflineQueryBackend {
  LocalAccount? account;
  bool online = false;
  String? missing, broken, mismatch;
  bool partialIndex = false;
  Completer<void>? diskGate;
  int authCalls = 0;
  final fetched = DateTime.utc(2026, 9, 1);
  @override
  Future<void> openOfflineAccount(LocalAccount value, List<int> key) async {
    account = value;
  }

  @override
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) async =>
      OfflineHomeRead([]);
  List<FeatureDetail> get terms => [
    for (final term in ['a', 'b'])
      FeatureDetail(
        title: '合成学期$term',
        presentation: TermPresentation(
          code: term,
          selected: term == 'a',
          index: 0,
        ),
      ),
  ];
  GradesTermOverview grade(String term, String score) => GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: [
      GradePresentation(courseName: '合成课程$term', score: score, credit: 2),
    ],
  );
  @override
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) async {
    await diskGate?.future;
    if (feature == FeatureId.grades && query.term == broken)
      throw const BackendException(UbaaErrorCode.internalError);
    if (feature == FeatureId.grades && query.term == missing)
      return const OfflineQueryRead(null);
    return OfflineQueryRead(
      CachedFeatureProjection(
        feature: feature,
        query: query,
        accountId: feature == FeatureId.grades && mismatch == '账号'
            ? 'other'
            : account!.id,
        route: feature == FeatureId.grades && mismatch == '路线'
            ? ConnectionMode.webvpn
            : ConnectionMode.direct,
        fetchedAt: fetched,
        complete: feature == FeatureId.schedule ? !partialIndex : true,
        details: feature == FeatureId.schedule ? terms : [],
        overview: feature == FeatureId.grades
            ? grade(mismatch == '学期' ? 'other' : query.term!, '80')
            : null,
      ),
    );
  }

  @override
  Future<RecoveredRouteSession> recoverRequiredSession(
    FeatureId feature,
  ) async {
    authCalls++;
    if (!online) throw const BackendException(UbaaErrorCode.networkError);
    return const RecoveredRouteSession(
      route: ConnectionMode.direct,
      profile: UserSummary(username: 'fixture-user'),
    );
  }

  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async => FeatureResult.success(
    details: feature == FeatureId.schedule ? terms : [],
    overview: feature == FeatureId.grades ? grade(query.term!, '95') : null,
    resolvedRoute: ConnectionMode.direct,
    evidence: feature == FeatureId.schedule
        ? DataEvidence(
            accountId: account!.id,
            origin: DataOrigin.online,
            fetchedAt: fetched,
            complete: !partialIndex,
            savedForOffline: true,
          )
        : null,
  );
  @override
  Future<void> logout() async {}
  @override
  Future<void> deactivateOfflineAccount() async {}
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
