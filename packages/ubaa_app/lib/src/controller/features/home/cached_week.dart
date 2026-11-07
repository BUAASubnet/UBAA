part of 'sources.dart';

Future<FeatureResult?> _cachedHomeWeek(
  ControllerState owner,
  DateTime now,
) async {
  final backend = owner.internalBackend, account = owner.internalLocalAccount;
  if (backend is! OfflineQueryBackend || account == null) return null;
  final scope = owner.internalCaptureReadScope();
  final policy = owner.internalLoginForm.routePolicy;
  bool current() =>
      scope.isCurrent && owner.internalLocalAccount?.id == account.id;
  Future<FeatureResult?> read(FeatureQuery query) async {
    await owner.internalOfflineOpenFuture;
    if (!current()) return null;
    final result = await (backend as OfflineQueryBackend).readCachedQuery(
      FeatureId.schedule,
      query,
      policy,
    );
    if (!current()) return null;
    if (result.error case final error?)
      owner.internalRecordFailure(
        error,
        DiagnosticOperation.read,
        feature: FeatureId.schedule,
      );
    final p = result.projection;
    if (p == null ||
        !p.complete ||
        p.accountId != account.id ||
        p.feature != FeatureId.schedule ||
        !p.readContext.hasSameQuery(query) ||
        (policy == RoutePolicy.direct && p.route != ConnectionMode.direct) ||
        (policy == RoutePolicy.webvpn && p.route != ConnectionMode.webvpn))
      return null;
    return FeatureResult.success(
      details: p.details,
      evidence: p.toSnapshot().evidence,
      resolvedRoute: p.route,
    );
  }

  try {
    final terms = await read(
      const FeatureQuery(view: FeatureQueryView.scheduleTerms),
    );
    final selected =
        terms?.details
            .map((d) => d.presentation)
            .whereType<TermPresentation>()
            .where((t) => t.selected && t.code.isNotEmpty)
            .toList() ??
        [];
    if (selected.length != 1) return null;
    final term = selected.single.code;
    final weeks = await read(
      FeatureQuery(view: FeatureQueryView.scheduleWeeks, term: term),
    );
    if (weeks == null || weeks.resolvedRoute != terms!.resolvedRoute)
      return null;
    final week = homeWeekOn(
      weeks.details.map((d) => d.presentation).whereType<WeekPresentation>(),
      homeCampusTime(now),
      term: term,
    );
    if (week == null) return null;
    return FeatureResult.success(
      details: [FeatureDetail(title: '第${week.number}周', presentation: week)],
      evidence: weeks.evidence,
      resolvedRoute: weeks.resolvedRoute,
    );
  } on Object catch (error, stack) {
    if (current())
      owner.internalRecordFailure(
        error,
        DiagnosticOperation.read,
        feature: FeatureId.schedule,
        stackTrace: stack,
      );
    return null;
  }
}
