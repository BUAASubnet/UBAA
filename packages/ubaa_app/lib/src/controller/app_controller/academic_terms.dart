part of '../app_controller.dart';

extension _AppControllerAcademicTerms on AppController {
  Future<FeatureResult> _loadAcademicTerms({required bool forceRefresh}) {
    if (_disposed || _writeTransitions != 0) {
      return Future.value(_academicTermsConflict());
    }
    if (_phase != AppPhase.home) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
        ),
      );
    }
    final backend = _backend;
    if (backend is! FeatureQueryBackend) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
        ),
      );
    }
    final lifecycle = _lifecycleEpoch;
    final epoch = _readCacheEpoch;
    if (_academicTermsLifecycle != lifecycle ||
        _academicTermsEpoch != epoch ||
        !identical(_academicTermsBackend, backend)) {
      _academicTermsResult = null;
      _academicTermsPending = null;
      _academicTermsLifecycle = lifecycle;
      _academicTermsEpoch = epoch;
      _academicTermsBackend = backend;
    }
    // force 绕过已完成缓存；同代正在进行的请求已是一次新读取，仍合并。
    if (_academicTermsPending case final pending?) return pending;
    if (!forceRefresh) {
      if (_academicTermsResult case final cached?) return Future.value(cached);
    }
    _academicTermsResult = null;
    final serial = ++_academicTermsSerial;
    final request = _fetchAcademicTerms(
      backend: backend,
      queryBackend: backend as FeatureQueryBackend,
      lifecycle: lifecycle,
      epoch: epoch,
      serial: serial,
    );
    _academicTermsPending = request;
    return request;
  }

  Future<FeatureResult> _fetchAcademicTerms({
    required UbaaBackend backend,
    required FeatureQueryBackend queryBackend,
    required int lifecycle,
    required int epoch,
    required int serial,
  }) async {
    bool current() =>
        !_disposed &&
        _writeTransitions == 0 &&
        _phase == AppPhase.home &&
        identical(_backend, backend) &&
        _lifecycleEpoch == lifecycle &&
        _readCacheEpoch == epoch &&
        _academicTermsSerial == serial;
    try {
      // 即使 backend 在返回 Future 前同步抛错，也先建立在途句柄再清理。
      final result = await Future<FeatureResult>.sync(
        () => queryBackend.loadFeatureQuery(
          FeatureId.schedule,
          const FeatureQuery(view: FeatureQueryView.scheduleTerms),
        ),
      );
      if (!current()) return _academicTermsConflict();
      if (result.error case final error?) {
        return FeatureResult.failure(
          _recordFailure(
            error,
            DiagnosticOperation.read,
            feature: FeatureId.schedule,
          ),
        );
      }
      final stable = result.isEmpty
          ? FeatureResult.empty(
              resolvedRoute: result.resolvedRoute,
              pagination: result.pagination,
            )
          : FeatureResult.success(
              summary: result.summary,
              resolvedRoute: result.resolvedRoute,
              pagination: result.pagination,
              details: List<FeatureDetail>.unmodifiable(
                result.details.map((detail) {
                  final navigation = detail.readNavigation;
                  return FeatureDetail(
                    title: detail.title,
                    subtitle: detail.subtitle,
                    fields: List<FeatureField>.unmodifiable(detail.fields),
                    actions: List<FeatureAction>.unmodifiable(detail.actions),
                    presentation: detail.presentation,
                    readNavigation: navigation == null
                        ? null
                        : FeatureReadNavigation(
                            feature: navigation.feature,
                            query: navigation.query.copyWith(
                              judgeKeys:
                                  List<JudgeAssignmentQueryKey>.unmodifiable(
                                    navigation.query.judgeKeys,
                                  ),
                            ),
                          ),
                  );
                }),
              ),
            );
      _academicTermsResult = stable;
      return stable;
    } on Object catch (error, stackTrace) {
      if (!current()) return _academicTermsConflict();
      return FeatureResult.failure(
        _recordFailure(
          error,
          DiagnosticOperation.read,
          stackTrace: stackTrace,
          feature: FeatureId.schedule,
        ),
      );
    } finally {
      if (_academicTermsSerial == serial) _academicTermsPending = null;
    }
  }

  FeatureResult _academicTermsConflict() => FeatureResult.failure(
    UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
  );
}
