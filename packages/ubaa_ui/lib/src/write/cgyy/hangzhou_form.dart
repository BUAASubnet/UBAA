import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../shared/dialogs/form_page.dart';

/// 场馆前端按 310 像素宽的原图计算拼图位移。
const double _captchaBaseWidth = 310;

/// 本次运行内记住手机号，减少重复输入；不落盘。
String _rememberedPhone = '';

/// 收集杭州空间预约：手机号、用户亲手拖动的滑块与点击“提交预约”时的真实坐标。
///
/// 验证码只交给用户完成，应用不识别拼图缺口；令牌与密钥只在本次内存中使用。
Future<HangzhouCgyySubmitInput?> uiCollectHangzhouCgyyReservation(
  BuildContext context, {
  required List<CgyyReserveAction> actions,
  required String selectionLabel,
  required Future<HangzhouCgyyCaptcha> Function() loadCaptcha,
}) => showUiPage<HangzhouCgyySubmitInput>(
  context,
  builder: (_) => _HangzhouCgyyForm(
    actions: actions,
    selectionLabel: selectionLabel,
    loadCaptcha: loadCaptcha,
  ),
);

class _HangzhouCgyyForm extends StatefulWidget {
  const _HangzhouCgyyForm({
    required this.actions,
    required this.selectionLabel,
    required this.loadCaptcha,
  });

  final List<CgyyReserveAction> actions;
  final String selectionLabel;
  final Future<HangzhouCgyyCaptcha> Function() loadCaptcha;

  @override
  State<_HangzhouCgyyForm> createState() => _HangzhouCgyyFormState();
}

class _HangzhouCgyyFormState extends State<_HangzhouCgyyForm> {
  late final phone = TextEditingController(text: _rememberedPhone);
  HangzhouCgyyCaptcha? _captcha;
  double? _offsetX;
  Offset? _tap;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  void _submit() {
    final value = phone.text.trim();
    final captcha = _captcha;
    final offset = _offsetX;
    final tap = _tap;
    if (!RegExp(r'^1\d{10}$').hasMatch(value)) {
      setState(() => error = '请输入 11 位手机号');
      return;
    }
    if (captcha == null || offset == null || offset <= 0) {
      setState(() => error = '请先拖动滑块完成验证');
      return;
    }
    if (tap == null) {
      setState(() => error = '请点击“提交预约”按钮提交');
      return;
    }
    _rememberedPhone = value;
    Navigator.of(context).pop(
      HangzhouCgyySubmitInput(
        actions: widget.actions,
        phone: value,
        captcha: captcha,
        sliderOffsetX: double.parse(offset.toStringAsFixed(2)),
        tapX: tap.dx.round(),
        tapY: tap.dy.round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return UiFormScaffold(
      title: '填写杭州空间预约',
      error: error,
      hint: '仅支持免费场地；提交后会自动完成 0 元确认。',
      secondary: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('返回修改时段'),
      ),
      // Listener 不参与手势竞争，只记录用户真实点击位置供场馆系统校验。
      primary: Listener(
        onPointerDown: (event) => _tap = event.position,
        child: FilledButton(
          key: const ValueKey('hangzhou-cgyy-submit'),
          onPressed: _submit,
          child: const Text('提交预约'),
        ),
      ),
      children: [
        Text('已选时段', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(widget.selectionLabel.replaceAll('\n', ' · ')),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('hangzhou-cgyy-phone'),
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: const InputDecoration(
            labelText: '联系电话',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text('拖动滑块，让拼图对准缺口', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _HangzhouSliderCaptcha(
          load: widget.loadCaptcha,
          onChanged: (captcha, offset) => setState(() {
            _captcha = captcha;
            _offsetX = offset;
            if (offset != null) error = null;
          }),
        ),
      ],
    );
  }
}

/// 滑块拼图：用户拖动拼图块，松手后把原图坐标系下的位移交给表单。
class _HangzhouSliderCaptcha extends StatefulWidget {
  const _HangzhouSliderCaptcha({required this.load, required this.onChanged});

  final Future<HangzhouCgyyCaptcha> Function() load;

  /// 换图时位移为 null；松手后给出 310 像素宽坐标系下的位移。
  final void Function(HangzhouCgyyCaptcha? captcha, double? offsetX) onChanged;

  @override
  State<_HangzhouSliderCaptcha> createState() => _HangzhouSliderCaptchaState();
}

class _LoadedCaptcha {
  const _LoadedCaptcha(
    this.value,
    this.background,
    this.piece,
    this.size,
    this.pieceSize,
  );
  final HangzhouCgyyCaptcha value;
  final Uint8List background, piece;
  final Size size, pieceSize;
}

class _HangzhouSliderCaptchaState extends State<_HangzhouSliderCaptcha> {
  _LoadedCaptcha? _loaded;
  bool _loading = false;
  String? _error;
  double _drag = 0;
  bool _released = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loading = true;
    unawaited(_load(++_generation));
  }

  static Uint8List _decode(String value) {
    final comma = value.indexOf(',');
    return base64Decode(
      (value.startsWith('data:') && comma >= 0
              ? value.substring(comma + 1)
              : value)
          .trim(),
    );
  }

  static Future<Size> _sizeOf(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  /// 换一张：清空上一张的位移，表单不得沿用旧验证码。
  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _drag = 0;
      _released = false;
    });
    widget.onChanged(null, null);
    await _load(generation);
  }

  Future<void> _load(int generation) async {
    try {
      final captcha = await widget.load();
      final background = _decode(captcha.originalImageBase64);
      final piece = _decode(captcha.jigsawImageBase64);
      final sizes = await Future.wait([_sizeOf(background), _sizeOf(piece)]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loaded = _LoadedCaptcha(
          captcha,
          background,
          piece,
          sizes[0],
          sizes[1],
        );
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loaded = null;
        _loading = false;
        _error = '验证码加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loaded = _loaded;
    if (loaded == null) {
      return SizedBox(
        height: 120,
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: Text(_error ?? '加载验证码'),
                ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 360.0);
        final scale = width / loaded.size.width;
        final height = loaded.size.height * scale;
        final pieceWidth = loaded.pieceSize.width * scale;
        final pieceHeight = loaded.pieceSize.height * scale;
        final maxDrag = (width - pieceWidth).clamp(0.0, width);
        final drag = _drag.clamp(0.0, maxDrag);
        void update(double delta) {
          if (_released) return;
          setState(() => _drag = (_drag + delta).clamp(0.0, maxDrag));
        }

        void release() {
          if (_released || _drag <= 0) return;
          setState(() => _released = true);
          widget.onChanged(loaded.value, _drag * _captchaBaseWidth / width);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Image.memory(
                    loaded.background,
                    width: width,
                    height: height,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    left: drag,
                    top: 0,
                    width: pieceWidth,
                    height: pieceHeight,
                    child: Image.memory(
                      loaded.piece,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: width,
              height: 40,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          _released ? '已完成，可提交或换一张' : '向右拖动滑块',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: drag.clamp(0.0, (width - 48).clamp(0.0, width)),
                    top: 0,
                    child: GestureDetector(
                      key: const ValueKey('hangzhou-cgyy-slider'),
                      // 滑块与拼图同步移动，位移完全来自用户手指。
                      onHorizontalDragUpdate: (details) =>
                          update(details.delta.dx),
                      onHorizontalDragEnd: (_) => release(),
                      child: Container(
                        width: 48,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _released
                              ? colors.primary
                              : colors.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          _released ? Icons.check : Icons.arrow_forward,
                          color: _released
                              ? colors.onPrimary
                              : colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('换一张'),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 询问杭州预约的取消原因；场馆系统要求填写原因。返回 null 表示保留预约。
Future<String?> uiAskHangzhouCgyyCancelReason(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (context) => const _HangzhouCancelReasonDialog(),
    );

class _HangzhouCancelReasonDialog extends StatefulWidget {
  const _HangzhouCancelReasonDialog();

  @override
  State<_HangzhouCancelReasonDialog> createState() =>
      _HangzhouCancelReasonDialogState();
}

class _HangzhouCancelReasonDialogState
    extends State<_HangzhouCancelReasonDialog> {
  final reason = TextEditingController(text: '行程有变');

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('取消这条杭州预约？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('取消后时段可能被他人预约，无法恢复。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('hangzhou-cgyy-cancel-reason'),
            controller: reason,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: '取消原因',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('保留预约'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.error),
          onPressed: () {
            final value = reason.text.trim();
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          child: const Text('确认取消'),
        ),
      ],
    );
  }
}
