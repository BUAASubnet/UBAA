import 'dart:async';
import 'section.dart';
import '../theme.dart';
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
    return ListView(
      key: ValueKey(('feature-landing', feature)),
      padding: EdgeInsets.all(
        UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
      ),
      children: [
        for (final item in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: UiEntryCard(
              title: item.$1,
              icon: item.$2,
              onTap: () => onOpen(
                FeatureReadNavigation(
                  feature: feature,
                  query: FeatureQuery(view: item.$3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
