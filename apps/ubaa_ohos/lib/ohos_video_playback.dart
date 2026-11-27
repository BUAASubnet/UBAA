import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:video_player/video_player.dart';

final class OhosVideoPlaybackCapability implements VideoPlaybackCapability {
  const OhosVideoPlaybackCapability({this.createController});

  final VideoPlayerController Function(Uri)? createController;

  @override
  bool get isAvailable => true;
  @override
  String? get unavailableReason => null;
  @override
  bool get supportsHls => true;
  @override
  List<double> get supportedRates => const [
    0.125,
    0.25,
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    1.75,
    2,
    3,
  ];

  @override
  Future<VideoPlayback> open(Uri url, {Duration? startAt}) async {
    validateVideoPlaybackUrl(url);
    VideoPlayerController? controller;
    try {
      final active = controller =
          createController?.call(url) ??
          VideoPlayerController.networkUrl(
            url,
            formatHint: url.path.toLowerCase().endsWith('.m3u8')
                ? VideoFormat.hls
                : null,
          );
      await active.initialize();
      if (startAt != null && startAt > Duration.zero) {
        await active.seekTo(startAt);
      }
      return _OhosVideoPlayback(active, supportedRates);
    } on Object {
      try {
        await controller?.dispose();
      } on Object {
        throw const VideoPlaybackException('无法打开视频');
      }
      throw const VideoPlaybackException('无法打开视频');
    }
  }
}

final class _OhosVideoPlayback implements VideoPlayback {
  _OhosVideoPlayback(this._controller, this._rates) {
    _controller.addListener(_refresh);
    _refresh();
  }

  final VideoPlayerController _controller;
  final List<double> _rates;
  final _state = ValueNotifier(const VideoPlaybackState());
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  void _refresh() {
    if (_disposed) return;
    final value = _controller.value;
    final buffered = value.buffered.fold(
      Duration.zero,
      (end, range) => range.end > end ? range.end : end,
    );
    _state.value = VideoPlaybackState(
      position: value.position,
      duration: value.duration,
      buffered: buffered,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      rate: value.playbackSpeed,
      aspectRatio: value.size.isEmpty ? null : value.aspectRatio,
      error: value.hasError ? '视频播放失败' : null,
      isCompleted: value.isCompleted,
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
  Future<void> play() => _run(_controller.play);
  @override
  Future<void> pause() => _run(_controller.pause);
  @override
  Future<void> seekTo(Duration position) =>
      _run(() => _controller.seekTo(position));

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    if (!_rates.contains(rate)) throw const VideoPlaybackException('不支持此播放倍速');
    await _run(() => _controller.setPlaybackSpeed(rate));
  }

  @override
  Widget buildView() =>
      _disposed ? const SizedBox.shrink() : VideoPlayer(_controller);

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _controller.removeListener(_refresh);
    try {
      await _controller.dispose();
    } on Object {
      throw const VideoPlaybackException('无法释放播放器');
    } finally {
      _state.dispose();
    }
  }
}
