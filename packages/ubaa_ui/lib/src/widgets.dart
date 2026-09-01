import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

typedef LibbookReservePreparer =
    Future<WriteIntent> Function({
      required String areaId,
      required String seatId,
      required String day,
      required String segment,
      required String startTime,
      required String endTime,
    });

typedef LibbookReserveStarter =
    Future<void> Function({
      required String areaId,
      required String seatId,
      required String day,
      required String segment,
      required String startTime,
      required String endTime,
    });

typedef EvaluationSubmitPreparer =
    Future<WriteIntent> Function(List<EvaluationCourseInput> courses);

typedef EvaluationSubmitStarter =
    Future<void> Function(List<EvaluationCourseInput> courses);

typedef CgyyReservationPreparer =
    Future<WriteIntent> Function(CgyySubmitInput input);

typedef CgyyReservationStarter = Future<void> Function(CgyySubmitInput input);

/// 启动页：保留旧版 UBAA 标题和标语。
class UbaaSplashView extends StatelessWidget {
  const UbaaSplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'UBAA',
              style: textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 72,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Make BUAA Great Again',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: textTheme.bodyLarge?.color?.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

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

/// 主界面容器：窄屏使用底部导航，桌面宽屏使用侧边导航。
class UbaaMainShell extends StatefulWidget {
  const UbaaMainShell({
    required this.user,
    required this.snapshots,
    required this.routePolicy,
    required this.telemetryEnabled,
    required this.onRefresh,
    required this.onRetryFeature,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    this.activeRoutes = const <ConnectionMode>[],
    this.onFeatureQuery,
    this.onPrepareBykcWrite,
    this.onPrepareBykcSignWrite,
    this.onPrepareSigninWrite,
    this.onPrepareCancellationWrite,
    this.onPrepareLibbookReserveWrite,
    this.onPrepareCgyySubmitWrite,
    this.onPrepareEvaluationWrite,
    this.onCommitWrite,
    this.onWriteSuccess,
    super.key,
  });

  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final Future<void> Function() onRefresh;
  final Future<void> Function(FeatureId feature) onRetryFeature;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final List<ConnectionMode> activeRoutes;
  final Future<void> Function(FeatureId feature, FeatureQuery query)?
  onFeatureQuery;
  final Future<WriteIntent> Function(WriteOperation operation, int courseId)?
  onPrepareBykcWrite;
  final Future<WriteIntent> Function(int courseId, int signType)?
  onPrepareBykcSignWrite;
  final Future<WriteIntent> Function(String courseId)? onPrepareSigninWrite;
  final Future<WriteIntent> Function(WriteOperation operation, String targetId)?
  onPrepareCancellationWrite;
  final LibbookReservePreparer? onPrepareLibbookReserveWrite;
  final CgyyReservationPreparer? onPrepareCgyySubmitWrite;
  final EvaluationSubmitPreparer? onPrepareEvaluationWrite;
  final Future<WriteCommitResult> Function(String intentId)? onCommitWrite;
  final Future<void> Function(WriteOperation operation)? onWriteSuccess;

  @override
  State<UbaaMainShell> createState() => _UbaaMainShellState();
}

class _UbaaMainShellState extends State<UbaaMainShell> {
  int _selectedIndex = 0;
  FeatureId? _openedFeature;
  final Map<FeatureId, FeatureQuery> _featureQueries =
      <FeatureId, FeatureQuery>{};
  WriteIntent? _pendingWrite;
  UiError? _writeError;
  bool _writeSubmitting = false;

  static const _tabs = <({String label, IconData icon, IconData selectedIcon})>[
    (label: '主页', icon: Icons.home_outlined, selectedIcon: Icons.home),
    (label: '普通功能', icon: Icons.apps_outlined, selectedIcon: Icons.apps),
    (
      label: '高级功能',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
    ),
    (label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = _pendingWrite != null
        ? WriteConfirmationView(
            intent: _pendingWrite!,
            onCancel: _cancelWrite,
            onConfirm: _confirmWrite,
            isSubmitting: _writeSubmitting,
            error: _writeError,
          )
        : _openedFeature == null
        ? _buildTab(context)
        : _FeatureDetailView(
            feature: _openedFeature!,
            snapshot: widget.snapshots[_openedFeature!]!,
            onBack: () => setState(() => _openedFeature = null),
            onRetry: () {
              final feature = _openedFeature!;
              final query = _featureQueries[feature];
              return query == null || widget.onFeatureQuery == null
                  ? widget.onRetryFeature(feature)
                  : widget.onFeatureQuery!(feature, query);
            },
            onQuery: widget.onFeatureQuery == null
                ? null
                : (query) {
                    final feature = _openedFeature!;
                    _featureQueries[feature] = query;
                    return widget.onFeatureQuery!(feature, query);
                  },
            onBykcWrite: widget.onPrepareBykcWrite == null
                ? null
                : _startBykcWrite,
            onBykcSignWrite: widget.onPrepareBykcSignWrite == null
                ? null
                : _startBykcSignWrite,
            onSigninWrite: widget.onPrepareSigninWrite == null
                ? null
                : _startSigninWrite,
            onCancellationWrite: widget.onPrepareCancellationWrite == null
                ? null
                : _startCancellationWrite,
            onLibbookReserveWrite: widget.onPrepareLibbookReserveWrite == null
                ? null
                : _startLibbookReserveWrite,
            onEvaluationWrite: widget.onPrepareEvaluationWrite == null
                ? null
                : _startEvaluationWrite,
            onCgyySubmitWrite: widget.onPrepareCgyySubmitWrite == null
                ? null
                : _startCgyySubmitWrite,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pendingWrite == null
              ? (_openedFeature?.title ?? _tabs[_selectedIndex].label)
              : '确认${_pendingWrite!.operation.title}',
        ),
        leading: _openedFeature == null || _pendingWrite != null
            ? null
            : IconButton(
                tooltip: '返回',
                onPressed: () => setState(() => _openedFeature = null),
                icon: const Icon(Icons.arrow_back),
              ),
        actions: <Widget>[
          if (_openedFeature == null && _selectedIndex == 0)
            IconButton(
              tooltip: '刷新',
              onPressed: () => widget.onRefresh(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      drawer: wide ? null : _buildDrawer(context),
      body: wide
          ? Row(
              children: <Widget>[
                _buildRail(context),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectTab,
              destinations: _tabs
                  .map(
                    (tab) => NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildTab(BuildContext context) => switch (_selectedIndex) {
    0 => _HomeView(
      user: widget.user,
      snapshots: widget.snapshots,
      onFeatureTap: (feature) => setState(() => _openedFeature = feature),
      onRetryFeature: widget.onRetryFeature,
      onRefresh: widget.onRefresh,
    ),
    1 => _FeatureGridView(
      snapshots: widget.snapshots,
      onFeatureTap: (feature) => setState(() => _openedFeature = feature),
      onRetryFeature: widget.onRetryFeature,
    ),
    2 => _AdvancedFeaturesView(
      snapshots: widget.snapshots,
      onFeatureTap: (feature) => setState(() => _openedFeature = feature),
      onRetryFeature: widget.onRetryFeature,
    ),
    _ => _ProfileView(
      user: widget.user,
      routePolicy: widget.routePolicy,
      telemetryEnabled: widget.telemetryEnabled,
      onRoutePolicyChanged: widget.onRoutePolicyChanged,
      onTelemetryChanged: widget.onTelemetryChanged,
      onLogout: widget.onLogout,
      onLogoutAndClearAccount: widget.onLogoutAndClearAccount,
      activeRoutes: widget.activeRoutes,
    ),
  };

  Widget _buildRail(BuildContext context) => NavigationRail(
    selectedIndex: _selectedIndex,
    onDestinationSelected: _selectTab,
    extended: MediaQuery.sizeOf(context).width >= 1100,
    leading: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: CircleAvatar(
        radius: 28,
        child: Text((widget.user?.preferredName ?? 'U').characters.first),
      ),
    ),
    destinations: _tabs
        .map(
          (tab) => NavigationRailDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: Text(tab.label),
          ),
        )
        .toList(),
  );

  Drawer _buildDrawer(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(widget.user?.preferredName ?? 'UBAA'),
            accountEmail: Text(widget.user?.username ?? ''),
            currentAccountPicture: CircleAvatar(
              child: Text((widget.user?.preferredName ?? 'U').characters.first),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _tabs.length,
              itemBuilder: (context, index) => ListTile(
                selected: _selectedIndex == index,
                leading: Icon(
                  _selectedIndex == index
                      ? _tabs[index].selectedIcon
                      : _tabs[index].icon,
                ),
                title: Text(_tabs[index].label),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectTab(index);
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _selectTab(int index) {
    if (_pendingWrite != null) return;
    setState(() {
      _selectedIndex = index;
      _openedFeature = null;
    });
  }

  Future<void> _startBykcWrite(WriteOperation operation, int courseId) async {
    final prepare = widget.onPrepareBykcWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(operation, courseId);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备操作；尚未提交任何写请求。')));
    }
  }

  Future<void> _startBykcSignWrite(int courseId, int signType) async {
    final prepare = widget.onPrepareBykcSignWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(courseId, signType);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备博雅签到；尚未提交任何写请求。')));
    }
  }

  Future<void> _startSigninWrite(String courseId) async {
    final prepare = widget.onPrepareSigninWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(courseId);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备签到；尚未提交任何写请求。')));
    }
  }

  Future<void> _startCancellationWrite(
    WriteOperation operation,
    String targetId,
  ) async {
    final prepare = widget.onPrepareCancellationWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(operation, targetId);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备取消操作；尚未提交任何写请求。')));
    }
  }

  Future<void> _startLibbookReserveWrite({
    required String areaId,
    required String seatId,
    required String day,
    required String segment,
    required String startTime,
    required String endTime,
  }) async {
    final prepare = widget.onPrepareLibbookReserveWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(
        areaId: areaId,
        seatId: seatId,
        day: day,
        segment: segment,
        startTime: startTime,
        endTime: endTime,
      );
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备图书馆预约；尚未提交任何写请求。')));
    }
  }

  Future<void> _startEvaluationWrite(
    List<EvaluationCourseInput> courses,
  ) async {
    final prepare = widget.onPrepareEvaluationWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(courses);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备教学评教；尚未提交任何写请求。')));
    }
  }

  Future<void> _startCgyySubmitWrite(CgyySubmitInput input) async {
    final prepare = widget.onPrepareCgyySubmitWrite;
    if (prepare == null || _pendingWrite != null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final intent = await prepare(input);
      if (!mounted) return;
      setState(() {
        _pendingWrite = intent;
        _writeSubmitting = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法准备场馆预约；尚未提交任何写请求。')));
    }
  }

  void _cancelWrite() {
    if (_writeSubmitting) return;
    setState(() {
      _pendingWrite = null;
      _writeError = null;
    });
  }

  Future<void> _confirmWrite() async {
    final intent = _pendingWrite;
    final commit = widget.onCommitWrite;
    if (intent == null || commit == null || _writeSubmitting) return;
    setState(() {
      _writeSubmitting = true;
      _writeError = null;
    });
    try {
      final result = await commit(intent.intentId);
      if (result.success && !result.outcomeUnknown) {
        try {
          await widget.onWriteSuccess?.call(result.operation);
        } on Object {
          // 写入已完成但读取核对失败；结果提示仍保持确定，不重试写请求。
        }
      }
      if (!mounted) return;
      setState(() {
        _pendingWrite = null;
        _writeSubmitting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } on Object {
      if (!mounted) return;
      setState(() {
        _pendingWrite = null;
        _writeSubmitting = false;
        _writeError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提交结果不确定，请先刷新相关课程状态，不要重复提交。')),
      );
    }
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.user,
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
  });

  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              '你好，${user?.preferredName ?? '同学'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: _FeatureGridSliver(
            snapshots: snapshots,
            onFeatureTap: onFeatureTap,
            onRetryFeature: onRetryFeature,
          ),
        ),
      ],
    ),
  );
}

class _FeatureGridView extends StatelessWidget {
  const _FeatureGridView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: _FeatureGridSliver(
          snapshots: snapshots,
          onFeatureTap: onFeatureTap,
          onRetryFeature: onRetryFeature,
        ),
      ),
    ],
  );
}

class _FeatureGridSliver extends StatelessWidget {
  const _FeatureGridSliver({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    this.features = ordinaryFeatureIds,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final List<FeatureId> features;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 360,
      mainAxisExtent: 160,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: features.length,
    itemBuilder: (context, index) {
      final feature = features[index];
      return _FeatureCard(
        feature: feature,
        snapshot: snapshots[feature]!,
        onTap: () => onFeatureTap(feature),
        onRetry: () => onRetryFeature(feature),
      );
    },
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.feature,
    required this.snapshot,
    required this.onTap,
    required this.onRetry,
  });

  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final VoidCallback onTap;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFailure = snapshot.status == FeatureLoadStatus.failure;
    final isStale = snapshot.status == FeatureLoadStatus.stale;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _featureIcon(feature),
                    size: 40,
                    color: colorScheme.primary,
                  ),
                  const Spacer(),
                  if (snapshot.status == FeatureLoadStatus.loading)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (isFailure || isStale)
                    IconButton(
                      tooltip: '重试',
                      onPressed: () => onRetry(),
                      icon: Icon(Icons.refresh, color: colorScheme.error),
                    )
                  else if (snapshot.status == FeatureLoadStatus.success)
                    Icon(Icons.check_circle, color: colorScheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                feature.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  _statusText(snapshot),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isFailure
                        ? colorScheme.error
                        : isStale
                        ? colorScheme.tertiary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (snapshot.resolvedRoute case final route?)
                Text(
                  '实际路线：${route.label}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(FeatureSnapshot snapshot) => switch (snapshot.status) {
    FeatureLoadStatus.idle => feature.description,
    FeatureLoadStatus.loading => '正在加载…',
    FeatureLoadStatus.success => snapshot.summary ?? '已加载，点击查看详情',
    FeatureLoadStatus.empty => '暂无数据',
    FeatureLoadStatus.stale => '${snapshot.summary ?? '已显示上次数据'}（刷新失败，可重试）',
    FeatureLoadStatus.failure => snapshot.error?.message ?? '加载失败，请重试',
  };
}

class _AdvancedFeaturesView extends StatelessWidget {
  const _AdvancedFeaturesView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: <Widget>[
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: _FeatureGridSliver(
          features: advancedFeatureIds,
          snapshots: snapshots,
          onFeatureTap: onFeatureTap,
          onRetryFeature: onRetryFeature,
        ),
      ),
    ],
  );
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.user,
    required this.routePolicy,
    required this.telemetryEnabled,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.activeRoutes,
  });

  final UserSummary? user;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final List<ConnectionMode> activeRoutes;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            radius: 28,
            child: Text((user?.preferredName ?? 'U').characters.first),
          ),
          title: Text(user?.preferredName ?? '未登录'),
          subtitle: Text(user?.username ?? ''),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('连接模式'),
              subtitle: Text(routePolicy.description),
              trailing: DropdownButton<RoutePolicy>(
                value: routePolicy,
                onChanged: (value) {
                  if (value != null) onRoutePolicyChanged(value);
                },
                items: RoutePolicy.values
                    .map(
                      (item) => DropdownMenuItem<RoutePolicy>(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('已认证路线'),
              subtitle: Text(
                activeRoutes.isEmpty
                    ? '暂无已认证路线'
                    : activeRoutes.map((route) => route.label).join('、'),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.insights_outlined),
              title: const Text('匿名产品改进统计'),
              subtitle: const Text('仅统计功能使用次数，不收集账号、成绩或请求内容'),
              value: telemetryEnabled,
              onChanged: onTelemetryChanged,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => onLogout(),
        icon: const Icon(Icons.logout),
        label: const Text('退出登录'),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => _confirmClearAccount(context),
        icon: const Icon(Icons.delete_outline),
        label: const Text('退出并清除本机账号'),
      ),
      const SizedBox(height: 32),
      Text(
        'UBAA 应用\nMake BUAA Great Again',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ],
  );

  Future<void> _confirmClearAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机账号？'),
        content: const Text('这会退出登录，并删除你主动保存的账号密码；学校服务器上的数据不会被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出并清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onLogoutAndClearAccount();
  }
}

class _FeatureDetailView extends StatelessWidget {
  const _FeatureDetailView({
    required this.feature,
    required this.snapshot,
    required this.onBack,
    required this.onRetry,
    this.onBykcWrite,
    this.onBykcSignWrite,
    this.onSigninWrite,
    this.onCancellationWrite,
    this.onLibbookReserveWrite,
    this.onCgyySubmitWrite,
    this.onEvaluationWrite,
    this.onQuery,
  });

  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(WriteOperation operation, int courseId)?
  onBykcWrite;
  final Future<void> Function(int courseId, int signType)? onBykcSignWrite;
  final Future<void> Function(String courseId)? onSigninWrite;
  final Future<void> Function(WriteOperation operation, String targetId)?
  onCancellationWrite;
  final LibbookReserveStarter? onLibbookReserveWrite;
  final CgyyReservationStarter? onCgyySubmitWrite;
  final EvaluationSubmitStarter? onEvaluationWrite;
  final Future<void> Function(FeatureQuery query)? onQuery;

  @override
  Widget build(BuildContext context) {
    final content = switch (snapshot.status) {
      FeatureLoadStatus.loading => const Center(
        child: CircularProgressIndicator(),
      ),
      FeatureLoadStatus.failure => _error(context),
      FeatureLoadStatus.stale => _stale(context),
      FeatureLoadStatus.empty => _empty(context),
      FeatureLoadStatus.idle => _empty(context),
      FeatureLoadStatus.success => _details(context),
    };
    return Column(
      children: <Widget>[
        if (onQuery != null && _supportsQuery)
          _FeatureQueryControls(
            feature: feature,
            details: snapshot.details,
            onApply: onQuery!,
          ),
        if (snapshot.resolvedRoute case final route?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.route, size: 18),
                label: Text('实际路线：${route.label}'),
              ),
            ),
          ),
        Expanded(child: content),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回功能列表'),
            ),
          ),
        ),
      ],
    );
  }

  bool get _supportsQuery => switch (feature) {
    FeatureId.schedule ||
    FeatureId.exam ||
    FeatureId.grades ||
    FeatureId.classroom ||
    FeatureId.bykc ||
    FeatureId.libbook ||
    FeatureId.ygdk ||
    FeatureId.cgyy ||
    FeatureId.signin ||
    FeatureId.spoc ||
    FeatureId.judge ||
    FeatureId.evaluation => true,
  };

  Widget _details(BuildContext context) {
    if (snapshot.details.isEmpty) return _empty(context);
    return _FeatureDetailList(
      feature: feature,
      details: snapshot.details,
      onBykcWrite: onBykcWrite,
      onBykcSignWrite: onBykcSignWrite,
      onSigninWrite: onSigninWrite,
      onCancellationWrite: onCancellationWrite,
      onLibbookReserveWrite: onLibbookReserveWrite,
      onCgyySubmitWrite: onCgyySubmitWrite,
      onEvaluationWrite: onEvaluationWrite,
    );
  }

  Widget _stale(BuildContext context) {
    if (snapshot.details.isEmpty) return _error(context);
    return Column(
      children: <Widget>[
        MaterialBanner(
          content: Text(snapshot.error?.message ?? '刷新失败，以下是上次成功加载的数据。'),
          leading: const Icon(Icons.sync_problem),
          actions: <Widget>[
            TextButton(onPressed: () => onRetry(), child: const Text('重试')),
          ],
        ),
        Expanded(
          child: _FeatureDetailList(
            feature: feature,
            details: snapshot.details,
            onBykcWrite: onBykcWrite,
            onBykcSignWrite: onBykcSignWrite,
            onSigninWrite: onSigninWrite,
            onCancellationWrite: onCancellationWrite,
            onLibbookReserveWrite: onLibbookReserveWrite,
            onCgyySubmitWrite: onCgyySubmitWrite,
            onEvaluationWrite: onEvaluationWrite,
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _featureIcon(feature),
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('暂无${feature.title}数据'),
          if (snapshot.summary case final summary?
              when summary.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(summary, textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );

  Widget _error(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FriendlyErrorCard(
          error:
              snapshot.error ??
              const UiError(
                code: UbaaErrorCode.internalError,
                title: '加载失败',
                message: '暂时无法加载该功能，请稍后重试。',
                retryable: true,
              ),
          onRetry: () => onRetry(),
        ),
      ),
    ),
  );
}

class _FeatureQueryControls extends StatefulWidget {
  const _FeatureQueryControls({
    required this.feature,
    required this.details,
    required this.onApply,
  });

  final FeatureId feature;
  final List<FeatureDetail> details;
  final Future<void> Function(FeatureQuery query) onApply;

  @override
  State<_FeatureQueryControls> createState() => _FeatureQueryControlsState();
}

class _FeatureQueryControlsState extends State<_FeatureQueryControls> {
  late final TextEditingController _termController;
  late final TextEditingController _dateController;
  late final TextEditingController _floorController;
  late final TextEditingController _sectionController;
  late final TextEditingController _weekController;
  late final TextEditingController _pageController;
  late final TextEditingController _sizeController;
  late final TextEditingController _premisesController;
  late final TextEditingController _storeyController;
  late final TextEditingController _areaController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _segmentController;
  late final TextEditingController _siteController;
  late final TextEditingController _orderController;
  late final TextEditingController _bykcCourseController;
  late final TextEditingController _spocAssignmentController;
  late final TextEditingController _judgeCourseController;
  late final TextEditingController _judgeAssignmentController;
  late final TextEditingController _judgeBatchController;
  int _campus = 1;
  FeatureQueryView _scheduleView = FeatureQueryView.summary;
  FeatureQueryView _examView = FeatureQueryView.summary;
  FeatureQueryView _gradesView = FeatureQueryView.summary;
  FeatureQueryView _evaluationView = FeatureQueryView.summary;
  FeatureQueryView _libbookView = FeatureQueryView.summary;
  FeatureQueryView _bykcView = FeatureQueryView.summary;
  FeatureQueryView _ygdkView = FeatureQueryView.summary;
  FeatureQueryView _cgyyView = FeatureQueryView.summary;
  FeatureQueryView _spocView = FeatureQueryView.summary;
  FeatureQueryView _judgeView = FeatureQueryView.summary;
  FeatureQueryView _signinView = FeatureQueryView.summary;
  bool _includeExpired = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _termController = TextEditingController();
    _dateController = TextEditingController(text: _today());
    _floorController = TextEditingController();
    _sectionController = TextEditingController();
    _weekController = TextEditingController();
    _pageController = TextEditingController(text: '1');
    _sizeController = TextEditingController(text: '20');
    _premisesController = TextEditingController();
    _storeyController = TextEditingController();
    _areaController = TextEditingController();
    _startController = TextEditingController(text: '08:00');
    _endController = TextEditingController(text: '22:00');
    _segmentController = TextEditingController();
    _siteController = TextEditingController();
    _orderController = TextEditingController();
    _bykcCourseController = TextEditingController();
    _spocAssignmentController = TextEditingController();
    _judgeCourseController = TextEditingController();
    _judgeAssignmentController = TextEditingController();
    _judgeBatchController = TextEditingController();
  }

  @override
  void dispose() {
    _termController.dispose();
    _dateController.dispose();
    _floorController.dispose();
    _sectionController.dispose();
    _weekController.dispose();
    _pageController.dispose();
    _sizeController.dispose();
    _premisesController.dispose();
    _storeyController.dispose();
    _areaController.dispose();
    _startController.dispose();
    _endController.dispose();
    _segmentController.dispose();
    _siteController.dispose();
    _orderController.dispose();
    _bykcCourseController.dispose();
    _spocAssignmentController.dispose();
    _judgeCourseController.dispose();
    _judgeAssignmentController.dispose();
    _judgeBatchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (widget.feature == FeatureId.schedule)
            DropdownButton<FeatureQueryView>(
              value: _scheduleView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _scheduleView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('今日课程'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.scheduleTerms,
                  child: Text('学期列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.scheduleWeeks,
                  child: Text('周次列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.scheduleWeek,
                  child: Text('周课表'),
                ),
              ],
            ),
          if (widget.feature == FeatureId.exam)
            DropdownButton<FeatureQueryView>(
              value: _examView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _examView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('全部考试'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.examArranged,
                  child: Text('已安排'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.examNotArranged,
                  child: Text('未安排'),
                ),
              ],
            ),
          if (widget.feature == FeatureId.grades)
            DropdownButton<FeatureQueryView>(
              value: _gradesView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _gradesView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('全部成绩'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.gradesScored,
                  child: Text('已出成绩'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.gradesMissing,
                  child: Text('待出成绩'),
                ),
              ],
            ),
          if (widget.feature == FeatureId.schedule ||
              widget.feature == FeatureId.exam ||
              widget.feature == FeatureId.grades) ...<Widget>[
            SizedBox(
              width: 180,
              child: TextField(
                controller: _termController,
                decoration: const InputDecoration(
                  labelText: '学期编码（可选）',
                  hintText: '留空使用当前学期',
                  isDense: true,
                ),
              ),
            ),
            if (widget.feature == FeatureId.schedule)
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _weekController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '周次（可选）',
                    hintText: '如 1',
                    isDense: true,
                  ),
                ),
              ),
          ],
          if (widget.feature == FeatureId.classroom) ...<Widget>[
            SizedBox(
              width: 150,
              child: TextField(
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: '日期',
                  hintText: 'YYYY-MM-DD',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _floorController,
                decoration: const InputDecoration(
                  labelText: '楼层（可选）',
                  hintText: '如 F2',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _sectionController,
                decoration: const InputDecoration(
                  labelText: '节次（可选）',
                  hintText: '如 3',
                  isDense: true,
                ),
              ),
            ),
            DropdownButton<int>(
              value: _campus,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _campus = value ?? 1),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 1, child: Text('校区 1')),
                DropdownMenuItem(value: 2, child: Text('校区 2')),
                DropdownMenuItem(value: 3, child: Text('校区 3')),
              ],
            ),
          ],
          if (widget.feature == FeatureId.bykc) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _bykcView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _bykcView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('课程列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.bykcDetail,
                  child: Text('课程详情'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.bykcChosenCourses,
                  child: Text('已选课程'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.bykcStatistics,
                  child: Text('修读统计'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.bykcProfile,
                  child: Text('个人资料'),
                ),
              ],
            ),
            if (_bykcView == FeatureQueryView.summary) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '页码',
                    hintText: '从 1 开始',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每页数量',
                    hintText: '1–100',
                    isDense: true,
                  ),
                ),
              ),
            ],
            if (_bykcView == FeatureQueryView.bykcDetail) ...<Widget>[
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _bykcCourseController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '课程 ID',
                    hintText: '从课程列表选择',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前列表选择课程',
                values: _detailFieldValues('课程 ID'),
                onSelected: (value) => _bykcCourseController.text = value,
              ),
            ],
          ],
          if (widget.feature == FeatureId.libbook) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _libbookView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _libbookView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('馆列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.libbookAreas,
                  child: Text('馆区列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.libbookAreaDetail,
                  child: Text('分区详情'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.libbookSeats,
                  child: Text('座位查询'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.libbookBookings,
                  child: Text('预约记录'),
                ),
              ],
            ),
            if (_libbookView == FeatureQueryView.libbookAreas) ...<Widget>[
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _premisesController,
                  decoration: const InputDecoration(
                    labelText: '馆区 ID',
                    hintText: '从馆列表选择',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _storeyController,
                  decoration: const InputDecoration(
                    labelText: '楼层 ID（可选）',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前馆列表选择',
                values: _detailFieldValues('馆 ID'),
                onSelected: (value) => _premisesController.text = value,
              ),
            ],
            if (_libbookView == FeatureQueryView.libbookAreaDetail) ...<Widget>[
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _areaController,
                  decoration: const InputDecoration(
                    labelText: '分区 ID',
                    hintText: '从馆区列表选择',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前馆区选择',
                values: _detailFieldValues('分区 ID'),
                onSelected: (value) => _areaController.text = value,
              ),
            ],
            if (_libbookView == FeatureQueryView.libbookSeats) ...<Widget>[
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _areaController,
                  decoration: const InputDecoration(
                    labelText: '分区 ID',
                    hintText: '从馆区列表选择',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: '日期',
                    hintText: 'YYYY-MM-DD',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _startController,
                  decoration: const InputDecoration(
                    labelText: '开始时间',
                    hintText: '08:00',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _endController,
                  decoration: const InputDecoration(
                    labelText: '结束时间',
                    hintText: '22:00',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _segmentController,
                  decoration: const InputDecoration(
                    labelText: '时段编号（可选）',
                    hintText: '预约时必填',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前馆区选择',
                values: _detailFieldValues('分区 ID'),
                onSelected: (value) => _areaController.text = value,
              ),
            ],
            if (_libbookView == FeatureQueryView.libbookBookings) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '页码',
                    hintText: '从 1 开始',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每页数量',
                    hintText: '1–100',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ],
          if (widget.feature == FeatureId.ygdk) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _ygdkView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _ygdkView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('概览'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.ygdkRecords,
                  child: Text('记录列表'),
                ),
              ],
            ),
            if (_ygdkView == FeatureQueryView.ygdkRecords) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '页码',
                    hintText: '从 1 开始',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每页数量',
                    hintText: '1–100',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ],
          if (widget.feature == FeatureId.cgyy) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _cgyyView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _cgyyView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('站点列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.cgyyPurposeTypes,
                  child: Text('用途类型'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.cgyyDayInfo,
                  child: Text('日期空间'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.cgyyOrders,
                  child: Text('订单列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.cgyyOrderDetail,
                  child: Text('订单详情'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.cgyyLockCode,
                  child: Text('门锁状态'),
                ),
              ],
            ),
            if (_cgyyView == FeatureQueryView.cgyyDayInfo) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _siteController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '站点 ID',
                    hintText: '从站点列表选择',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: '日期',
                    hintText: 'YYYY-MM-DD',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前站点选择',
                values: _detailFieldValues('站点 ID'),
                onSelected: (value) => _siteController.text = value,
              ),
            ],
            if (_cgyyView == FeatureQueryView.cgyyOrders) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '页码',
                    hintText: '从 1 开始',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _sizeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每页数量',
                    hintText: '1–100',
                    isDense: true,
                  ),
                ),
              ),
            ],
            if (_cgyyView == FeatureQueryView.cgyyOrderDetail) ...<Widget>[
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _orderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '订单 ID',
                    hintText: '从订单列表选择',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前订单选择',
                values: _detailFieldValues('订单编号'),
                onSelected: (value) => _orderController.text = value,
              ),
            ],
          ],
          if (widget.feature == FeatureId.spoc) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _spocView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _spocView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('作业列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.spocDetail,
                  child: Text('作业详情'),
                ),
              ],
            ),
            if (_spocView == FeatureQueryView.spocDetail) ...<Widget>[
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _spocAssignmentController,
                  decoration: const InputDecoration(
                    labelText: '作业编号',
                    hintText: '从作业列表选择',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前作业列表选择',
                values: _detailFieldValues('作业编号'),
                onSelected: (value) => _spocAssignmentController.text = value,
              ),
            ],
          ],
          if (widget.feature == FeatureId.evaluation)
            DropdownButton<FeatureQueryView>(
              value: _evaluationView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _evaluationView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('全部课程'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.evaluationPending,
                  child: Text('待评课程'),
                ),
              ],
            ),
          if (widget.feature == FeatureId.signin)
            DropdownButton<FeatureQueryView>(
              value: _signinView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _signinView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('全部课程'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.signinPending,
                  child: Text('未签到'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.signinCompleted,
                  child: Text('已签到'),
                ),
              ],
            ),
          if (widget.feature == FeatureId.judge) ...<Widget>[
            DropdownButton<FeatureQueryView>(
              value: _judgeView,
              onChanged: _submitting
                  ? null
                  : (value) => setState(
                      () => _judgeView = value ?? FeatureQueryView.summary,
                    ),
              items: const <DropdownMenuItem<FeatureQueryView>>[
                DropdownMenuItem(
                  value: FeatureQueryView.summary,
                  child: Text('作业列表'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.judgeDetail,
                  child: Text('作业详情'),
                ),
                DropdownMenuItem(
                  value: FeatureQueryView.judgeBatchDetails,
                  child: Text('批量详情'),
                ),
              ],
            ),
            if (_judgeView == FeatureQueryView.judgeDetail) ...<Widget>[
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _judgeCourseController,
                  decoration: const InputDecoration(
                    labelText: '课程编号',
                    hintText: '从作业列表选择',
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _judgeAssignmentController,
                  decoration: const InputDecoration(
                    labelText: '作业编号',
                    hintText: '从作业列表选择',
                    isDense: true,
                  ),
                ),
              ),
              _valuePicker(
                label: '从当前作业列表选择课程',
                values: _detailFieldValues('课程编号'),
                onSelected: (value) => _judgeCourseController.text = value,
              ),
              _valuePicker(
                label: '从当前作业列表选择作业',
                values: _detailFieldValues('作业编号'),
                onSelected: (value) => _judgeAssignmentController.text = value,
              ),
            ],
            if (_judgeView == FeatureQueryView.judgeBatchDetails)
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _judgeBatchController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '批量作业键',
                    hintText: '每行：课程编号/作业编号',
                    helperText: '仅填写作业列表中的公开编号',
                    isDense: true,
                  ),
                ),
              ),
            if (_judgeView == FeatureQueryView.summary)
              FilterChip(
                label: const Text('包含已过期作业'),
                selected: _includeExpired,
                onSelected: _submitting
                    ? null
                    : (selected) => setState(() => _includeExpired = selected),
              ),
          ],
          FilledButton.tonal(
            onPressed: _submitting ? null : _apply,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('应用筛选'),
          ),
        ],
      ),
    ),
  );

  Future<void> _apply() async {
    setState(() => _submitting = true);
    try {
      DateTime? date;
      int? week;
      var page = 0;
      var size = 20;
      if (widget.feature == FeatureId.schedule) {
        final rawWeek = _weekController.text.trim();
        if (rawWeek.isNotEmpty) {
          week = int.tryParse(rawWeek);
          if (week == null || week <= 0) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('周次必须是正整数。')));
            }
            return;
          }
        }
        if (_scheduleView == FeatureQueryView.scheduleWeeks ||
            _scheduleView == FeatureQueryView.scheduleWeek) {
          if (_termController.text.trim().isEmpty) {
            _showMessage('学期编码不能为空。');
            return;
          }
        }
        if (_scheduleView == FeatureQueryView.scheduleWeek && week == null) {
          _showMessage('周次不能为空。');
          return;
        }
      }
      if (widget.feature == FeatureId.classroom) {
        final rawDate = _dateController.text.trim();
        if (rawDate.isNotEmpty) {
          date = DateTime.tryParse(rawDate);
          if (date == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日期格式无效，请使用 YYYY-MM-DD。')),
              );
            }
            return;
          }
        }
        final rawSection = _sectionController.text.trim();
        if (rawSection.isNotEmpty) {
          final section = int.tryParse(rawSection);
          if (section == null || section <= 0) {
            _showMessage('节次必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.bykc) {
        if (_bykcView == FeatureQueryView.summary) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('页码必须从 1 开始，每页数量须为 1–100。')),
              );
            }
            return;
          }
        }
        if (_bykcView == FeatureQueryView.bykcDetail) {
          final courseId = int.tryParse(_bykcCourseController.text.trim());
          if (courseId == null || courseId <= 0) {
            _showMessage('课程 ID 必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.libbook) {
        if (_libbookView == FeatureQueryView.libbookAreas &&
            _premisesController.text.trim().isEmpty) {
          _showMessage('馆区 ID 不能为空。');
          return;
        }
        if ((_libbookView == FeatureQueryView.libbookAreaDetail ||
                _libbookView == FeatureQueryView.libbookSeats) &&
            _areaController.text.trim().isEmpty) {
          _showMessage('分区 ID 不能为空。');
          return;
        }
        if (_libbookView == FeatureQueryView.libbookSeats) {
          final rawDate = _dateController.text.trim();
          if (rawDate.isNotEmpty) {
            date = DateTime.tryParse(rawDate);
            if (date == null) {
              _showMessage('日期格式无效，请使用 YYYY-MM-DD。');
              return;
            }
          }
          if (_startController.text.trim().isEmpty ||
              _endController.text.trim().isEmpty) {
            _showMessage('开始和结束时间不能为空。');
            return;
          }
        }
        if (_libbookView == FeatureQueryView.libbookBookings) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.ygdk &&
          _ygdkView == FeatureQueryView.ygdkRecords) {
        page = int.tryParse(_pageController.text.trim()) ?? 0;
        size = int.tryParse(_sizeController.text.trim()) ?? 0;
        if (page <= 0 || size <= 0 || size > 100) {
          _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
          return;
        }
      }
      if (widget.feature == FeatureId.cgyy) {
        if (_cgyyView == FeatureQueryView.cgyyDayInfo) {
          final site = int.tryParse(_siteController.text.trim());
          if (site == null || site <= 0) {
            _showMessage('站点 ID 必须是正整数。');
            return;
          }
          final rawDate = _dateController.text.trim();
          if (rawDate.isNotEmpty) {
            date = DateTime.tryParse(rawDate);
            if (date == null) {
              _showMessage('日期格式无效，请使用 YYYY-MM-DD。');
              return;
            }
          }
        }
        if (_cgyyView == FeatureQueryView.cgyyOrders) {
          page = int.tryParse(_pageController.text.trim()) ?? 0;
          size = int.tryParse(_sizeController.text.trim()) ?? 0;
          if (page <= 0 || size <= 0 || size > 100) {
            _showMessage('页码必须从 1 开始，每页数量须为 1–100。');
            return;
          }
        }
        if (_cgyyView == FeatureQueryView.cgyyOrderDetail) {
          final order = int.tryParse(_orderController.text.trim());
          if (order == null || order <= 0) {
            _showMessage('订单 ID 必须是正整数。');
            return;
          }
        }
      }
      if (widget.feature == FeatureId.spoc &&
          _spocView == FeatureQueryView.spocDetail &&
          _spocAssignmentController.text.trim().isEmpty) {
        _showMessage('作业编号不能为空。');
        return;
      }
      if (widget.feature == FeatureId.judge &&
          _judgeView == FeatureQueryView.judgeDetail) {
        if (_judgeCourseController.text.trim().isEmpty) {
          _showMessage('课程编号不能为空。');
          return;
        }
        if (_judgeAssignmentController.text.trim().isEmpty) {
          _showMessage('作业编号不能为空。');
          return;
        }
      }
      List<JudgeAssignmentQueryKey> judgeKeys =
          const <JudgeAssignmentQueryKey>[];
      if (widget.feature == FeatureId.judge &&
          _judgeView == FeatureQueryView.judgeBatchDetails) {
        final parsedKeys = _parseJudgeBatchKeys();
        if (parsedKeys == null) return;
        if (parsedKeys.isEmpty) {
          _showMessage('请至少填写一项批量作业键，格式为课程编号/作业编号。');
          return;
        }
        judgeKeys = parsedKeys;
      }
      await widget.onApply(
        FeatureQuery(
          term: _termController.text.trim().isEmpty
              ? null
              : _termController.text.trim(),
          date: date,
          campus: widget.feature == FeatureId.classroom ? _campus : null,
          floorId: widget.feature == FeatureId.classroom
              ? _optionalText(_floorController)
              : null,
          section: widget.feature == FeatureId.classroom
              ? _optionalText(_sectionController)
              : null,
          week: week,
          page: page,
          size: size,
          view: widget.feature == FeatureId.exam
              ? _examView
              : widget.feature == FeatureId.schedule
              ? _scheduleView
              : widget.feature == FeatureId.grades
              ? _gradesView
              : widget.feature == FeatureId.evaluation
              ? _evaluationView
              : widget.feature == FeatureId.ygdk
              ? _ygdkView
              : widget.feature == FeatureId.cgyy
              ? _cgyyView
              : widget.feature == FeatureId.bykc
              ? _bykcView
              : widget.feature == FeatureId.spoc
              ? _spocView
              : widget.feature == FeatureId.judge
              ? _judgeView
              : widget.feature == FeatureId.signin
              ? _signinView
              : _libbookView,
          premisesId: _optionalText(_premisesController),
          storeyId: _optionalText(_storeyController),
          areaId: _optionalText(_areaController),
          startTime: _optionalText(_startController),
          endTime: _optionalText(_endController),
          segment: _optionalText(_segmentController),
          siteId: widget.feature == FeatureId.cgyy
              ? int.tryParse(_siteController.text.trim())
              : null,
          orderId: widget.feature == FeatureId.cgyy
              ? int.tryParse(_orderController.text.trim())
              : null,
          assignmentId: widget.feature == FeatureId.spoc
              ? _optionalText(_spocAssignmentController)
              : widget.feature == FeatureId.judge &&
                    _judgeView == FeatureQueryView.judgeDetail
              ? _optionalText(_judgeAssignmentController)
              : null,
          courseId:
              widget.feature == FeatureId.judge &&
                  _judgeView == FeatureQueryView.judgeDetail
              ? _optionalText(_judgeCourseController)
              : widget.feature == FeatureId.bykc
              ? _optionalText(_bykcCourseController)
              : null,
          judgeKeys: judgeKeys,
          includeExpired:
              widget.feature == FeatureId.judge &&
                  _judgeView == FeatureQueryView.summary
              ? _includeExpired
              : false,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  List<String> _detailFieldValues(String label) => widget.details
      .expand((detail) => detail.fields)
      .where((field) => field.label == label && field.value.trim().isNotEmpty)
      .map((field) => field.value.trim())
      .toSet()
      .toList(growable: false);

  Widget _valuePicker({
    required String label,
    required List<String> values,
    required ValueChanged<String> onSelected,
  }) => DropdownButton<String>(
    hint: Text(label),
    onChanged: _submitting || values.isEmpty
        ? null
        : (value) {
            if (value != null) onSelected(value);
          },
    items: values
        .map(
          (value) => DropdownMenuItem<String>(value: value, child: Text(value)),
        )
        .toList(growable: false),
  );

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  List<JudgeAssignmentQueryKey>? _parseJudgeBatchKeys() {
    final keys = <JudgeAssignmentQueryKey>[];
    for (final rawLine in _judgeBatchController.text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('/');
      if (separator <= 0 ||
          separator == line.length - 1 ||
          line.indexOf('/', separator + 1) != -1) {
        _showMessage('批量作业键格式无效，请使用课程编号/作业编号。');
        return null;
      }
      final courseId = line.substring(0, separator).trim();
      final assignmentId = line.substring(separator + 1).trim();
      if (courseId.isEmpty || assignmentId.isEmpty) {
        _showMessage('批量作业键格式无效，请使用课程编号/作业编号。');
        return null;
      }
      keys.add(
        JudgeAssignmentQueryKey(courseId: courseId, assignmentId: assignmentId),
      );
    }
    return List<JudgeAssignmentQueryKey>.unmodifiable(keys);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 88,
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(child: Text(value)),
    ],
  );
}

/// 详情列表的本地筛选只作用于 bridge 白名单字段。
class _FeatureDetailList extends StatefulWidget {
  const _FeatureDetailList({
    required this.feature,
    required this.details,
    this.onBykcWrite,
    this.onBykcSignWrite,
    this.onSigninWrite,
    this.onCancellationWrite,
    this.onLibbookReserveWrite,
    this.onCgyySubmitWrite,
    this.onEvaluationWrite,
  });

  final FeatureId feature;
  final List<FeatureDetail> details;
  final Future<void> Function(WriteOperation operation, int courseId)?
  onBykcWrite;
  final Future<void> Function(int courseId, int signType)? onBykcSignWrite;
  final Future<void> Function(String courseId)? onSigninWrite;
  final Future<void> Function(WriteOperation operation, String targetId)?
  onCancellationWrite;
  final LibbookReserveStarter? onLibbookReserveWrite;
  final CgyyReservationStarter? onCgyySubmitWrite;
  final EvaluationSubmitStarter? onEvaluationWrite;

  @override
  State<_FeatureDetailList> createState() => _FeatureDetailListState();
}

class _FeatureDetailListState extends State<_FeatureDetailList> {
  static const _pageSize = 20;
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final details = query.isEmpty
        ? widget.details
        : widget.details
              .where((detail) {
                final values = <String>[
                  detail.title,
                  if (detail.subtitle case final subtitle?) subtitle,
                  for (final field in detail.fields) ...<String>[
                    field.label,
                    field.value,
                  ],
                ];
                return values.any(
                  (value) => value.toLowerCase().contains(query),
                );
              })
              .toList(growable: false);
    final pageCount = details.isEmpty
        ? 0
        : (details.length + _pageSize - 1) ~/ _pageSize;
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final start = page * _pageSize;
    final visible = details.skip(start).take(_pageSize).toList(growable: false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: '筛选详情',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {
              _query = value;
              _page = 0;
            }),
          ),
        ),
        Expanded(
          child: details.isEmpty
              ? const Center(child: Text('没有匹配的详情'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final detail = visible[index];
                    final courseId = _courseId(detail);
                    final signinCourseId = _courseKey(detail);
                    final cancellation = _cancellationTarget(detail);
                    final reservation = _libbookReserveTarget(detail);
                    final cgyyReservation = _cgyyReservationTarget(detail);
                    final evaluation = _evaluationTarget(detail);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              detail.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (detail.subtitle case final subtitle?
                                when subtitle.trim().isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            for (final field in detail.fields) ...<Widget>[
                              const SizedBox(height: 8),
                              _DetailField(
                                label: field.label,
                                value: field.value,
                              ),
                            ],
                            if (widget.feature == FeatureId.bykc &&
                                widget.onBykcWrite != null &&
                                courseId != null) ...<Widget>[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    onPressed: () => widget.onBykcWrite!(
                                      WriteOperation.bykcSelectCourse,
                                      courseId,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('准备选课'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => widget.onBykcWrite!(
                                      WriteOperation.bykcDeselectCourse,
                                      courseId,
                                    ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    label: const Text('准备退选'),
                                  ),
                                ],
                              ),
                            ],
                            if (widget.feature == FeatureId.bykc &&
                                widget.onBykcSignWrite != null &&
                                courseId != null) ...<Widget>[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        widget.onBykcSignWrite!(courseId, 1),
                                    icon: const Icon(Icons.login),
                                    label: const Text('准备博雅签到'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        widget.onBykcSignWrite!(courseId, 2),
                                    icon: const Icon(Icons.logout),
                                    label: const Text('准备博雅签退'),
                                  ),
                                ],
                              ),
                            ],
                            if (widget.feature == FeatureId.signin &&
                                widget.onSigninWrite != null &&
                                signinCourseId != null &&
                                signinCourseId.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    widget.onSigninWrite!(signinCourseId),
                                icon: const Icon(Icons.how_to_reg),
                                label: const Text('准备签到'),
                              ),
                            ],
                            if (cancellation != null &&
                                widget.onCancellationWrite != null) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => widget.onCancellationWrite!(
                                  cancellation.operation,
                                  cancellation.targetId,
                                ),
                                icon: const Icon(Icons.event_busy),
                                label: Text(
                                  cancellation.operation ==
                                          WriteOperation.libbookCancelBooking
                                      ? '准备取消预约'
                                      : '准备取消订单',
                                ),
                              ),
                            ],
                            if (reservation != null &&
                                widget.onLibbookReserveWrite !=
                                    null) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => widget.onLibbookReserveWrite!(
                                  areaId: reservation.areaId,
                                  seatId: reservation.seatId,
                                  day: reservation.day,
                                  segment: reservation.segment,
                                  startTime: reservation.startTime,
                                  endTime: reservation.endTime,
                                ),
                                icon: const Icon(Icons.event_available),
                                label: const Text('准备预约此座位'),
                              ),
                            ],
                            if (evaluation != null &&
                                widget.onEvaluationWrite != null) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => widget.onEvaluationWrite!(
                                  <EvaluationCourseInput>[evaluation],
                                ),
                                icon: const Icon(Icons.rate_review_outlined),
                                label: const Text('准备提交评教'),
                              ),
                            ],
                            if (cgyyReservation != null &&
                                widget.onCgyySubmitWrite != null) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () => _showCgyyReservationForm(
                                  context,
                                  cgyyReservation,
                                ),
                                icon: const Icon(Icons.event_available),
                                label: const Text('准备场馆预约'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (pageCount > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: '上一页',
                  onPressed: page == 0
                      ? null
                      : () => setState(() => _page = page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Semantics(
                  label: '详情分页',
                  child: Text('${page + 1} / $pageCount'),
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed: page + 1 >= pageCount
                      ? null
                      : () => setState(() => _page = page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }

  int? _courseId(FeatureDetail detail) {
    for (final field in detail.fields) {
      if (field.label == '课程 ID') return int.tryParse(field.value.trim());
    }
    return null;
  }

  String? _courseKey(FeatureDetail detail) {
    for (final field in detail.fields) {
      if (field.label == '课程 ID') return field.value.trim();
    }
    return null;
  }

  ({WriteOperation operation, String targetId})? _cancellationTarget(
    FeatureDetail detail,
  ) {
    final label = switch (widget.feature) {
      FeatureId.libbook => '预约 ID',
      FeatureId.cgyy => '订单编号',
      _ => null,
    };
    if (label == null) return null;
    for (final field in detail.fields) {
      final value = field.value.trim();
      if (field.label == label && value.isNotEmpty) {
        return (
          operation: widget.feature == FeatureId.libbook
              ? WriteOperation.libbookCancelBooking
              : WriteOperation.cgyyCancelOrder,
          targetId: value,
        );
      }
    }
    return null;
  }

  ({
    String areaId,
    String seatId,
    String day,
    String segment,
    String startTime,
    String endTime,
  })?
  _libbookReserveTarget(FeatureDetail detail) {
    if (widget.feature != FeatureId.libbook) return null;
    final values = <String, String>{
      for (final field in detail.fields) field.label: field.value.trim(),
    };
    if (values['可预约'] != '是') return null;
    const required = <String>['分区 ID', '座位 ID', '日期', '时段', '开始时间', '结束时间'];
    if (required.any((label) => (values[label] ?? '').isEmpty)) return null;
    return (
      areaId: values['分区 ID']!,
      seatId: values['座位 ID']!,
      day: values['日期']!,
      segment: values['时段']!,
      startTime: values['开始时间']!,
      endTime: values['结束时间']!,
    );
  }

  ({
    int venueSiteId,
    String reservationDate,
    CgyyReservationSelectionInput selection,
  })?
  _cgyyReservationTarget(FeatureDetail detail) {
    if (widget.feature != FeatureId.cgyy) return null;
    final values = <String, String>{
      for (final field in detail.fields) field.label: field.value.trim(),
    };
    if (values['可预约'] != '是') return null;
    final siteId = int.tryParse(values['站点 ID'] ?? '');
    final spaceId = int.tryParse(values['空间 ID'] ?? '');
    final timeId = int.tryParse(values['时段 ID'] ?? '');
    final date = values['日期'];
    if (siteId == null ||
        siteId <= 0 ||
        spaceId == null ||
        spaceId <= 0 ||
        timeId == null ||
        timeId <= 0 ||
        date == null ||
        date.isEmpty) {
      return null;
    }
    final groupId = int.tryParse(values['空间组 ID'] ?? '');
    return (
      venueSiteId: siteId,
      reservationDate: date,
      selection: CgyyReservationSelectionInput(
        spaceId: spaceId,
        timeId: timeId,
        venueSpaceGroupId: groupId,
      ),
    );
  }

  Future<void> _showCgyyReservationForm(
    BuildContext context,
    ({
      int venueSiteId,
      String reservationDate,
      CgyyReservationSelectionInput selection,
    })
    target,
  ) async {
    final phone = TextEditingController();
    final theme = TextEditingController();
    final purpose = TextEditingController();
    final joinerNum = TextEditingController(text: '1');
    final content = TextEditingController();
    final joiners = TextEditingController();
    final input = await showDialog<CgyySubmitInput>(
      context: context,
      builder: (dialogContext) {
        var philosophy = false;
        var offSchool = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('填写场馆预约信息'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '站点 ${target.venueSiteId} · ${target.reservationDate}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '空间 ${target.selection.spaceId} · 时段 ${target.selection.timeId}',
                    ),
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '联系电话'),
                    ),
                    TextField(
                      controller: theme,
                      decoration: const InputDecoration(labelText: '预约主题'),
                    ),
                    TextField(
                      controller: purpose,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '用途编号'),
                    ),
                    TextField(
                      controller: joinerNum,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '参与人数'),
                    ),
                    TextField(
                      controller: content,
                      decoration: const InputDecoration(labelText: '活动内容'),
                    ),
                    TextField(
                      controller: joiners,
                      decoration: const InputDecoration(labelText: '参与人说明（可选）'),
                    ),
                    CheckboxListTile(
                      value: philosophy,
                      onChanged: (value) => setState(() {
                        philosophy = value ?? false;
                      }),
                      title: const Text('哲学社会科学类活动'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: offSchool,
                      onChanged: (value) => setState(() {
                        offSchool = value ?? false;
                      }),
                      title: const Text('含校外参与人'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (error case final message?)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final parsedPurpose = int.tryParse(purpose.text.trim());
                  final parsedJoinerNum = int.tryParse(joinerNum.text.trim());
                  if (phone.text.trim().isEmpty ||
                      theme.text.trim().isEmpty ||
                      content.text.trim().isEmpty ||
                      parsedPurpose == null ||
                      parsedPurpose <= 0 ||
                      parsedJoinerNum == null ||
                      parsedJoinerNum <= 0) {
                    setState(() => error = '请完整填写联系电话、主题、用途编号、人数和活动内容。');
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    CgyySubmitInput(
                      venueSiteId: target.venueSiteId,
                      reservationDate: target.reservationDate,
                      selections: <CgyyReservationSelectionInput>[
                        target.selection,
                      ],
                      phone: phone.text.trim(),
                      theme: theme.text.trim(),
                      purposeType: parsedPurpose,
                      joinerNum: parsedJoinerNum,
                      activityContent: content.text.trim(),
                      joiners: joiners.text.trim(),
                      isPhilosophySocialSciences: philosophy,
                      isOffSchoolJoiner: offSchool,
                    ),
                  );
                },
                child: const Text('继续确认'),
              ),
            ],
          ),
        );
      },
    );
    // 等待对话框退出动画完成后再销毁控制器，避免 TextField 在过渡帧读取已释放的输入。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    phone.dispose();
    theme.dispose();
    purpose.dispose();
    joinerNum.dispose();
    content.dispose();
    joiners.dispose();
    if (input != null && mounted) {
      await widget.onCgyySubmitWrite?.call(input);
    }
  }

  EvaluationCourseInput? _evaluationTarget(FeatureDetail detail) {
    if (widget.feature != FeatureId.evaluation) return null;
    final values = <String, String>{
      for (final field in detail.fields) field.label: field.value.trim(),
    };
    if (values['状态'] != '待评') return null;
    final id = values['课程 ID'];
    final rwid = values['任务 ID'];
    final wjid = values['问卷 ID'];
    final kcdm = values['课程代码'];
    final msid = values['模型 ID'];
    if ([
      id,
      rwid,
      wjid,
      kcdm,
      msid,
    ].any((value) => value == null || value.isEmpty)) {
      return null;
    }
    return EvaluationCourseInput(
      id: id!,
      kcmc: detail.title,
      bpmc: detail.subtitle?.trim() ?? '',
      rwid: rwid!,
      wjid: wjid!,
      kcdm: kcdm!,
      msid: msid!,
    );
  }
}

/// 所有写操作共用的二次确认组件。
///
/// 组件不接收任意 JSON 或原始请求，只接收 bridge 已校验的 [WriteIntent]；
/// 提交按钮在意图过期或提交中自动禁用。
class WriteConfirmationView extends StatelessWidget {
  const WriteConfirmationView({
    required this.intent,
    required this.onCancel,
    required this.onConfirm,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  final WriteIntent intent;
  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;
  final bool isSubmitting;
  final UiError? error;

  @override
  Widget build(BuildContext context) {
    final expired = intent.isExpired();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '确认${intent.operation.title}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                _DetailField(label: '目标', value: intent.targetSummary),
                const SizedBox(height: 8),
                _DetailField(label: '实际路线', value: intent.resolvedRoute.label),
                const SizedBox(height: 8),
                _DetailField(
                  label: '有效期至',
                  value: _formatDateTime(intent.expiresAt),
                ),
                if (intent.warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text('请注意', style: Theme.of(context).textTheme.titleSmall),
                  for (final warning in intent.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('• $warning'),
                    ),
                ],
                if (error case final error?) ...<Widget>[
                  const SizedBox(height: 16),
                  FriendlyErrorCard(error: error),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: isSubmitting ? null : onCancel,
                      child: const Text('取消'),
                    ),
                    FilledButton.icon(
                      onPressed: expired || isSubmitting
                          ? null
                          : () => onConfirm(),
                      icon: isSubmitting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(expired ? '意图已过期' : '确认提交'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

/// 统一错误卡片，避免将上游正文、URL 或堆栈直接展示给用户。
class FriendlyErrorCard extends StatelessWidget {
  const FriendlyErrorCard({required this.error, this.onRetry, super.key});

  final UiError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    error.title,
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error.message,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                  if (error.retryable && onRetry != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onRetry,
                      child: Text(error.actionLabel ?? '重试'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _featureIcon(FeatureId feature) => switch (feature) {
  FeatureId.schedule => Icons.calendar_today,
  FeatureId.exam => Icons.assignment_outlined,
  FeatureId.grades => Icons.grade,
  FeatureId.bykc => Icons.school,
  FeatureId.classroom => Icons.meeting_room,
  FeatureId.spoc => Icons.assignment_turned_in,
  FeatureId.judge => Icons.code,
  FeatureId.libbook => Icons.event_seat,
  FeatureId.signin => Icons.how_to_reg,
  FeatureId.cgyy => Icons.sports_gymnastics,
  FeatureId.ygdk => Icons.wb_sunny,
  FeatureId.evaluation => Icons.assignment_turned_in,
};
