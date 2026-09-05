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

  @override
  State<UbaaLoginView> createState() => _UbaaLoginViewState();
}

class _UbaaLoginViewState extends State<UbaaLoginView> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _captchaController;
  bool _obscurePassword = true;

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

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 24 : 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
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
                        autofillHints: const <String>[AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: '学号'),
                        onChanged: widget.onUsernameChanged,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        enabled: !widget.isLoading,
                        obscureText: _obscurePassword,
                        autofillHints: const <String>[AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '密码',
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: widget.onPasswordChanged,
                        onSubmitted: (_) => widget.onSubmit(),
                      ),
                      if (widget.captcha.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _captchaController,
                          enabled: !widget.isLoading,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(labelText: '验证码'),
                          onChanged: widget.onCaptchaChanged,
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
                      ],
                      const SizedBox(height: 32),
                      Text(
                        '开源项目: github.com/BUAASubnet/UBAA',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: _RoutePolicyButton(
                policy: widget.routePolicy,
                enabled: !widget.isLoading,
                onChanged: widget.onRoutePolicyChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canSubmit =>
      widget.username.trim().isNotEmpty && widget.password.isNotEmpty;
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                value: rememberPassword,
                onChanged: enabled && persistenceAvailable
                    ? (value) => onRememberPasswordChanged(value ?? false)
                    : null,
              ),
              const Text('记住密码'),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                value: autoLogin,
                onChanged: enabled && persistenceAvailable
                    ? (value) => onAutoLoginChanged(value ?? false)
                    : null,
              ),
              const Text('自动登录'),
            ],
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
    itemBuilder: (context) => RoutePolicy.values
        .map(
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
        )
        .toList(),
    child: FilledButton.tonalIcon(
      onPressed: null,
      icon: const Icon(Icons.tune),
      label: Text('模式：${policy.label}'),
    ),
  );
}
