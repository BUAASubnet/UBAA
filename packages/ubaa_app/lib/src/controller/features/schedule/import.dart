import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/schedule_import.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/controller/error_mapper.dart';
import '../../state/models.dart' show ScheduleImportScope;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerScheduleImport on ControllerState {
  @internal
  void internalPruneScheduleImports() {
    if (internalScheduleImportEpoch != internalLifecycleEpoch) {
      internalScheduleImportEpoch = internalLifecycleEpoch;
      internalScheduleImports.clear();
    }
    for (final entry in internalScheduleImportScopes.entries.toList()) {
      if (entry.value.ownerCurrent()) continue;
      entry.value.cancel();
      internalScheduleImportScopes.remove(entry.key);
      internalScheduleImports.remove(entry.key);
    }
  }

  @internal
  Future<void> internalSaveScheduleSemester(String term) {
    if (!canSaveScheduleSemester || term.trim().isEmpty) {
      return Future.error(
        const BackendException(UbaaErrorCode.operationConflict),
      );
    }
    internalPruneScheduleImports();
    final previous = internalScheduleImportScopes[term];
    if (previous != null && previous.valid) return previous.completion.future;
    final epoch = internalLifecycleEpoch, backend = internalBackend;
    final account = internalLocalAccount?.id;
    final scope = ScheduleImportScope(
      () =>
          !internalDisposed &&
          !internalIsSigningOut &&
          !internalClearingBusinessCache &&
          internalPhase == AppPhase.home &&
          epoch == internalLifecycleEpoch &&
          identical(backend, internalBackend) &&
          account == internalLocalAccount?.id,
    );
    internalScheduleImportScopes[term] = scope;
    internalScheduleImports[term] = const ScheduleImportState(
      status: ScheduleImportStatus.running,
    );
    internalNotify();
    unawaited(
      internalRunScheduleImport(term, scope, backend as ScheduleImportBackend),
    );
    return scope.completion.future;
  }

  @internal
  void internalCancelScheduleImport(String term) {
    final scope = internalScheduleImportScopes[term];
    if (scope == null || !scope.valid) return;
    scope.cancel();
    internalScheduleImports[term] = ScheduleImportState(
      status: ScheduleImportStatus.cancelled,
      progress: internalScheduleImports[term]?.progress,
    );
    internalNotify();
  }

  @internal
  Future<void> internalRunScheduleImport(
    String term,
    ScheduleImportScope scope,
    ScheduleImportBackend backend,
  ) async {
    try {
      await internalOfflineOpenFuture;
      final task = await internalScheduledRead(
        FeatureId.schedule,
        ReadPriority.background,
        () => scope.valid,
        () => backend.beginScheduleImport(term),
        discard: (task) => task.cancel(),
      );
      scope.task = task;
      while (scope.valid) {
        await internalScheduleReadAuthentication(
          FeatureId.schedule,
          ReadPriority.background,
          () => scope.valid,
        );
        final progress = await internalReadScheduler.run(
          ReadPriority.background,
          () => scope.valid,
          task.next,
        );
        if (progress.term != term)
          throw const BackendException(UbaaErrorCode.upstreamChanged);
        internalScheduleImports[term] = ScheduleImportState(
          status: !progress.finished
              ? ScheduleImportStatus.running
              : progress.saved
              ? ScheduleImportStatus.saved
              : ScheduleImportStatus.failed,
          progress: progress,
        );
        internalNotify();
        if (progress.finished) {
          if (progress.saved)
            await _publishImportedWeek(term, scope, progress.route);
          break;
        }
      }
    } on ReadCancelled {
      // 用户取消或归属变化已清理界面；在途返回不能恢复旧状态。
    } on Object catch (error) {
      if (scope.valid && error is BackendException && error.accountMismatch) {
        await internalRejectMismatchedAccount();
      } else if (scope.valid) {
        if (error is BackendException &&
            error.code == UbaaErrorCode.authenticationRequired) {
          internalFeatureRecoveryStates[FeatureId.schedule] =
              SessionRecoveryStatus.needsLogin;
        }
        internalScheduleImports[term] = ScheduleImportState(
          status: ScheduleImportStatus.failed,
          progress: internalScheduleImports[term]?.progress,
          error: UbaaErrorMapper.fromObject(error),
        );
      }
    } finally {
      scope.task?.cancel();
      if (identical(internalScheduleImportScopes[term], scope))
        internalScheduleImportScopes.remove(term);
      scope.completion.complete();
      if (!internalDisposed) internalNotify();
    }
  }

  Future<void> _publishImportedWeek(
    String term,
    ScheduleImportScope scope,
    ConnectionMode route,
  ) async {
    final backend = internalBackend;
    final account = internalLocalAccount;
    final previous = internalSnapshots[FeatureId.schedule];
    final query = previous?.readContext?.query;
    if (!scope.valid ||
        backend is! OfflineQueryBackend ||
        account == null ||
        !(query?.view == FeatureQueryView.scheduleWeek ||
            (query?.view == FeatureQueryView.summary && query?.week != null)) ||
        query?.term != term ||
        previous!.status == FeatureLoadStatus.loading)
      return;
    bool current() =>
        scope.valid &&
        identical(internalSnapshots[FeatureId.schedule], previous);
    try {
      final read = await (backend as OfflineQueryBackend).readCachedQuery(
        FeatureId.schedule,
        query!,
        route == ConnectionMode.direct
            ? RoutePolicy.direct
            : RoutePolicy.webvpn,
      );
      if (!current()) return;
      final projection = read.projection;
      if (projection != null &&
          projection.complete &&
          projection.feature == FeatureId.schedule &&
          projection.accountId == account.id &&
          projection.route == route &&
          projection.readContext.hasSameQuery(query)) {
        internalSnapshots[FeatureId.schedule] = projection
            .toSnapshot()
            .copyWith(readContext: previous.readContext);
      }
      if (read.error != null) {
        internalLocalCacheError = internalRecordFailure(
          read.error!,
          DiagnosticOperation.read,
          feature: FeatureId.schedule,
        );
      }
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      internalLocalCacheError = internalRecordFailure(
        error,
        DiagnosticOperation.read,
        feature: FeatureId.schedule,
        stackTrace: stackTrace,
      );
    }
  }
}
