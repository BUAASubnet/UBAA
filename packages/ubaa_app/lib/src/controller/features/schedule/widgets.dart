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
  YgdkReminderSettings get homeReminder;
  ConnectionMode get _route => agendaRoute(
    internalLoginForm.routePolicy,
    activeRoutes,
    schoolRoute: currentAgendaRoute,
  );
  RoutePolicy get _policy =>
      _route == ConnectionMode.direct ? RoutePolicy.direct : RoutePolicy.webvpn;

  Future<WeekPresentation?> widgetWeekOn(DateTime date) async {
    final backend = internalBackend,
        owner = internalScheduleWidgetOwner,
        epoch = internalLifecycleEpoch,
        cache = internalBusinessCacheEpoch;
    if (backend is! OfflineQueryBackend || owner == null) return null;
    final policy = _policy;
    bool current() =>
        !internalDisposed &&
        owner == internalScheduleWidgetOwner &&
        identical(backend, internalBackend) &&
        epoch == internalLifecycleEpoch &&
        cache == internalBusinessCacheEpoch &&
        policy == _policy;
    await internalOfflineOpenFuture;
    return readWidgetDateWeek(
      backend: backend as OfflineQueryBackend,
      owner: owner,
      policy: policy,
      date: date,
      term: currentAgendaTerm,
      isCurrent: current,
    );
  }

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
    internalAgendaEpoch,
    currentAgendaTerm,
    _route,
    homeSnapshots[FeatureId.ygdk]?.resolvedRoute,
    homeReminder.enabled,
    homeReminder.weekDoneKey,
    homeReminder.termDoneKey,
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
    bool current() =>
        publisherCurrent() &&
        !internalDisposed &&
        epoch == internalLifecycleEpoch &&
        identical(backend, internalBackend) &&
        owner == internalScheduleWidgetOwner &&
        cacheEpoch == internalBusinessCacheEpoch;
    await internalOfflineOpenFuture;
    await internalAgendaOpenFuture;
    final term = currentAgendaTerm, route = _route, reminder = homeReminder;
    return readScheduleWidgetSnapshot(
      backend: backend as OfflineQueryBackend,
      owner: owner,
      policy: _policy,
      agendaTerm: term,
      isCurrent: current,
      queryAgenda: (weeks, weekRoute, day, at) async {
        final service = agenda;
        if (service == null || internalAgendaFailure != null) return null;
        final sunlight = homeSnapshots[FeatureId.ygdk]?.resolvedRoute;
        final week =
            sunlight != null && weekRoute != null && sunlight != weekRoute
            ? null
            : homeWeekOn(weeks, day, term: term);
        // 与首页待办一样按构建时刻（精确到分钟）查询，状态表仍从校园日零点起算。
        // 构建时尚未开放的 SPOC 作业不会自行出现，要等查询分钟到达开放时刻之后的
        // 下一次发布（如打开应用或日程同步完成）才进入待办。
        return service.query(
          AgendaQuery(
            route: route,
            term: term,
            from: agendaDate(day),
            to: agendaDate(day.add(const Duration(days: 28))),
            now: agendaTime(at),
            includeHidden: false,
            ygdkEnabled: reminder.enabled,
            ygdkWeekDone:
                week != null &&
                reminder.weekDoneKey == '${week.responseTerm}:${week.number}',
            ygdkTermDone:
                week != null && reminder.termDoneKey == week.responseTerm,
          ),
        );
      },
    );
  }
}
