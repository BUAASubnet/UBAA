import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/layout/connection_status.dart';
import '../../theme.dart';

AppBar uiShellHeader(
  BuildContext context, {
  required bool wide,
  required bool atRoot,
  required FeatureId? feature,
  required String rootTitle,
  required ValueListenable<(FeatureSnapshot, String)?> visiblePage,
  required ValueListenable<Map<FeatureId, Widget>> slots,
  required VoidCallback goBack,
  required VoidCallback selectTerm,
  required String? connectionStatus,
  required VoidCallback? onReconnect,
  required ValueChanged<BuildContext>? onCompleteLogin,
  required Widget syncStatus,
}) => AppBar(
  centerTitle: false,
  toolbarHeight: wide ? 72 : 64,
  // 分类根页用大标题；进入功能、详情等下一级后标题小一号，层级更清楚，
  // 也给右上角的校区切换与更新状态留出空间。
  titleTextStyle: atRoot
      ? null
      : Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 20),
  automaticallyImplyLeading: false,
  // 下一级页面的标题紧跟返回箭头。
  titleSpacing: !atRoot
      ? 4
      : wide
      ? UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width)
      : null,
  title: ValueListenableBuilder<(FeatureSnapshot, String)?>(
    valueListenable: visiblePage,
    builder: (context, page, _) => Text(
      feature == FeatureId.schedule
          ? '课表'
          : feature != null
          ? (page?.$1.feature == feature ? page!.$2 : feature.title)
          : rootTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ),
  leading: !atRoot
      ? IconButton(
          tooltip: '返回',
          onPressed: goBack,
          icon: const Icon(Icons.arrow_back),
        )
      : null,
  actions: <Widget>[
    if (connectionStatus != null || onCompleteLogin != null)
      UiConnectionStatusButton(
        status: connectionStatus,
        onReconnect: onReconnect,
        onCompleteLogin: onCompleteLogin,
      ),
    if (feature != null)
      ValueListenableBuilder<Map<FeatureId, Widget>>(
        valueListenable: slots,
        builder: (context, slots, _) =>
            slots[feature] ?? const SizedBox.shrink(),
      ),
    if (feature == FeatureId.schedule)
      // 文字按钮比日历图标更不易被误认为“选日期”。
      Tooltip(
        message: '选择学期',
        child: TextButton.icon(
          onPressed: selectTerm,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_drop_down),
          label: const Text('学期'),
        ),
      ),
    syncStatus,
  ],
);
