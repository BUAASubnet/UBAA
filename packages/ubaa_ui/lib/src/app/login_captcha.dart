import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 从 Core 已解码像素建立本控件独占的图形对象，不使用 ImageProvider 或全局缓存。
class CaptchaPixels extends StatefulWidget {
  const CaptchaPixels({required this.frame});
  final CaptchaPixelFrame frame;

  @override
  State<CaptchaPixels> createState() => _CaptchaPixelsState();
}

class _CaptchaPixelsState extends State<CaptchaPixels> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(covariant CaptchaPixels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) {
      _image?.dispose();
      _image = null;
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final generation = ++_generation;
    final frame = widget.frame;
    final bytes = frame.rgba;
    if (bytes == null ||
        frame.width <= 0 ||
        frame.height <= 0 ||
        frame.width > 1024 ||
        frame.height > 1024 ||
        bytes.length != frame.width * frame.height * 4)
      return;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      if (!mounted || generation != _generation || frame.isReleased) return;
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: frame.width,
        height: frame.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      decoded = (await codec.getNextFrame()).image;
      if (!mounted || generation != _generation || frame.isReleased) return;
      setState(() {
        _image = decoded;
        decoded = null;
      });
    } on Object {
      // 图形系统失败只影响当前控件；刷新入口保持可用，不导出图像或错误原文。
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _image != null && !widget.frame.isReleased
      ? RawImage(
          image: _image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        )
      : const Text('正在显示验证码');
}
