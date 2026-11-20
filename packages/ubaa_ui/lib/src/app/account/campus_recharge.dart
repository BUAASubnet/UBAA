import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';

/// 校园卡充值：下单后在应用内打开航财通收银台，展示支付宝渠道并由用户确认付款。
class CampusRechargePage extends StatefulWidget {
  const CampusRechargePage({
    super.key,
    required this.service,
    required this.supportsCashier,
    required this.openCashier,
    this.onRejected,
  });

  final CampusRechargeService service;

  /// 检查系统能否在应用内打开收银台。
  final Future<bool> Function() supportsCashier;

  /// 在应用内通过系统 WebView 打开收银台；返回是否成功。
  final Future<bool> Function(Uri url) openCashier;

  /// 记录页面仍在时收到的服务错误。
  final void Function(Object error)? onRejected;

  @override
  State<CampusRechargePage> createState() => _CampusRechargePageState();
}

class _CampusRechargePageState extends State<CampusRechargePage> {
  final _amount = TextEditingController();
  CampusRechargePreflight? _preflight;
  ({CampusRechargeOrder order, Uri? url})? _checkout;
  UiError? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _openingCashier = false;
  bool _cashierOpenFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final supported = await widget.supportsCashier();
      if (!mounted) return;
      if (!supported) {
        setState(() {
          _error = const UiError(
            code: UbaaErrorCode.unsupported,
            title: '此设备不支持应用内收银台',
            message: '未创建订单，请通过掌上服务大厅为校园卡充值',
          );
          _loading = false;
        });
        return;
      }
      final value = await widget.service.preflight();
      if (!mounted) return;
      setState(() {
        _preflight = value;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      widget.onRejected?.call(error);
      setState(() {
        _error = error is UiError
            ? error
            : const UiError(
                code: UbaaErrorCode.internalError,
                title: '无法读取校园卡',
                message: '请稍后重试',
              );
        _loading = false;
      });
    }
  }

  /// 元转分，只接受 0.01–1000 元且最多两位小数。
  String? _toFen(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d{1,4}(\.\d{0,2})?$').hasMatch(trimmed)) return null;
    final parts = trimmed.split('.');
    final yuan = int.tryParse(parts[0]);
    if (yuan == null) return null;
    final cents = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    final fen = yuan * 100 + (int.tryParse(cents) ?? -1);
    if (fen < 1 || fen > 100_000) return null;
    return '$fen';
  }

  bool get _canSubmit =>
      !_submitting &&
      _checkout == null &&
      _error?.code != UbaaErrorCode.outcomeUnknown;

  Future<void> _submit() async {
    final preflight = _preflight;
    if (preflight == null || !_canSubmit) return;
    final fen = _toFen(_amount.text);
    if (fen == null) {
      setState(
        () => _error = const UiError(
          code: UbaaErrorCode.invalidInput,
          title: '金额无效',
          message: '请输入 0.01–1000 元之间的金额，最多两位小数',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final yuan = (int.parse(fen) / 100).toStringAsFixed(2);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认充值'),
          content: Text(
            '将为尾号 ${_mask(preflight.idserial)} 的校园卡充值 $yuan 元。\n'
            '支付渠道：支付宝。请在支付宝内核对订单并确认付款。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (mounted && confirmed == true) {
        await _createOrder(preflight.idserial, fen);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createOrder(String idserial, String fen) async {
    final CampusRechargeOrder order;
    try {
      order = await widget.service.createOrder(
        idserial: idserial,
        amountFen: fen,
      );
    } on Object catch (error) {
      if (!mounted) return;
      widget.onRejected?.call(error);
      setState(() {
        _error = error is UiError && error.code != UbaaErrorCode.outcomeUnknown
            ? error
            : const UiError(
                code: UbaaErrorCode.outcomeUnknown,
                title: '无法确认是否已创建订单',
                message: '请到掌上服务大厅核对订单状态后再试',
              );
      });
      return;
    }
    if (!mounted) return;
    final url = Uri.tryParse(order.cashierUrl);
    setState(() => _checkout = (order: order, url: url));
    if (url != null) await _openCheckout(url);
  }

  Future<void> _openCheckout(Uri url) async {
    if (_openingCashier) return;
    setState(() {
      _openingCashier = true;
      _cashierOpenFailed = false;
    });
    var opened = false;
    try {
      opened = await widget.openCashier(url);
    } on Object {
      // 启动错误可能包含付款地址，不传给诊断。
    }
    if (!mounted) return;
    setState(() {
      _openingCashier = false;
      _cashierOpenFailed = !opened;
    });
  }

  static String _mask(String value) =>
      value.length <= 4 ? value : value.substring(value.length - 4);

  @override
  Widget build(BuildContext context) {
    final canSubmit = _canSubmit;
    return PopScope<void>(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('校园卡充值')),
        body: ListView(
          padding: UbaaTheme.pageInsets(context, top: 16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_preflight != null) ...[
              _InfoRow(label: '卡号尾号', value: _mask(_preflight!.idserial)),
              _InfoRow(label: '当前余额', value: '${_preflight!.balance} 元'),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('campus-recharge-amount'),
                controller: _amount,
                enabled: canSubmit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '充值金额（元）',
                  helperText: '单次 0.01–1000 元',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('支付渠道：支付宝'),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('campus-recharge-submit'),
                onPressed: canSubmit ? _submit : null,
                child: Text(
                  _checkout != null
                      ? '订单已创建'
                      : _submitting
                      ? '处理中…'
                      : '创建订单',
                ),
              ),
            ],
            if (_checkout case final checkout?) ...[
              const SizedBox(height: 20),
              const Divider(),
              _InfoRow(label: '订单号', value: checkout.order.orderno),
              if (checkout.url == null || _cashierOpenFailed)
                Text(
                  '未能在应用内打开航财通收银台。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (checkout.url case final url?) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _openingCashier ? null : () => _openCheckout(url),
                  child: const Text('重新打开航财通收银台'),
                ),
              ],
              const Text('订单 15 分钟内有效。请勿重复下单。', style: TextStyle(fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                '${_error!.title}：${_error!.message}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
