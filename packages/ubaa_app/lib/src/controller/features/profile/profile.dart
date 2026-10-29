import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_app/src/controller/read_scheduler.dart';
import 'package:ubaa_app/src/contracts/profile.dart';
import '../../state/models.dart' show ProfileRequest;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerProfile on ControllerState {
  @internal
  bool internalProfileCurrent(
    UbaaBackend backend,
    String accountId,
    int epoch,
    RoutePolicy policy,
  ) =>
      !internalDisposed &&
      !internalIsSigningOut &&
      identical(backend, internalBackend) &&
      epoch == internalLifecycleEpoch &&
      internalLocalAccount?.id == accountId &&
      internalLoginForm.routePolicy == policy &&
      (internalPhase == AppPhase.home || internalPhase == AppPhase.loggingIn);

  @internal
  bool get internalHasFreshProfile =>
      internalProfileDisplayEpoch == internalLifecycleEpoch &&
      internalProfileDisplay != null &&
      internalProfileDisplay?.profileEvidence?.origin != DataOrigin.persisted;

  @internal
  Future<void> internalRestoreCachedProfile(
    UbaaBackend backend,
    LocalAccount account,
    int epoch,
  ) async {
    if (backend is! ProfileCacheBackend) return;
    final policy = internalLoginForm.routePolicy;
    try {
      final read = await (backend as ProfileCacheBackend).readCachedProfile(
        policy,
      );
      if (!internalProfileCurrent(backend, account.id, epoch, policy)) return;
      final value = read.profile;
      if (value != null &&
          value.accountId == account.id &&
          !internalHasFreshProfile) {
        final display = value.toDisplay();
        internalProfileDisplay = internalProfileFailureEpoch == epoch
            ? profileDisplay(
                display,
                display.profileEvidence,
                display.profileRoute,
                notice: '资料暂未更新，保留上次内容',
              )
            : display;
        internalProfileDisplayEpoch = epoch;
      }
      if (read.error != null && !internalHasFreshProfile)
        internalProfileFailure(read.error!);
      internalNotify();
    } on Object catch (error) {
      if (internalProfileCurrent(backend, account.id, epoch, policy) &&
          !internalHasFreshProfile) {
        internalProfileFailure(error);
        internalNotify();
      }
    }
  }

  @internal
  Future<void> internalQueueProfileRefresh({bool force = false}) {
    final backend = internalBackend, account = internalLocalAccount;
    if (backend is! ProfileCacheBackend ||
        account == null ||
        internalPhase != AppPhase.home ||
        internalDisposed ||
        internalIsSigningOut ||
        internalSessionRecoveryStatus != SessionRecoveryStatus.ready)
      return Future<void>.value();
    final policy = internalLoginForm.routePolicy,
        epoch = internalLifecycleEpoch;
    final active = internalProfileRequest;
    if (active != null &&
        identical(active.backend, backend) &&
        active.epoch == epoch &&
        active.policy == policy &&
        active.accountId == account.id)
      return active.completion.future;
    if (!force &&
        internalProfileRefreshedEpoch == epoch &&
        internalProfileRefreshedPolicy == policy &&
        internalProfileRefreshedAt != null &&
        DateTime.now().difference(internalProfileRefreshedAt!) <
            const Duration(minutes: 5))
      return Future<void>.value();
    final request = ProfileRequest(backend, account.id, epoch, policy);
    internalProfileRequest = request;
    unawaited(
      internalRunProfileRefresh(request, account).whenComplete(() {
        if (identical(internalProfileRequest, request))
          internalProfileRequest = null;
        request.completion.complete();
      }),
    );
    return request.completion.future;
  }

  @internal
  Future<void> internalRunProfileRefresh(
    ProfileRequest request,
    LocalAccount account,
  ) async {
    bool current() => internalProfileCurrent(
      request.backend,
      account.id,
      request.epoch,
      request.policy,
    );
    try {
      await internalOfflineOpenFuture;
      if (!current()) return;
      final result = await internalReadScheduler.run(
        ReadPriority.background,
        current,
        () => (request.backend as ProfileCacheBackend).refreshProfile(
          account: account,
        ),
        lane: request.backend is ConcurrentReadBackend
            ? ReadLane.profile
            : null,
      );
      if (!current()) return;
      if (result.evidence.accountId != account.id ||
          (result.profile.username != account.username &&
              result.profile.schoolId != account.username)) {
        await internalRejectMismatchedAccount();
        return;
      }
      if (result.evidence.origin != DataOrigin.online ||
          !result.evidence.complete)
        throw const BackendException(UbaaErrorCode.upstreamChanged);
      internalProfileFailureEpoch = -1;
      internalProfileDisplay = result.evidence.savedForOffline
          ? result.toDisplay()
          : profileDisplay(
              result.profile,
              result.evidence,
              result.route,
              notice: '本次资料未能保存，仍可查看在线内容',
            );
      internalProfileDisplayEpoch = request.epoch;
      internalProfileRefreshedAt = DateTime.now();
      internalProfileRefreshedEpoch = request.epoch;
      internalProfileRefreshedPolicy = request.policy;
      internalNotify();
    } on ReadCancelled {
      /* 退出、路线和实例变化丢弃旧任务。 */
    } on Object catch (error) {
      if (current()) {
        if (error is BackendException && error.accountMismatch) {
          await internalRejectMismatchedAccount();
          return;
        }
        internalProfileFailure(error);
        internalNotify();
      }
    }
  }

  @internal
  void internalProfileFailure(Object error) {
    internalRecordFailure(error, DiagnosticOperation.read);
    internalProfileFailureEpoch = internalLifecycleEpoch;
    final shown = internalProfileDisplay ?? internalUser;
    if (shown != null)
      internalProfileDisplay = profileDisplay(
        shown,
        shown.profileEvidence,
        shown.profileRoute,
        notice: '资料暂未更新，保留上次内容',
        accountScope: internalLocalAccount?.id,
      );
  }
}
