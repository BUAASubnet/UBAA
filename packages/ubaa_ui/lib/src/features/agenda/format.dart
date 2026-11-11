import 'package:ubaa_domain/ubaa_domain.dart';
import 'dart:ui' show Color;

Color? agendaColor(String? value) {
  if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value))
    return null;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

DateTime campusDate(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));
String agendaDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
const agendaWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// 「11月8日」，列表、日历与详情共用。
String agendaMonthDay(DateTime value) => '${value.month}月${value.day}日';

/// 「11月8日 周日」，列表分组标题与详情共用。
String agendaMonthDayWeek(DateTime value) =>
    '${agendaMonthDay(value)} 周${agendaWeekdays[value.weekday - 1]}';

/// 「09:50」，使用已换算到北京时间的值。
String agendaHm(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
AgendaTime agendaTime(DateTime value) => AgendaTime(
  rfc3339:
      '${agendaDate(value)}T${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00+08:00',
  timezone: 'Asia/Shanghai',
);
DateTime? agendaValue(AgendaTime? value) =>
    value == null ? null : campusDate(DateTime.parse(value.rfc3339));
String agendaTitle(AgendaEntry e) => e.local?.content.title ?? e.school!.title;
String agendaSource(AgendaEntry e) => e.local != null
    ? '我的'
    : switch (e.school!.navigation.feature) {
        AgendaFeature.schedule => '课程',
        AgendaFeature.exam => '考试',
        AgendaFeature.bykc => '博雅',
        AgendaFeature.spoc => 'SPOC作业',
        AgendaFeature.judge => '希冀作业',
        AgendaFeature.signin => '签到',
        AgendaFeature.cgyy => '研讨室',
        AgendaFeature.ygdk => '阳光打卡',
      };
String agendaWhen(AgendaEntry e) => switch (e.timing.kind) {
  AgendaTimingKind.undated => '无日期',
  AgendaTimingKind.allDay => '全天',
  AgendaTimingKind.deadline =>
    '${e.timing.due?.rfc3339.substring(11, 16) ?? '时间待定'} 截止',
  AgendaTimingKind.period => switch (e.timing.start) {
    null => '时间待定',
    final start =>
      '${start.rfc3339.substring(11, 16)} — ${e.timing.end?.rfc3339.substring(11, 16) ?? '结束时间待定'}',
  },
};
AgendaTime? recurrenceAt(AgendaOccurrence occurrence) =>
    occurrence.recurrenceId == 'undated'
    ? null
    : AgendaTime(rfc3339: occurrence.recurrenceId, timezone: 'Asia/Shanghai');
FeatureReadNavigation agendaNavigation(AgendaNavigation n) =>
    FeatureReadNavigation(
      feature: FeatureId.values.byName(n.feature.name),
      query: switch (n.feature) {
        AgendaFeature.schedule => FeatureQuery(
          view: FeatureQueryView.summary,
          term: n.term,
          week: n.week,
        ),
        AgendaFeature.bykc => FeatureQuery(
          view: FeatureQueryView.bykcDetail,
          courseId: '${n.bykcCourseId}',
        ),
        AgendaFeature.spoc => FeatureQuery(
          view: FeatureQueryView.spocDetail,
          assignmentId: n.assignmentId,
        ),
        AgendaFeature.judge => FeatureQuery(
          view: FeatureQueryView.judgeDetail,
          courseId: n.courseId,
          assignmentId: n.assignmentId,
        ),
        AgendaFeature.exam => FeatureQuery(
          view: FeatureQueryView.examArranged,
          term: n.term,
        ),
        AgendaFeature.signin => const FeatureQuery(
          view: FeatureQueryView.signinPending,
        ),
        AgendaFeature.cgyy => const FeatureQuery(
          view: FeatureQueryView.cgyyOrders,
        ),
        _ => const FeatureQuery(),
      },
    );

/// 本机日程入口所需的服务与状态由宿主一起投影。
final class AgendaAccess {
  const AgendaAccess({
    this.service,
    this.failure,
    this.term = '',
    this.onChanged,
    this.prepareSync,
    this.saveFile,
  });
  final AgendaService? service;
  final AgendaFailure? failure;
  final String term;
  final void Function()? onChanged;
  final AgendaSyncPrepare? prepareSync;
  final Future<String?> Function(AgendaExportResult, String, bool Function())?
  saveFile;
}

/// 「1-5周,7-13周[理论]」写成「1–5、7–13 周 · 理论」；认不出的格式原样返回。
String agendaWeeksLabel(String raw) {
  final match = RegExp(r'^(.*?)(?:\[([^\]]+)\])?$').firstMatch(raw.trim());
  if (match == null) return raw;
  final pieces = [
    for (final piece in match[1]!.split(RegExp(r'[,，]')))
      piece.trim().replaceFirst(RegExp(r'周$'), '').replaceAll('-', '–'),
  ];
  if (pieces.isEmpty ||
      !pieces.every((p) => RegExp(r'^\d+(–\d+)?[单双]?$').hasMatch(p))) {
    return raw;
  }
  final kind = match[2]?.trim();
  return '${pieces.join('、')} 周${kind == null || kind.isEmpty ? '' : ' · $kind'}';
}

/// 「葛宁[主讲],王五[辅讲]」写成「葛宁（主讲）、王五（辅讲）」。
String agendaTeacherLabel(String raw) => raw
    .split(RegExp(r'[,，]'))
    .map((name) => name.trim())
    .where((name) => name.isNotEmpty)
    .map(
      (name) =>
          name.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) => '（${m[1]}）'),
    )
    .join('、');
