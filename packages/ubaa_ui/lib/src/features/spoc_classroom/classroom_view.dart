import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiStatePanel;
import '../../common/tag.dart' show UiTag, UiTagTone;
import '../../shared/text.dart' show uiNonBlank;
import '../../theme.dart' show UbaaTheme;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import 'classroom_format.dart';
import 'player_page.dart' show ClassroomPlayerPage;

/// 课堂：一门 SPOC 课程（精确 kcid）在智学北航的整学期节次。
///
/// 只读页面：直播中置顶，其余按教学周分组、新周在上；回放与直播可进入播放页。
class ClassroomView extends StatefulWidget {
  const ClassroomView({
    super.key,
    required this.access,
    required this.kcid,
    required this.courseName,
  });
  final SpocClassroomAccess access;
  final String kcid, courseName;

  @override
  State<ClassroomView> createState() => _ClassroomViewState();
}

class _ClassroomViewState extends State<ClassroomView> {
  ClassroomCatalog? _catalog;
  Object? _error;
  var _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final read = await widget.access.service.catalog(widget.kcid);
      if (!mounted || generation != _generation) return;
      setState(() {
        _catalog = read.data;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _open(ClassroomSessionSummary session) {
    final catalog = _catalog;
    if (catalog == null) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => ClassroomPlayerPage(
          access: widget.access,
          courseId: catalog.courseId,
          courseTitle: uiNonBlank(catalog.title) ?? widget.courseName,
          session: session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 4,
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontSize: 20,
        ),
        title: const Text('课堂'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    final catalog = _catalog;
    if (_loading && catalog == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && catalog == null) {
      final error = _error is UiError ? _error as UiError : null;
      return ListView(
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
        children: [
          _CourseHeader(title: widget.courseName),
          const SizedBox(height: 12),
          UiStatePanel(
            icon: Icons.smart_display_outlined,
            title: '课堂读取失败',
            detail: error?.message ?? '请稍后重试',
            error: error,
            action: '重试',
            onAction: _load,
          ),
        ],
      );
    }
    if (catalog == null) return const SizedBox.shrink();
    final live = [
      for (final s in catalog.sessions)
        if (s.status == ClassroomStatus.live) s,
    ];
    final groups = groupSessionsByWeek([
      for (final s in catalog.sessions)
        if (s.status != ClassroomStatus.live) s,
    ]);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey('spoc-classroom-sessions'),
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
        children: [
          _CourseHeader(
            title: uiNonBlank(catalog.title) ?? widget.courseName,
            term: uiNonBlank(catalog.termName),
            teachers: catalog.teachers,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _StaleBanner(onRetry: _load),
          ],
          for (final session in live) ...[
            const SizedBox(height: 12),
            _LiveCard(session: session, onOpen: () => _open(session)),
          ],
          if (catalog.sessions.isEmpty) ...[
            const SizedBox(height: 12),
            const UiStatePanel(
              icon: Icons.smart_display_outlined,
              title: '还没有课堂记录',
              detail: '老师开课后，直播和回放会显示在这里',
            ),
          ],
          for (final group in groups) ...[
            const SizedBox(height: 16),
            _WeekHeader(label: group.label, count: group.sessions.length),
            const SizedBox(height: 8),
            _SessionCard(sessions: group.sessions, onOpen: _open),
          ],
        ],
      ),
    );
  }
}

class _CourseHeader extends StatelessWidget {
  const _CourseHeader({
    required this.title,
    this.term,
    this.teachers = const [],
  });
  final String title;
  final String? term;
  final List<String> teachers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final meta = [?term, if (teachers.isNotEmpty) teachers.join('、')];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(meta.join(' · '), style: muted),
          ],
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          const Expanded(child: Text('刷新失败，显示的是上次读取的内容')),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 正在直播的节次：强调卡片，置顶。
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.session, required this.onOpen});
  final ClassroomSessionSummary session;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final place = [
      sessionTimeRange(session),
      ?uiNonBlank(session.room),
      ?uiNonBlank(session.lecturer),
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(color: colors.error.withValues(alpha: .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LiveBadge(),
                    const SizedBox(height: 6),
                    Text(
                      session.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(place.join(' · '), style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('进入直播'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 红点 + “直播中”：状态同时用文字、图标和颜色表达。
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '正在直播',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: colors.error),
        ),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '$label · $count 节',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.sessions, required this.onOpen});
  final List<ClassroomSessionSummary> sessions;
  final void Function(ClassroomSessionSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < sessions.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.outlineVariant),
            _SessionRow(session: sessions[i], onOpen: onOpen),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onOpen});
  final ClassroomSessionSummary session;
  final void Function(ClassroomSessionSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final playable = sessionPlayable(session.status);
    final start = sessionStart(session);
    final detail = [
      sessionTimeRange(session),
      ?uiNonBlank(session.room),
      ?uiNonBlank(session.lecturer),
    ];
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  '${start.month}/${start.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(weekdayLabel(start), style: muted),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sessionPeriodLabel(session),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: playable ? null : colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  detail.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusTag(status: session.status),
          if (playable)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            )
          else
            const SizedBox(width: 24),
        ],
      ),
    );
    final hint = sessionUnavailableHint(session.status);
    return Semantics(
      button: playable,
      child: InkWell(
        onTap: playable ? () => onOpen(session) : null,
        child: hint == null ? row : Tooltip(message: hint, child: row),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});
  final ClassroomStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    ClassroomStatus.replay => const UiTag(
      '回放',
      tone: UiTagTone.primary,
      icon: Icons.play_circle_outline,
    ),
    ClassroomStatus.live => const UiTag(
      '直播中',
      tone: UiTagTone.error,
      icon: Icons.sensors,
    ),
    ClassroomStatus.upcoming => const UiTag('未开始', icon: Icons.schedule),
    ClassroomStatus.noReplay => const UiTag('无回放'),
    ClassroomStatus.tencentMeeting => const UiTag('腾讯会议'),
    ClassroomStatus.other => const UiTag('不可播放'),
  };
}
