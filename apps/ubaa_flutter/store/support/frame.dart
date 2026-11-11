import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'render.dart';

const _brand = Color(0xFF1976D2);
const _ink = Color(0xFF1F2933);
const _muted = Color(0xFF596B7E);

/// 商店宣传图：标题、副标题与带状态栏的设备屏幕，按商店像素尺寸一次排版。
class StoreFrame extends StatelessWidget {
  const StoreFrame({
    super.key,
    required this.device,
    required this.screen,
    required this.title,
    required this.accent,
    required this.subtitle,
    this.dark = false,
  });

  final StoreDevice device;
  final ui.Image screen;

  /// [title] 用正文色，[accent] 用品牌蓝。
  final String title, accent, subtitle;

  /// 屏幕内容是否为深色主题；背景与状态栏随之切换。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final size = device.canvas;
    final unit = size.shortestSide / 100;
    final tablet = device == StoreDevice.ipad;
    final headline = switch (device) {
      StoreDevice.iphone ||
      StoreDevice.iphoneLarge ||
      StoreDevice.iphoneMedium ||
      StoreDevice.android => unit * 7.6,
      StoreDevice.ipad => unit * 4.8,
      StoreDevice.desktop => unit * 5.4,
    };
    final top = switch (device) {
      StoreDevice.ipad => size.height * .027,
      StoreDevice.desktop => size.height * .045,
      _ => size.height * .04,
    };
    final titleStyle = TextStyle(
      fontFamily: storeFontFamily,
      fontSize: headline,
      height: 1.2,
      fontWeight: FontWeight.w900,
      color: dark ? Colors.white : _ink,
    );
    final accentStyle = titleStyle.copyWith(
      color: dark ? const Color(0xFF83BEF7) : _brand,
    );
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF0E1A28), Color(0xFF163250)]
                : const [Color(0xFFDCEBFA), Color(0xFFF7FAFE)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: -size.width * .25,
              top: -size.width * .2,
              child: _Glow(diameter: size.width * .8, dark: dark),
            ),
            Positioned(
              left: -size.width * .3,
              bottom: size.height * .08,
              child: _Glow(diameter: size.width * .7, dark: dark),
            ),
            Column(
              children: [
                SizedBox(height: top),
                Text(
                  'UBAA',
                  style: TextStyle(
                    fontFamily: storeFontFamily,
                    fontSize: unit * (tablet ? 2.1 : 2.7),
                    fontWeight: FontWeight.w900,
                    letterSpacing: unit * .28,
                    color: dark ? const Color(0xFF83BEF7) : _brand,
                  ),
                ),
                SizedBox(height: headline * (tablet ? .13 : .22)),
                // 横屏把两句标题排在一行，给应用界面留出高度。
                if (tablet)
                  Text.rich(
                    TextSpan(
                      text: '$title　',
                      children: [TextSpan(text: accent, style: accentStyle)],
                    ),
                    textAlign: TextAlign.center,
                    style: titleStyle,
                  )
                else ...[
                  Text(title, textAlign: TextAlign.center, style: titleStyle),
                  Text(accent, textAlign: TextAlign.center, style: accentStyle),
                ],
                SizedBox(height: headline * (tablet ? .16 : .42)),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: storeFontFamily,
                    fontSize: headline * .38,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: dark ? const Color(0xFFB8C7D9) : _muted,
                  ),
                ),
                SizedBox(height: headline * (tablet ? .43 : .9)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      size.width * .07,
                      0,
                      size.width * .07,
                      size.height * .04,
                    ),
                    child: SizedBox.expand(
                      child: _Device(
                        device: device,
                        screen: screen,
                        dark: dark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.diameter, required this.dark});
  final double diameter;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? const Color(0xFF2B6CB0) : const Color(0xFFB7D6F6);
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: dark ? .35 : .55),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// 通用设备外框：不仿制具体机型，只保留屏幕圆角、边框与前置摄像头圆点。
class _Device extends StatelessWidget {
  const _Device({
    required this.device,
    required this.screen,
    required this.dark,
  });
  final StoreDevice device;
  final ui.Image screen;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final logical = device.screen;
    final desktop = device == StoreDevice.desktop;
    // 外框以屏幕逻辑尺寸排版，再整体缩放进可用区域，圆角与状态栏随之等比。
    final bezel = switch (device) {
      StoreDevice.iphone ||
      StoreDevice.iphoneLarge ||
      StoreDevice.iphoneMedium ||
      StoreDevice.android => 11.0,
      StoreDevice.ipad => 18.0,
      StoreDevice.desktop => 0.0,
    };
    final titleBar = desktop ? 34.0 : 0.0;
    final radius = switch (device) {
      StoreDevice.iphone ||
      StoreDevice.iphoneLarge ||
      StoreDevice.iphoneMedium => 52.0,
      StoreDevice.android => 40.0,
      StoreDevice.ipad => 26.0,
      StoreDevice.desktop => 14.0,
    };
    final outer = Size(
      logical.width + bezel * 2,
      logical.height + bezel * 2 + titleBar,
    );
    return FittedBox(
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      child: Container(
        width: outer.width,
        height: outer.height,
        padding: EdgeInsets.all(bezel),
        decoration: BoxDecoration(
          color: desktop
              ? (dark ? const Color(0xFF253242) : const Color(0xFFE9EEF3))
              : const Color(0xFF1B2028),
          borderRadius: BorderRadius.circular(radius + bezel),
          border: desktop
              ? Border.all(
                  strokeAlign: BorderSide.strokeAlignOutside,
                  color: dark
                      ? const Color(0xFF3A4A5C)
                      : const Color(0xFFCBD5E0),
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B2545).withValues(alpha: .22),
              blurRadius: 60,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          children: [
            if (desktop) _TitleBar(height: titleBar, dark: dark),
            ClipRRect(
              borderRadius: desktop
                  ? BorderRadius.vertical(bottom: Radius.circular(radius))
                  : BorderRadius.circular(radius),
              child: SizedBox.fromSize(
                size: logical,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RawImage(image: screen, fit: BoxFit.fill),
                    if (!desktop) _StatusBar(device: device, dark: dark),
                    if (!desktop) _HomeIndicator(device: device, dark: dark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.height, required this.dark});
  final double height;
  final bool dark;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      children: [
        const SizedBox(width: 16),
        for (final _ in [1, 2, 3])
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? const Color(0xFF4A5A6C) : const Color(0xFFC3CCD6),
            ),
          ),
        const Spacer(),
        Text(
          'UBAA',
          style: TextStyle(
            fontFamily: storeFontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: dark ? const Color(0xFFB8C7D9) : _muted,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 76),
      ],
    ),
  );
}

/// 静态状态栏：固定时间与满格信号，避免截图暴露采集时的真实设备状态。
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.device, required this.dark});
  final StoreDevice device;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : const Color(0xFF111111);
    final height = device.padding.top;
    final android = device == StoreDevice.android;
    final ipad = device == StoreDevice.ipad;
    final iconSize = android ? 16.0 : (ipad ? 15.0 : 18.0);
    final camera = switch (device) {
      StoreDevice.iphone ||
      StoreDevice.iphoneLarge ||
      StoreDevice.iphoneMedium => 13.0,
      StoreDevice.android => 11.0,
      _ => 7.0,
    };
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: camera,
                height: camera,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B0D10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: android ? 22 : (ipad ? 24 : 36),
              ),
              child: Row(
                children: [
                  Text(
                    ipad ? '9:41  9月22日 周二' : '9:41',
                    style: TextStyle(
                      fontFamily: storeFontFamily,
                      fontSize: android ? 14 : (ipad ? 14 : 17),
                      fontWeight: android ? FontWeight.w500 : FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.signal_cellular_alt, size: iconSize, color: color),
                  const SizedBox(width: 4),
                  Icon(Icons.wifi, size: iconSize, color: color),
                  const SizedBox(width: 4),
                  RotatedBox(
                    quarterTurns: 1,
                    child: Icon(
                      Icons.battery_full,
                      size: iconSize + 4,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator({required this.device, required this.dark});
  final StoreDevice device;
  final bool dark;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      width: device == StoreDevice.ipad ? 320 : 140,
      height: 5,
      margin: EdgeInsets.only(bottom: device.padding.bottom * .3),
      decoration: BoxDecoration(
        color: dark ? Colors.white : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}
