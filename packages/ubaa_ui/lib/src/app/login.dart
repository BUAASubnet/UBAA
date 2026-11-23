import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'app_service/privacy.dart'
    show uiShowPrivacyAgreement, uiShowPrivacyPolicy;
import '../theme.dart' show UbaaTheme;
import '../shared/layout/rail_identity.dart' show UiAppIcon;
import '../common/app_links.dart' show uiShowAppLinkFailure;
import '../common/error_card.dart'
    show FriendlyErrorCard, uiDiagnosticsGuidance, uiShowDiagnosticsDialog;

/// 登录表单。状态由应用协调器持有，组件本身不保存密码。
class UbaaLoginView extends StatefulWidget {
  const UbaaLoginView({
    required this.username,
    required this.password,
    required this.captcha,
    required this.rememberPassword,
    required this.autoLogin,
    required this.routePolicy,
    required this.error,
    required this.isLoading,
    required this.credentialPersistenceAvailable,
    required this.onUsernameChanged,
    required this.onPasswordChanged,
    required this.onCaptchaChanged,
    required this.onRememberPasswordChanged,
    required this.onAutoLoginChanged,
    required this.onSubmit,
    required this.privacyAccepted,
    required this.onAcceptPrivacy,
    this.appServiceAvailable = false,
    this.onReadDiagnostics,
    this.onOpenAppLink,
    this.verification,
    super.key,
  });

  final String username;
  final String password;
  final String captcha;
  final bool rememberPassword;
  final bool autoLogin;
  final RoutePolicy routePolicy;
  final UiError? error;
  final bool isLoading;
  final bool credentialPersistenceAvailable;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String> onCaptchaChanged;
  final ValueChanged<bool> onRememberPasswordChanged;
  final ValueChanged<bool> onAutoLoginChanged;
  final VoidCallback onSubmit;
  final bool privacyAccepted;
  final Future<void> Function() onAcceptPrivacy;
  final bool appServiceAvailable;
  final String Function()? onReadDiagnostics;
  final Future<bool> Function(AppLink)? onOpenAppLink;
  final LoginVerificationState? verification;

  @override
  State<UbaaLoginView> createState() => _UbaaLoginViewState();
}

class _UbaaLoginViewState extends State<UbaaLoginView> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _captchaController;
  bool _obscurePassword = true;
  bool _openingProject = false;
  bool _privacyChecked = false;
  bool _submittingPrivacy = false;

  Future<void> _submit() async {
    if (widget.isLoading || _submittingPrivacy) return;
    if (!widget.privacyAccepted) {
      setState(() => _submittingPrivacy = true);
      try {
        if (_privacyChecked) {
          await widget.onAcceptPrivacy();
        } else if (!await uiShowPrivacyAgreement(
          context,
          appServiceAvailable: widget.appServiceAvailable,
          onAgree: widget.onAcceptPrivacy,
        )) {
          return;
        }
        if (mounted) setState(() => _privacyChecked = true);
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('隐私政策同意未保存，请重试。')));
        }
        return;
      } finally {
        if (mounted) setState(() => _submittingPrivacy = false);
      }
    }
    if (mounted) widget.onSubmit();
  }

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.username);
    _passwordController = TextEditingController(text: widget.password);
    _captchaController = TextEditingController(text: widget.captcha);
  }

  @override
  void didUpdateWidget(covariant UbaaLoginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_usernameController, oldWidget.username, widget.username);
    _syncController(_passwordController, oldWidget.password, widget.password);
    _syncController(_captchaController, oldWidget.captcha, widget.captcha);
  }

  void _syncController(
    TextEditingController controller,
    String oldValue,
    String newValue,
  ) {
    if (oldValue == newValue || controller.text == newValue) return;
    controller.value = controller.value.copyWith(
      text: newValue,
      selection: TextSelection.collapsed(offset: newValue.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _openProject() async {
    if (widget.isLoading || _openingProject || widget.onOpenAppLink == null)
      return;
    setState(() => _openingProject = true);
    var opened = false;
    try {
      opened = await widget.onOpenAppLink!(AppLink.project);
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    if (!opened && !widget.isLoading) {
      await uiShowAppLinkFailure(context, AppLink.project);
    }
    if (mounted) setState(() => _openingProject = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AutofillGroup(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Center(child: UiAppIcon(size: 72)),
                          const SizedBox(height: 16),
                          // 大字号下整体缩小，不把“UBAA 登录”拆成两行。
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'UBAA 登录',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextField(
                            controller: _usernameController,
                            enabled: !widget.isLoading,
                            autofillHints: const <String>[
                              AutofillHints.username,
                            ],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: '学号'),
                            onChanged: widget.onUsernameChanged,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            enabled: !widget.isLoading,
                            obscureText: _obscurePassword,
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: '密码',
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                onPressed: widget.isLoading
                                    ? null
                                    : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            onChanged: widget.onPasswordChanged,
                            onSubmitted: (_) => _submitFromKeyboard(),
                          ),
                          if (widget.captcha.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _captchaController,
                              enabled: !widget.isLoading,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: '验证码',
                              ),
                              onChanged: widget.onCaptchaChanged,
                              onSubmitted: (_) => _submitFromKeyboard(),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _LoginOptions(
                            rememberPassword: widget.rememberPassword,
                            autoLogin: widget.autoLogin,
                            enabled: !widget.isLoading,
                            persistenceAvailable:
                                widget.credentialPersistenceAvailable,
                            onRememberPasswordChanged:
                                widget.onRememberPasswordChanged,
                            onAutoLoginChanged: widget.onAutoLoginChanged,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _canSubmit ? _submit : null,
                              child: widget.isLoading
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('登录'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _PrivacyAgreementRow(
                            checked: widget.privacyAccepted || _privacyChecked,
                            onChanged:
                                widget.privacyAccepted ||
                                    widget.isLoading ||
                                    _submittingPrivacy
                                ? null
                                : (value) =>
                                      setState(() => _privacyChecked = value),
                            onOpenPolicy: () => uiShowPrivacyPolicy(
                              context,
                              bundledPrivacyPolicy,
                            ),
                          ),
                          if (widget.error case final error?) ...<Widget>[
                            const SizedBox(height: 16),
                            FriendlyErrorCard(
                              error: error,
                              diagnosticsGuidance:
                                  widget.onReadDiagnostics == null
                                  ? uiDiagnosticsGuidance
                                  : '如需反馈，请点下方「诊断信息」分享完整诊断。',
                            ),
                            if (widget.onReadDiagnostics != null)
                              TextButton.icon(
                                onPressed: () => uiShowDiagnosticsDialog(
                                  context,
                                  widget.onReadDiagnostics!,
                                ),
                                icon: const Icon(Icons.bug_report_outlined),
                                label: const Text('诊断信息'),
                              ),
                          ],
                          const SizedBox(height: 32),
                          Text(
                            '本软件由学生开发者制作并维护，为第三方工具，与北京航空航天大学官方无任何利益关系',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            link: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                UbaaTheme.controlRadius,
                              ),
                              onTap:
                                  widget.isLoading ||
                                      _openingProject ||
                                      widget.onOpenAppLink == null
                                  ? null
                                  : _openProject,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  '开源项目: github.com/BUAASubnet/UBAA',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 键盘回车提交：按输入框当前内容判断，不等外层重建后的属性。
  void _submitFromKeyboard() {
    if (!widget.isLoading &&
        _usernameController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        (widget.verification == null || widget.verification!.canSubmit)) {
      unawaited(_submit());
    }
  }

  bool get _canSubmit =>
      !widget.isLoading &&
      !_submittingPrivacy &&
      widget.username.trim().isNotEmpty &&
      widget.password.isNotEmpty &&
      (widget.verification == null || widget.verification!.canSubmit);
}

class _LoginOptions extends StatelessWidget {
  const _LoginOptions({
    required this.rememberPassword,
    required this.autoLogin,
    required this.enabled,
    required this.persistenceAvailable,
    required this.onRememberPasswordChanged,
    required this.onAutoLoginChanged,
  });

  final bool rememberPassword;
  final bool autoLogin;
  final bool enabled;
  final bool persistenceAvailable;
  final ValueChanged<bool> onRememberPasswordChanged;
  final ValueChanged<bool> onAutoLoginChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        children: <Widget>[
          _LoginOption(
            label: '记住密码',
            value: rememberPassword,
            enabled: enabled && persistenceAvailable,
            onChanged: onRememberPasswordChanged,
          ),
          _LoginOption(
            label: '自动登录',
            value: autoLogin,
            enabled: enabled && persistenceAvailable,
            onChanged: onAutoLoginChanged,
          ),
        ],
      ),
      if (!persistenceAvailable)
        Text(
          '当前平台暂未启用安全存储，密码只在本次运行中使用。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );
}

class _LoginOption extends StatelessWidget {
  const _LoginOption({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 整行统一处理鼠标和键盘，复选框只呈现勾选及禁用状态。
            ExcludeFocus(
              child: IgnorePointer(
                child: Checkbox(
                  value: value,
                  onChanged: enabled
                      ? (value) => onChanged(value ?? false)
                      : null,
                ),
              ),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

/// 登录按钮下方的隐私政策勾选行：复选框、说明文字和政策链接排成一句。
///
/// 点说明文字等同于点复选框；已接受当前版本时保持勾选外观但不可取消。
class _PrivacyAgreementRow extends StatelessWidget {
  const _PrivacyAgreementRow({
    required this.checked,
    required this.onChanged,
    required this.onOpenPolicy,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final toggle = onChanged == null ? null : () => onChanged!(!checked);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 32,
          child: Checkbox(
            value: checked,
            // 已接受时仍显示为正常勾选，只是不响应点击。
            onChanged: onChanged == null
                ? (_) {}
                : (v) => onChanged!(v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            semanticLabel: '我已阅读并同意《隐私政策》',
          ),
        ),
        Flexible(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: toggle,
            child: ExcludeSemantics(child: Text('我已阅读并同意', style: style)),
          ),
        ),
        Semantics(
          link: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(UbaaTheme.controlRadius),
            onTap: onOpenPolicy,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '《隐私政策》',
                style: style?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
