import 'dart:async';
import 'package:clock/clock.dart' as system_clock;
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

part 'projection.dart';
part 'sources.dart';

/// 首页的补充读取、展示日期和投影由应用层统一持有。
/// 回调沿用 Controller 的账号与路线检查，本类不接触学校协议。
final class HomeCoordinator {
  HomeCoordinator({
    required this.loadSupplement,
    required this.loadDay,
    required this.project,
    required this.refreshMain,
    required this.retryMain,
    required this.changed,
    this.readCachedWeek,
    this.readCachedDay,
    this.reportUserRejection,
    this.scheduleBackground = scheduleMicrotask,
    DateTime Function()? now,
  }) : clock = now ?? (() => system_clock.clock.now());
  final Future<FeatureResult> Function(HomeSupplement, bool) loadSupplement;
  final Future<FeatureResult> Function(String, bool) loadDay;
  final HomeTodoReader project;
  final Future<void> Function() refreshMain;
  final Future<void> Function(FeatureId) retryMain;
  final Future<FeatureResult?> Function(DateTime)? readCachedWeek;
  final Future<FeatureResult?> Function(String)? readCachedDay;
  final void Function(Object?)? reportUserRejection;
  final void Function(void Function()) scheduleBackground;
  final VoidCallback changed;
  final DateTime Function() clock;
  final _supplements = <HomeSupplement, FeatureResult>{};
  final _supplementTimes = <HomeSupplement, DateTime>{};
  final _supplementTasks = <HomeSupplement, Future<UiError?>>{};
  final _days = <String, FeatureSnapshot>{};
  final _dayTasks = <String, Future<UiError?>>{};
  final _dayAttempts = <String>{};
  final _supplementAttempts = <HomeSupplement>{};
  Future<void>? _projectionDone;
  Future<void>? _cachedWeekTask;
  final _cachedDayTasks = <String, Future<void>>{};
  late String _observedToday = homeDateKey(homeCampusTime(clock()));
  Map<FeatureId, FeatureSnapshot> _snapshots = const {};
  Object? _owner;
  Object? _contentScope;
  int _epoch = -1, _generation = 0, _agenda = -1;
  bool _active = false, _online = false, _blocked = false, _disposed = false;
  bool _readDays = false;
  bool _forceDayReads = false;
  bool _scheduled = false, _projecting = false, _dirtyProjection = false;
  bool _projected = false;
  List<HomeTodo> _todos = const [];
  Object? _projectionFailure;
  Timer? _timer, _projectionRetry;
  Future<void>? _refresh;
  YgdkReminderSettings _reminder = const YgdkReminderSettings(enabled: false);
  late DateTime _now = clock();
  late HomeState _state = _compose();
  HomeState get state => _state;

  void update({
    required Object owner,
    Object? contentScope,
    required Map<FeatureId, FeatureSnapshot> snapshots,
    required int epoch,
    required int agenda,
    required bool active,
    required bool online,
    required bool blocked,
    required bool foreground,
    bool readDays = true,
  }) {
    if (_disposed) return;
    final newOwner = owner != _owner;
    final nextContentScope = contentScope ?? owner;
    final newContentScope = nextContentScope != _contentScope;
    final newEpoch = epoch != _epoch;
    final contentChanged = !mapEquals(snapshots, _snapshots);
    final signinChanged =
        snapshots[FeatureId.signin] != _snapshots[FeatureId.signin];
    final agendaChanged = agenda != _agenda;
    if (newOwner) {
      _generation++;
      _owner = owner;
      _contentScope = nextContentScope;
      _observedToday = homeDateKey(homeCampusTime(clock()));
      _cachedWeekTask = null;
      _cachedDayTasks.clear();
      _refresh = null;
      _supplementTasks.clear();
      _dayTasks.clear();
      if (newContentScope) {
        _supplements.clear();
        _supplementTimes.clear();
        _days.clear();
        _todos = const [];
        _projected = false;
      } else {
        // 同账号客户端恢复保留只读内容，旧客户端的签到操作立即撤销。
        _todos = _todos.map((todo) => todo.withoutSigninAction()).toList();
      }
      _projectionFailure = null;
      _projectionRetry?.cancel();
    }
    final resumed = active && !_active;
    final blockingChanged = blocked != _blocked;
    final unblocked = _blocked && !blocked;
    final ready = online && !_online;
    final daysReady = readDays && !_readDays;
    _readDays = readDays;
    _active = active;
    if (!active) {
      _todos = const [];
      _projected = false;
    }
    _online = online;
    if (blocked && !_blocked) {
      _todos = _todos.map((todo) => todo.withoutSigninAction()).toList();
    }
    _blocked = blocked;
    _snapshots = Map.of(snapshots);
    if (newOwner || newEpoch) {
      _forceDayReads = !newOwner;
      _epoch = epoch;
      // 新的一轮刷新重新核验展示日期；当前内容仍保留。
      _dayAttempts.clear();
      _supplementAttempts.clear();
    }
    if (foreground && active) {
      _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (newOwner || resumed) _restoreWeek();
    if (_active && _readDays) _restoreVisibleDay();
    if (newOwner ||
        newEpoch ||
        contentChanged ||
        agendaChanged ||
        resumed ||
        unblocked) {
      _agenda = agenda;
      _dirtyProjection = true;
      // 其他来源重算不改变签到资格；读取范围或签到来源变化才撤销旧操作。
      if ((newEpoch || signinChanged) &&
          _todos.any((todo) => todo.signinAction != null)) {
        _todos = _todos
            .map(
              (todo) =>
                  todo.signinAction == null ? todo : todo.withoutSigninAction(),
            )
            .toList();
      }
    }
    if (newOwner ||
        newEpoch ||
        contentChanged ||
        agendaChanged ||
        resumed ||
        blockingChanged ||
        ready ||
        daysReady) {
      _state = _compose();
      _schedule();
    }
  }

  void setReminder(YgdkReminderSettings? value) {
    final next = value ?? const YgdkReminderSettings(enabled: false);
    if (_reminder.enabled == next.enabled &&
        _reminder.weekDoneKey == next.weekDoneKey &&
        _reminder.termDoneKey == next.termDoneKey)
      return;
    _reminder = next;
    _dirtyProjection = true;
    _schedule();
  }

  void tick() {
    if (_disposed || !_active) return;
    _now = clock();
    _dirtyProjection = true;
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleBackground(() {
      _scheduled = false;
      if (_disposed) return;
      _now = clock();
      if (_active && !_blocked) {
        if (_online) {
          for (final source in HomeSupplement.values) {
            if (_supplementAttempts.add(source)) unawaited(_load(source));
          }
        }
        final schedule = _scheduleState();
        if (_readDays) _restoreVisibleDay();
        if (_online &&
            _readDays &&
            schedule.remote &&
            _dayAttempts.add(schedule.date)) {
          unawaited(_loadDay(schedule.date, force: _forceDayReads));
        }
        if (_dirtyProjection && !_projecting) unawaited(_project());
      }
      _publish();
    });
  }

  HomeState _compose() {
    final sources = _sources();
    final schedule = _scheduleState();
    final dates = [
      for (final s in sources.values)
        if (s.updatedAt != null) s.updatedAt!,
      if (schedule.snapshot.updatedAt != null) schedule.snapshot.updatedAt!,
      if (_supplements[HomeSupplement.currentWeek]?.evidence?.fetchedAt
          case final at?)
        at,
    ];
    dates.sort();
    return HomeState(
      now: _now,
      sources: sources,
      schedule: schedule,
      week: _supplements[HomeSupplement.currentWeek],
      todos: _todos,
      projected: _projected,
      projectionFailure: _projectionFailure,
      busy:
          sources.values.any(
            (s) => s.status == FeatureLoadStatus.loading && !s.refining,
          ) ||
          _supplementTasks.isNotEmpty ||
          _dayTasks.containsKey(schedule.date),
      refining: sources.values.any((s) => s.refining),
      updatedAt: dates.firstOrNull,
    );
  }

  void _publish() {
    if (_disposed) return;
    _state = _compose();
    changed();
  }

  Future<void> refresh() {
    if (_refresh case final pending?) return pending;
    final complete = Completer<void>();
    final generation = _generation;
    _refresh = complete.future;
    unawaited(() async {
      try {
        final main = refreshMain();
        await Future.wait([
          main,
          for (final source in HomeSupplement.values)
            _report(_load(source, force: true)),
        ]);
        if (_disposed || generation != _generation || !_active) {
          complete.complete();
          return;
        }
        final schedule = _scheduleState();
        if (schedule.remote)
          await _report(_loadDay(schedule.date, force: true));
        await flushProjection();
        complete.complete();
      } on Object catch (error, stack) {
        complete.completeError(error, stack);
      } finally {
        if (identical(_refresh, complete.future)) _refresh = null;
        _publish();
      }
    }());
    return complete.future;
  }

  Future<void> retry(FeatureId feature) async {
    switch (feature) {
      case FeatureId.bykc:
        await _report(_load(HomeSupplement.bykcChosen, force: true));
      case FeatureId.cgyy:
        await _report(_load(HomeSupplement.cgyyOrders, force: true));
      case FeatureId.schedule:
        final schedule = _scheduleState();
        if (schedule.remote) {
          await _report(_loadDay(schedule.date, force: true));
        } else {
          await retryMain(feature);
        }
      default:
        await retryMain(feature);
    }
  }

  Future<void> _report(Future<UiError?> result) async {
    final error = await result;
    reportUserRejection?.call(error);
  }

  Future<void> flushProjection() => _flushProjection();

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _projectionRetry?.cancel();
  }
}
