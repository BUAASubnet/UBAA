import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/dialogs/sheet.dart';

/// 取一次签到二维码内容：服务器时间戳加上 [offset] 后拼成的签到地址。
typedef SigninQrContentFetcher = Future<String> Function(Duration offset);

/// 把二维码 PNG 存进系统相册（桌面端为另存为图片）。
typedef SigninQrImageSaver = Future<bool> Function(Uint8List png, String name);

/// 查询这节课现在是否已签到；读取失败时抛错。
typedef SigninSignedChecker = Future<bool> Function();

/// 面板打开且未签到时，按这个间隔检查签到状态。
const signinQrStatusInterval = Duration(seconds: 3);

/// 实时二维码用服务器原始时间戳，面板打开期间按这个间隔重新获取。
const signinQrRefreshInterval = Duration(seconds: 2);

/// 保存到相册时，时间戳在点击时的服务器时间上再加这么多。
const signinQrSavedOffset = Duration(seconds: 2);

/// 打开签到二维码面板，供 iClass App 或微信扫码签到。
Future<void> showSigninQrSheet(
  BuildContext context, {
  required String courseTitle,
  required SigninQrContentFetcher fetch,
  SigninQrImageSaver? save,
  SigninSignedChecker? closeWhenSigned,
}) => showUiSheet<void>(
  context,
  dialogWidth: 420,
  builder: (context) => SigninQrSheet(
    courseTitle: courseTitle,
    fetch: fetch,
    save: save,
    closeWhenSigned: closeWhenSigned,
  ),
);

class SigninQrSheet extends StatefulWidget {
  const SigninQrSheet({
    super.key,
    required this.courseTitle,
    required this.fetch,
    this.save,
    this.closeWhenSigned,
    this.refreshInterval = signinQrRefreshInterval,
    this.statusInterval = signinQrStatusInterval,
    this.renderPng = _SigninQrSheetState._renderPng,
  });
  final String courseTitle;
  final SigninQrContentFetcher fetch;

  /// 为空时不显示保存按钮（平台不支持）。
  final SigninQrImageSaver? save;

  /// 打开时尚未签到才传入：轮询到已签到就自动关闭面板。
  final SigninSignedChecker? closeWhenSigned;
  final Duration refreshInterval;
  final Duration statusInterval;
  final Future<Uint8List> Function(String content) renderPng;

  @override
  State<SigninQrSheet> createState() => _SigninQrSheetState();
}

class _SigninQrSheetState extends State<SigninQrSheet> {
  String? _content;
  bool _failed = false;
  bool _loading = false;
  bool _saving = false;

  /// 保存结果提示，几秒后恢复为刷新说明。
  ({String text, bool error})? _saveNote;
  Timer? _noteTimer;
  Timer? _timer;
  Timer? _statusTimer;
  bool _checking = false;
  bool _closed = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 切到后台时停止刷新，回到前台立即取一次新的。
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_failed) {
          _startStatus();
        } else {
          _start();
        }
        // 可能刚去 iClass 扫过码，回来立即查一次。
        unawaited(_checkSigned());
      },
      onHide: _stop,
    );
    _start();
  }

  @override
  void dispose() {
    _stop();
    _noteTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _start() {
    _stop();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
    _startStatus();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _startStatus() {
    if (widget.closeWhenSigned == null || _closed) return;
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(widget.statusInterval, (_) => _checkSigned());
  }

  /// 签到成功（被扫码）后自动关闭；单次查询失败不打断，下次再查。
  Future<void> _checkSigned() async {
    final check = widget.closeWhenSigned;
    if (check == null || _checking || _closed) return;
    _checking = true;
    try {
      if (!await check() || !mounted || _closed) return;
      _closed = true;
      _stop();
      unawaited(Navigator.maybePop(context));
    } catch (_) {
      // 忽略，等下一次。
    } finally {
      _checking = false;
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final content = await widget.fetch(Duration.zero);
      if (!mounted) return;
      setState(() {
        _content = content;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 失败后只停自动刷新，旧二维码已过期，不再显示；签到状态检查不受影响
      //（切到后台时已由 _stop 停掉，这里不能把它重新启动）。
      _timer?.cancel();
      _timer = null;
      setState(() {
        _content = null;
        _failed = true;
      });
    } finally {
      _loading = false;
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _start();
  }

  /// 点击时单独取一次服务器时间戳（加 2 秒），生成图片后保存。
  Future<void> _saveToAlbum() async {
    final save = widget.save;
    if (save == null || _saving) return;
    setState(() => _saving = true);
    try {
      final content = await widget.fetch(signinQrSavedOffset);
      final png = await widget.renderPng(content);
      if (!await save(png, 'iclass_signin_qr.png')) return;
      _note(_savesToAlbum ? '已保存到相册' : '已保存图片', error: false);
    } catch (_) {
      _note('保存失败，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _note(String text, {required bool error}) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() => _saveNote = (text: text, error: error));
    _noteTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saveNote = null);
    });
  }

  /// 手机存进相册；桌面端没有相册，是另存为图片。
  bool get _savesToAlbum => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    final platform => platform.name == 'ohos',
  };

  static Future<Uint8List> _renderPng(String content) async {
    const side = 720.0;
    const margin = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, side + margin * 2, side + margin * 2),
      Paint()..color = Colors.white,
    );
    canvas.translate(margin, margin);
    QrPainter(
      data: content,
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    ).paint(canvas, const Size.square(side));
    final image = await recorder.endRecording().toImage(
      (side + margin * 2).toInt(),
      (side + margin * 2).toInt(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('二维码图片编码失败');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final side = (width - 96).clamp(180.0, 260.0);
    final content = _content;
    final Widget code = Container(
      width: side + 32,
      height: side + 32,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // 深色模式下也保持白底黑码，扫码才稳定。
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: content != null
          ? QrImageView(
              data: content,
              size: side,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
              semanticsLabel: '上课二维码',
            )
          : _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_2_rounded,
                  size: 56,
                  color: Colors.black.withValues(alpha: .18),
                ),
                const SizedBox(height: 12),
                Text(
                  '二维码获取失败',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            )
          : const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
    );
    return UiSheetBody(
      title: widget.courseTitle,
      subtitle: '打开智慧教室扫码上课',
      primaryAction: _failed
          ? FilledButton.tonalIcon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新获取'),
            )
          : widget.save != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: uiInSheetDialog(context)
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _saveToAlbum,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_savesToAlbum ? '保存到相册' : '保存图片'),
                ),
                const SizedBox(height: 8),
                // 保存的码已提前 2 秒，有效期很短，提醒尽快扫。
                Text(
                  '请在保存后 2–7 秒内完成扫描',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
      children: [
        const SizedBox(height: 8),
        Center(child: code),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final note = _saveNote;
            final error = _failed || (note?.error ?? false);
            final color = error
                ? scheme.error
                : note != null
                ? scheme.primary
                : scheme.onSurfaceVariant;
            final (IconData icon, String text) = _failed
                ? (Icons.error_outline_rounded, '请检查网络后重新获取')
                : note != null
                ? (
                    note.error
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    note.text,
                  )
                : (Icons.autorenew_rounded, '二维码每 2 秒自动刷新');
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
