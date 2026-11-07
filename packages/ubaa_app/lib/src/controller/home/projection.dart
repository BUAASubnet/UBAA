part of 'coordinator.dart';

extension _HomeProjection on HomeCoordinator {
  Future<void> _project() async {
    if (_disposed || !_active || _blocked || _projecting) return;
    _projecting = true;
    _dirtyProjection = false;
    final generation = _generation;
    final weeks =
        _supplements[HomeSupplement.currentWeek]?.details
            .map((d) => d.presentation)
            .whereType<WeekPresentation>()
            .toList() ??
        [];
    final request = HomeTodoRequest(
      snapshots: _sources(),
      now: _now,
      currentWeek: weeks.length == 1 ? weeks.single : null,
      currentWeekRoute: _supplements[HomeSupplement.currentWeek]?.resolvedRoute,
      reminder: _reminder,
    );
    final done = Completer<void>();
    _projectionDone = done.future;
    try {
      final result = await project(request);
      if (_disposed || generation != _generation || _blocked) return;
      if (_dirtyProjection) return;
      if (!_sameTodos(_todos, result.todos)) _todos = result.todos;
      _projected = true;
      _projectionFailure = result.overlayFailure;
    } on Object catch (error) {
      if (_disposed ||
          generation != _generation ||
          _blocked ||
          _dirtyProjection)
        return;
      if (error is AgendaException &&
          error.failure == AgendaFailure.superseded) {
        _projectionRetry?.cancel();
        _projectionRetry = Timer(const Duration(milliseconds: 200), () {
          _dirtyProjection = true;
          _schedule();
        });
      } else {
        _projected = true;
        _projectionFailure = error;
      }
    } finally {
      _projecting = false;
      done.complete();
      if (_dirtyProjection) _schedule();
      _publish();
    }
  }

  Future<void> _flushProjection() async {
    await _cachedWeekTask;
    await _restoreVisibleDay();
    while (!_disposed && !_blocked && _active) {
      if (_projecting) {
        await _projectionDone;
      } else if (_dirtyProjection) {
        await _project();
      } else {
        return;
      }
    }
  }
}

bool _sameTodos(List<HomeTodo> a, List<HomeTodo> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.id != y.id ||
        x.title != y.title ||
        x.subtitle != y.subtitle ||
        x.feature != y.feature ||
        x.statusLabel != y.statusLabel ||
        x.timeLabel != y.timeLabel ||
        x.sortTime != y.sortTime ||
        x.soon != y.soon ||
        x.deadline != y.deadline ||
        x.startsAt != y.startsAt ||
        x.endsAt != y.endsAt ||
        x.navigation?.feature != y.navigation?.feature ||
        (x.navigation == null) != (y.navigation == null) ||
        (x.navigation != null &&
            !x.navigation!.query.hasSameParameters(y.navigation!.query)) ||
        x.signinAction?.scheduleId != y.signinAction?.scheduleId ||
        x.signinAction?.eligibility != y.signinAction?.eligibility)
      return false;
  }
  return true;
}
