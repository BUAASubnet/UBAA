import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/player_controls.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/player_page.dart';

import 'fixture.dart';

final class _RecordingPlayback implements VideoPlaybackCapability {
  _RecordingPlayback({
    this.supportsHls = true,
    this.beforeOpen,
    this.beforePlay,
    this.beforePause,
    this.beforeDispose,
  });

  final memory = MemoryVideoPlaybackCapability();
  final opens = <(Uri, Duration?)>[];
  final playbacks = <_RecordedPlayback>[];
  final Future<void> Function(Uri)? beforeOpen;
  final Future<void> Function()? beforePlay, beforePause, beforeDispose;

  @override
  final bool supportsHls;

  @override
  bool get isAvailable => memory.isAvailable;

  @override
  String? get unavailableReason => memory.unavailableReason;

  @override
  List<double> get supportedRates => memory.supportedRates;

  @override
  Future<VideoPlayback> open(Uri url, {Duration? startAt}) async {
    opens.add((url, startAt));
    await beforeOpen?.call(url);
    final playback = _RecordedPlayback(
      await memory.open(url, startAt: startAt),
      url,
      beforePlay,
      beforePause,
      beforeDispose,
    );
    playbacks.add(playback);
    return playback;
  }
}

final class _RecordedPlayback implements VideoPlayback {
  _RecordedPlayback(
    this.memory,
    this.url,
    this.beforePlay,
    this.beforePause,
    this.beforeDispose,
  );

  final MemoryVideoPlayback memory;
  final Uri url;
  final Future<void> Function()? beforePlay, beforePause, beforeDispose;
  final calls = <String>[];

  @override
  ValueListenable<VideoPlaybackState> get state => memory.state;

  @override
  Future<void> play() async {
    calls.add('播放');
    await beforePlay?.call();
    await memory.play();
  }

  @override
  Future<void> pause() async {
    calls.add('暂停');
    await beforePause?.call();
    await memory.pause();
  }

  @override
  Future<void> seekTo(Duration position) {
    calls.add('跳转');
    return memory.seekTo(position);
  }

  @override
  Future<void> setRate(double rate) => memory.setRate(rate);

  @override
  Widget buildView() => SizedBox(key: ValueKey(url));

  @override
  Future<void> dispose() async {
    calls.add('释放');
    try {
      await beforeDispose?.call();
    } finally {
      await memory.dispose();
    }
  }
}

final _teacherUrl = Uri.https('example.invalid', '/teacher.mp4');
final _slidesUrl = Uri.https('example.invalid', '/slides.mp4');
final _liveUrl = Uri.https('example.invalid', '/teacher.m3u8');

Future<void> _pumpPlayer(
  WidgetTester tester,
  ClassroomFixture fixture, {
  VideoPlaybackCapability? playback,
  ClassroomStatus status = ClassroomStatus.replay,
  double width = 420,
  double height = 900,
}) async {
  setViewport(tester, width: width, height: height);
  await pumpClassroom(
    tester,
    ClassroomPlayerPage(
      access: fixture.access(playback: playback),
      courseId: fixture.data.courseId,
      courseTitle: fixture.data.title,
      session: fixture.period(status),
    ),
  );
}

Future<void> _expectDisposed(MemoryVideoPlayback playback) async {
  final previous = playback.state.value;
  await playback.seekTo(const Duration(minutes: 7));
  playback.replaceState(const VideoPlaybackState());
  expect(playback.state.value, same(previous));
}

Finder get _playerBack => find.descendant(
  of: find.byType(ClassroomPlayerPage),
  matching: find.byTooltip('返回'),
);

void main() {
  testWidgets('回放默认打开教师路并开始播放，切换 PPT 路时保持同一位置（不按 time_offset 平移）和倍速', (
    tester,
  ) async {
    final fixture = await ClassroomFixture.load();
    final capability = _RecordingPlayback();
    await _pumpPlayer(tester, fixture, playback: capability);

    expect(capability.opens, [(_teacherUrl, Duration.zero)]);
    final teacher = capability.memory.lastPlayback!;
    expect(teacher.state.value.isPlaying, isTrue);

    await tester.tap(find.text('倍速'));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.text('1.5×'));
    expect(teacher.state.value.rate, 1.5);
    await teacher.seekTo(const Duration(seconds: 30));
    await tester.pump();
    await tapAndSettle(tester, find.text('PPT'));

    const slidesStart = Duration(seconds: 30);
    expect(capability.opens, [
      (_teacherUrl, Duration.zero),
      (_slidesUrl, slidesStart),
    ]);
    final slides = capability.memory.lastPlayback!;
    expect(slides.state.value.position, slidesStart);
    expect(slides.state.value.rate, 1.5);
    expect(slides.state.value.isPlaying, isTrue);
    await _expectDisposed(teacher);
  });

  testWidgets('全屏换源后画面与暂停、播放、进度均使用新句柄', (tester) async {
    final fixture = await ClassroomFixture.load();
    final nextSource = Completer<void>();
    final capability = _RecordingPlayback(
      beforeOpen: (url) async {
        if (url == _slidesUrl) await nextSource.future;
      },
    );
    await _pumpPlayer(tester, fixture, playback: capability);
    final teacher = capability.playbacks.single;
    await tapAndSettle(tester, find.byTooltip('全屏'));
    expect(find.byKey(ValueKey(_teacherUrl)), findsOneWidget);

    await tester.tap(find.text('PPT'));
    await tester.pump();
    expect(find.byKey(ValueKey(_teacherUrl)), findsNothing);
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    nextSource.complete();
    await tester.pumpAndSettle();

    final slides = capability.playbacks.last;
    expect(find.byKey(ValueKey(_slidesUrl)), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('暂停'));
    expect(slides.state.value.isPlaying, isFalse);
    await tester.tapAt(tester.getRect(find.byType(Slider)).center);
    await tester.pumpAndSettle();
    expect(slides.state.value.position, greaterThan(Duration.zero));
    await tapAndSettle(tester, find.byTooltip('播放').first);
    expect(slides.state.value.isPlaying, isTrue);
    expect(slides.calls, ['播放', '暂停', '跳转', '播放']);
    expect(teacher.calls, ['播放', '释放']);

    await tapAndSettle(tester, find.byTooltip('退出全屏'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(ValueKey(_slidesUrl)), findsOneWidget);
  });

  for (final platform in TargetPlatform.values.where(
    (platform) => const {'android', 'iOS', 'ohos'}.contains(platform.name),
  )) {
    final ohos = platform.name == 'ohos';
    testWidgets('${platform.name} 全屏进入隐藏系统栏并横屏，退出后恢复', (tester) async {
      final calls = <List<Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode' ||
              call.method == 'SystemChrome.setEnabledSystemUIOverlays' ||
              call.method == 'SystemChrome.setPreferredOrientations') {
            calls.add([call.method, call.arguments]);
          }
          return null;
        },
      );
      final fixture = await ClassroomFixture.load();
      await _pumpPlayer(
        tester,
        fixture,
        playback: MemoryVideoPlaybackCapability(),
      );

      await tapAndSettle(tester, find.byTooltip('全屏'));
      expect(calls, [
        if (ohos)
          ['SystemChrome.setEnabledSystemUIOverlays', <String>[]]
        else
          [
            'SystemChrome.setEnabledSystemUIMode',
            'SystemUiMode.immersiveSticky',
          ],
        [
          'SystemChrome.setPreferredOrientations',
          [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ],
        ],
      ]);

      calls.clear();
      await tapAndSettle(tester, find.byTooltip('退出全屏'));
      expect(calls, [
        if (ohos)
          [
            'SystemChrome.setEnabledSystemUIOverlays',
            ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
          ]
        else
          ['SystemChrome.setEnabledSystemUIMode', 'SystemUiMode.edgeToEdge'],
        [
          'SystemChrome.setPreferredOrientations',
          ['DeviceOrientation.portraitUp'],
        ],
      ]);
      await tester.pump(const Duration(seconds: 1));
      expect(calls.last, ['SystemChrome.setPreferredOrientations', <String>[]]);
      expect(calls, hasLength(3));
    }, variant: TargetPlatformVariant({platform}));

    if (ohos) {
      for (final (menu, option, withNotice) in [
        ('更多', '用外部播放器打开', false),
        ('倍速', '1.5×', false),
        ('更多', '用外部播放器打开', true),
      ]) {
        testWidgets('OHOS 迟到的全屏进入失败会关闭$menu菜单${withNotice ? '并保留上层公告' : ''}', (
          tester,
        ) async {
          final landscape = Completer<void>();
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'SystemChrome.setPreferredOrientations' &&
                (call.arguments as List).contains(
                  'DeviceOrientation.landscapeLeft',
                )) {
              await landscape.future;
              throw PlatformException(code: '合成横屏设置失败');
            }
            return null;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          final fixture = await ClassroomFixture.load();
          final capability = _RecordingPlayback();
          await _pumpPlayer(tester, fixture, playback: capability);
          await tapAndSettle(tester, find.byTooltip('全屏'));
          await tapAndSettle(tester, find.byTooltip(menu));
          expect(find.text(option), findsOneWidget);

          if (withNotice) {
            final context = tester.element(find.byTooltip('退出全屏'));
            unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(title: Text('演示公告')),
              ),
            );
            await tester.pumpAndSettle();
          } else {
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(find.text(option), findsNothing);
            expect(find.byTooltip('退出全屏'), findsOneWidget);
            await tapAndSettle(tester, find.byTooltip(menu));
            expect(find.text(option), findsOneWidget);
          }

          landscape.complete();
          try {
            await tester.pumpAndSettle();
            if (withNotice) {
              expect(find.text('演示公告'), findsOneWidget);
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }

            expect(find.byTooltip('退出全屏'), findsNothing);
            expect(find.text(option, skipOffstage: false), findsNothing);
            expect(find.byTooltip('全屏'), findsOneWidget);
            await tapAndSettle(tester, find.byTooltip('暂停'));
            expect(capability.playbacks.single.calls, ['播放', '暂停']);
          } finally {
            await tester.pump(const Duration(seconds: 1));
          }
        }, variant: TargetPlatformVariant({platform}));
      }
      for (final noReply in [true, false]) {
        testWidgets('OHOS 全屏通道${noReply ? '未回包时仍可手动退出' : '都报错时退出并尝试恢复'}', (
          tester,
        ) async {
          final calls = <Object?>[];
          final pending = Completer<Object?>();
          final messenger = tester.binding.defaultBinaryMessenger;
          addTearDown(
            () => messenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            ),
          );
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            switch (call.method) {
              case 'SystemChrome.setEnabledSystemUIMode':
              case 'SystemChrome.setEnabledSystemUIOverlays':
              case 'SystemChrome.setPreferredOrientations':
                calls.add(call.arguments);
                if (call.arguments case final List args
                    when noReply &&
                        (args.isEmpty &&
                                call.method ==
                                    'SystemChrome.setEnabledSystemUIOverlays' ||
                            args.contains('DeviceOrientation.portraitUp'))) {
                  return pending.future;
                }
                if (!noReply) throw PlatformException(code: '合成系统栏或方向设置失败');
            }
            return null;
          });
          final fixture = await ClassroomFixture.load();
          await _pumpPlayer(
            tester,
            fixture,
            playback: MemoryVideoPlaybackCapability(),
          );

          await tapAndSettle(tester, find.byTooltip('全屏'));
          if (noReply) {
            expect(find.byTooltip('退出全屏'), findsOneWidget);
            await tapAndSettle(tester, find.byTooltip('退出全屏'));
          }
          await tester.pump(const Duration(seconds: 1));
          expect(find.byTooltip('全屏'), findsOneWidget);
          expect(calls, [
            <String>[],
            [
              'DeviceOrientation.landscapeLeft',
              'DeviceOrientation.landscapeRight',
            ],
            ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
            ['DeviceOrientation.portraitUp'],
            if (!noReply) ...[
              ['SystemUiOverlay.top', 'SystemUiOverlay.bottom'],
              ['DeviceOrientation.portraitUp'],
            ],
            <String>[],
            if (!noReply) <String>[],
          ]);
          expect(tester.takeException(), isNull);
        }, variant: TargetPlatformVariant({platform}));
      }
      for (final exiting in [false, true]) {
        for (final systemUiFails in [false, true]) {
          testWidgets(
            'OHOS ${exiting ? '退出' : '进入'}全屏时${systemUiFails ? '仅系统栏失败' : '仅方向失败'}会恢复两项设置',
            (tester) async {
              final finishFailure = Completer<void>();
              var failedRequestSent = false;
              var barsHidden = false;
              var landscapeLocked = false;
              final orientations = <List<String>>[];
              final messenger = tester.binding.defaultBinaryMessenger;
              messenger.setMockMethodCallHandler(SystemChannels.platform, (
                call,
              ) async {
                final systemUi =
                    call.method == 'SystemChrome.setEnabledSystemUIOverlays';
                if (!systemUi &&
                    call.method != 'SystemChrome.setPreferredOrientations') {
                  return null;
                }
                final args = List<String>.from(call.arguments as List);
                final fullscreen = systemUi
                    ? args.isEmpty
                    : args.contains('DeviceOrientation.landscapeLeft');
                if (!failedRequestSent &&
                    systemUi == systemUiFails &&
                    fullscreen != exiting) {
                  failedRequestSent = true;
                  await finishFailure.future;
                  throw PlatformException(code: '合成单项设置失败');
                }
                if (systemUi) {
                  barsHidden = fullscreen;
                } else {
                  orientations.add(args);
                  landscapeLocked = fullscreen;
                }
                return null;
              });
              addTearDown(
                () => messenger.setMockMethodCallHandler(
                  SystemChannels.platform,
                  null,
                ),
              );
              final fixture = await ClassroomFixture.load();
              await _pumpPlayer(
                tester,
                fixture,
                playback: MemoryVideoPlaybackCapability(),
              );
              await tapAndSettle(tester, find.byTooltip('全屏'));
              if (exiting) {
                expect(barsHidden && landscapeLocked, isTrue);
                await tapAndSettle(tester, find.byTooltip('退出全屏'));
              }
              expect(failedRequestSent, isTrue);
              expect(barsHidden, systemUiFails == exiting);
              expect(landscapeLocked, systemUiFails != exiting);

              finishFailure.complete();
              await tester.pumpAndSettle();
              final restored = (barsHidden, landscapeLocked);
              final fullscreenClosed = find
                  .byTooltip('退出全屏')
                  .evaluate()
                  .isEmpty;
              await tester.pump(const Duration(seconds: 1));
              // 即使断言失败也退出残留路由，避免测试结束时留下延迟任务。
              if (!fullscreenClosed) {
                await tapAndSettle(tester, find.byTooltip('退出全屏'));
                await tester.pump(const Duration(seconds: 1));
              }
              expect(fullscreenClosed, isTrue);
              expect(restored, (false, false));
              expect(orientations.last, isEmpty);
              expect(tester.takeException(), isNull);
            },
            variant: TargetPlatformVariant({platform}),
          );
        }
      }
    }
  }

  for (final switchSource in [false, true]) {
    testWidgets('${switchSource ? '换源' : '首次打开'}等候期间进入后台，句柄交付后不自动播放', (
      tester,
    ) async {
      final fixture = await ClassroomFixture.load();
      final opening = Completer<void>();
      final delayedUrl = switchSource ? _slidesUrl : _teacherUrl;
      final capability = _RecordingPlayback(
        beforeOpen: (url) async {
          if (url == delayedUrl) await opening.future;
        },
      );
      setViewport(tester);
      await pumpClassroom(tester, fixture.view(playback: capability));
      final replay = find.text(fixture.period(ClassroomStatus.replay).title);
      if (switchSource) {
        await tapAndSettle(tester, replay);
        await tester.tap(find.text('PPT'));
      } else {
        await tester.tap(replay);
      }
      await tester.pump();
      expect(capability.opens.last.$1, delayedUrl);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      try {
        opening.complete();
        await tester.pump();
        final playback = capability.playbacks.last;
        expect(playback.url, delayedUrl);
        expect(playback.calls, isNot(contains('播放')));
        expect(playback.state.value.isPlaying, isFalse);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
    });
  }

  testWidgets('开始播放尚未完成时进入后台，结束后保持暂停', (tester) async {
    final fixture = await ClassroomFixture.load();
    final play = Completer<void>();
    final capability = _RecordingPlayback(beforePlay: () => play.future);
    setViewport(tester);
    await pumpClassroom(tester, fixture.view(playback: capability));
    await tester.tap(find.text(fixture.period(ClassroomStatus.replay).title));
    await tester.pump();
    final playback = capability.playbacks.single;
    expect(playback.calls, ['播放']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    try {
      play.complete();
      await tester.pump();
      expect(playback.state.value.isPlaying, isFalse);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();
  });

  testWidgets('后台暂停失败后释放待交付句柄，迟到开播保留播放错误', (tester) async {
    final fixture = await ClassroomFixture.load();
    final play = Completer<void>();
    final pause = Completer<void>();
    final capability = _RecordingPlayback(
      beforePlay: () => play.future,
      beforePause: () => pause.future,
    );
    setViewport(tester);
    await pumpClassroom(tester, fixture.view(playback: capability));
    await tester.tap(find.text(fixture.period(ClassroomStatus.replay).title));
    await tester.pump();
    final playback = capability.playbacks.single;
    expect(playback.calls, ['播放']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    try {
      pause.completeError(const VideoPlaybackException('合成后台暂停失败'));
      await tester.pump();
      expect(playback.calls, ['播放', '暂停', '释放']);
    } finally {
      play.complete();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('合成后台暂停失败'), findsOneWidget);
    expect(playback.state.value.isPlaying, isFalse);
    expect(find.byKey(ValueKey(_teacherUrl)), findsNothing);
  });

  testWidgets('切换到 PPT 后卸载帧前进入后台，先暂停教师路再卸载释放', (tester) async {
    final fixture = await ClassroomFixture.load();
    final teacherView = find.byKey(ValueKey(_teacherUrl), skipOffstage: false);
    final capability = _RecordingPlayback(
      beforeDispose: () async => expect(teacherView, findsNothing),
    );
    await _pumpPlayer(tester, fixture, playback: capability);
    final teacher = capability.playbacks.single;

    await tester.tap(find.text('PPT'));
    expect(teacherView, findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    try {
      await tester.idle();
      expect(teacher.calls, ['播放', '暂停']);
      expect(teacher.state.value.isPlaying, isFalse);
      expect(teacherView, findsOneWidget);
      expect(capability.opens, hasLength(1));
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();

    expect(teacher.calls, ['播放', '暂停', '释放']);
    expect(find.byKey(ValueKey(_slidesUrl)), findsOneWidget);
    expect(capability.playbacks.last.calls, ['播放']);
    expect(capability.playbacks.last.state.value.isPlaying, isTrue);
  });

  for (final switchSource in [false, true]) {
    testWidgets('全屏后台暂停失败后，${switchSource ? '切源' : '重试'}须等待旧句柄释放', (
      tester,
    ) async {
      final fixture = await ClassroomFixture.load();
      final disposal = Completer<void>();
      int? controlsAtDisposal;
      int? viewsAtDisposal;
      final capability = _RecordingPlayback(
        beforePause: () async {
          if (!disposal.isCompleted) {
            throw const VideoPlaybackException('合成后台暂停失败');
          }
        },
        beforeDispose: () async {
          if (disposal.isCompleted) return;
          controlsAtDisposal = find
              .byType(ClassroomPlayerControls, skipOffstage: false)
              .evaluate()
              .length;
          viewsAtDisposal = find
              .byKey(ValueKey(_teacherUrl), skipOffstage: false)
              .evaluate()
              .length;
          await disposal.future;
        },
      );
      await _pumpPlayer(tester, fixture, playback: capability);
      await tapAndSettle(tester, find.byTooltip('全屏'));
      expect(
        find.byType(ClassroomPlayerControls, skipOffstage: false),
        findsNWidgets(2),
      );
      final teacher = capability.playbacks.single;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      try {
        await tester.pump();
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('合成后台暂停失败'), findsOneWidget);

      await tester.tap(find.text(switchSource ? '切换到 PPT' : '重试'));
      await tester.pump();
      final openedBeforeDisposal = List.of(capability.opens);
      disposal.complete();
      await tester.pumpAndSettle();

      expect(openedBeforeDisposal, hasLength(1));
      expect(controlsAtDisposal, 0);
      expect(viewsAtDisposal, 0);
      final next = capability.playbacks.last;
      expect(next, isNot(same(teacher)));
      expect(next.url, switchSource ? _slidesUrl : _teacherUrl);
      await tapAndSettle(tester, find.byTooltip('暂停'));
      expect(next.calls, ['播放', '暂停']);
      expect(teacher.calls, ['播放', '暂停', '释放']);
      await _expectDisposed(teacher.memory);
      await tapAndSettle(tester, find.byTooltip('退出全屏'));
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('全屏暂停失败后的释放挂起时销毁页面，释放只执行一次且异常留在页内', (tester) async {
    final fixture = await ClassroomFixture.load();
    final disposal = Completer<void>();
    var disposalStarted = false;
    final capability = _RecordingPlayback(
      beforePause: () async => throw const VideoPlaybackException('合成后台暂停失败'),
      beforeDispose: () async {
        if (disposalStarted) return;
        disposalStarted = true;
        await disposal.future;
      },
    );
    await _pumpPlayer(tester, fixture, playback: capability);
    await tapAndSettle(tester, find.byTooltip('全屏'));
    final teacher = capability.playbacks.single;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    try {
      await tester.pump();
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();
    expect(teacher.calls, ['播放', '暂停', '释放']);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    disposal.completeError(const VideoPlaybackException('合成释放失败'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(capability.opens, hasLength(1));
    expect(teacher.calls, ['播放', '暂停', '释放']);
    await _expectDisposed(teacher.memory);
  });

  testWidgets('旧来源的后台暂停迟到失败不影响新句柄', (tester) async {
    final fixture = await ClassroomFixture.load();
    final pause = Completer<void>();
    final capability = _RecordingPlayback(beforePause: () => pause.future);
    await _pumpPlayer(tester, fixture, playback: capability);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tapAndSettle(tester, find.text('PPT'));
    pause.completeError(const VideoPlaybackException('合成旧来源暂停失败'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(ValueKey(_slidesUrl)), findsOneWidget);
    expect(capability.playbacks.last.state.value.isPlaying, isTrue);
  });

  testWidgets('全屏播放失败后仍能切换到同节次的 PPT 路', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = _RecordingPlayback();
    await _pumpPlayer(tester, fixture, playback: capability);
    final teacher = capability.playbacks.single;
    await tapAndSettle(tester, find.byTooltip('全屏'));

    teacher.memory.replaceState(const VideoPlaybackState(error: '合成教师路播放失败'));
    await tester.pumpAndSettle();
    expect(find.text('视频播放失败'), findsOneWidget);
    await tapAndSettle(tester, find.text('切换到 PPT'));
    expect(find.byKey(ValueKey(_slidesUrl)), findsOneWidget);
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(teacher.calls, ['播放', '释放']);
    final slides = capability.playbacks.last;
    await tapAndSettle(tester, find.byTooltip('播放').first);
    expect(slides.state.value.isPlaying, isTrue);
    expect(slides.calls, ['播放']);
    await tapAndSettle(tester, find.byTooltip('退出全屏'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('暂停期间控件保持显示，恢复播放三秒后隐藏', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = MemoryVideoPlaybackCapability();
    await _pumpPlayer(tester, fixture, playback: capability);
    final playback = capability.lastPlayback!;
    final controls = find.descendant(
      of: find.byType(ClassroomPlayerControls),
      matching: find.byType(AnimatedOpacity),
    );
    double opacity() => tester.widget<AnimatedOpacity>(controls).opacity;

    await playback.pause();
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(), 1);
    await playback.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2999));
    expect(opacity(), 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(opacity(), 0);
  });

  testWidgets('点击章节、逐字稿和摘要时间链接，按教师时间轴跳转并播放', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = MemoryVideoPlaybackCapability();
    await _pumpPlayer(tester, fixture, playback: capability);
    final playback = capability.lastPlayback!;

    Future<void> checkSeek(Finder control, Duration expected) async {
      await playback.seekTo(const Duration(seconds: 30));
      await playback.pause();
      await tester.pump();
      await tester.ensureVisible(control);
      await tapAndSettle(tester, control);
      expect(playback.state.value.position, expected);
      expect(playback.state.value.isPlaying, isTrue);
    }

    await checkSeek(find.text('课堂介绍'), Duration.zero);
    await tapAndSettle(tester, find.text('逐字稿'));
    await checkSeek(find.text('点击时间点可以跳到相应片段。'), const Duration(seconds: 3));
    await tapAndSettle(tester, find.text('摘要'));
    await tapAndSettle(tester, find.text('如何定位片段？'));
    await checkSeek(find.text('跳到 00:03'), const Duration(seconds: 3));
  });

  testWidgets('逐字稿搜索显示命中计数和无结果，清除后恢复普通列表', (tester) async {
    final fixture = await ClassroomFixture.load();
    await _pumpPlayer(
      tester,
      fixture,
      playback: MemoryVideoPlaybackCapability(),
    );

    await tapAndSettle(tester, find.text('逐字稿'));
    final search = find.widgetWithText(TextField, '搜索逐字稿');
    await tester.enterText(search, '。');
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('下一个'));
    expect(find.text('2/2'), findsOneWidget);

    await tester.enterText(search, '没有这句');
    await tester.pumpAndSettle();
    expect(find.text('无结果'), findsOneWidget);
    await tapAndSettle(tester, find.byTooltip('清除'));
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('无结果'), findsNothing);
    expect(find.byTooltip('清除'), findsNothing);
    expect(find.text('今天介绍课堂直录播的示例。'), findsOneWidget);
    expect(find.text('点击时间点可以跳到相应片段。'), findsOneWidget);
  });

  testWidgets('点击另一个资料页签时立即取消逐字稿搜索焦点', (tester) async {
    final fixture = await ClassroomFixture.load();
    await _pumpPlayer(
      tester,
      fixture,
      playback: MemoryVideoPlaybackCapability(),
    );
    await tapAndSettle(tester, find.text('逐字稿'));
    final search = find.widgetWithText(TextField, '搜索逐字稿');
    await tester.enterText(search, '。');
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('摘要'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.pumpAndSettle();
  });

  for (final (description, capability, reason) in [
    ('缺少播放能力', null, '当前平台暂不支持应用内播放'),
    ('播放能力不可用', const UnavailableVideoPlayback(), '当前平台不支持应用内播放'),
  ]) {
    testWidgets('$description时可用外部播放器打开回放', (tester) async {
      final fixture = await ClassroomFixture.load();
      await _pumpPlayer(tester, fixture, playback: capability);

      expect(find.text(reason), findsOneWidget);
      expect(find.byType(ClassroomPlayerControls), findsNothing);
      expect(fixture.externalUrls, isEmpty);
      await tapAndSettle(tester, find.text('用外部播放器打开'));
      expect(fixture.externalUrls, [_teacherUrl]);
    });
  }

  testWidgets('不支持 HLS 时直播只提供外部打开，不创建应用内播放实例', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = _RecordingPlayback(supportsHls: false);
    await _pumpPlayer(
      tester,
      fixture,
      playback: capability,
      status: ClassroomStatus.live,
    );

    expect(find.text('当前平台暂不支持在应用内看直播'), findsOneWidget);
    expect(capability.opens, isEmpty);
    expect(fixture.externalUrls, isEmpty);
    await tapAndSettle(tester, find.text('用外部播放器打开'));
    expect(fixture.externalUrls, [_liveUrl]);
    expect(capability.opens, isEmpty);
  });

  testWidgets('返回节次列表且画面卸载后进入后台，释放不等下一帧', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = _RecordingPlayback();
    setViewport(tester);
    await pumpClassroom(tester, fixture.view(playback: capability));
    final replay = fixture.period(ClassroomStatus.replay);
    await tapAndSettle(tester, find.text(replay.title));
    final playback = capability.playbacks.single;
    expect(playback.state.value.isPlaying, isTrue);

    await tester.tap(_playerBack);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ClassroomPlayerPage, skipOffstage: false), findsNothing);
    expect(
      find.byKey(ValueKey(_teacherUrl), skipOffstage: false),
      findsNothing,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    try {
      await tester.idle();
      expect(playback.calls, ['播放', '释放']);
      await _expectDisposed(playback.memory);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();
    expect(find.text(replay.title), findsOneWidget);
    expect(playback.calls, ['播放', '释放']);
  });

  testWidgets('退出时也释放仍在等待开始播放的实例', (tester) async {
    final fixture = await ClassroomFixture.load();
    final play = Completer<void>();
    final capability = _RecordingPlayback(beforePlay: () => play.future);
    setViewport(tester);
    await pumpClassroom(tester, fixture.view(playback: capability));
    await tester.tap(find.text(fixture.period(ClassroomStatus.replay).title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final playback = capability.memory.lastPlayback!;
    expect(playback.state.value.isPlaying, isFalse);

    await tapAndSettle(tester, _playerBack);
    expect(find.byType(ClassroomPlayerPage), findsNothing);
    await _expectDisposed(playback);
    play.complete();
    await tester.pump();
    expect(playback.state.value.isPlaying, isFalse);
  });

  testWidgets('开始播放失败时释放已创建的实例', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = _RecordingPlayback(
      beforePlay: () async => throw const VideoPlaybackException('演示播放失败'),
    );
    await _pumpPlayer(tester, fixture, playback: capability);

    expect(find.text('视频播放失败'), findsOneWidget);
    expect(find.text('演示播放失败'), findsOneWidget);
    final playback = capability.memory.lastPlayback!;
    await _expectDisposed(playback);
  });

  testWidgets('播放错误与标题相同则显示通用失败说明', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = MemoryVideoPlaybackCapability();
    await _pumpPlayer(tester, fixture, playback: capability);
    capability.lastPlayback!.replaceState(
      const VideoPlaybackState(error: '视频播放失败'),
    );
    await tester.pumpAndSettle();
    expect(find.text('视频播放失败'), findsOneWidget);
    expect(find.text('请重试，或用外部播放器打开'), findsOneWidget);
  });

  for (final (width, height, sideWidth) in [
    (899.0, 900.0, null),
    (900.0, 900.0, 380.0),
    (874.0, 402.0, 874 * 0.42),
  ]) {
    testWidgets(
      '${width.toInt()}×${height.toInt()} 下资料区${sideWidth == null ? '位于视频下方' : '位于视频右侧'}',
      (tester) async {
        final fixture = await ClassroomFixture.load();
        await _pumpPlayer(
          tester,
          fixture,
          playback: MemoryVideoPlaybackCapability(),
          width: width,
          height: height,
        );

        final video = tester.getRect(find.byType(ClassroomPlayerControls));
        final tabs = tester.getRect(find.byType(TabBar));
        expect(tester.takeException(), isNull);
        if (sideWidth != null) {
          expect(tabs.left, greaterThan(video.right));
          expect(tabs.top, closeTo(video.top, 1));
          expect(tabs.width, closeTo(sideWidth, 1));
        } else {
          expect(tabs.top, greaterThanOrEqualTo(video.bottom));
          expect(tabs.left, closeTo(video.left, 1));
        }
      },
    );
  }
}
