import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

VideoPlaybackCapability createMediaKitVideoPlaybackCapability({
  String? operatingSystem,
  void Function()? initialize,
}) {
  try {
    (initialize ?? MediaKit.ensureInitialized)();
    return const MediaKitVideoPlaybackCapability();
  } on Object {
    return UnavailableVideoPlayback(
      unavailableReason:
          (operatingSystem ?? Platform.operatingSystem) == 'linux'
          ? '请安装 libmpv 后重新启动应用'
          : '当前设备无法初始化应用内播放器',
    );
  }
}

final class MediaKitVideoPlaybackCapability implements VideoPlaybackCapability {
  const MediaKitVideoPlaybackCapability({this.createPlayer, this.buildVideo});

  final Player Function()? createPlayer;
  final Widget Function(Player)? buildVideo;

  @override
  bool get isAvailable => true;
  @override
  String? get unavailableReason => null;
  @override
  bool get supportsHls => true;
  @override
  List<double> get supportedRates => const [0.75, 1, 1.25, 1.5, 2, 3];

  @override
  Future<VideoPlayback> open(Uri url, {Duration? startAt}) async {
    validateVideoPlaybackUrl(url);
    Player? player;
    _MediaKitVideoPlayback? playback;
    try {
      final active = player = createPlayer?.call() ?? Player();
      final native = active.platform;
      if (native is NativePlayer) {
        await native.setProperty('tls-verify', 'yes');
        if (await native.getProperty('tls-verify') != 'yes') {
          throw const VideoPlaybackException('无法启用视频连接的 TLS 校验');
        }
        await native.setProperty('cache-on-disk', 'no');
      }
      final view = buildVideo?.call(active) ?? await _createVideoView(active);
      playback = _MediaKitVideoPlayback(active, view, supportedRates);
      await active.open(Media(url.toString(), start: startAt), play: false);
      playback.refresh();
      return playback;
    } on Object catch (error) {
      try {
        await (playback?.dispose() ?? player?.dispose());
      } on Object {
        throw const VideoPlaybackException('无法打开视频');
      }
      if (error is VideoPlaybackException) rethrow;
      throw const VideoPlaybackException('无法打开视频');
    }
  }
}

Future<Widget> _createVideoView(Player player) async {
  final controller = VideoController(player);
  WidgetsBinding.instance.ensureVisualUpdate();
  await controller.platform.future;
  return Video(controller: controller, controls: NoVideoControls);
}

final class _MediaKitVideoPlayback implements VideoPlayback {
  _MediaKitVideoPlayback(this._player, this._view, this._rates) {
    final stream = _player.stream;
    _subscriptions = [
      for (final changes in [
        stream.position,
        stream.duration,
        stream.buffer,
        stream.playing,
        stream.buffering,
        stream.rate,
        stream.videoParams,
        stream.completed,
      ])
        changes.listen((_) => refresh()),
      stream.error.listen((_) {
        _error = '视频播放失败';
        refresh();
      }),
    ];
  }

  final Player _player;
  final Widget _view;
  final List<double> _rates;
  final _state = ValueNotifier(const VideoPlaybackState());
  late final List<StreamSubscription<Object?>> _subscriptions;
  String? _error;
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  void refresh() {
    if (_disposed) return;
    final value = _player.state;
    final params = value.videoParams;
    final aspect = params.aspect;
    final rotated = params.rotate == 90 || params.rotate == 270;
    _state.value = VideoPlaybackState(
      position: value.position,
      duration: value.duration,
      buffered: value.buffer,
      isPlaying: value.playing,
      isBuffering: value.buffering,
      rate: value.rate,
      aspectRatio: aspect == null || !aspect.isFinite || aspect <= 0
          ? null
          : (rotated ? 1 / aspect : aspect),
      error: _error,
      isCompleted: value.completed,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed) return;
    try {
      await action();
    } on Object {
      if (!_disposed) throw const VideoPlaybackException('视频播放操作失败');
    }
  }

  @override
  Future<void> play() => _run(_player.play);
  @override
  Future<void> pause() => _run(_player.pause);
  @override
  Future<void> seekTo(Duration position) => _run(() => _player.seek(position));

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    if (!_rates.contains(rate)) throw const VideoPlaybackException('不支持此播放倍速');
    await _run(() => _player.setRate(rate));
  }

  @override
  Widget buildView() => _disposed ? const SizedBox.shrink() : _view;

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      await Future.wait(
        _subscriptions.map((subscription) => subscription.cancel()),
      );
    } finally {
      _state.dispose();
      try {
        await _player.dispose();
      } on Object {
        throw const VideoPlaybackException('无法释放播放器');
      }
    }
  }
}
