import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/form_page.dart' show showUiPage;
import '../../theme.dart' show UbaaTheme;

/// 登录或恢复会话前征求明示同意。拒绝返回 false，不改变本机账号。
Future<bool> uiShowPrivacyAgreement(
  BuildContext context, {
  required bool appServiceAvailable,
  required Future<void> Function() onAgree,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: _PrivacyAgreementDialog(
          appServiceAvailable: appServiceAvailable,
          onAgree: onAgree,
        ),
      ),
    ) ??
    false;

class _PrivacyAgreementDialog extends StatefulWidget {
  const _PrivacyAgreementDialog({
    required this.appServiceAvailable,
    required this.onAgree,
  });

  final bool appServiceAvailable;
  final Future<void> Function() onAgree;

  @override
  State<_PrivacyAgreementDialog> createState() =>
      _PrivacyAgreementDialogState();
}

class _PrivacyAgreementDialogState extends State<_PrivacyAgreementDialog> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _agree() async {
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onAgree();
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('隐私政策'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('请阅读并同意《隐私政策》后使用 UBAA。'),
        if (widget.appServiceAvailable) ...[
          const SizedBox(height: 8),
          const Text('同意后将开启产品改进统计，按天汇总功能使用情况与错误类别，不包含密码、成绩、课表等内容，可随时在设置中关闭。'),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: _saving
              ? null
              : () => uiShowPrivacyPolicy(context, bundledPrivacyPolicy),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text('查看隐私政策全文'),
        ),
        const SizedBox(height: 8),
        Text(
          '本软件为学生开发的第三方工具，与北京航空航天大学官方无关。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 8),
          Text(
            '隐私政策同意未保存，请重试。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('不同意'),
      ),
      FilledButton(onPressed: _saving ? null : _agree, child: const Text('同意')),
    ],
  );
}

/// 从统计开关重新启用应用服务时的同意弹窗路由。
///
/// 只能通过「同意」或「不同意」关闭，保存失败时留在当前弹窗重试。
DialogRoute<void> uiPrivacyConsentRoute(
  BuildContext context, {
  required PrivacyPolicyDocument policy,
  required AppServiceView view,
  required Future<void> Function() onAgree,
  required Future<void> Function() onDecline,
}) => DialogRoute<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PopScope(
    canPop: false,
    child: PrivacyConsentDialog(
      policy: policy,
      view: view,
      onAgree: onAgree,
      onDecline: onDecline,
    ),
  ),
);

/// 从设置页重新打开同意弹窗。
Future<void> uiShowPrivacyConsent(
  BuildContext context, {
  required PrivacyPolicyDocument policy,
  required AppServiceView view,
  required Future<void> Function() onAgree,
  required Future<void> Function() onDecline,
}) => Navigator.of(context).push(
  uiPrivacyConsentRoute(
    context,
    policy: policy,
    view: view,
    onAgree: onAgree,
    onDecline: onDecline,
  ),
);

class PrivacyConsentDialog extends StatefulWidget {
  const PrivacyConsentDialog({
    super.key,
    required this.policy,
    required this.view,
    required this.onAgree,
    required this.onDecline,
  });
  final PrivacyPolicyDocument policy;
  final AppServiceView view;
  final Future<void> Function() onAgree, onDecline;
  @override
  State<PrivacyConsentDialog> createState() => _PrivacyConsentDialogState();
}

class _PrivacyConsentDialogState extends State<PrivacyConsentDialog> {
  bool _busy = false, _failed = false;

  bool get _updated =>
      widget.view.consent == AppServiceConsent.reconsentRequired;

  Future<void> _choose(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
      // 宿主可能已因状态变化移除弹窗，只关闭仍在最上层的自己。
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on Object {
      // 选择未能保存时留在弹窗里，用户可以再选一次。
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = _updated
        ? [
            for (final change in widget.policy.changes) change,
            '同意后将按本次选择开启产品改进统计，可以随时在设置中关闭。',
          ]
        : const [
            '同意后默认开启「产品改进统计」：按天汇总功能使用次数、错误类别和加载耗时，并按分钟汇总登录与功能加载次数，不包含密码、成绩、课表等内容。可以随时在设置中关闭。',
            '统计会用学号在本机计算出的标识区分用户、统计年级分布，学号原文不会上传。',
            '统计数据会传输到维护者位于中国大陆的服务器处理和保存。',
            '同意后，应用还会联网检查更新、获取公告。',
          ];
    return AlertDialog(
      title: Text(_updated ? '隐私政策已更新' : '隐私政策'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _updated
                ? '隐私政策已更新到第 ${widget.policy.version} 版，主要变化：'
                : '使用 UBAA 前，请阅读以下说明和隐私政策全文。',
          ),
          const SizedBox(height: 12),
          for (final point in points) _Point(point),
          const SizedBox(height: 4),
          Text(
            '不同意也可以正常使用学校功能，只是不会检查更新、接收公告或上传统计。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('privacy-consent-read-policy'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => uiShowPrivacyPolicy(context, widget.policy),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('查看隐私政策全文'),
            ),
          ),
          if (_failed)
            Text(
              '选择未能保存，请重试',
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('privacy-consent-decline'),
          onPressed: _busy ? null : () => _choose(widget.onDecline),
          child: const Text('不同意'),
        ),
        FilledButton(
          key: const ValueKey('privacy-consent-agree'),
          onPressed: _busy ? null : () => _choose(widget.onAgree),
          child: const Text('同意'),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1, right: 8),
          child: Text('•'),
        ),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// 隐私政策全文。正文随应用构建嵌入，查看时不联网。
Future<void> uiShowPrivacyPolicy(
  BuildContext context,
  PrivacyPolicyDocument policy,
) => showUiPage<void>(
  context,
  fixedHeight: true,
  builder: (_) => PrivacyPolicyPage(policy: policy),
);

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key, required this.policy});
  final PrivacyPolicyDocument policy;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(policy.title)),
      body: SelectionArea(
        child: ListView(
          key: const ValueKey('privacy-policy-body'),
          padding: UbaaTheme.pageInsets(context, top: 8, bottom: 24),
          children: [
            Text(
              '第 ${policy.version} 版',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final block in policy.blocks) _PolicyBlock(block),
          ],
        ),
      ),
    );
  }
}

class _PolicyBlock extends StatelessWidget {
  const _PolicyBlock(this.block);
  final PrivacyPolicyBlock block;
  Widget _text(TextStyle? style) {
    if (block.bold.isEmpty) return Text(block.text, style: style);
    final spans = <TextSpan>[];
    var offset = 0;
    for (final (start, end) in block.bold) {
      spans.add(TextSpan(text: block.text.substring(offset, start)));
      spans.add(
        TextSpan(
          text: block.text.substring(start, end),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      offset = end;
    }
    spans.add(TextSpan(text: block.text.substring(offset)));
    return Text.rich(TextSpan(children: spans), style: style);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return switch (block.kind) {
      PrivacyPolicyBlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: _text(
          (block.level <= 2 ? text.titleMedium : text.titleSmall)?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      PrivacyPolicyBlockKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _text(text.bodyMedium?.copyWith(height: 1.5)),
      ),
      PrivacyPolicyBlockKind.bullet => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(right: 8), child: Text('•')),
            Expanded(child: _text(text.bodyMedium?.copyWith(height: 1.5))),
          ],
        ),
      ),
    };
  }
}
