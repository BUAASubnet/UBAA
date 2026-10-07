import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerAcademicTerms on ControllerState {
  @internal
  Future<FeatureResult> internalLoadAcademicTerms({
    required bool forceRefresh,
    ReadPriority priority = ReadPriority.interactive,
  }) {
    if (internalDisposed ||
        internalReadTransitionBlocked ||
        internalLegacyReadSessionBlocked) {
      return Future.value(internalAcademicTermsConflict());
    }
    if (internalPhase != AppPhase.home) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.authenticationRequired),
        ),
      );
    }
    final backend = internalBackend;
    if (backend is! FeatureQueryBackend) {
      return Future.value(
        FeatureResult.failure(
          UbaaErrorMapper.fromCode(UbaaErrorCode.unsupported),
        ),
      );
    }
    final lifecycle = internalLifecycleEpoch;
    final epoch = internalReadCacheEpoch;
    if (internalAcademicTermsLifecycle != lifecycle ||
        internalAcademicTermsEpoch != epoch ||
        !identical(internalAcademicTermsBackend, backend)) {
      internalAcademicTermsResult = null;
      internalAcademicTermsPending = null;
      internalAcademicTermsLifecycle = lifecycle;
      internalAcademicTermsEpoch = epoch;
      internalAcademicTermsBackend = backend;
    }
    // force 绕过已完成缓存；同代正在进行的请求已是一次新读取，仍合并。
    if (internalAcademicTermsPending case final pending?) {
      if (internalAcademicTermsDemand?.promote(priority) == true)
        internalReadScheduler.pump();
      return pending;
    }
    if (!forceRefresh) {
      if (internalAcademicTermsResult case final cached?)
        return Future.value(cached);
    }
    internalAcademicTermsResult = null;
    final serial = ++internalAcademicTermsSerial;
    final demand = internalAcademicTermsDemand = ReadDemand(priority);
    final request = internalFetchAcademicTerms(
      backend: backend,
      queryBackend: backend as FeatureQueryBackend,
      lifecycle: lifecycle,
      epoch: epoch,
      serial: serial,
      demand: demand,
    );
    internalAcademicTermsPending = request;
    return request;
  }

  @internal
  Future<FeatureResult> internalFetchAcademicTerms({
    required UbaaBackend backend,
    required FeatureQueryBackend queryBackend,
    required int lifecycle,
    required int epoch,
    required int serial,
    required ReadDemand demand,
  }) async {
    bool current() =>
        !internalDisposed &&
        internalPhase == AppPhase.home &&
        identical(internalBackend, backend) &&
        internalLifecycleEpoch == lifecycle &&
        internalReadCacheEpoch == epoch &&
        internalAcademicTermsSerial == serial;
    try {
      // 即使 backend 在返回 Future 前同步抛错，也先建立在途句柄再清理。
      final result = await internalScheduleAuxiliaryRead(
        backend,
        FeatureId.schedule,
        ReadPriority.interactive,
        current,
        () => queryBackend.loadFeatureQuery(
          FeatureId.schedule,
          const FeatureQuery(view: FeatureQueryView.scheduleTerms),
        ),
        demand: demand,
      );
      if (!current()) return internalAcademicTermsConflict();
      if (result.error case final error?) {
        return FeatureResult.failure(
          internalRecordFailure(
            error,
            DiagnosticOperation.read,
            feature: FeatureId.schedule,
          ),
        );
      }
      final stable = result.isEmpty
          ? FeatureResult.empty(
              resolvedRoute: result.resolvedRoute,
              evidence: result.evidence,
              pagination: result.pagination,
            )
          : FeatureResult.success(
              summary: result.summary,
              resolvedRoute: result.resolvedRoute,
              evidence: result.evidence,
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
      internalAcademicTermsResult = stable;
      return stable;
    } on Object catch (error, stackTrace) {
      if (!current()) return internalAcademicTermsConflict();
      return FeatureResult.failure(
        internalRecordFailure(
          error,
          DiagnosticOperation.read,
          stackTrace: stackTrace,
          feature: FeatureId.schedule,
        ),
      );
    } finally {
      if (internalAcademicTermsSerial == serial)
        internalAcademicTermsPending = null;
    }
  }

  @internal
  FeatureResult internalAcademicTermsConflict() => FeatureResult.failure(
    UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
  );
}
