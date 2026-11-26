import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_information.dart';

abstract interface class VideoPlaybackCapability {
  bool get isAvailable;
  String? get unavailableReason;
  bool get supportsHls;
  List<double> get supportedRates;

  Future<VideoPlayback> open(Uri url, {Duration? startAt});
}

abstract interface class VideoPlayback {
  ValueListenable<VideoPlaybackState> get state;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setRate(double rate);
  Widget buildView();
  Future<void> dispose();
}

@immutable
final class VideoPlaybackState {
  const VideoPlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.rate = 1,
    this.aspectRatio,
    this.error,
    this.isCompleted = false,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool isPlaying;
  final bool isBuffering;
  final double rate;
  final double? aspectRatio;
  final String? error;
  final bool isCompleted;
}

final class VideoPlaybackException implements Exception {
  const VideoPlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}

void validateVideoPlaybackUrl(Uri url) {
  if (!url.isScheme('https') || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw const VideoPlaybackException('只支持不含登录信息的 HTTPS 视频地址');
  }
}

Future<void> openExternally(
  Uri url, {
  Future<bool> Function(Uri)? opener,
}) async {
  validateVideoPlaybackUrl(url);
  try {
    if (await (opener ?? openExternalUrl)(url)) return;
  } on Object {
    throw const VideoPlaybackException('无法使用外部播放器打开视频');
  }
  throw const VideoPlaybackException('无法使用外部播放器打开视频');
}

final class UnavailableVideoPlayback implements VideoPlaybackCapability {
  const UnavailableVideoPlayback({this.unavailableReason = '当前平台不支持应用内播放'});

  @override
  final String unavailableReason;
  @override
  bool get isAvailable => false;
  @override
  bool get supportsHls => false;
  @override
  List<double> get supportedRates => const [];

  @override
  Future<VideoPlayback> open(Uri url, {Duration? startAt}) async {
    validateVideoPlaybackUrl(url);
    throw VideoPlaybackException(unavailableReason);
  }
}

final class MemoryVideoPlaybackCapability implements VideoPlaybackCapability {
  MemoryVideoPlaybackCapability({this.duration = const Duration(minutes: 30)});

  final Duration duration;
  MemoryVideoPlayback? lastPlayback;

  @override
  bool get isAvailable => true;
  @override
  String? get unavailableReason => null;
  @override
  bool get supportsHls => true;
  @override
  List<double> get supportedRates => const [0.75, 1, 1.25, 1.5, 2, 3];

  @override
  Future<MemoryVideoPlayback> open(Uri url, {Duration? startAt}) async {
    validateVideoPlaybackUrl(url);
    return lastPlayback = MemoryVideoPlayback._(
      VideoPlaybackState(
        position: startAt ?? Duration.zero,
        duration: duration,
        buffered: duration,
        aspectRatio: 16 / 9,
      ),
      supportedRates,
    );
  }
}

final class MemoryVideoPlayback implements VideoPlayback {
  MemoryVideoPlayback._(VideoPlaybackState initial, this._rates)
    : _state = ValueNotifier(initial);

  final ValueNotifier<VideoPlaybackState> _state;
  final List<double> _rates;
  bool _disposed = false;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  void replaceState(VideoPlaybackState value) {
    if (!_disposed) _state.value = value;
  }

  void _update({Duration? position, bool? playing, double? rate}) {
    if (_disposed) return;
    final value = _state.value;
    replaceState(
      VideoPlaybackState(
        position: position ?? value.position,
        duration: value.duration,
        buffered: value.buffered,
        isPlaying: playing ?? value.isPlaying,
        isBuffering: value.isBuffering,
        rate: rate ?? value.rate,
        aspectRatio: value.aspectRatio,
        error: value.error,
        isCompleted: value.isCompleted && position == null && playing != true,
      ),
    );
  }

  @override
  Future<void> play() async => _update(playing: true);
  @override
  Future<void> pause() async => _update(playing: false);
  @override
  Future<void> seekTo(Duration position) async => _update(position: position);

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    if (!_rates.contains(rate)) throw const VideoPlaybackException('不支持此播放倍速');
    _update(rate: rate);
  }

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future<void>.value();
    _state.dispose();
  }
}
