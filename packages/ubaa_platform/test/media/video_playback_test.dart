import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  final video = Uri.https('example.invalid', '/video.mp4');
  final insecure = Uri.http('example.invalid', '/video.mp4');

  test('不可用能力不提供 HLS 或倍速，并返回稳定错误', () async {
    const capability = UnavailableVideoPlayback();
    expect(capability.isAvailable, isFalse);
    expect(capability.supportsHls, isFalse);
    expect(capability.supportedRates, isEmpty);
    await expectLater(
      capability.open(video),
      throwsA(
        isA<VideoPlaybackException>().having(
          (error) => error.message,
          '提示',
          capability.unavailableReason,
        ),
      ),
    );
  });

  test('内存播放器更新状态，释放后不通知也不接受命令', () async {
    final capability = MemoryVideoPlaybackCapability();
    final playback = await capability.open(
      video,
      startAt: const Duration(seconds: 10),
    );
    expect(playback.state.value.position, const Duration(seconds: 10));
    var notifications = 0;
    playback.state.addListener(() => notifications++);
    await playback.play();
    expect(playback.state.value.isPlaying, isTrue);
    await playback.seekTo(const Duration(seconds: 20));
    await playback.setRate(2);
    await playback.pause();
    expect(playback.state.value.position, const Duration(seconds: 20));
    expect(playback.state.value.rate, 2);
    expect(playback.state.value.isPlaying, isFalse);
    expect(notifications, 4);

    await playback.dispose();
    await playback.dispose();
    await playback.play();
    await playback.pause();
    await playback.seekTo(Duration.zero);
    await playback.setRate(99);
    expect(notifications, 4);
  });

  test('拒绝非 HTTPS 和 URL 内嵌凭据，且不调用外部打开器', () async {
    final capability = MemoryVideoPlaybackCapability();
    for (final url in [insecure, Uri.parse('https://secret@example.invalid')]) {
      await expectLater(
        capability.open(url),
        throwsA(isA<VideoPlaybackException>()),
      );
      await expectLater(
        openExternally(url, opener: (_) async => fail('不能调用打开器')),
        throwsA(isA<VideoPlaybackException>()),
      );
    }
  });

  test('外部打开器失败时只暴露稳定提示', () async {
    for (final opener in <Future<bool> Function(Uri)>[
      (_) async => false,
      (_) async => throw StateError('原生异常正文'),
    ]) {
      await expectLater(
        openExternally(video, opener: opener),
        throwsA(
          isA<VideoPlaybackException>().having(
            (error) => error.message,
            '提示',
            '无法使用外部播放器打开视频',
          ),
        ),
      );
    }
  });
}
