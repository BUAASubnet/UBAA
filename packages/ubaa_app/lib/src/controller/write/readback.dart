import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/backend.dart';
import 'package:ubaa_app/src/contracts/write_readback.dart';
import '../state/models.dart' show WriteReadbackRead;
import '../state/state.dart' show ControllerState;
import '../state/types.dart' show AppPhase;

mixin ControllerWriteReadbacks on ControllerState {
  @internal
  bool internalReadbackCurrent(
    UbaaBackend backend,
    String account,
    int epoch,
  ) =>
      !internalDisposed &&
      !internalIsSigningOut &&
      internalPhase == AppPhase.home &&
      epoch == internalLifecycleEpoch &&
      identical(internalBackend, backend) &&
      internalLocalAccount?.id == account;

  @internal
  Future<void> internalLoadWriteReadbacks({bool force = false}) {
    final backend = internalBackend,
        account = internalLocalAccount?.id,
        epoch = internalLifecycleEpoch;
    if (backend is! WriteReadbackBackend ||
        account == null ||
        !internalReadbackCurrent(backend, account, epoch))
      return Future.value();
    if (!force &&
        internalWriteReadbackLoadedEpoch == epoch &&
        internalWriteReadbackError == null)
      return Future.value();
    // 提交后的强制重读不能加入提交前的旧读取并丢掉刚保存的提示。
    if (force) internalWriteReadbackRevision++;
    final pending = internalWriteReadbackRead;
    if (pending != null &&
        pending.epoch == epoch &&
        pending.revision == internalWriteReadbackRevision)
      return pending.completion.future;
    final request = WriteReadbackRead(epoch, internalWriteReadbackRevision);
    internalWriteReadbackRead = request;
    unawaited(() async {
      bool current() =>
          internalReadbackCurrent(backend, account, epoch) &&
          request.revision == internalWriteReadbackRevision;
      try {
        await internalOfflineOpenFuture;
        if (!current()) return;
        final values = await (backend as WriteReadbackBackend)
            .readWriteReadbackHints(accountId: account);
        if (!current()) return;
        internalWriteReadbacks = List.unmodifiable(values);
        internalWriteReadbackLoadedEpoch = epoch;
        internalWriteReadbackError = null;
      } on Object catch (error, stackTrace) {
        if (current())
          internalWriteReadbackError = internalRecordFailure(
            error,
            DiagnosticOperation.read,
            stackTrace: stackTrace,
          );
      } finally {
        if (identical(internalWriteReadbackRead, request))
          internalWriteReadbackRead = null;
        request.completion.complete();
        if (current()) internalNotify();
      }
    }());
    return request.completion.future;
  }

  @internal
  Future<void> internalDismissControllerReadback(String id) async {
    final backend = internalBackend,
        account = internalLocalAccount?.id,
        epoch = internalLifecycleEpoch;
    if (backend is! WriteReadbackBackend ||
        account == null ||
        !internalReadbackCurrent(backend, account, epoch) ||
        internalWriteTransitions != 0 ||
        internalWriteCoordinator.hasPendingOperation ||
        internalClearingBusinessCache ||
        !internalWriteReadbacks.any((hint) => hint.id == id)) {
      throw const BackendException(UbaaErrorCode.operationConflict);
    }
    await (backend as WriteReadbackBackend).dismissWriteReadbackHint(
      id,
      accountId: account,
    );
    if (!internalReadbackCurrent(backend, account, epoch)) return;
    internalWriteReadbackRevision++;
    internalWriteReadbacks = internalWriteReadbacks
        .where((hint) => hint.id != id)
        .toList(growable: false);
    internalWriteReadbackError = null;
    internalNotify();
  }

  @internal
  void internalClearWriteReadbacks() {
    internalWriteReadbackRevision++;
    internalWriteReadbackLoadedEpoch = -1;
    internalWriteReadbacks = const [];
    internalWriteReadbackError = null;
    internalWriteReadbackRead = null;
  }
}
