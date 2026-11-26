import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/player_controls.dart';
import 'package:ubaa_ui/src/features/spoc_classroom/player_page.dart';

import 'fixture.dart';

final class _RecordingPlayback implements VideoPlaybackCapability {
  _RecordingPlayback({this.supportsHls = true, this.beforePlay});

  final memory = MemoryVideoPlaybackCapability();
  final opens = <(Uri, Duration?)>[];
  final Future<void> Function()? beforePlay;

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
    final playback = await memory.open(url, startAt: startAt);
    final hook = beforePlay;
    return hook == null ? playback : _PendingPlayback(playback, hook);
  }
}

final class _PendingPlayback implements VideoPlayback {
  _PendingPlayback(this.memory, this.beforePlay);

  final MemoryVideoPlayback memory;
  final Future<void> Function() beforePlay;

  @override
  ValueListenable<VideoPlaybackState> get state => memory.state;

  @override
  Future<void> play() async {
    await beforePlay();
    await memory.play();
  }

  @override
  Future<void> pause() => memory.pause();

  @override
  Future<void> seekTo(Duration position) => memory.seekTo(position);

  @override
  Future<void> setRate(double rate) => memory.setRate(rate);

  @override
  Widget buildView() => memory.buildView();

  @override
  Future<void> dispose() => memory.dispose();
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

  testWidgets('从节次列表进入回放后返回，播放实例不再更新', (tester) async {
    final fixture = await ClassroomFixture.load();
    final capability = MemoryVideoPlaybackCapability();
    setViewport(tester);
    await pumpClassroom(tester, fixture.view(playback: capability));
    final replay = fixture.period(ClassroomStatus.replay);
    await tapAndSettle(tester, find.text(replay.title));
    final playback = capability.lastPlayback!;
    expect(playback.state.value.isPlaying, isTrue);

    await tapAndSettle(tester, _playerBack);
    expect(find.byType(ClassroomPlayerPage), findsNothing);
    expect(find.text(replay.title), findsOneWidget);
    await _expectDisposed(playback);
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
