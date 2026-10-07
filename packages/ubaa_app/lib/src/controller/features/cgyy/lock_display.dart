import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/cgyy/lock_display.dart';
import '../../state/models.dart' show GuardedLockDisplaySession;
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase, SessionRecoveryStatus;

mixin ControllerLockDisplay on ControllerState {
  @internal
  Future<CgyyLockDisplaySession> internalOpenLockDisplay() async {
    internalLockDisplay?.cancel();
    final request = ++internalLockDisplayGeneration;
    final backend = internalBackend;
    final epoch = internalLifecycleEpoch;
    bool current() =>
        !internalDisposed &&
        internalAppForeground &&
        !internalInteractiveEngaged &&
        internalPhase == AppPhase.home &&
        internalUser != null &&
        internalWriteTransitions == 0 &&
        internalSessionRecoveryStatus != SessionRecoveryStatus.needsLogin &&
        (!internalUsesLocalRecovery ||
            internalSessionRecoveryStatus == SessionRecoveryStatus.ready) &&
        request == internalLockDisplayGeneration &&
        epoch == internalLifecycleEpoch &&
        identical(backend, internalBackend);
    if (!current() || backend is! CgyyLockDisplayBackend) {
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    final session = await (backend as CgyyLockDisplayBackend).openLockDisplay();
    if (!current()) {
      session.cancel();
      throw const BackendException(UbaaErrorCode.authenticationRequired);
    }
    return internalLockDisplay = GuardedLockDisplaySession(session, current);
  }
}
