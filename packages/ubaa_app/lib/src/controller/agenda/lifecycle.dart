import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../state/state.dart';

mixin ControllerAgenda on ControllerState {
  /// 只给界面上的同步按钮使用；日程服务自身的自动同步没有提示回调。
  AgendaSyncJob prepareAgendaSync(AgendaSyncAction action, AgendaTime now) {
    final service = agenda;
    if (service == null) throw const AgendaException(AgendaFailure.inactive);
    return service.prepareSync(
      action,
      now,
      onRejected: (error) {
        if (identical(agenda, service))
          internalReportUserSchoolRejection(error);
      },
    );
  }

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
    internalAgendaEpoch++;
    final generation = ++internalAgendaOpenEpoch;
    internalAgendaFailure = null;
    internalAgendaOpenFuture = () async {
      var serviceGeneration = service.accountGeneration;
      try {
        final opening = service.openAccount(account.id);
        serviceGeneration = service.accountGeneration;
        await opening;
      } on Object catch (error) {
        if (generation != internalAgendaOpenEpoch ||
            serviceGeneration != service.accountGeneration ||
            internalDisposed ||
            !identical(backend, internalBackend) ||
            internalLocalAccount?.id != account.id) {
          return;
        }
        internalAgendaFailure = error is AgendaException
            ? error.failure
            : AgendaFailure.unavailable;
      }
      if (generation == internalAgendaOpenEpoch && !internalDisposed) {
        internalAgendaEpoch++;
        internalNotify();
      }
    }();
  }

  @override
  @internal
  Future<void> internalCloseAgenda() {
    internalAgendaOpenEpoch++;
    internalAgendaEpoch++;
    internalAgendaFailure = null;
    final backend = internalBackend;
    return backend is AgendaProvider
        ? (backend as AgendaProvider).agenda.close()
        : Future<void>.value();
  }
}
