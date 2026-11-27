import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../contracts/course_hub.dart';
import '../presentation/course_hub.dart';
import 'app_controller.dart';
import 'error_mapper.dart';
import 'state/types.dart';

final class CourseHubController extends ValueNotifier<CourseHubSnapshot> {
  CourseHubController(this.app) : super(const CourseHubSnapshot()) {
    app.addListener(_sync);
    _sync();
  }
  final AppController app;
  Timer? _timer;
  Object? _owner, _catalogKey, _localKey, _revision;
  CourseHubBackend? _backend;
  bool _needed = false, _closed = false;
  bool? _graduate;
  int _catalogTicket = 0, _localTicket = 0;
  List<SpocCourse> _catalog = const [];
  List<CourseHubWeek> _weeks = const [];
  Set<String> _overrides = const {};
  static const _idle = CourseHubSourceStatus(CourseHubSourceState.notLoaded);
  static const _loading = CourseHubSourceStatus(CourseHubSourceState.loading);
  static const _ready = CourseHubSourceStatus(CourseHubSourceState.ready);
  CourseHubSourceStatus _catalogStatus = _idle, _scheduleStatus = _idle;
  Future<void>? _catalogWork;
  Future<void>? _localWork;
  bool _linksAvailable = false;
  String? get _term =>
      app.currentAgendaTerm.isEmpty ? null : app.currentAgendaTerm;
  ConnectionMode? get _spocRoute => switch (app.loginForm.routePolicy) {
    RoutePolicy.direct => ConnectionMode.direct,
    RoutePolicy.webvpn => ConnectionMode.webvpn,
    RoutePolicy.auto => app.internalHomeDefaults[FeatureId.spoc]?.resolvedRoute,
  };
  bool get _online =>
      app.networkOnline &&
      app.internalAppForeground &&
      !app.internalReadTransitionBlocked &&
      (!app.usesLocalRecovery ||
          app.sessionRecoveryStatus == SessionRecoveryStatus.ready);

  void ensureLoaded() {
    if (_closed) return;
    _needed = true;
    _sync();
  }

  void _sync() {
    if (_closed) return;
    final owner =
        app.phase != AppPhase.home ||
            app.internalIsSigningOut ||
            app.internalClearingBusinessCache
        ? null
        : (
            app.internalBackend,
            app.cacheAccountId,
            app.user?.username,
            app.internalLifecycleEpoch,
            app.internalRoutePolicyGeneration,
            app.businessCacheEpoch,
          );
    if (owner != _owner) {
      _owner = owner;
      _backend?.onAcademicIdentity = null;
      final backend = app.internalBackend;
      _backend = owner != null && backend is CourseHubBackend
          ? backend as CourseHubBackend
          : null;
      _graduate = null;
      _backend?.onAcademicIdentity = (value) {
        if (!_closed && _owner == owner && _graduate != value) {
          _graduate = value;
          _sync();
        }
      };
      _catalogKey = null;
      _catalogTicket++;
      _catalogWork = null;
      _catalog = const [];
      _catalogStatus = _idle;
      _localKey = null;
      _localTicket++;
      _weeks = const [];
      _linksAvailable = false;
      _overrides = const {};
      _scheduleStatus = _idle;
      _revision = null;
      if (owner == null) {
        _needed = false;
        value = const CourseHubSnapshot();
      }
    }
    if (!_needed || owner == null || !app.internalAppForeground) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => _publish());
    final catalogKey = (_term, _spocRoute, app.recoveredRoute);
    if (_catalogKey != catalogKey) {
      _catalogKey = catalogKey;
      _catalogTicket++;
      _catalogWork = null;
      _catalog = const [];
      _catalogStatus = _idle;
    }
    if (_online && _catalogStatus == _idle && app.spocFilesService != null)
      unawaited(_loadCatalog());
    final term = _term,
        route = app.currentAgendaRoute,
        backend = _backend,
        account = app.cacheAccountId;
    final saved = app.internalScheduleImports[term];
    final localKey = (
      account,
      route,
      term,
      _graduate,
      saved?.status == ScheduleImportStatus.saved ? saved : null,
    );
    if (localKey != _localKey) {
      _localKey = localKey;
      final ticket = ++_localTicket;
      _weeks = const [];
      _overrides = const {};
      _scheduleStatus = _graduate == false
          ? _idle
          : const CourseHubSourceStatus(CourseHubSourceState.notApplicable);
      if (term != null &&
          route != null &&
          account != null &&
          backend != null &&
          _graduate == false) {
        _scheduleStatus = _loading;
        _localWork = _loadLocal(ticket, backend, account, route, term);
      }
    }
    final defaults = app.internalHomeDefaults;
    final revision = (
      defaults[FeatureId.spoc],
      defaults[FeatureId.judge],
      defaults[FeatureId.exam],
      app.internalSnapshots[FeatureId.grades],
      _catalogStatus,
      _scheduleStatus,
      _localKey,
      _catalogKey,
    );
    if (revision != _revision) {
      _revision = revision;
      _publish();
    }
  }

  Future<void> _loadCatalog() {
    final service = app.spocFilesService;
    if (service == null || !_online) return Future.value();
    if (_catalogWork case final pending?) return pending;
    final ticket = ++_catalogTicket, route = _spocRoute;
    _catalogStatus = _loading;
    return _catalogWork = Future.sync(service.courses)
        .then((read) {
          if (ticket != _catalogTicket) return;
          if (route != null && route != read.route) {
            _catalog = const [];
            throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
          }
          _catalog = read.data;
          _catalogStatus = _ready;
        })
        .catchError((Object error) {
          if (ticket == _catalogTicket)
            _catalogStatus = CourseHubSourceStatus(
              CourseHubSourceState.failed,
              UbaaErrorMapper.fromObject(error),
            );
        })
        .whenComplete(() {
          if (ticket == _catalogTicket) {
            _catalogWork = null;
            _publish();
          }
        });
  }

  Future<void> _loadLocal(
    int ticket,
    CourseHubBackend backend,
    String account,
    ConnectionMode route,
    String term,
  ) async {
    try {
      await app.internalOfflineOpenFuture;
      if (ticket != _localTicket) return;
      final weeks = await backend.courseHubWeeks(account, route, term);
      if (ticket != _localTicket) return;
      _weeks = weeks;
      _linksAvailable = false;
      final overrides = (await backend.courseHubOverrides(
        account,
        term,
      )).toSet();
      if (ticket != _localTicket) return;
      _overrides = overrides;
      _linksAvailable = true;
      _scheduleStatus = weeks.isEmpty ? _idle : _ready;
    } on Object catch (error) {
      if (ticket != _localTicket) return;
      _scheduleStatus = CourseHubSourceStatus(
        _weeks.isEmpty
            ? CourseHubSourceState.failed
            : CourseHubSourceState.partial,
        UbaaErrorMapper.fromObject(error),
      );
    }
    _publish();
  }

  Future<void> refresh() async {
    ensureLoaded();
    if (_owner == null) return;
    _localKey = null;
    _sync();
    await Future.wait([
      if (_localWork case final work?) work,
      if (_online) ...[
        _loadCatalog(),
        app.refreshHome(only: [FeatureId.spoc, FeatureId.judge]),
      ],
    ]);
  }

  Future<void> setJudgeLink(
    String courseKey,
    String judgeCourseId,
    bool linked,
  ) async {
    final term = _term,
        account = app.cacheAccountId,
        backend = _backend,
        ticket = _localTicket;
    final link = value.courses
        .where((c) => c.key == courseKey)
        .expand((c) => c.judgeLinks)
        .where((l) => l.judgeCourseId == judgeCourseId)
        .singleOrNull;
    if (link == null || term == null || account == null || backend == null)
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    await backend.saveCourseHubLink(account, term, judgeCourseId, linked);
    if (ticket != _localTicket) return;
    _overrides = {..._overrides};
    if (linked) {
      _overrides.remove(judgeCourseId);
    } else {
      _overrides.add(judgeCourseId);
    }
    _publish();
  }

  void _publish() {
    if (_closed || _owner == null || !_needed) return;
    final defaults = app.internalHomeDefaults;
    final sources = {
      CourseHubSource.schedule: _scheduleStatus,
      CourseHubSource.spocCourses: _catalogStatus,
    };
    List<FeatureDetail> details(FeatureId feature, CourseHubSource source) {
      final snap = feature == FeatureId.grades
          ? app.internalSnapshots[feature]!
          : defaults[feature]!;
      final policy = app.loginForm.routePolicy;
      if ((snap.evidence != null &&
              snap.evidence!.accountId != app.cacheAccountId) ||
          (snap.resolvedRoute != null &&
              policy != RoutePolicy.auto &&
              policy.name != snap.resolvedRoute!.name))
        return const [];
      sources[source] = CourseHubSourceStatus(switch (snap.status) {
        FeatureLoadStatus.idle => CourseHubSourceState.notLoaded,
        FeatureLoadStatus.loading =>
          snap.details.isEmpty
              ? CourseHubSourceState.loading
              : CourseHubSourceState.partial,
        FeatureLoadStatus.failure => CourseHubSourceState.failed,
        FeatureLoadStatus.stale => CourseHubSourceState.partial,
        _ =>
          snap.evidence?.complete == false || snap.pagination?.hasMore == true
              ? CourseHubSourceState.partial
              : CourseHubSourceState.ready,
      }, snap.error);
      return snap.details;
    }

    final termInfo = defaults[FeatureId.spoc]?.overview;
    value = buildCourseHub(
      termCode: _term,
      termName: termInfo is SpocTermOverview && termInfo.termCode == _term
          ? termInfo.termName
          : null,
      graduate: _graduate,
      now: DateTime.now(),
      weeks: _weeks,
      spocCourses: _catalog,
      overrides: _overrides,
      judgeLinksAvailable: _linksAvailable,
      spocAssignments: details(FeatureId.spoc, CourseHubSource.spocAssignments),
      judgeAssignments: details(
        FeatureId.judge,
        CourseHubSource.judgeAssignments,
      ),
      exams: details(FeatureId.exam, CourseHubSource.exams),
      grades: details(FeatureId.grades, CourseHubSource.grades),
      sources: sources,
    );
  }

  @override
  void dispose() {
    _closed = true;
    _localTicket++;
    _catalogTicket++;
    _timer?.cancel();
    _backend?.onAcademicIdentity = null;
    app.removeListener(_sync);
    super.dispose();
  }
}
