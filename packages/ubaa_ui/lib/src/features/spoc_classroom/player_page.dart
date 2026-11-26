import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart'
    show
        VideoPlayback,
        VideoPlaybackCapability,
        VideoPlaybackException,
        VideoPlaybackState;

import '../../common/state_panel.dart' show UiStatePanel;
import '../../shared/feedback.dart' show UbaaFeedback, UbaaFeedbackKind;
import '../../shared/text.dart' show uiNonBlank;
import '../coursework/spoc_classroom_access.dart' show SpocClassroomAccess;
import 'classroom_format.dart';
import 'classroom_panels.dart';
import 'player_controls.dart';
import 'slide_strip.dart';

// 两路回放共用同一时间轴：2026-11-26 用真实回放校准，PPT 路比教师路只晚约 2–3 秒，
// PPT 截图时间戳对应 PPT 路自身位置。上游 `time_offset`（PPT 路 -120）不是播放位置的平移量，
// 因此切换画面时保持同一位置，资料面板的时间也直接用于两路。详见协议文档。

/// 课堂播放页：回放（教师 / PPT 切换）或直播（教师 / 学生切换），
/// 以及章节、逐字稿、摘要和 PPT 缩略图条。所有资料按教师路时间轴对齐。
class ClassroomPlayerPage extends StatefulWidget {
  const ClassroomPlayerPage({
    super.key,
    required this.access,
    required this.courseId,
    required this.courseTitle,
    required this.session,
  });
  final SpocClassroomAccess access;
  final String courseId, courseTitle;
  final ClassroomSessionSummary session;

  @override
  State<ClassroomPlayerPage> createState() => _ClassroomPlayerPageState();
}

class _ClassroomPlayerPageState extends State<ClassroomPlayerPage>
    with WidgetsBindingObserver {
  ClassroomSession? _session;
  Object? _sessionError;
  ClassroomPlaybackSource? _source;
  VideoPlayback? _playback;
  VideoPlayback? _openingPlayback;
  Object? _openError;
  var _opening = false;
  double _rate = 1;
  final _teacherPosition = ValueNotifier(Duration.zero);
  ClassroomLoad<ClassroomTranscript>? _transcript;
  ClassroomLoad<ClassroomSummary>? _summary;
  ClassroomLoad<ClassroomSlides>? _slides;
  int _openGeneration = 0;

  VideoPlaybackCapability? get _capability => widget.access.playback;

  bool get _isLive =>
      (_session?.status ?? widget.session.status) == ClassroomStatus.live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openGeneration++;
    _playback?.state.removeListener(_onPlaybackState);
    unawaited((_playback ?? _openingPlayback)?.dispose());
    _teacherPosition.dispose();
    _transcript?.dispose();
    _summary?.dispose();
    _slides?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台就暂停：不在后台继续拉流。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_playback?.pause());
    }
  }

  Future<void> _loadSession() async {
    setState(() {
      _sessionError = null;
      _session = null;
    });
    try {
      final read = await widget.access.service.session(
        widget.courseId,
        widget.session.subId,
      );
      if (!mounted) return;
      final session = read.data;
      final teacher = _teacherSource(session);
      final guid = teacher?.resourceGuid;
      setState(() {
        _session = session;
        if (!_isLiveSession(session) && guid != null) {
          final service = widget.access.service;
          final subId = widget.session.subId;
          _transcript ??= ClassroomLoad(
            () async => (await service.transcript(subId, guid)).data,
          );
          _summary ??= ClassroomLoad(
            () async => (await service.summary(subId, guid)).data,
          );
          _slides ??= ClassroomLoad(
            () async =>
                (await service.slides(widget.courseId, subId, guid)).data,
          );
        }
      });
      final first =
          teacher ?? (session.sources.isEmpty ? null : session.sources.first);
      if (first != null) await _open(first, startAt: Duration.zero, play: true);
    } on Object catch (error) {
      if (mounted) setState(() => _sessionError = error);
    }
  }

  static bool _isLiveSession(ClassroomSession s) =>
      s.status == ClassroomStatus.live;

  static ClassroomPlaybackSource? _teacherSource(ClassroomSession s) {
    for (final source in s.sources) {
      if (source.kind == ClassroomPlaybackKind.teacher) return source;
    }
    return null;
  }

  /// 两路共用时间轴（见文件头说明），位置无需换算。
  Duration _toTeacher(Duration streamPos) => streamPos;

  Duration _fromTeacher(Duration teacherPos, ClassroomPlaybackSource source) =>
      teacherPos;

  /// 当前平台不能在应用内播放这一路时给出原因；能播放返回 null。
  String? _unsupportedReason(ClassroomPlaybackSource source) {
    final capability = _capability;
    if (capability == null) return '当前平台暂不支持应用内播放';
    if (!capability.isAvailable) {
      return capability.unavailableReason ?? '当前平台暂不支持应用内播放';
    }
    if (_isLive && !capability.supportsHls) return '当前平台暂不支持在应用内看直播';
    return null;
  }

  Future<void> _open(
    ClassroomPlaybackSource source, {
    required Duration startAt,
    required bool play,
  }) async {
    final generation = ++_openGeneration;
    final old = _playback ?? _openingPlayback;
    _playback?.state.removeListener(_onPlaybackState);
    _openingPlayback = null;
    setState(() {
      _source = source;
      _playback = null;
      _openError = null;
      _opening = _unsupportedReason(source) == null;
    });
    try {
      if (old != null) await old.dispose();
      if (!mounted || generation != _openGeneration || !_opening) return;
      final playback = await _capability!.open(
        Uri.parse(source.url),
        startAt: _isLive ? null : startAt,
      );
      if (!mounted || generation != _openGeneration) {
        await playback.dispose();
        return;
      }
      _openingPlayback = playback;
      if (_rate != 1 && !_isLive) await playback.setRate(_rate);
      if (play) await playback.play();
      if (!mounted || generation != _openGeneration) return;
      playback.state.addListener(_onPlaybackState);
      _openingPlayback = null;
      setState(() {
        _playback = playback;
        _opening = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _openGeneration) return;
      final failed = _openingPlayback;
      _openingPlayback = null;
      setState(() {
        _opening = false;
        _openError = error;
      });
      await failed?.dispose();
    }
  }

  void _onPlaybackState() {
    final playback = _playback;
    if (playback == null) return;
    _teacherPosition.value = _toTeacher(playback.state.value.position);
  }

  Future<void> _switch(ClassroomPlaybackSource next) async {
    if (next == _source) return;
    final playing = _playback?.state.value.isPlaying ?? true;
    final teacherPos = _teacherPosition.value;
    await _open(next, startAt: _fromTeacher(teacherPos, next), play: playing);
  }

  /// 资料面板给出的是教师时间轴位置。
  void _seekTeacher(Duration teacherPos) {
    final playback = _playback, source = _source;
    if (playback == null || source == null || _isLive) return;
    unawaited(playback.seekTo(_fromTeacher(teacherPos, source)));
    unawaited(playback.play());
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _playback?.setRate(rate);
  }

  Future<void> _openExternally() async {
    final source = _source;
    if (source == null) return;
    try {
      await widget.access.openExternal(Uri.parse(source.url));
    } on Object catch (error) {
      if (!mounted) return;
      UbaaFeedback.show(
        context,
        error is VideoPlaybackException ? error.message : '无法使用外部播放器打开视频',
        kind: UbaaFeedbackKind.error,
      );
    }
  }

  Future<void> _fullscreen() async {
    final playback = _playback;
    if (playback == null) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, _, _) =>
            _FullscreenPlayer(playback: playback, controls: _controlsFor),
      ),
    );
  }

  Widget _controlsFor(VideoPlayback playback, {required bool fullscreen}) =>
      ClassroomPlayerControls(
        playback: playback,
        live: _isLive,
        rate: _rate,
        rates: _capability?.supportedRates ?? const [1],
        sources: _session?.sources ?? const [],
        current: _source,
        onSwitch: _switch,
        onRate: _setRate,
        onExternal: _openExternally,
        fullscreen: fullscreen,
        onFullscreen: fullscreen
            ? () => Navigator.of(context, rootNavigator: true).maybePop()
            : _fullscreen,
      );

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.courseTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              _subtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final video = _videoArea();
          final strip = _slides == null
              ? const SizedBox.shrink()
              : ClassroomSlideStrip(
                  load: _slides!,
                  position: _teacherPosition,
                  onSeek: _seekTeacher,
                );
          if (_isLive || _sessionError != null) {
            return ListView(
              children: [video, if (_sessionError == null) _liveInfo(theme)],
            );
          }
          final tabs = _tabs();
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(children: [video, strip]),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                SizedBox(width: 380, child: tabs),
              ],
            );
          }
          return Column(
            children: [
              video,
              strip,
              Expanded(child: tabs),
            ],
          );
        },
      ),
    );
  }

  String _subtitle() {
    final s = widget.session;
    final start = sessionStart(s);
    return [
      '${start.month}/${start.day} ${weekdayLabel(start)}',
      sessionPeriodLabel(s),
      ?uiNonBlank(s.room),
    ].join(' · ');
  }

  Widget _videoArea() {
    final source = _source;
    Widget child;
    if (_sessionError != null) {
      final error = _sessionError is UiError ? _sessionError as UiError : null;
      child = _VideoMessage(
        icon: Icons.cloud_off,
        title: '这节课读取失败',
        detail: error?.message ?? '请稍后重试',
        primary: ('重试', _loadSession),
      );
    } else if (_session == null || _opening) {
      child = const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    } else if (source == null) {
      child = _VideoMessage(
        icon: Icons.videocam_off_outlined,
        title: _isLive ? '直播暂时没有画面' : '这节课没有可播放的视频',
        detail: '稍后刷新再试',
        primary: ('刷新', _loadSession),
      );
    } else if (_unsupportedReason(source) case final reason?) {
      child = _VideoMessage(
        icon: Icons.open_in_new,
        title: reason,
        detail: '可以用系统里的播放器打开',
        primary: ('用外部播放器打开', _openExternally),
      );
    } else if (_openError != null || _playback?.state.value.error != null) {
      child = _VideoMessage(
        icon: Icons.error_outline,
        title: '视频播放失败',
        detail:
            _playback?.state.value.error ??
            switch (_openError) {
              final VideoPlaybackException e => e.message,
              final UiError e => e.message,
              _ => '请重试，或用外部播放器打开',
            },
        primary: (
          '重试',
          () => _open(
            source,
            startAt: _fromTeacher(_teacherPosition.value, source),
            play: true,
          ),
        ),
        secondary: ('用外部播放器打开', _openExternally),
      );
    } else {
      final playback = _playback!;
      child = Stack(
        fit: StackFit.expand,
        children: [
          Center(child: _AspectView(playback: playback)),
          _controlsFor(playback, fullscreen: false),
        ],
      );
    }
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekByIntent(-10),
        SingleActivator(LogicalKeyboardKey.arrowRight): _SeekByIntent(10),
      },
      child: Actions(
        actions: {
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (_) {
              final p = _playback;
              if (p == null) return null;
              p.state.value.isPlaying ? p.pause() : p.play();
              return null;
            },
          ),
          _SeekByIntent: CallbackAction<_SeekByIntent>(
            onInvoke: (intent) {
              final p = _playback;
              if (p == null || _isLive) return null;
              final next =
                  p.state.value.position + Duration(seconds: intent.seconds);
              p.seekTo(next.isNegative ? Duration.zero : next);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: Colors.black, child: child),
          ),
        ),
      ),
    );
  }

  Widget _liveInfo(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.session.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            sessionTimeRange(widget.session),
            ?uiNonBlank(widget.session.room),
            ?uiNonBlank(widget.session.lecturer),
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '直播结束后，回放、逐字稿和摘要一般会在课后陆续生成。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _tabs() {
    final transcript = _transcript, summary = _summary;
    if (transcript == null || summary == null) {
      return const UiStatePanel(
        compact: true,
        icon: Icons.notes_outlined,
        title: '本节没有课堂资料',
        detail: '没有教师路视频时，章节、逐字稿和摘要不可用',
      );
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '章节'),
              Tab(text: '逐字稿'),
              Tab(text: '摘要'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ClassroomChaptersPanel(
                  load: summary,
                  position: _teacherPosition,
                  onSeek: _seekTeacher,
                ),
                ClassroomTranscriptPanel(
                  load: transcript,
                  position: _teacherPosition,
                  onSeek: _seekTeacher,
                ),
                ClassroomSummaryPanel(load: summary, onSeek: _seekTeacher),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class _SeekByIntent extends Intent {
  const _SeekByIntent(this.seconds);
  final int seconds;
}

/// 按视频自身宽高比显示画面。
class _AspectView extends StatelessWidget {
  const _AspectView({required this.playback});
  final VideoPlayback playback;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VideoPlaybackState>(
        valueListenable: playback.state,
        builder: (context, state, _) => AspectRatio(
          aspectRatio: switch (state.aspectRatio) {
            final r? when r > 0 => r,
            _ => 16 / 9,
          },
          child: playback.buildView(),
        ),
      );
}

class _VideoMessage extends StatelessWidget {
  const _VideoMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.primary,
    this.secondary,
  });
  final IconData icon;
  final String title, detail;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 36),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: primary.$2, child: Text(primary.$1)),
                if (secondary case final s?)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: s.$2,
                    child: Text(s.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏：黑底，移动端横屏沉浸，退出时恢复方向与系统栏。
class _FullscreenPlayer extends StatefulWidget {
  const _FullscreenPlayer({required this.playback, required this.controls});
  final VideoPlayback playback;
  final Widget Function(VideoPlayback, {required bool fullscreen}) controls;

  @override
  State<_FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<_FullscreenPlayer> {
  bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_mobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    if (_mobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        Center(child: _AspectView(playback: widget.playback)),
        SafeArea(child: widget.controls(widget.playback, fullscreen: true)),
      ],
    ),
  );
}

/// 便于测试替换：页面用到的位置流。
typedef ClassroomPosition = ValueListenable<Duration>;
