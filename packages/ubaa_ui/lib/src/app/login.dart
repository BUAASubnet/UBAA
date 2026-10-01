part of '../widgets.dart';

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
    required this.onRoutePolicyChanged,
    required this.onSubmit,
    this.onReadDiagnostics,
    this.onOpenAppLink,
    this.verification,
    this.onCaptchaAnswerChanged,
    this.onRefreshCaptcha,
    this.onContinueReady,
    this.onContinueFixedReady,
    this.onCancelVerification,
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
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final VoidCallback onSubmit;
  final String Function()? onReadDiagnostics;
  final Future<bool> Function(AppLink)? onOpenAppLink;
  final LoginVerificationState? verification;
  final void Function(ConnectionMode, String)? onCaptchaAnswerChanged;
  final ValueChanged<ConnectionMode>? onRefreshCaptcha;
  final ValueChanged<ConnectionMode>? onContinueReady;
  final ValueChanged<ConnectionMode>? onContinueFixedReady;
  final VoidCallback? onCancelVerification;

  @override
  State<UbaaLoginView> createState() => _UbaaLoginViewState();
}

class _UbaaLoginViewState extends State<UbaaLoginView>
    with WidgetsBindingObserver {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _captchaController;
  bool _obscurePassword = true;
  bool _openingProject = false;
  final Map<ConnectionMode, TextEditingController> _answerControllers =
      <ConnectionMode, TextEditingController>{};
  bool _verificationVisible = true;
  bool _appHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usernameController = TextEditingController(text: widget.username);
    _passwordController = TextEditingController(text: widget.password);
    _captchaController = TextEditingController(text: widget.captcha);
    _syncVerificationInputs();
  }

  @override
  void didUpdateWidget(covariant UbaaLoginView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_usernameController, oldWidget.username, widget.username);
    _syncController(_passwordController, oldWidget.password, widget.password);
    _syncController(_captchaController, oldWidget.captcha, widget.captcha);
    final fresh =
        widget.verification?.routes.any(
          (route) =>
              route.hasUsableFrame &&
              oldWidget.verification?.forRoute(route.route)?.revision !=
                  route.revision,
        ) ??
        false;
    if (fresh && !_appHidden) _verificationVisible = true;
    _syncVerificationInputs();
  }

  void _syncVerificationInputs() {
    final routes =
        widget.verification?.routes ?? const <LoginRouteVerification>[];
    for (final route in routes) {
      final controller = _answerControllers.putIfAbsent(
        route.route,
        () => TextEditingController(),
      );
      _syncController(controller, controller.text, route.answer);
    }
    for (final route in _answerControllers.keys.toList()) {
      if (!routes.any((value) => value.route == route)) {
        _answerControllers.remove(route)?.dispose();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appHidden = true;
      widget.verification?.releaseFrames();
      for (final controller in _answerControllers.values) {
        controller.clear();
      }
      if (mounted) setState(() => _verificationVisible = false);
      widget.onCancelVerification?.call();
    } else if (state == AppLifecycleState.resumed) {
      _appHidden = false;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    widget.verification?.releaseFrames();
    widget.onCancelVerification?.call();
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
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
      await _showAppLinkFailure(context, AppLink.project);
    }
    if (mounted) setState(() => _openingProject = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _RoutePolicyButton(
                    policy: widget.routePolicy,
                    enabled: !widget.isLoading,
                    onChanged: widget.onRoutePolicyChanged,
                  ),
                ),
              ),
            ),
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
                          Text(
                            'UBAA 登录',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
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
                            onSubmitted: (_) {
                              if (_canSubmit) widget.onSubmit();
                            },
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
                            ),
                          ],
                          if (_verificationVisible &&
                              widget.verification != null)
                            ..._buildVerificationControls(),
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
                              onPressed: _canSubmit ? widget.onSubmit : null,
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
                          if (widget.error case final error?) ...<Widget>[
                            const SizedBox(height: 16),
                            FriendlyErrorCard(error: error),
                            if (widget.onReadDiagnostics != null)
                              TextButton(
                                onPressed: () => _showDiagnosticsDialog(
                                  context,
                                  widget.onReadDiagnostics!,
                                ),
                                child: const Text('查看诊断信息'),
                              ),
                          ],
                          const SizedBox(height: 32),
                          Semantics(
                            link: true,
                            child: InkWell(
                              onTap:
                                  widget.isLoading ||
                                      _openingProject ||
                                      widget.onOpenAppLink == null
                                  ? null
                                  : _openProject,
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

  bool get _canSubmit =>
      !widget.isLoading &&
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
      if (persistenceAvailable)
        Text(
          '密码仅保存在系统安全存储；自动登录决定是否自动使用已保存密码。',
          style: Theme.of(context).textTheme.bodySmall,
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(
            value: value,
            onChanged: enabled ? (value) => onChanged(value ?? false) : null,
          ),
          Text(label),
        ],
      ),
    ),
  );
}

class _RoutePolicyButton extends StatelessWidget {
  const _RoutePolicyButton({
    required this.policy,
    required this.enabled,
    required this.onChanged,
  });

  final RoutePolicy policy;
  final bool enabled;
  final ValueChanged<RoutePolicy> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<RoutePolicy>(
    enabled: enabled,
    initialValue: policy,
    tooltip: '连接模式',
    onSelected: onChanged,
    icon: const Icon(Icons.route_outlined),
    itemBuilder: (context) => [
      const PopupMenuItem<RoutePolicy>(
        enabled: false,
        child: Text('尚未读取；这里设置登录与后续查询的默认策略。'),
      ),
      ...RoutePolicy.values.map(
        (item) => PopupMenuItem<RoutePolicy>(
          value: item,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item == policy
                  ? Icons.radio_button_checked
                  : Icons.circle_outlined,
            ),
            title: Text(item.label),
            subtitle: Text(item.description),
          ),
        ),
      ),
    ],
  );
}
