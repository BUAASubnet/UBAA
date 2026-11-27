part of 'shell.dart';

extension UbaaShellSync on _UbaaMainShellState {
  CampusAccountOverview? get _campusOverview => _campusLoader.overview;
  bool get _onMeTab =>
      _utilityPage == null &&
      _openedFeature == null &&
      _selectedIndex == UiDestination.me.index;
  void _resetCampusAccount({bool keepContent = false}) =>
      _campusLoader.bind(widget.campusAccountService, keepContent: keepContent);
  void _ensureCampusAccountLoaded() {
    _campusLoader.ensure(online: !widget.connecting);
  }

  Future<void> _refreshCampusAccount() =>
      widget.connecting ? Future.value() : _campusLoader.refresh();

  Widget _buildSyncStatus(Future<void> Function()? refresh) => shellSyncStatus(
    context,
    pageBusy: _pageBusy,
    connecting: widget.connecting,
    pulling: _pulling != 0,
    home: widget.homeState,
    featureId: _openedFeature,
    canSaveSemester: widget.onSaveScheduleSemester != null,
    visiblePage: _visiblePage,
    snapshots: widget.snapshots,
    showHome: _utilityPage == null && _selectedIndex == 0,
    showCampus: _onMeTab && widget.campusAccountService != null,
    campus: _campusOverview,
    refresh: refresh,
  );
}
