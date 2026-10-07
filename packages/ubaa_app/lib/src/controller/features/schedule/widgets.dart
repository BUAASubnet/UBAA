import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/offline.dart';
import 'package:ubaa_app/src/presentation/schedule_widget.dart';
import '../../state/state.dart' show ControllerState;
import '../../state/types.dart' show AppPhase;

mixin ControllerScheduleWidgets on ControllerState {
  @internal
  String? get internalScheduleWidgetOwner =>
      internalPhase == AppPhase.home &&
          !internalIsSigningOut &&
          !internalClearingBusinessCache
      ? internalLocalAccount?.id
      : null;

  @internal
  Object get internalScheduleWidgetRevision => (
    internalBusinessCacheEpoch,
    internalBackend,
    Object.hashAll(
      internalScheduleImports.entries
          .where((e) => e.value.status == ScheduleImportStatus.saved)
          .map((e) => (e.key, e.value.progress)),
    ),
  );

  @internal
  Future<ScheduleWidgetSnapshot> internalReadScheduleWidgets(
    bool Function() publisherCurrent,
  ) async {
    final owner = internalScheduleWidgetOwner,
        epoch = internalLifecycleEpoch,
        backend = internalBackend;
    final cacheEpoch = internalBusinessCacheEpoch;
    if (owner == null || backend is! OfflineQueryBackend) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    await internalOfflineOpenFuture;
    return readScheduleWidgetSnapshot(
      backend: backend as OfflineQueryBackend,
      owner: owner,
      policy: RoutePolicy.auto,
      isCurrent: () =>
          publisherCurrent() &&
          !internalDisposed &&
          epoch == internalLifecycleEpoch &&
          identical(backend, internalBackend) &&
          owner == internalScheduleWidgetOwner &&
          cacheEpoch == internalBusinessCacheEpoch,
    );
  }
}
