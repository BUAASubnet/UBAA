import '../write/actions.dart';
import 'catalog.dart';
import '../common/route.dart';

import 'presentation.dart';
import 'result.dart';
import '../agenda/school.dart';
import '../agenda/models.dart';
import 'schedule/home.dart';

import 'read_navigation.dart';

/// 首页额外读取只允许旧版已有的三类来源。
enum HomeSupplement { bykcChosen, cgyyOrders, currentWeek }

/// 首页提醒只使用公开读结果；不能由时间或进度授予学校写入资格。
final class HomeTodo {
  const HomeTodo({
    required this.id,
    required this.feature,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.timeLabel,
    required this.sortTime,
    this.soon = false,
    this.navigation,
    this.signinAction,
    this.signin,
    this.deadline,
    this.startsAt,
    this.endsAt,
    this.local = false,
    this.color,
  });
  final String id, title, subtitle, statusLabel, timeLabel;
  final FeatureId feature;
  final DateTime sortTime;
  final DateTime? deadline, startsAt, endsAt;
  final bool local;

  /// 自建事项的颜色，格式为 #RRGGBB；学校事项由界面按来源配色。
  final String? color;

  HomeTodo withoutSigninAction() => HomeTodo(
    id: id,
    feature: feature,
    title: title,
    subtitle: subtitle,
    statusLabel: statusLabel,
    timeLabel: timeLabel,
    sortTime: sortTime,
    navigation: navigation,
    signin: switch (signin) {
      final SigninPresentation course when course.signStatus == 1 =>
        SigninPresentation(
          courseId: course.courseId,
          classBeginTime: course.classBeginTime,
          classEndTime: course.classEndTime,
          signStatus: 1,
        ),
      _ => null,
    },
    deadline: deadline,
    startsAt: startsAt,
    endsAt: endsAt,
    soon: soon,
    local: local,
    color: color,
  );
  final bool soon;

  final FeatureReadNavigation? navigation;
  final SigninPerformAction? signinAction;
  final SigninPresentation? signin;
}

String _clockHome(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _formatHomeTime(DateTime? value) => value == null
    ? '时间待定'
    : '${value.month}月${value.day}日 ${_clockHome(value)}';
String _relativeHomeTime(DateTime value, DateTime now) {
  final date = DateTime.utc(value.year, value.month, value.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final delta = date.difference(today).inDays;
  final prefix = switch (delta) {
    0 => '今天',
    1 => '明天',
    _ => null,
  };
  return prefix == null
      ? _formatHomeTime(value)
      : '$prefix ${_clockHome(value)}';
}

String _homeRange(DateTime? start, DateTime? end, DateTime now) {
  if (start == null || end == null) return '开始 ${_formatHomeTime(start)}';
  final sameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  return '${_relativeHomeTime(start, now)}–${sameDay ? _clockHome(end) : _relativeHomeTime(end, now)}';
}

/// 本地提醒偏好与已观察到的达标记忆；不表示学校提交成功。
final class YgdkReminderSettings {
  const YgdkReminderSettings({
    this.enabled = true,
    this.manualEnabled,
    this.weekDoneKey,
    this.termDoneKey,
  });
  final bool enabled;

  /// 用户手动选择优先于课表决定的默认值。
  final bool? manualEnabled;
  final String? weekDoneKey, termDoneKey;
  YgdkReminderSettings copyWith({
    bool? enabled,
    bool? manualEnabled,
    String? weekDoneKey,
    String? termDoneKey,
  }) => YgdkReminderSettings(
    enabled: enabled ?? this.enabled,
    manualEnabled: manualEnabled ?? this.manualEnabled,
    weekDoneKey: weekDoneKey ?? this.weekDoneKey,
    termDoneKey: termDoneKey ?? this.termDoneKey,
  );
}

/// 首页只提交已经取得的 typed 读结果；纯时间刷新不会请求学校。
final class HomeTodoRequest {
  HomeTodoRequest({
    required Map<FeatureId, FeatureSnapshot> snapshots,
    required this.now,
    this.accountId,
    this.currentWeek,
    this.currentWeekRoute,
    this.reminder = const YgdkReminderSettings(),
  }) : snapshots = Map.unmodifiable(snapshots);
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final DateTime now;
  final String? accountId;
  final WeekPresentation? currentWeek;
  final ConnectionMode? currentWeekRoute;
  final YgdkReminderSettings reminder;
}

final class HomeTodoProjection {
  HomeTodoProjection(List<HomeTodo> todos, {this.overlayFailure})
    : todos = List.unmodifiable(todos);
  final List<HomeTodo> todos;
  final AgendaFailure? overlayFailure;
}

abstract interface class HomeTodoBackend {
  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request);
}

typedef HomeTodoReader =
    Future<HomeTodoProjection> Function(HomeTodoRequest request);

/// 这里只格式化 Core 已筛选、排序和判定紧迫程度的条目。
HomeTodo formatHomeTodo(
  AgendaEntry entry, {
  required DateTime now,
  FeatureReadNavigation? navigation,
  SigninPerformAction? signinAction,
  SigninPresentation? signin,
}) {
  if (entry.local case final local?) {
    final start = local.content.start?.rfc3339;
    final end = local.content.end?.rfc3339;
    final due = local.content.due?.rfc3339;
    final startTime = start == null
        ? null
        : homeCampusTime(DateTime.parse(start));
    final endTime = end == null ? null : homeCampusTime(DateTime.parse(end));
    final dueTime = due == null ? null : homeCampusTime(DateTime.parse(due));
    final label = dueTime != null
        ? '${_relativeHomeTime(dueTime, now)} 截止'
        : _homeRange(startTime, endTime, now);
    return HomeTodo(
      id: 'local:${local.itemId}:${local.recurrenceId}',
      feature: FeatureId.schedule,
      title: local.content.title,
      subtitle: local.content.location ?? '我的日程',
      statusLabel: '我的日程',
      timeLabel: label,
      sortTime: startTime ?? dueTime ?? now,
      deadline: dueTime,
      startsAt: startTime,
      endsAt: endTime,
      soon: entry.soon,
      local: true,
      color: local.content.color,
    );
  }
  final item = entry.school!;
  DateTime? display(String? raw) =>
      raw == null ? null : homeCampusTime(DateTime.parse(raw));
  final start = display(entry.timing.start?.rfc3339),
      end = display(entry.timing.end?.rfc3339),
      due = display(entry.timing.due?.rfc3339);
  final day = entry.timing.from == null
      ? null
      : DateTime.parse(entry.timing.from!);
  final label = due != null
      ? '${_relativeHomeTime(due, now)} 截止'
      : item.navigation.feature == AgendaFeature.signin &&
            start != null &&
            end != null
      ? '${_clockHome(start)}–${_clockHome(end)}'
      : start == null && item.navigation.feature == AgendaFeature.exam
      ? '${(day ?? homeCampusTime(DateTime.parse(entry.sortTime!.rfc3339))).month}月${(day ?? homeCampusTime(DateTime.parse(entry.sortTime!.rfc3339))).day}日 · 时间待定'
      : _homeRange(start, end, now);
  return HomeTodo(
    id: '${item.key.source}:${item.key.upstreamId}',
    feature: FeatureId.values.byName(item.key.source),
    title: item.title,
    subtitle: item.subtitle,
    statusLabel: item.statusLabel,
    timeLabel: label,
    sortTime: display(entry.sortTime!.rfc3339)!,
    deadline: due,
    startsAt: start,
    endsAt: end,
    soon: entry.soon,
    navigation: navigation,
    signinAction: signinAction,
    signin: signin,
  );
}
