part of '../shell.dart';

/// “我的”页面的读取：先显示本机快照，再在后台在线刷新。
///
/// 三组数据分别更新；刷新保留旧值直至新结果到达，失败时旧值与错误同时显示。
/// 再次进入时距上次成功刷新超过 [_campusStaleAfter] 才后台刷新。
extension UbaaShellCampusAccount on _UbaaMainShellState {
  bool get _onMeTab =>
      _utilityPage == null &&
      _openedFeature == null &&
      _selectedIndex == UiDestination.me.index;

  static const _campusStaleAfter = Duration(minutes: 5);

  /// 服务绑定变化（账号、会话或路线代次）后丢弃旧结果。
  void _resetCampusAccount() {
    _campusRevision++;
    _campusOverview = null;
    _campusRefresh = null;
    _campusRefreshedAt = null;
  }

  void _ensureCampusAccountLoaded() {
    final service = widget.campusAccountService;
    if (service == null || _campusRefresh != null) return;
    if (_campusOverview == null) {
      unawaited(_loadCampusAccount(service));
      return;
    }
    final refreshedAt = _campusRefreshedAt;
    if (refreshedAt == null ||
        (widget.homeClock ?? clock).now().difference(refreshedAt) >=
            _campusStaleAfter) {
      unawaited(_refreshCampusAccount());
    }
  }

  /// 首次进入：先显示本机快照，再在线刷新。快照读取失败按无快照处理。
  Future<void> _loadCampusAccount(CampusAccountService service) {
    final revision = _campusRevision;
    _setCampusOverview(
      const CampusAccountOverview(
        identity: CampusSection.loading(),
        metrics: CampusSection.loading(),
        network: CampusSection.loading(),
      ),
    );
    late final Future<void> load;
    load =
        (() async {
          CampusAccountSnapshot snapshot;
          try {
            snapshot = await service.cached();
          } on Object {
            snapshot = const CampusAccountSnapshot();
          }
          if (!mounted ||
              revision != _campusRevision ||
              !identical(service, widget.campusAccountService)) {
            return;
          }
          _setCampusOverview(
            CampusAccountOverview(
              identity: CampusSection.loading(snapshot.identity),
              metrics: CampusSection.loading(snapshot.metrics),
              network: CampusSection.loading(snapshot.network),
            ),
          );
          if (identical(_campusRefresh, load)) _campusRefresh = null;
          await _refreshCampusAccount();
        })().whenComplete(() {
          if (identical(_campusRefresh, load)) _campusRefresh = null;
        });
    _campusRefresh = load;
    return load;
  }

  Future<void> _refreshCampusAccount() {
    final pending = _campusRefresh;
    if (pending != null) return pending;
    final service = widget.campusAccountService;
    if (service == null) return Future<void>.value();
    final revision = _campusRevision;
    final previous = _campusOverview ?? const CampusAccountOverview();
    _setCampusOverview(
      CampusAccountOverview(
        identity: CampusSection.loading(previous.identity.data),
        metrics: CampusSection.loading(previous.metrics.data),
        network: CampusSection.loading(previous.network.data),
      ),
    );

    bool current() =>
        mounted &&
        revision == _campusRevision &&
        identical(service, widget.campusAccountService);

    Future<void> load<T>(
      Future<T> Function() read,
      CampusAccountOverview Function(
        CampusAccountOverview overview,
        CampusSection<T> section,
      )
      apply,
      T? Function(CampusAccountOverview overview) old,
    ) async {
      CampusSection<T> section;
      try {
        section = CampusSection.ready(await read());
      } on UiError catch (error) {
        if (!current()) return;
        section = CampusSection.failed(error.message, old(_campusOverview!));
      } on Object {
        if (!current()) return;
        section = CampusSection.failed('读取失败，请稍后重试。', old(_campusOverview!));
      }
      if (!current()) return;
      _setCampusOverview(apply(_campusOverview!, section));
    }

    late final Future<void> refresh;
    refresh =
        Future.wait([
              load<PortalIdentity>(
                service.identity,
                (o, s) => CampusAccountOverview(
                  identity: s,
                  metrics: o.metrics,
                  network: o.network,
                ),
                (o) => o.identity.data,
              ),
              load<CampusMetrics>(
                service.metrics,
                (o, s) => CampusAccountOverview(
                  identity: o.identity,
                  metrics: s,
                  network: o.network,
                ),
                (o) => o.metrics.data,
              ),
              load<NetworkUsage>(
                service.networkUsage,
                (o, s) => CampusAccountOverview(
                  identity: o.identity,
                  metrics: o.metrics,
                  network: s,
                ),
                (o) => o.network.data,
              ),
            ])
            .then((_) {
              final o = _campusOverview;
              // 任一组失败时不记时间，下次进入会再试。
              if (current() &&
                  o != null &&
                  o.identity.error == null &&
                  o.metrics.error == null &&
                  o.network.error == null) {
                _campusRefreshedAt = (widget.homeClock ?? clock).now();
              }
            })
            .whenComplete(() {
              if (identical(_campusRefresh, refresh)) _campusRefresh = null;
            });
    _campusRefresh = refresh;
    return refresh;
  }
}
