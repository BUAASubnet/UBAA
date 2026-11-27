import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/loading.dart';
import '../../shared/sync_status.dart';
import '../../features/home/shell_helpers.dart';

Widget shellSyncStatus(
  BuildContext context, {
  required UiBusyRegistry pageBusy,
  required bool connecting,
  required bool pulling,
  required HomeState? home,
  required FeatureId? featureId,
  required bool canSaveSemester,
  required ValueListenable<(FeatureSnapshot, String)?> visiblePage,
  required Map<FeatureId, FeatureSnapshot> snapshots,
  required bool showHome,
  required bool showCampus,
  required CampusAccountOverview? campus,
  required Future<void> Function()? refresh,
}) {
  Widget status(
    Object key,
    bool busy,
    DateTime? updatedAt, {
    String? notice,
    VoidCallback? onShowDetails,
  }) => ListenableBuilder(
    listenable: pageBusy,
    builder: (context, _) => UiSyncStatus(
      key: ValueKey(key),
      // 下拉刷新已有下拉指示器，期间标题栏不再重复转圈。
      // 页面内的首次读取只登记忙碌（LoadingPlaceholder），也在这里显示。
      busy:
          (busy || connecting || pageBusy.busy) &&
          !pulling &&
          !(key == 'home' && (home?.offline ?? false)),
      updatedAt: updatedAt,
      notice: notice,
      onShowDetails: onShowDetails,
      onRefresh: refresh,
      refreshTooltip:
          featureId == null ||
              (featureId == FeatureId.schedule && canSaveSemester)
          ? '刷新'
          : '刷新当前查询',
    ),
  );
  if (featureId case final feature?) {
    return ValueListenableBuilder<(FeatureSnapshot, String)?>(
      valueListenable: visiblePage,
      builder: (context, page, _) {
        final snapshot = page?.$1.feature == feature
            ? page!.$1
            : snapshots[feature];
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
  if (showHome) {
    // App 汇总首页全部来源，含博雅、研讨室和当前展示日期课表。
    return status(
      'home',
      !(home?.offline ?? false) && (home?.busy ?? false),
      home?.updatedAt,
      notice: homeSyncNotice(home),
      onShowDetails: home == null
          ? null
          : () => showHomeSyncDetails(context, home),
    );
  }
  if (showCampus) {
    final o = campus;
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
