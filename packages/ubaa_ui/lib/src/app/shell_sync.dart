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

  /// 标题栏右侧的统一刷新状态：功能页、首页和“我的”各自给出刷新中与更新时间。
  Widget _buildSyncStatus(Future<void> Function()? refresh) {
    Widget status(
      Object key,
      bool busy,
      DateTime? updatedAt, {
      String? notice,
      VoidCallback? onShowDetails,
    }) => ListenableBuilder(
      listenable: _pageBusy,
      builder: (context, _) => UiSyncStatus(
        key: ValueKey(key),
        // 下拉刷新已有下拉指示器，期间标题栏不再重复转圈。
        // 页面内的首次读取只登记忙碌（LoadingPlaceholder），也在这里显示。
        busy:
            (busy || widget.connecting || _pageBusy.busy) &&
            _pulling == 0 &&
            !(key == 'home' && (widget.homeState?.offline ?? false)),
        updatedAt: updatedAt,
        notice: notice,
        onShowDetails: onShowDetails,
        onRefresh: refresh,
        refreshTooltip:
            _openedFeature == null ||
                (_openedFeature == FeatureId.schedule &&
                    widget.onSaveScheduleSemester != null)
            ? '刷新'
            : '刷新当前查询',
      ),
    );
    if (_openedFeature case final feature?) {
      return ValueListenableBuilder<(FeatureSnapshot, String)?>(
        valueListenable: _visiblePage,
        builder: (context, page, _) {
          final snapshot = page?.$1.feature == feature
              ? page!.$1
              : widget.snapshots[feature];
          return status(
            ('feature', feature),
            snapshot?.status == FeatureLoadStatus.loading &&
                !(snapshot?.refining ?? false),
            // 只有已保存数据时显示其读取时间，与“更新于”语义一致。
            snapshot?.updatedAt ?? snapshot?.evidence?.fetchedAt,
          );
        },
      );
    }
    if (_utilityPage == null && _selectedIndex == 0) {
      // App 汇总首页全部来源，含博雅、研讨室和当前展示日期课表。
      return status(
        'home',
        !(widget.homeState?.offline ?? false) &&
            (widget.homeState?.busy ?? false),
        widget.homeState?.updatedAt,
        notice: homeSyncNotice(widget.homeState),
        onShowDetails: widget.homeState == null
            ? null
            : () => showHomeSyncDetails(context, widget.homeState!),
      );
    }
    if (_onMeTab && widget.campusAccountService != null) {
      final o = _campusOverview;
      final metrics = o?.metrics.data;
      return status(
        'me',
        o != null &&
            (o.identity.loading || o.metrics.loading || o.network.loading),
        uiOldestUpdate([
          o?.identity.data?.fetchedAt,
          o?.network.data?.fetchedAt,
          for (final metric in [
            metrics?.cardBalance,
            metrics?.networkBalance,
            metrics?.unreadMail,
            metrics?.borrowedBooks,
            metrics?.cloudStorageRemaining,
          ])
            if (metric is CampusMetricValue) metric!.fetchedAt,
        ]),
      );
    }
    return status('other', false, null);
  }
}
