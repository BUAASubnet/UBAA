import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ubaa_flutter/media_kit_playback.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(value.error, isNull);
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

  for (final caFile in ['/test/cacert.pem', null]) {
    test('打开媒体前校验 TLS，CA 路径为 $caFile', () async {
      final native = _NativePlayer();
      final playback = await _open(native, tlsCaFile: () async => caFile);
      addTearDown(playback.dispose);
      expect(native.calls, [
        'set tls-verify yes',
        'get tls-verify',
        if (caFile != null) ...['set tls-ca-file $caFile', 'get tls-ca-file'],
        'set cache-on-disk no',
        'open',
      ]);
    });
  }

  for (final failPreparation in [true, false]) {
    test(failPreparation ? '证书准备失败时不打开媒体' : 'CA 路径回读失败时不打开媒体', () async {
      final native = _NativePlayer(ignoreCaFile: !failPreparation);
      await expectLater(
        _open(
          native,
          tlsCaFile: () async {
            if (failPreparation) throw StateError('证书异常正文');
            return '/test/cacert.pem';
          },
        ),
        throwsA(
          isA<VideoPlaybackException>().having(
            (error) => error.message,
            '说明',
            '无法准备视频连接的证书',
          ),
        ),
      );
      expect(native.calls, isNot(contains('open')));
      expect(native.driver.disposals, 1);
    });
  }

  test('写入随包 CA，内容相同时保留文件，内容不同时更新', () async {
    final directory = await Directory.systemTemp.createTemp('ubaa-test-ca-');
    addTearDown(() => directory.delete(recursive: true));
    final asset = await rootBundle.load('assets/tls/cacert.pem');
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final file = File(await writeBundledTlsCaFile(directory));
    expect(file.path, '${directory.path}/ubaa_tls/cacert.pem');
    expect(await file.readAsBytes(), bytes);

    await file.setLastModified(DateTime.utc(2020));
    final modified = await file.lastModified();
    expect(await writeBundledTlsCaFile(directory), file.path);
    expect(await file.lastModified(), modified);

    await file.writeAsString('旧的证书内容');
    expect(await writeBundledTlsCaFile(directory), file.path);
    expect(await file.readAsBytes(), bytes);
  });

  testWidgets('媒体未加载时，首条错误等满三秒才报告播放失败', (tester) async {
    final driver = _Player();
    final playback = await _open(driver);
    addTearDown(playback.dispose);
    driver.emitError('原生错误正文');
    await tester.pump();
    expect(playback.state.value.error, isNull);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(playback.state.value.error, isNull);
    driver.emitError('重复错误');
    await tester.pump(const Duration(milliseconds: 1));
    expect(playback.state.value.error, '视频播放失败');
  });

  testWidgets('宽限内读到时长，取消播放失败计时', (tester) async {
    final driver = _Player();
    final playback = await _open(driver);
    addTearDown(playback.dispose);
    driver.emitError('音频设备不可用');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    driver.state = driver.state.copyWith(duration: _start);
    driver.emitPosition(Duration.zero);
    await tester.pump();
    expect(playback.state.value.duration, _start);
    await tester.pump(const Duration(seconds: 2));
    expect(playback.state.value.error, isNull);
  });

  testWidgets('已有画面的无时长媒体忽略后续错误', (tester) async {
    final driver = _Player();
    final playback = await _open(driver);
    addTearDown(playback.dispose);
    driver.state = driver.state.copyWith(
      videoParams: const VideoParams(w: 640, h: 360),
    );
    driver.emitError('音频设备不可用');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(playback.state.value.duration, Duration.zero);
    expect(playback.state.value.error, isNull);
  });

  testWidgets('释放时取消尚未到期的播放失败计时器', (tester) async {
    final driver = _Player();
    final playback = await _open(driver);
    var calls = 0;
    playback.state.addListener(() => calls++);
    driver.emitError('原生错误正文');
    await tester.pump();
    await tester.runAsync(playback.dispose);
    expect(driver.disposals, 1);
    expect(calls, 0);
    expect(playback.state.value.error, isNull);
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

Future<VideoPlayback> _open(
  PlatformPlayer driver, {
  Future<String?> Function()? tlsCaFile,
}) => MediaKitVideoPlaybackCapability(
  createPlayer: () => Player(platformPlayer: driver),
  buildVideo: (_) => const SizedBox.shrink(),
  tlsCaFile: tlsCaFile ?? () async => null,
).open(Uri.https('example.invalid', '/video.mp4'));

final class _NativePlayer extends Fake implements NativePlayer {
  _NativePlayer({this.ignoreCaFile = false});

  final bool ignoreCaFile;
  final driver = _Player();
  final calls = <String>[];
  final _properties = <String, String>{};

  @override
  PlayerState get state => driver.state;

  @override
  PlayerStream get stream => driver.stream;

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    calls.add('set $property $value');
    if (!ignoreCaFile || property != 'tls-ca-file') {
      _properties[property] = value;
    }
  }

  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    calls.add('get $property');
    return _properties[property] ?? '';
  }

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) {
    calls.add('open');
    return driver.open(playable, play: play);
  }

  @override
  Future<void> dispose({bool synchronized = true}) => driver.dispose();
}

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
