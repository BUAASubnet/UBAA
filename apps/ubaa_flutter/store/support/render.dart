import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 宣传图统一使用的字体族；测试环境默认字体只画方块，必须显式加载真实字体。
const storeFontFamily = 'StoreSans';

/// 商店截图规格：画布是商店要求的像素尺寸，屏幕是应用实际排版的逻辑尺寸。
enum StoreDevice {
  // 默认手机竖屏。
  iphone(
    canvas: Size(1179, 2556),
    screen: Size(393, 852),
    pixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
  // App Store 大屏 iPhone。
  iphoneLarge(
    canvas: Size(1320, 2868),
    screen: Size(440, 956),
    pixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
  // App Store 中号 Dynamic Island iPhone。
  iphoneMedium(
    canvas: Size(1206, 2622),
    screen: Size(402, 874),
    pixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
    platform: TargetPlatform.iOS,
  ),
  // 默认平板横屏。
  ipad(
    canvas: Size(2732, 2048),
    screen: Size(1366, 1024),
    pixelRatio: 2,
    padding: EdgeInsets.only(top: 24, bottom: 20),
    platform: TargetPlatform.iOS,
  ),
  // Google Play 与鸿蒙应用市场的 9:16 手机图。
  android(
    canvas: Size(1080, 1920),
    screen: Size(412, 915),
    pixelRatio: 2.625,
    padding: EdgeInsets.only(top: 36, bottom: 24),
    platform: TargetPlatform.android,
  ),
  // Mac App Store 与使用指南网站的桌面图。
  desktop(
    canvas: Size(2880, 1800),
    screen: Size(1280, 760),
    pixelRatio: 2,
    padding: EdgeInsets.zero,
    platform: TargetPlatform.macOS,
  );

  const StoreDevice({
    required this.canvas,
    required this.screen,
    required this.pixelRatio,
    required this.padding,
    required this.platform,
  });

  final Size canvas;
  final Size screen;
  final double pixelRatio;
  final EdgeInsets padding;
  final TargetPlatform platform;

  String get directory => switch (this) {
    iphoneLarge => 'iphone_large',
    iphoneMedium => 'iphone_medium',
    _ => name,
  };
}

/// 按字体目录加载思源黑体（Noto Sans CJK SC）与 Material 图标字体。
Future<void> loadStoreFonts(WidgetTester tester) async {
  final directory = _fontDirectory();
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/'
    'material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icons.existsSync()) {
    throw StateError('找不到 Flutter SDK 自带的 Material 图标字体：${icons.path}');
  }
  await tester.runAsync(() async {
    final sans = FontLoader(storeFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
      sans.addFont(_bytes(File('${directory.path}/NotoSansCJKsc-$weight.otf')));
    }
    await sans.load();
    await (FontLoader('MaterialIcons')..addFont(_bytes(icons))).load();
  });
}

Directory _fontDirectory() {
  final home = Platform.environment['HOME'] ?? '';
  final candidates = [
    Platform.environment['UBAA_STORE_FONT_DIR'],
    '$home/Library/Fonts',
    '/Library/Fonts',
    '/usr/share/fonts/opentype/noto',
  ].whereType<String>();
  for (final path in candidates) {
    if (File('$path/NotoSansCJKsc-Regular.otf').existsSync()) {
      return Directory(path);
    }
  }
  throw StateError(
    '缺少 Noto Sans CJK SC 字体（NotoSansCJKsc-Regular.otf 等）。'
    '请安装后重试，或用 UBAA_STORE_FONT_DIR 指向字体目录。',
  );
}

Future<ByteData> _bytes(File file) async =>
    ByteData.sublistView(await file.readAsBytes());

/// 截取 [key] 对应的 RepaintBoundary，调用方在使用后释放图像。
Future<ui.Image> captureBoundary(
  WidgetTester tester,
  Key key, {
  double pixelRatio = 1,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(
    () => boundary.toImage(pixelRatio: pixelRatio),
  ))!;
}
