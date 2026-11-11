// 这个 Widget 测试放在 store/，只由宣传图命令显式运行。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

import '../test_driver/evidence_directory.dart';
import 'support/frame.dart';
import 'support/promo_backend.dart';
import 'support/promo_data.dart';
import 'support/render.dart';

const _screenKey = ValueKey('store-screen');
const _frameKey = ValueKey('store-frame');

void main() {
  late Directory destination;
  var fontsLoaded = false;
  setUpAll(() async {
    destination = checkedEvidenceDirectory(
      Platform.environment['UBAA_UI_EVIDENCE_DIR'],
    );
    if (await destination.exists() && !await destination.list().isEmpty) {
      throw StateError('宣传图输出目录必须为空，请使用新的任务子目录。');
    }
    await destination.create(recursive: true);
    final permissions = await Process.run('chmod', ['700', destination.path]);
    if (permissions.exitCode != 0) throw StateError('无法设置输出目录私有权限。');
  });

  for (final device in StoreDevice.values) {
    testWidgets('宣传图 ${device.directory}', (tester) async {
      if (!fontsLoaded) {
        await loadStoreFonts(tester);
        fontsLoaded = true;
      }
      debugDefaultTargetPlatformOverride = device.platform;
      UbaaTheme.debugFontFamily = storeFontFamily;
      final previousShadows = debugDisableShadows;
      // Flutter 测试默认以纯色描边代替 Material 阴影。宣传图保留应用外观。
      debugDisableShadows = false;
      try {
        final output = Directory('${destination.path}/${device.directory}')
          ..createSync();
        await withClock(Clock.fixed(storeNow), () async {
          for (final scene in _scenes(device)) {
            final screen = await _renderScreen(tester, device, scene);
            try {
              await _writeFrame(tester, device, scene, screen, output);
            } finally {
              screen.dispose();
            }
          }
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
        UbaaTheme.debugFontFamily = null;
        debugDisableShadows = previousShadows;
        tester.view.reset();
      }
    });
  }
}

Future<ui.Image> _renderScreen(
  WidgetTester tester,
  StoreDevice device,
  _Scene scene,
) async {
  tester.view.devicePixelRatio = device.pixelRatio;
  tester.view.physicalSize = device.screen * device.pixelRatio;
  final padding = FakeViewPadding(
    top: device.padding.top * device.pixelRatio,
    bottom: device.padding.bottom * device.pixelRatio,
  );
  tester.view.padding = padding;
  tester.view.viewPadding = padding;

  if (device == StoreDevice.ipad || device == StoreDevice.desktop) {
    // 侧栏图标由资源包异步解码，布局稳定时图片未必已经可绘制。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await precacheImage(
        ResizeImage(
          const AssetImage('assets/icons/app_icon.png', package: 'ubaa_ui'),
          // 侧栏按 36 个逻辑像素显示，并按物理宽度缓存解码结果。
          width: (36 * device.pixelRatio).round(),
        ),
        tester.element(find.byType(SizedBox)),
      );
    });
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenKey,
      child: UbaaFlutterApp(
        backend: PromoBackend(),
        credentialVault: MemoryCredentialVault(),
        localAccountStore: const PromoAccountStore(),
        preferenceValues: MemoryPreferenceValues(),
        initialThemeMode: ThemeMode.light,
        initialDestination: scene.destination,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final feature = scene.feature;
  if (feature != null) {
    final entry = find.text(feature.title).first;
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }
  switch (scene) {
    case _Scene.agenda:
      await _tap(tester, find.byTooltip('周视图'));
    case _Scene.grades:
      await _tap(tester, find.byTooltip('下一学期'));
    case _Scene.coursework:
      await _tap(tester, find.byKey(const ValueKey('feature-filter-button')));
      await _tap(tester, find.text('仅显示未提交'));
      await _tap(tester, find.byTooltip('关闭筛选'));
    case _:
      break;
  }

  expect(tester.takeException(), isNull, reason: scene.file);
  expect(
    find
        .byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.replaceAll('\n', '') == scene.marker,
          description: '显示示例内容「${scene.marker}」',
        )
        .hitTestable(),
    findsWidgets,
    reason: '必须看见示例内容后才能生成 ${scene.file}。',
  );
  return captureBoundary(tester, _screenKey, pixelRatio: device.pixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _writeFrame(
  WidgetTester tester,
  StoreDevice device,
  _Scene scene,
  ui.Image screen,
  Directory output,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = device.canvas;
  tester.view.resetPadding();
  tester.view.resetViewPadding();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frameKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: StoreFrame(
          device: device,
          screen: screen,
          title: scene.title,
          accent: scene.accent,
          subtitle: scene.subtitle,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: scene.file);
  final frame = await captureBoundary(tester, _frameKey);
  try {
    expect(
      (frame.width, frame.height),
      (device.canvas.width.toInt(), device.canvas.height.toInt()),
    );
    await tester.runAsync(() async {
      final data = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
      await File('${output.path}/${scene.file}.png').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    });
    // 先移除引用应用截图的 Widget，再由调用方释放图像。
    await tester.pumpWidget(const SizedBox.shrink());
  } finally {
    frame.dispose();
  }
}

Iterable<_Scene> _scenes(StoreDevice device) => switch (device) {
  StoreDevice.desktop => const [_Scene.home, _Scene.schedule, _Scene.agenda],
  StoreDevice.android => _Scene.values.take(5),
  _ => _Scene.values,
};

enum _Scene {
  home('01_home', '今天上什么课', '首页一眼看清', '今日课程和学校待办集中呈现', '数据结构与程序设计'),
  schedule(
    '02_schedule',
    '这一周的课',
    '打开就是课表',
    '按周查看上课时间、教室和任课老师',
    '数据结构与程序设计',
    feature: FeatureId.schedule,
  ),
  agenda(
    '03_agenda',
    '课内课外',
    '安排在同一份日程',
    '把学校课程、个人日程和待办放在一起',
    '图书馆自习',
    destination: UiDestination.agenda,
  ),
  grades(
    '04_grades',
    '每一门课的成绩',
    '学分绩点随时查',
    '按学期查看成绩和学分',
    '操作系统',
    feature: FeatureId.grades,
  ),
  coursework(
    '05_coursework',
    '作业什么时候交',
    '进度和截止时间一起看',
    '集中查看 SPOC 作业与提交状态',
    '实验二：链表与栈',
    feature: FeatureId.spoc,
  ),
  exams(
    '06_exams',
    '考试几点开始',
    '时间地点早知道',
    '按日期查看考试安排',
    '离散数学（阶段测验）',
    feature: FeatureId.exam,
  );

  const _Scene(
    this.file,
    this.title,
    this.accent,
    this.subtitle,
    this.marker, {
    this.feature,
    UiDestination? destination,
  }) : destination =
           destination ??
           (feature == null ? UiDestination.home : UiDestination.study);

  final String file, title, accent, subtitle, marker;
  final FeatureId? feature;
  final UiDestination destination;
}
