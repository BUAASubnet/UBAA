part of 'ubaa_app_host.dart';

typedef _HomeCardScope = ({
  AgendaService service,
  int generation,
  RoutePolicy policy,
  ConnectionMode route,
  String term,
  int cacheEpoch,
});

extension _UbaaAppHostHomeCard on _UbaaAppHostState {
  _HomeCardScope? get _homeCardScope {
    final controller = _readyController;
    if (controller == null ||
        controller.scheduleWidgetOwner == null ||
        controller.localAgendaFailure != null) {
      return null;
    }
    final service = controller.agenda;
    if (service == null) return null;
    final policy = controller.loginForm.routePolicy;
    return (
      service: service,
      generation: service.accountGeneration,
      policy: policy,
      route: agendaRoute(
        policy,
        controller.activeRoutes,
        schoolRoute: controller.currentAgendaRoute,
      ),
      term: controller.currentAgendaTerm,
      cacheEpoch: controller.businessCacheEpoch,
    );
  }

  void _syncHomeCard({bool force = false}) {
    if (_disposed || widget.publishHomeCard == null) return;
    final scope = _homeCardScope;
    final now = campusDate(DateTime.now());
    if (_homeCardRequest == 0 || scope != _lastHomeCardScope) {
      if (_homeCardRequest == 0 || _lastHomeCardScope != null) {
        _writeHomeCard(
          buildHomeCardSnapshot(const [], now: now, signedIn: false),
        );
      }
      _lastHomeCardScope = scope;
      _homeCardRevision = null;
      _homeCardRequest++;
    }
    if (_wasBackgrounded || scope == null) {
      _homeCardTimer?.cancel();
      _homeCardTimer = null;
      if (_homeCardRevision != null) {
        _homeCardRevision = null;
        _homeCardRequest++;
      }
      return;
    }

    _homeCardTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _syncHomeCard(force: true),
    );
    final reminder = _controller.homeReminder;
    final day = agendaDate(now);
    final revision = (
      day,
      _controller.agendaProjectionEpoch,
      _controller.readCacheEpoch,
      reminder.enabled,
      reminder.termDoneKey,
    );
    if (!force && revision == _homeCardRevision) return;
    _homeCardRevision = revision;
    final request = ++_homeCardRequest;
    bool current() =>
        !_disposed &&
        !_wasBackgrounded &&
        request == _homeCardRequest &&
        scope == _homeCardScope &&
        day == agendaDate(campusDate(DateTime.now()));

    final campusNow = campusDate(now);
    final weekStart = agendaDate(
      DateTime.utc(
        campusNow.year,
        campusNow.month,
        campusNow.day - (campusNow.weekday - 1),
      ),
    );
    scheduleMicrotask(() async {
      if (!current()) return;
      try {
        final result = await scope.service.query(
          AgendaQuery(
            route: scope.route,
            term: scope.term,
            from: weekStart,
            to: agendaDate(now.add(const Duration(days: 28))),
            now: agendaTime(now),
            includeHidden: false,
            ygdkEnabled: reminder.enabled,
            ygdkWeekDone: false,
            ygdkTermDone: reminder.termDoneKey == scope.term,
          ),
        );
        if (!current()) return;
        _writeHomeCard(
          buildHomeCardSnapshot(result.entries, now: now, signedIn: true),
          isCurrent: current,
        );
      } on Object {
        return;
      }
    });
  }

  void _writeHomeCard(HomeCardSnapshot snapshot, {bool Function()? isCurrent}) {
    final publish = widget.publishHomeCard!;
    _homeCardWrite = _homeCardWrite.then((_) async {
      if (isCurrent != null && !isCurrent()) return;
      final previous = _lastHomeCardSnapshot;
      if (previous != null &&
          previous.campusDay == snapshot.campusDay &&
          previous.signedIn == snapshot.signedIn &&
          _sameCardItems(previous.agenda, snapshot.agenda) &&
          _sameCardItems(previous.homework, snapshot.homework) &&
          _sameCardItems(previous.todo, snapshot.todo) &&
          _sameWeek(previous, snapshot)) {
        return;
      }
      try {
        await publish(snapshot);
        _lastHomeCardSnapshot = snapshot;
      } on Object {
        _lastHomeCardSnapshot = null;
      }
    });
  }
}

bool _sameWeek(HomeCardSnapshot a, HomeCardSnapshot b) {
  if (a.weekLabel != b.weekLabel ||
      a.todayWeekday != b.todayWeekday ||
      a.weekRows.length != b.weekRows.length) {
    return false;
  }
  for (var i = 0; i < a.weekRows.length; i++) {
    final x = a.weekRows[i], y = b.weekRows[i];
    if (x.time != y.time || x.cells.length != y.cells.length) return false;
    for (var j = 0; j < x.cells.length; j++) {
      final p = x.cells[j], q = y.cells[j];
      if ((p.title, p.time, p.location, p.color) !=
          (q.title, q.time, q.location, q.color)) {
        return false;
      }
    }
  }
  return true;
}

bool _sameCardItems(List<HomeCardItem> a, List<HomeCardItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if ((x.title, x.time, x.location) != (y.title, y.time, y.location)) {
      return false;
    }
  }
  return true;
}
