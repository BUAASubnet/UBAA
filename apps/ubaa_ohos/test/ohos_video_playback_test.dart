import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ohos/ohos_video_playback.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:video_player/video_player.dart';

void main() {
  final url = Uri.https('example.invalid', '/live.m3u8');

  test('video_player 映射状态，释放后取消订阅和操作', () async {
    final driver = _Controller(url);
    final playback = await OhosVideoPlaybackCapability(
      createController: (_) => driver,
    ).open(url, startAt: const Duration(seconds: 10));
    expect(driver.seekPosition, const Duration(seconds: 10));
    expect(driver.httpHeaders, isEmpty);
    driver.value = driver.value.copyWith(
      position: const Duration(seconds: 10),
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 20)),
        DurationRange(const Duration(seconds: 25), const Duration(seconds: 30)),
      ],
      size: const Size(1920, 1080),
      isPlaying: true,
      isBuffering: true,
      isCompleted: true,
      playbackSpeed: 1.75,
      errorDescription: '原生错误正文',
    );
    final value = playback.state.value;
    expect(value.position, const Duration(seconds: 10));
    expect(value.duration, const Duration(seconds: 40));
    expect(value.buffered, const Duration(seconds: 30));
    expect(value.isPlaying, isTrue);
    expect(value.isBuffering, isTrue);
    expect(value.rate, 1.75);
    expect(value.aspectRatio, 16 / 9);
    expect(value.isCompleted, isTrue);
    expect(value.error, '视频播放失败');
    var calls = 0;
    playback.state.addListener(() => calls++);
    await Future.wait([playback.dispose(), playback.dispose()]);
    await playback.play();
    await playback.seekTo(Duration.zero);
    await playback.setRate(99);
    expect(driver.disposals, 1);
    expect(driver.seekPosition, const Duration(seconds: 10));
    expect(calls, 0);
    expect(playback.buildView(), isA<SizedBox>());
  });

  test('初始化失败时释放 video_player 且不暴露异常正文', () async {
    final driver = _Controller(url, failOpen: true);
    await expectLater(
      OhosVideoPlaybackCapability(createController: (_) => driver).open(url),
      throwsA(isA<VideoPlaybackException>()),
    );
    expect(driver.disposals, 1);
  });
}

final class _Controller extends VideoPlayerController {
  _Controller(super.url, {this.failOpen = false}) : super.networkUrl();

  final bool failOpen;
  Duration? seekPosition;
  int disposals = 0;

  @override
  Future<void> initialize() async {
    if (failOpen) throw StateError('原生错误正文');
    value = const VideoPlayerValue(
      duration: Duration(seconds: 40),
      isInitialized: true,
    );
  }

  @override
  Future<void> seekTo(Duration position) async => seekPosition = position;

  @override
  Future<void> dispose() {
    disposals++;
    return super.dispose();
  }
}
