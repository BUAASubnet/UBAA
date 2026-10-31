part of 'shell.dart';

extension UbaaShellSync on _UbaaMainShellState {
  /// 标题栏右侧的统一刷新状态：功能页、首页和“我的”各自给出刷新中与更新时间。
  Widget _buildSyncStatus(Future<void> Function()? refresh) {
    Widget status(Object key, bool busy, DateTime? updatedAt) => UiSyncStatus(
      key: ValueKey(key),
      // 下拉刷新已有下拉指示器，期间标题栏不再重复转圈。
      busy: (busy || widget.connecting) && _pulling == 0,
      updatedAt: updatedAt,
      onRefresh: refresh,
      refreshTooltip:
          _openedFeature == null ||
              (_openedFeature == FeatureId.schedule &&
                  widget.onSaveScheduleSemester != null)
          ? '刷新'
          : '刷新当前查询',
    );
    DateTime? oldest(Iterable<DateTime?> times) {
      DateTime? result;
      for (final time in times) {
        if (time != null && (result == null || time.isBefore(result))) {
          result = time;
        }
      }
      return result;
    }

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
            snapshot?.updatedAt,
          );
        },
      );
    }
    if (_utilityPage == null && _selectedIndex == 0) {
      // 首页状态由 HomeView 按其显示的全部来源上报，含博雅与研讨室补充来源。
      return status('home', _homeSync.$1, _homeSync.$2);
    }
    if (_onMeTab && widget.campusAccountService != null) {
      final o = _campusOverview;
      final metrics = o?.metrics.data;
      return status(
        'me',
        o != null &&
            (o.identity.loading || o.metrics.loading || o.network.loading),
        oldest([
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
