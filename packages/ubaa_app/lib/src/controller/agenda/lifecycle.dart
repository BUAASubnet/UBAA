import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../state/state.dart';

mixin ControllerAgenda on ControllerState {
  /// 本机修改完成后使首页本地覆盖投影重新计算，不刷新学校来源。
  void notifyAgendaChanged() {
    internalAgendaEpoch++;
    internalNotify();
  }

  @override
  @internal
  void internalOpenAgenda(LocalAccount account) {
    final backend = internalBackend;
    if (backend is! AgendaProvider) return;
    final service = (backend as AgendaProvider).agenda;
    final generation = ++internalAgendaEpoch;
    internalAgendaFailure = null;
    internalAgendaOpenFuture = () async {
      try {
        await service.openAccount(account.id);
      } on Object catch (error) {
        if (generation != internalAgendaEpoch ||
            internalDisposed ||
            !identical(backend, internalBackend) ||
            internalLocalAccount?.id != account.id) {
          return;
        }
        internalAgendaFailure = error is AgendaException
            ? error.failure
            : AgendaFailure.unavailable;
      }
      if (generation == internalAgendaEpoch && !internalDisposed) {
        internalAgendaEpoch++;
        internalNotify();
      }
    }();
  }

  @override
  @internal
  Future<void> internalCloseAgenda() {
    internalAgendaEpoch++;
    internalAgendaFailure = null;
    final backend = internalBackend;
    return backend is AgendaProvider
        ? (backend as AgendaProvider).agenda.close()
        : Future<void>.value();
  }
}
