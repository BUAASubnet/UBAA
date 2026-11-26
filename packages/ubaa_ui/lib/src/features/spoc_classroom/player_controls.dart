import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart'
    show VideoPlayback, VideoPlaybackState;

import 'classroom_format.dart' show mediaClock;

/// 平台无关的播放控件：叠在画面上，播放中 3 秒无操作自动淡出，点画面切换显示。
class ClassroomPlayerControls extends StatefulWidget {
  const ClassroomPlayerControls({
    super.key,
    required this.playback,
    required this.live,
    required this.rate,
    required this.rates,
    required this.sources,
    required this.current,
    required this.onSwitch,
    required this.onRate,
    required this.onExternal,
    required this.fullscreen,
    required this.onFullscreen,
  });
  final VideoPlayback playback;
  final bool live, fullscreen;
  final double rate;
  final List<double> rates;
  final List<ClassroomPlaybackSource> sources;
  final ClassroomPlaybackSource? current;
  final void Function(ClassroomPlaybackSource) onSwitch;
  final void Function(double) onRate;
  final VoidCallback onExternal, onFullscreen;

  @override
  State<ClassroomPlayerControls> createState() =>
      _ClassroomPlayerControlsState();
}

class _ClassroomPlayerControlsState extends State<ClassroomPlayerControls> {
  var _visible = true;
  Timer? _hide;
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _bump();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _bump() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final state = widget.playback.state.value;
      if (state.isPlaying && _dragMs == null) setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    if (_visible) {
      _hide?.cancel();
      setState(() => _visible = false);
    } else {
      _bump();
    }
  }

  static String _kindLabel(ClassroomPlaybackKind kind) => switch (kind) {
    ClassroomPlaybackKind.teacher => '教师',
    ClassroomPlaybackKind.slides => 'PPT',
    ClassroomPlaybackKind.student => '学生',
  };

  static String _rateLabel(double r) =>
      '${r == r.roundToDouble() ? r.toStringAsFixed(1) : r.toString()}×';

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlaybackState>(
        valueListenable: widget.playback.state,
        builder: (context, state, _) {
          final showAll = _visible || !state.isPlaying;
          return MouseRegion(
            onHover: (_) => _bump(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVisible,
              onDoubleTap: () {
                state.isPlaying
                    ? widget.playback.pause()
                    : widget.playback.play();
                _bump();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (state.isBuffering)
                    const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  IgnorePointer(
                    ignoring: !showAll,
                    child: AnimatedOpacity(
                      opacity: showAll ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0, .25, .6, 1],
                                colors: [
                                  Color(0x66000000),
                                  Color(0x00000000),
                                  Color(0x00000000),
                                  Color(0x99000000),
                                ],
                              ),
                            ),
                          ),
                          if (!state.isPlaying && !state.isBuffering)
                            Center(
                              child: IconButton.filled(
                                tooltip: '播放',
                                iconSize: 40,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black45,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  if (state.isCompleted) {
                                    widget.playback.seekTo(Duration.zero);
                                  }
                                  widget.playback.play();
                                  _bump();
                                },
                                icon: Icon(
                                  state.isCompleted
                                      ? Icons.replay
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: _topBar(context),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _bottomBar(context, state),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _topBar(BuildContext context) {
    final switchable = widget.sources.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
      child: Row(
        children: [
          if (widget.live) const _LivePill(),
          const Spacer(),
          if (switchable)
            _SourceSwitch(
              sources: widget.sources,
              current: widget.current,
              label: _kindLabel,
              onSwitch: (s) {
                widget.onSwitch(s);
                _bump();
              },
            ),
          PopupMenuButton<String>(
            tooltip: '更多',
            iconColor: Colors.white,
            onOpened: _hide?.cancel,
            onSelected: (value) {
              if (value == 'external') widget.onExternal();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'external',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_new),
                  title: Text('用外部播放器打开'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, VideoPlaybackState state) {
    final theme = Theme.of(context);
    final text = theme.textTheme.labelMedium?.copyWith(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final durationMs = state.duration.inMilliseconds.toDouble();
    final positionMs = (_dragMs ?? state.position.inMilliseconds.toDouble())
        .clamp(0, durationMs > 0 ? durationMs : 0)
        .toDouble();
    final bufferedMs = state.buffered.inMilliseconds
        .toDouble()
        .clamp(0, durationMs > 0 ? durationMs : 0)
        .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.live && durationMs > 0)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: Colors.white24,
                secondaryActiveTrackColor: Colors.white54,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: positionMs,
                secondaryTrackValue: bufferedMs,
                max: durationMs,
                onChangeStart: (v) {
                  _hide?.cancel();
                  setState(() => _dragMs = v);
                },
                onChanged: (v) => setState(() => _dragMs = v),
                onChangeEnd: (v) {
                  widget.playback.seekTo(Duration(milliseconds: v.round()));
                  setState(() => _dragMs = null);
                  _bump();
                },
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: state.isPlaying ? '暂停' : '播放',
                color: Colors.white,
                onPressed: () {
                  state.isPlaying
                      ? widget.playback.pause()
                      : widget.playback.play();
                  _bump();
                },
                icon: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              if (!widget.live)
                Text(
                  '${mediaClock(Duration(milliseconds: positionMs.round()))} / ${mediaClock(state.duration)}',
                  style: text,
                ),
              const Spacer(),
              if (!widget.live && widget.rates.length > 1)
                PopupMenuButton<double>(
                  tooltip: '倍速',
                  onOpened: _hide?.cancel,
                  initialValue: widget.rate,
                  onSelected: (r) {
                    widget.onRate(r);
                    _bump();
                  },
                  itemBuilder: (_) => [
                    for (final r in widget.rates)
                      PopupMenuItem(value: r, child: Text(_rateLabel(r))),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Text(
                      widget.rate == 1 ? '倍速' : _rateLabel(widget.rate),
                      style: text,
                    ),
                  ),
                ),
              IconButton(
                tooltip: widget.fullscreen ? '退出全屏' : '全屏',
                color: Colors.white,
                onPressed: widget.onFullscreen,
                icon: Icon(
                  widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sensors, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          '直播中',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white),
        ),
      ],
    ),
  );
}

/// 画面切换：两路时用分段按钮（教师 / PPT，教师 / 学生）。
class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({
    required this.sources,
    required this.current,
    required this.label,
    required this.onSwitch,
  });
  final List<ClassroomPlaybackSource> sources;
  final ClassroomPlaybackSource? current;
  final String Function(ClassroomPlaybackKind) label;
  final void Function(ClassroomPlaybackSource) onSwitch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelMedium;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in sources)
            Semantics(
              button: true,
              selected: s == current,
              label: '切换到${label(s.kind)}画面',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: s == current ? null : () => onSwitch(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: s == current ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label(s.kind),
                    style: text?.copyWith(
                      color: s == current ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
