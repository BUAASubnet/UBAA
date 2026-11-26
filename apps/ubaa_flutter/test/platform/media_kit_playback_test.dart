import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ubaa_flutter/media_kit_playback.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('Linux 探测不到 libmpv 时保留外部打开入口', () {
    final capability = createMediaKitVideoPlaybackCapability(
      operatingSystem: 'linux',
      initialize: () => throw StateError('原生错误'),
    );
    expect(capability.isAvailable, isFalse);
    expect(capability.unavailableReason, contains('请安装 libmpv'));
  });

  test('media_kit 映射状态，释放后取消订阅和操作', () async {
    final driver = _Player();
    final playback = await MediaKitVideoPlaybackCapability(
      createPlayer: () => Player(platformPlayer: driver),
      buildVideo: (_) => const SizedBox.shrink(),
    ).open(Uri.https('example.invalid', '/video.mp4'), startAt: _start);
    expect(driver.media?.start, _start);
    expect(driver.media?.httpHeaders, isNull);
    driver.state = driver.state.copyWith(
      position: _start,
      duration: const Duration(seconds: 40),
      buffer: const Duration(seconds: 30),
      playing: true,
      buffering: true,
      rate: 2,
      completed: true,
      videoParams: const VideoParams(aspect: 16 / 9),
    );
    driver.emitPosition(_start);
    driver.emitError('原生错误正文');
    await pumpEventQueue();
    final value = playback.state.value;
    expect(value.position, _start);
    expect(value.duration, const Duration(seconds: 40));
    expect(value.buffered, const Duration(seconds: 30));
    expect(value.isPlaying, isTrue);
    expect(value.isBuffering, isTrue);
    expect(value.rate, 2);
    expect(value.aspectRatio, 16 / 9);
    expect(value.isCompleted, isTrue);
    expect(value.error, '视频播放失败');
    var calls = 0;
    playback.state.addListener(() => calls++);
    driver.emitPosition(const Duration(seconds: 22));
    await Future.wait([playback.dispose(), playback.dispose()]);
    await playback.play();
    await playback.seekTo(Duration.zero);
    await playback.setRate(99);
    expect(driver.disposals, 1);
    expect(calls, 0);
    expect(playback.buildView(), isA<SizedBox>());
  });

  test('媒体打开失败时释放 media_kit 且不暴露异常正文', () async {
    final driver = _Player(failOpen: true);
    await expectLater(
      MediaKitVideoPlaybackCapability(
        createPlayer: () => Player(platformPlayer: driver),
        buildVideo: (_) => const SizedBox.shrink(),
      ).open(Uri.https('example.invalid', '/video.mp4')),
      throwsA(isA<VideoPlaybackException>()),
    );
    expect(driver.disposals, 1);
  });
}

const _start = Duration(seconds: 10);

final class _Player extends PlatformPlayer {
  _Player({this.failOpen = false})
    : super(configuration: const PlayerConfiguration());

  final bool failOpen;
  Media? media;
  int disposals = 0;

  void emitPosition(Duration position) => positionController.add(position);
  void emitError(String error) => errorController.add(error);

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    expect(play, isFalse);
    if (failOpen) throw StateError('原生错误正文');
    media = playable as Media;
  }

  @override
  Future<void> dispose() {
    disposals++;
    return super.dispose();
  }
}
