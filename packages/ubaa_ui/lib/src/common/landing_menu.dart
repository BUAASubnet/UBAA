import '../theme.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 所有功能都已改为进入即显示第一页；保留入口供导航判断。
bool uiHasLandingMenu(FeatureId feature) => false;

/// 博雅、图书馆与研讨室不再有二级菜单：进入即显示第一页，顶部分段切换同级页面。
List<(String, FeatureQueryView)> uiFeatureTabs(FeatureId feature) =>
    switch (feature) {
      FeatureId.bykc => const [
        ('选课', FeatureQueryView.summary),
        ('已选', FeatureQueryView.bykcChosenCourses),
        ('统计', FeatureQueryView.bykcStatistics),
      ],
      FeatureId.libbook => const [
        ('预约座位', FeatureQueryView.summary),
        ('我的预约', FeatureQueryView.libbookBookings),
      ],
      FeatureId.cgyy => const [
        ('预约', FeatureQueryView.summary),
        ('我的预约', FeatureQueryView.cgyyOrders),
      ],
      _ => const [],
    };

/// 页面内部读取（图书馆的楼层、分区、座位，研讨室的日表）仍属于第一个分段。
FeatureQueryView uiFeatureTabView(FeatureId feature, FeatureQuery? query) {
  final view = query?.view ?? FeatureQueryView.summary;
  if (feature == FeatureId.libbook &&
      view != FeatureQueryView.libbookBookings) {
    return FeatureQueryView.summary;
  }
  if (feature == FeatureId.cgyy && view == FeatureQueryView.cgyyDayInfo) {
    return FeatureQueryView.summary;
  }
  return view;
}

/// 分段切换只出现在同级页面的根层（不含课程详情等下一层）。
bool uiShowsFeatureTabs(FeatureId feature, FeatureQuery? query) {
  final view = uiFeatureTabView(feature, query);
  return uiFeatureTabs(feature).any((tab) => tab.$2 == view) &&
      query?.courseId == null;
}

class FeatureTabsBar extends StatelessWidget {
  const FeatureTabsBar({
    required this.feature,
    required this.query,
    required this.onSelect,
  });
  final FeatureId feature;
  final FeatureQuery? query;
  final ValueChanged<FeatureQueryView> onSelect;

  @override
  Widget build(BuildContext context) {
    final current = uiFeatureTabView(feature, query);
    final tabs = SegmentedButton<FeatureQueryView>(
      key: ValueKey(('feature-tabs', feature)),
      showSelectedIcon: false,
      segments: [
        for (final tab in uiFeatureTabs(feature))
          ButtonSegment(value: tab.$2, label: Text(tab.$1)),
      ],
      selected: {current},
      onSelectionChanged: (value) {
        if (value.single != current) onSelect(value.single);
      },
    );
    return Padding(
      padding: UbaaTheme.pageInsets(context, top: 8, bottom: 4),
      child: feature == FeatureId.cgyy
          // 研讨室门锁密码是低频动作，放在分段右侧而不是单独一级菜单。
          ? Row(
              children: [
                Expanded(child: tabs),
                const SizedBox(width: 8),
                IconButton.outlined(
                  key: const ValueKey('cgyy-lock-code'),
                  tooltip: '查看密码',
                  onPressed: () => onSelect(FeatureQueryView.cgyyLockCode),
                  icon: const Icon(Icons.lock_outline),
                ),
              ],
            )
          : SizedBox(width: double.infinity, child: tabs),
    );
  }
}

String uiReadPageTitle(FeatureId feature, FeatureQuery? query, bool landing) {
  if (landing || query == null) return feature.title;
  return switch ((feature, query.view)) {
    (FeatureId.schedule, FeatureQueryView.scheduleWeek) =>
      query.week == null ? '周课表' : '第${query.week}周',
    (FeatureId.schedule, FeatureQueryView.scheduleToday) => '今日课程',
    (FeatureId.schedule, FeatureQueryView.scheduleTerms) => '选择学期',
    (FeatureId.schedule, FeatureQueryView.scheduleWeeks) => '选择教学周',
    (FeatureId.bykc, FeatureQueryView.bykcDetail) => '课程详情',
    (FeatureId.bykc, FeatureQueryView.bykcChosenCourses)
        when query.courseId != null =>
      '课程详情',
    (FeatureId.bykc, FeatureQueryView.bykcProfile) => '博雅资料',
    (FeatureId.cgyy, FeatureQueryView.cgyyOrderDetail) => '预约详情',
    (FeatureId.cgyy, FeatureQueryView.cgyyLockCode) => '查看密码',
    (FeatureId.cgyy, FeatureQueryView.cgyyPurposeTypes) => '用途类型',
    (FeatureId.spoc, FeatureQueryView.spocDetail) ||
    (FeatureId.judge, FeatureQueryView.judgeDetail) => '作业详情',
    (FeatureId.judge, FeatureQueryView.judgeBatchDetails) => '所选作业详情',
    _ => feature.title,
  };
}
