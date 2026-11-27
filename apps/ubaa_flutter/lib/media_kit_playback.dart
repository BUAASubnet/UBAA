import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

/// 随应用分发的 Mozilla 根证书（certifi，见 THIRD_PARTY_NOTICES.md）。
///
/// iOS 随包 libmpv 使用 mbedTLS，需显式提供 CA 文件才能校验 HTTPS。
/// Linux 使用系统 libmpv / FFmpeg，沿用系统证书路径。
const _tlsCaAsset = 'assets/tls/cacert.pem';
Future<String>? _bundledCaFile;

Future<String?> _defaultTlsCaFile() async {
  if (Platform.isLinux) return null;
  final pending = _bundledCaFile ??= writeBundledTlsCaFile(
    Directory.systemTemp,
  );
  try {
    return await pending;
  } on Object {
    _bundledCaFile = null;
    rethrow;
  }
}

@visibleForTesting
Future<String> writeBundledTlsCaFile(Directory temporaryDirectory) async {
  final data = await rootBundle.load(_tlsCaAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final directory = Directory('${temporaryDirectory.path}/ubaa_tls');
  await directory.create(recursive: true);
  final file = File('${directory.path}/cacert.pem');
  if (!await file.exists() || !listEquals(await file.readAsBytes(), bytes)) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}

final class MediaKitVideoPlaybackCapability implements VideoPlaybackCapability {
  const MediaKitVideoPlaybackCapability({
    this.createPlayer,
    this.buildVideo,
    this.tlsCaFile = _defaultTlsCaFile,
  });

  final Player Function()? createPlayer;
  final Widget Function(Player)? buildVideo;

  /// 返回 libmpv 校验 HTTPS 用的 CA 文件路径；返回 null 表示沿用系统证书路径。
  final Future<String?> Function() tlsCaFile;

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
        final String? caFile;
        try {
          caFile = await tlsCaFile();
        } on Object {
          throw const VideoPlaybackException('无法准备视频连接的证书');
        }
        if (caFile != null) {
          await native.setProperty('tls-ca-file', caFile);
          if (await native.getProperty('tls-ca-file') != caFile) {
            throw const VideoPlaybackException('无法准备视频连接的证书');
          }
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
      stream.error.listen((_) => _onError()),
    ];
  }

  /// media_kit 的错误流会推送 libmpv 的全部错误级日志，其中不少不影响播放
  /// （例如模拟器打不开音频设备）。只有媒体始终没加载起来才视为播放失败：
  /// 已加载后出现的错误忽略；未加载时等待一小段时间，期间加载成功就不报错。
  static const _failureGrace = Duration(seconds: 3);
  Timer? _failureTimer;

  bool get _loaded {
    final value = _player.state;
    return value.duration > Duration.zero || (value.videoParams.w ?? 0) > 0;
  }

  void _onError() {
    if (_disposed || _error != null || _loaded) return;
    _failureTimer ??= Timer(_failureGrace, () {
      _failureTimer = null;
      if (_disposed || _loaded) return;
      _error = '视频播放失败';
      refresh();
    });
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
    if (_loaded) {
      _failureTimer?.cancel();
      _failureTimer = null;
    }
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
    _failureTimer?.cancel();
    _failureTimer = null;
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
