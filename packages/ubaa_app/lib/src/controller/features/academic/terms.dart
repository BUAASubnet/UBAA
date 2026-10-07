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
    return internalReadCaches.terms.load(
      scope: internalCaptureReadScope(),
      forceRefresh: forceRefresh,
      priority: priority,
      fetch: (current, demand) => internalFetchAcademicTerms(
        backend: backend,
        queryBackend: backend as FeatureQueryBackend,
        ownerCurrent: current,
        demand: demand,
      ),
      conflict: internalAcademicTermsConflict,
      pump: internalReadScheduler.pump,
    );
  }

  @internal
  Future<FeatureResult> internalFetchAcademicTerms({
    required UbaaBackend backend,
    required FeatureQueryBackend queryBackend,
    required bool Function() ownerCurrent,
    required ReadDemand demand,
  }) async {
    bool current() => internalPhase == AppPhase.home && ownerCurrent();
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
    }
  }

  @internal
  FeatureResult internalAcademicTermsConflict() => FeatureResult.failure(
    UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict),
  );
}
