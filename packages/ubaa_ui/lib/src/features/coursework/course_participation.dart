import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../../shared/dialogs/sheet.dart';
import '../../shared/text.dart' show uiHiddenAcademicField;
import '../../shared/when.dart'
    show uiCampusNow, uiClock, uiParseCampusTime, uiShortRange;
import '../../theme.dart' show UbaaTheme;
import '../../common/tag.dart';
import 'signin_qr_sheet.dart' show showSigninQrSheet;

bool uiSupportsParticipationContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.signin => detail.presentation is SigninPresentation,
    FeatureId.evaluation => detail.presentation is EvaluationCoursePresentation,
    _ => false,
  },
);

class CourseParticipationContent extends StatelessWidget {
  const CourseParticipationContent({
    required this.feature,
    required this.details,
    required this.evaluationRow,
    this.onSignin,
    this.writesEnabled = true,
    this.onFetchSigninQr,
    this.onSaveSigninQr,
    this.onCheckSigninStatus,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) evaluationRow;
  final SigninStarter? onSignin;
  final bool writesEnabled;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;
  @override
  Widget build(BuildContext context) => feature == FeatureId.evaluation
      ? _EvaluationList(details: details, row: evaluationRow)
      : _SigninList(
          details: details,
          onSignin: onSignin,
          writesEnabled: writesEnabled,
          onFetchSigninQr: onFetchSigninQr,
          onSaveSigninQr: onSaveSigninQr,
          onCheckSigninStatus: onCheckSigninStatus,
        );
}

/// 二维码：课前 10 分钟到下课。
const _qrLead = Duration(minutes: 10);

/// 直接签到：课前 5 分钟到上课后 30 分钟。
const _submitLead = Duration(minutes: 5);
const _submitAfterBegin = Duration(minutes: 30);

@visibleForTesting
enum SigninPhase { open, upcoming, ended, unknown }

/// [phase] 按二维码时间窗；[submitOpen] 为此刻能否直接签到，
/// [submitOpensAt] 为直接签到开始时间。
@visibleForTesting
({
  SigninPhase phase,
  DateTime? opensAt,
  DateTime? submitOpensAt,
  bool submitOpen,
})
signinPhase(SigninPresentation p, DateTime now) {
  final begin = uiParseCampusTime(p.classBeginTime, day: now);
  final end = uiParseCampusTime(p.classEndTime, day: now);
  if (begin == null || end == null) {
    return (
      phase: SigninPhase.unknown,
      opensAt: null,
      submitOpensAt: null,
      submitOpen: false,
    );
  }
  final opens = begin.subtract(_qrLead);
  final submitOpens = begin.subtract(_submitLead);
  final submitCloses = begin.add(_submitAfterBegin);
  final phase = now.isBefore(opens)
      ? SigninPhase.upcoming
      : now.isBefore(end)
      ? SigninPhase.open
      : SigninPhase.ended;
  return (
    phase: phase,
    opensAt: opens,
    submitOpensAt: submitOpens,
    submitOpen:
        phase == SigninPhase.open &&
        !now.isBefore(submitOpens) &&
        now.isBefore(submitCloses),
  );
}

class _SigninList extends StatefulWidget {
  const _SigninList({
    required this.details,
    required this.onSignin,
    required this.writesEnabled,
    required this.onFetchSigninQr,
    required this.onSaveSigninQr,
    required this.onCheckSigninStatus,
  });
  final List<FeatureDetail> details;
  final SigninStarter? onSignin;
  final bool writesEnabled;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;
  @override
  State<_SigninList> createState() => _SigninListState();
}

class _SigninListState extends State<_SigninList> {
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tick?.cancel();
    _tick = null;
    if (!TickerMode.of(context)) return;
    // 签到窗口按分钟变化，定时刷新按钮与状态。
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = uiCampusNow();
    int rank(FeatureDetail d) {
      final p = d.presentation! as SigninPresentation;
      return switch (signinPhase(p, now).phase) {
        SigninPhase.open => p.signStatus == 1 ? 1 : 0,
        SigninPhase.unknown => 1,
        SigninPhase.upcoming => 2,
        SigninPhase.ended => 3,
      };
    }

    final ordered =
        [for (final (i, d) in widget.details.indexed) (i, d, rank(d))]
          ..sort((a, b) {
            final r = a.$3.compareTo(b.$3);
            return r != 0 ? r : a.$1.compareTo(b.$1);
          });
    return ListView.separated(
      padding: UbaaTheme.pageInsets(context, top: 8),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _SigninCourseCard(
        detail: ordered[index].$2,
        now: now,
        onSignin: widget.onSignin,
        writesEnabled: widget.writesEnabled,
        onFetchSigninQr: widget.onFetchSigninQr,
        onSaveSigninQr: widget.onSaveSigninQr,
        onCheckSigninStatus: widget.onCheckSigninStatus,
      ),
    );
  }
}

class _SigninCourseCard extends StatelessWidget {
  const _SigninCourseCard({
    required this.detail,
    required this.now,
    required this.onSignin,
    required this.writesEnabled,
    required this.onFetchSigninQr,
    required this.onSaveSigninQr,
    required this.onCheckSigninStatus,
  });
  final FeatureDetail detail;
  final DateTime now;
  final SigninStarter? onSignin;
  final bool writesEnabled;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    final action = detail.action<SigninPerformAction>();
    final done = p.signStatus == 1;
    final scheduleId = action?.scheduleId.trim() ?? '';
    final allowed =
        action?.eligibility == ActionEligibility.allowed &&
        scheduleId.isNotEmpty;
    final window = signinPhase(p, now);
    final canSignNow = !done && window.phase == SigninPhase.open;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fetchQr = onFetchSigninQr;
    final inWindow = window.phase == SigninPhase.open;
    final canShowQr = inWindow && fetchQr != null && scheduleId.isNotEmpty;
    void openQr() {
      final check = onCheckSigninStatus;
      showSigninQrSheet(
        context,
        courseTitle: detail.title,
        fetch: (offset) => fetchQr!(scheduleId, offset),
        save: onSaveSigninQr,
        // 已签到再打开（如给同学扫）时不自动关闭。
        closeWhenSigned: !done && check != null
            ? () => check(scheduleId)
            : null,
      );
    }

    final qrButton = IconButton(
      onPressed: openQr,
      tooltip: '签到二维码',
      icon: const Icon(Icons.qr_code_2_rounded),
    );
    final signButton = onSignin == null || action == null
        ? null
        : window.submitOpen
        ? FilledButton(
            onPressed: writesEnabled && allowed
                ? () => onSignin!(action)
                : null,
            child: const Text('签到'),
          )
        // 课前 10～5 分钟只能扫码，提示直接签到的开始时间；上课 30 分钟后只剩二维码。
        : switch (window.submitOpensAt) {
            final opens? when now.isBefore(opens) => UiTag(
              '${uiClock(opens)} 起可签',
            ),
            _ => null,
          };
    // 签到窗口内：二维码（给智慧教室扫码）与直接签到并列。
    final Widget? trailing = done && canShowQr
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const UiTag('已签到', tone: UiTagTone.primary),
              const SizedBox(width: 4),
              qrButton,
            ],
          )
        : done
        ? const UiTag('已签到', tone: UiTagTone.primary)
        : canSignNow && (canShowQr || signButton != null)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canShowQr) qrButton,
              if (canShowQr && signButton != null) const SizedBox(width: 4),
              ?signButton,
            ],
          )
        : switch (window.phase) {
            SigninPhase.upcoming => UiTag('${uiClock(window.opensAt!)} 起可签'),
            SigninPhase.ended => const UiTag('未签到'),
            _ => null,
          };
    final time =
        uiShortRange(
          p.classBeginTime,
          p.classEndTime,
          withDate: false,
          now: now,
        ) ??
        '时间未提供';
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(
          color: canSignNow && !done ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: '课程详情',
        child: InkWell(
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: window.phase == SigninPhase.ended && !done
                                  ? scheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            time,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    final state = switch (p.signStatus) {
      0 => '未签到',
      1 => '已签到',
      _ => null,
    };
    return showUiSheet<void>(
      context,
      builder: (context) => UiSheetBody(
        title: detail.title,
        subtitle: state,
        children: [
          UiInfoRow(
            icon: Icons.schedule_outlined,
            text: uiShortRange(p.classBeginTime, p.classEndTime) ?? '时间未提供',
          ),
          for (final field in detail.fields)
            if (!uiHiddenAcademicField(field.label) &&
                field.value.trim().isNotEmpty)
              UiInfoRow(
                icon: Icons.info_outline,
                text: field.value,
                label: field.label,
              ),
        ],
      ),
    );
  }
}

/// 待评在前；已评默认收起，减少需要滚动的内容。
class _EvaluationList extends StatelessWidget {
  const _EvaluationList({required this.details, required this.row});
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) row;
  bool _done(FeatureDetail d) =>
      (d.presentation! as EvaluationCoursePresentation).isEvaluated;
  @override
  Widget build(BuildContext context) {
    final pending = details.where((d) => !_done(d)).toList();
    final done = details.where(_done).toList();
    return ListView(
      padding: UbaaTheme.pageInsets(context, top: 8),
      children: [
        for (final detail in pending) row(detail),
        if (done.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const PageStorageKey('evaluation-done'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: pending.isEmpty,
              title: Text('已评 ${done.length} 门'),
              children: [for (final detail in done) row(detail)],
            ),
          ),
      ],
    );
  }
}
