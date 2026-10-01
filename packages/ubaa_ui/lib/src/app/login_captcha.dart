part of '../widgets.dart';

extension _LoginVerificationControls on _UbaaLoginViewState {
  List<Widget> _buildVerificationControls() => <Widget>[
    for (final route in widget.verification!.routes) ...<Widget>[
      if (route.status ==
          LoginRouteVerificationStatus.captchaRequired) ...<Widget>[
        const SizedBox(height: 16),
        Text('${route.route.label} 验证码'),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: '${route.route.label} 验证码，点击刷新',
          child: InkWell(
            key: ValueKey<String>('captcha-image-${route.route.name}'),
            onTap: widget.isLoading || widget.onRefreshCaptcha == null
                ? null
                : () => widget.onRefreshCaptcha!(route.route),
            child: Container(
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: route.isRefreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : route.hasUsableFrame
                  ? _CaptchaPixels(frame: route.frame!)
                  : const Text('图片暂不可用，点击刷新'),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('点击图片刷新', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        TextField(
          key: ValueKey<String>('captcha-answer-${route.route.name}'),
          controller: _answerControllers[route.route],
          enabled: !widget.isLoading && route.hasUsableFrame,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          enableInteractiveSelection: false,
          contextMenuBuilder: (_, _) => const SizedBox.shrink(),
          decoration: InputDecoration(labelText: '${route.route.label} 验证码答案'),
          onChanged: (value) =>
              widget.onCaptchaAnswerChanged?.call(route.route, value),
          onSubmitted: (_) {
            if (_canSubmit) widget.onSubmit();
          },
        ),
        if (route.error case final error?) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            error.message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
      if (route.status == LoginRouteVerificationStatus.ready) ...<Widget>[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.isLoading || widget.onContinueReady == null
              ? null
              : () => widget.onContinueReady!(route.route),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            widget.routePolicy == RoutePolicy.auto
                ? '保持自动连接并继续'
                : '使用已就绪的${route.route.label}',
          ),
        ),
        if (widget.routePolicy == RoutePolicy.auto)
          OutlinedButton(
            onPressed: widget.isLoading || widget.onContinueFixedReady == null
                ? null
                : () => widget.onContinueFixedReady!(route.route),
            child: Text('改用${route.route.label}并继续'),
          ),
      ],
      if (route.status == LoginRouteVerificationStatus.failed) ...<Widget>[
        const SizedBox(height: 8),
        Text('${route.route.label} 暂未就绪'),
      ],
    ],
  ];
}

/// 从 Core 已解码像素建立本控件独占的图形对象，不使用 ImageProvider 或全局缓存。
class _CaptchaPixels extends StatefulWidget {
  const _CaptchaPixels({required this.frame});
  final CaptchaPixelFrame frame;

  @override
  State<_CaptchaPixels> createState() => _CaptchaPixelsState();
}

class _CaptchaPixelsState extends State<_CaptchaPixels> {
  ui.Image? _image;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(covariant _CaptchaPixels oldWidget) {
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
