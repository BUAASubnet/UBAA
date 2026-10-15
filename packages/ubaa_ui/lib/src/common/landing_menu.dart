import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

bool uiHasLandingMenu(FeatureId feature) =>
    const {FeatureId.bykc, FeatureId.libbook, FeatureId.cgyy}.contains(feature);

String uiReadPageTitle(FeatureId feature, FeatureQuery? query, bool landing) {
  if (landing || query == null) return feature.title;
  return switch ((feature, query.view)) {
    (FeatureId.schedule, FeatureQueryView.scheduleWeek) =>
      query.week == null ? '周课表' : '第${query.week}周',
    (FeatureId.schedule, FeatureQueryView.scheduleToday) => '今日课程',
    (FeatureId.schedule, FeatureQueryView.scheduleTerms) => '选择学期',
    (FeatureId.schedule, FeatureQueryView.scheduleWeeks) => '选择教学周',
    (FeatureId.bykc, FeatureQueryView.summary) => '选择课程',
    (FeatureId.bykc, FeatureQueryView.bykcDetail) => '课程详情',
    (FeatureId.bykc, FeatureQueryView.bykcChosenCourses) => '我的课程',
    (FeatureId.bykc, FeatureQueryView.bykcStatistics) => '课程统计',
    (FeatureId.bykc, FeatureQueryView.bykcProfile) => '博雅资料',
    (FeatureId.cgyy, FeatureQueryView.cgyyOrders) => '我的预约',
    (FeatureId.cgyy, FeatureQueryView.cgyyOrderDetail) => '预约详情',
    (FeatureId.cgyy, FeatureQueryView.cgyyLockCode) => '查看密码',
    (FeatureId.cgyy, FeatureQueryView.cgyyPurposeTypes) => '用途类型',
    (FeatureId.cgyy, _) => '预约研讨室',
    (FeatureId.libbook, FeatureQueryView.libbookBookings) => '我的座位预约',
    (FeatureId.libbook, _) => '预约座位',
    (FeatureId.spoc, FeatureQueryView.spocDetail) ||
    (FeatureId.judge, FeatureQueryView.judgeDetail) => '作业详情',
    (FeatureId.judge, FeatureQueryView.judgeBatchDetails) => '所选作业详情',
    _ => feature.title,
  };
}

class FeatureLandingMenu extends StatelessWidget {
  const FeatureLandingMenu({required this.feature, required this.onOpen});
  final FeatureId feature;
  final Future<void> Function(FeatureReadNavigation) onOpen;

  @override
  Widget build(BuildContext context) {
    final entries = switch (feature) {
      FeatureId.bykc => [
        ('选择课程', Icons.list_alt, FeatureQueryView.summary),
        ('我的课程', Icons.menu_book, FeatureQueryView.bykcChosenCourses),
        ('课程统计', Icons.bar_chart, FeatureQueryView.bykcStatistics),
      ],
      FeatureId.libbook => [
        ('预约座位', Icons.event_seat, FeatureQueryView.summary),
        ('我的预约', Icons.history, FeatureQueryView.libbookBookings),
      ],
      FeatureId.cgyy => [
        ('预约研讨室', Icons.date_range, FeatureQueryView.summary),
        ('我的预约', Icons.history, FeatureQueryView.cgyyOrders),
        ('查看密码', Icons.lock_outline, FeatureQueryView.cgyyLockCode),
      ],
      _ => throw StateError('此领域没有子菜单'),
    };
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return GridView.builder(
          key: ValueKey(('feature-landing', feature)),
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth >= 900 ? 3 : 2,
            mainAxisExtent: 144 * scale.clamp(1.0, 2.0),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final item = entries[index];
            return Card(
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surfaceContainerHigh,
              child: InkWell(
                onTap: () => onOpen(
                  FeatureReadNavigation(
                    feature: feature,
                    query: FeatureQuery(view: item.$3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$2, size: 48, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        item.$1,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
