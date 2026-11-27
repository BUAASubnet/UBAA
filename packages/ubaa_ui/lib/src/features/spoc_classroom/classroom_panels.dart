import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../common/state_panel.dart' show UiStatePanel;
import '../../common/tag.dart' show UiTag;
import '../../theme.dart' show UbaaTheme;
import 'classroom_format.dart' show mediaClock;

/// 播放页侧栏 / 下方页签共用的加载状态：每个页签独立加载、独立重试。
class ClassroomLoad<T> {
  ClassroomLoad(this._loader);
  final Future<T> Function() _loader;
  final ValueNotifier<AsyncSnapshot<T>> state = ValueNotifier(
    const AsyncSnapshot.nothing(),
  );
  var _started = false;
  int _generation = 0;

  void ensure() {
    if (_started) return;
    _started = true;
    reload();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    state.value = const AsyncSnapshot.waiting();
    try {
      final data = await _loader();
      if (generation == _generation) {
        state.value = AsyncSnapshot.withData(ConnectionState.done, data);
      }
    } on Object catch (error, stack) {
      if (generation == _generation) {
        state.value = AsyncSnapshot.withError(
          ConnectionState.done,
          error,
          stack,
        );
      }
    }
  }

  void dispose() {
    _generation++;
    state.dispose();
  }
}

class _LoadView<T> extends StatelessWidget {
  const _LoadView({
    required this.load,
    required this.builder,
    required this.failureTitle,
  });
  final ClassroomLoad<T> load;
  final Widget Function(BuildContext, T) builder;
  final String failureTitle;

  @override
  Widget build(BuildContext context) {
    load.ensure();
    return ValueListenableBuilder<AsyncSnapshot<T>>(
      valueListenable: load.state,
      builder: (context, snapshot, _) {
        if (snapshot.hasData) return builder(context, snapshot.data as T);
        if (snapshot.hasError) {
          final error = snapshot.error is UiError
              ? snapshot.error as UiError
              : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              UiStatePanel(
                compact: true,
                icon: Icons.cloud_off,
                title: failureTitle,
                detail: error?.message ?? '请稍后重试',
                error: error,
                action: '重试',
                onAction: load.reload,
              ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

Widget _empty(String title, String detail) => ListView(
  padding: const EdgeInsets.all(16),
  children: [
    UiStatePanel(
      compact: true,
      icon: Icons.notes_outlined,
      title: title,
      detail: detail,
    ),
  ],
);

/// 可点击跳转的时间戳。
class _Stamp extends StatelessWidget {
  const _Stamp(this.ms, {this.active = false});
  final int ms;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      mediaClock(Duration(milliseconds: ms)),
      style: theme.textTheme.labelMedium?.copyWith(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ───────────────────────────── 章节 ─────────────────────────────

class ClassroomChaptersPanel extends StatelessWidget {
  const ClassroomChaptersPanel({
    super.key,
    required this.load,
    required this.position,
    required this.onSeek,
  });
  final ClassroomLoad<ClassroomSummary> load;
  final ValueListenable<Duration> position;
  final void Function(Duration) onSeek;

  @override
  Widget build(BuildContext context) => _LoadView<ClassroomSummary>(
    load: load,
    failureTitle: '章节读取失败',
    builder: (context, summary) {
      final chapters = summary.chapters;
      if (chapters.isEmpty) return _empty('本节没有章节', '学校还没有为这节课生成章节');
      return ValueListenableBuilder<Duration>(
        valueListenable: position,
        builder: (context, now, _) {
          final ms = now.inMilliseconds;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: chapters.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final c = chapters[i];
              final next = i + 1 < chapters.length
                  ? chapters[i + 1].startMs
                  : null;
              final active =
                  ms >= c.startMs && (next == null ? ms < c.endMs : ms < next);
              return _ChapterTile(
                chapter: c,
                index: i + 1,
                active: active,
                onTap: () => onSeek(Duration(milliseconds: c.startMs)),
              );
            },
          );
        },
      );
    },
  );
}

class _ChapterTile extends StatefulWidget {
  const _ChapterTile({
    required this.chapter,
    required this.index,
    required this.active,
    required this.onTap,
  });
  final ClassroomChapter chapter;
  final int index;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final c = widget.chapter;
    final hasSummary = c.summary.trim().isNotEmpty;
    return Material(
      color: widget.active
          ? colors.primaryContainer.withValues(alpha: .55)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
        side: BorderSide(
          color: widget.active
              ? colors.primary.withValues(alpha: .4)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Stamp(c.startMs, active: widget.active),
                        Text(
                          ' – ${mediaClock(Duration(milliseconds: c.endMs))}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.headline.trim().isEmpty
                          ? '第 ${widget.index} 章'
                          : c.headline.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (hasSummary) ...[
                      const SizedBox(height: 4),
                      Text(
                        c.summary.trim(),
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasSummary)
                IconButton(
                  tooltip: _expanded ? '收起' : '展开',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 逐字稿 ─────────────────────────────

class ClassroomTranscriptPanel extends StatefulWidget {
  const ClassroomTranscriptPanel({
    super.key,
    required this.load,
    required this.position,
    required this.onSeek,
  });
  final ClassroomLoad<ClassroomTranscript> load;
  final ValueListenable<Duration> position;
  final void Function(Duration) onSeek;

  @override
  State<ClassroomTranscriptPanel> createState() =>
      _ClassroomTranscriptPanelState();
}

class _ClassroomTranscriptPanelState extends State<ClassroomTranscriptPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  var _follow = true;
  var _query = '';
  var _hit = 0;
  int? _current;
  var _programmatic = false;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPosition);
  }

  @override
  void didUpdateWidget(ClassroomTranscriptPanel old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      old.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPosition);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ClassroomTranscriptSegment> get _segments =>
      widget.load.state.value.data?.segments ?? const [];

  int? _indexAt(int ms) {
    final segments = _segments;
    if (segments.isEmpty) return null;
    var lo = 0, hi = segments.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (segments[mid].beginMs <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found < 0 ? null : found;
  }

  void _onPosition() {
    final index = _indexAt(widget.position.value.inMilliseconds);
    if (index == _current) return;
    setState(() => _current = index);
    if (_follow && _query.isEmpty && index != null) _reveal(index);
  }

  void _reveal(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[index]?.currentContext;
      if (ctx == null || !mounted) return;
      _programmatic = true;
      Scrollable.ensureVisible(
        ctx,
        alignment: .3,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ).whenComplete(() => _programmatic = false);
    });
  }

  List<int> _hits() {
    if (_query.isEmpty) return const [];
    final q = _query.toLowerCase();
    return [
      for (var i = 0; i < _segments.length; i++)
        if (_segments[i].text.toLowerCase().contains(q)) i,
    ];
  }

  void _jumpHit(List<int> hits, int delta) {
    if (hits.isEmpty) return;
    setState(() => _hit = (_hit + delta) % hits.length);
    if (_hit < 0) _hit += hits.length;
    _reveal(hits[_hit]);
  }

  @override
  Widget build(BuildContext context) => _LoadView<ClassroomTranscript>(
    load: widget.load,
    failureTitle: '逐字稿读取失败',
    builder: (context, transcript) {
      if (transcript.segments.isEmpty) {
        return _empty('本节没有逐字稿', '学校还没有为这节课生成语音转写');
      }
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final hits = _hits();
      final hitSet = hits.toSet();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: '搜索逐字稿',
                suffixIcon: _query.isEmpty
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hits.isEmpty ? '无结果' : '${_hit + 1}/${hits.length}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            tooltip: '上一个',
                            visualDensity: VisualDensity.compact,
                            onPressed: hits.isEmpty
                                ? null
                                : () => _jumpHit(hits, -1),
                            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                          ),
                          IconButton(
                            tooltip: '下一个',
                            visualDensity: VisualDensity.compact,
                            onPressed: hits.isEmpty
                                ? null
                                : () => _jumpHit(hits, 1),
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: '清除',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _search.clear();
                              setState(() {
                                _query = '';
                                _hit = 0;
                              });
                              if (_follow && _current != null) {
                                _reveal(_current!);
                              }
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value.trim();
                  _hit = 0;
                });
                final next = _hits();
                if (next.isNotEmpty) _reveal(next.first);
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                NotificationListener<UserScrollNotification>(
                  onNotification: (n) {
                    if (!_programmatic && _follow && _query.isEmpty) {
                      setState(() => _follow = false);
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 72),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < transcript.segments.length; i++)
                          _SegmentRow(
                            key: _keys.putIfAbsent(i, GlobalKey.new),
                            segment: transcript.segments[i],
                            active: i == _current,
                            query: hitSet.contains(i) ? _query : '',
                            focused: hits.isNotEmpty && hits[_hit] == i,
                            onTap: () {
                              setState(() => _follow = true);
                              widget.onSeek(
                                Duration(
                                  milliseconds: transcript.segments[i].beginMs,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_follow && _query.isEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _follow = true);
                        if (_current != null) _reveal(_current!);
                      },
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('回到当前'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    super.key,
    required this.segment,
    required this.active,
    required this.query,
    required this.focused,
    required this.onTap,
  });
  final ClassroomTranscriptSegment segment;
  final bool active, focused;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final base = theme.textTheme.bodyMedium?.copyWith(
      height: 1.55,
      color: active
          ? colors.onSurface
          : colors.onSurface.withValues(alpha: .82),
      fontWeight: active ? FontWeight.w500 : null,
    );
    return Material(
      color: active
          ? colors.primaryContainer.withValues(alpha: .45)
          : focused
          ? UbaaTheme.warning(colors).withValues(alpha: .12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 48,
                  child: _Stamp(segment.beginMs, active: active),
                ),
              ),
              Expanded(
                child: Text.rich(_highlight(segment.text, query, base, colors)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TextSpan _highlight(
    String text,
    String query,
    TextStyle? base,
    ColorScheme colors,
  ) {
    if (query.isEmpty) return TextSpan(text: text, style: base);
    final lower = text.toLowerCase(), q = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final at = lower.indexOf(q, start);
      if (at < 0) break;
      if (at > start) spans.add(TextSpan(text: text.substring(start, at)));
      spans.add(
        TextSpan(
          text: text.substring(at, at + q.length),
          style: TextStyle(
            backgroundColor: UbaaTheme.warning(colors).withValues(alpha: .28),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = at + q.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return TextSpan(style: base, children: spans);
  }
}

// ───────────────────────────── 摘要 ─────────────────────────────

class ClassroomSummaryPanel extends StatelessWidget {
  const ClassroomSummaryPanel({
    super.key,
    required this.load,
    required this.onSeek,
  });
  final ClassroomLoad<ClassroomSummary> load;
  final void Function(Duration) onSeek;

  @override
  Widget build(BuildContext context) => _LoadView<ClassroomSummary>(
    load: load,
    failureTitle: '摘要读取失败',
    builder: (context, summary) {
      final text = summary.summary?.trim() ?? '';
      if (text.isEmpty && summary.keywords.isEmpty && summary.qa.isEmpty) {
        return _empty('本节没有摘要', '学校还没有为这节课生成智能摘要');
      }
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final heading = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      );
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (text.isNotEmpty) ...[
            Text('总结', style: heading),
            const SizedBox(height: 6),
            SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
          ],
          if (summary.keywords.isNotEmpty) ...[
            Text('关键词', style: heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final k in summary.keywords) UiTag(k)],
            ),
            const SizedBox(height: 20),
          ],
          if (summary.qa.isNotEmpty) ...[
            Text('问答', style: heading),
            const SizedBox(height: 4),
            for (final q in summary.qa)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(
                    q.question,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  children: [
                    SelectableText(
                      q.answer,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          onSeek(Duration(milliseconds: q.startMs)),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        '跳到 ${mediaClock(Duration(milliseconds: q.startMs))}',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );
}
