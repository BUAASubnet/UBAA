import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

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
                onChanged: enabled
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
                onChanged: enabled
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
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    super.key,
  });

  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final Future<void> Function() onRefresh;
  final Future<void> Function(FeatureId feature) onRetryFeature;
  final Future<void> Function() onLogout;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;

  @override
  State<UbaaMainShell> createState() => _UbaaMainShellState();
}

class _UbaaMainShellState extends State<UbaaMainShell> {
  int _selectedIndex = 0;
  FeatureId? _openedFeature;

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
    final body = _openedFeature == null
        ? _buildTab(context)
        : _FeaturePlaceholder(
            feature: _openedFeature!,
            snapshot: widget.snapshots[_openedFeature!]!,
            onBack: () => setState(() => _openedFeature = null),
            onRetry: () => widget.onRetryFeature(_openedFeature!),
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(_openedFeature?.title ?? _tabs[_selectedIndex].label),
        leading: _openedFeature == null
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
      onFeatureTap: (title) => _showComingSoon(context, title),
    ),
    _ => _ProfileView(
      user: widget.user,
      routePolicy: widget.routePolicy,
      telemetryEnabled: widget.telemetryEnabled,
      onRoutePolicyChanged: widget.onRoutePolicyChanged,
      onTelemetryChanged: widget.onTelemetryChanged,
      onLogout: widget.onLogout,
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
    setState(() {
      _selectedIndex = index;
      _openedFeature = null;
    });
  }

  void _showComingSoon(BuildContext context, String title) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title将在只读首发后接入。')));
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
  });

  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 360,
      mainAxisExtent: 160,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: FeatureId.values.length,
    itemBuilder: (context, index) {
      final feature = FeatureId.values[index];
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
                  else if (isFailure)
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
                        : colorScheme.onSurfaceVariant,
                  ),
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
    FeatureLoadStatus.failure => snapshot.error?.message ?? '加载失败，请重试',
  };
}

class _AdvancedFeaturesView extends StatelessWidget {
  const _AdvancedFeaturesView({required this.onFeatureTap});

  final ValueChanged<String> onFeatureTap;

  static const _items = <({String title, String description, IconData icon})>[
    (title: '研讨室预约', description: '查询、提交和管理研讨室预约', icon: Icons.date_range),
    (title: '阳光打卡', description: '查看记录并提交体育活动打卡', icon: Icons.wb_sunny),
    (
      title: '自动评教',
      description: '一键完成学期末评教任务',
      icon: Icons.assignment_turned_in,
    ),
    (title: '更多功能', description: '更多高级功能正在开发中…', icon: Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 360,
      mainAxisExtent: 160,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: _items.length,
    itemBuilder: (context, index) {
      final item = _items[index];
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => onFeatureTap(item.title),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  item.icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    },
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
  });

  final UserSummary? user;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final Future<void> Function() onLogout;

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
      const SizedBox(height: 32),
      Text(
        'UBAA 应用\nMake BUAA Great Again',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _FeaturePlaceholder extends StatelessWidget {
  const _FeaturePlaceholder({
    required this.feature,
    required this.snapshot,
    required this.onBack,
    required this.onRetry,
  });

  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
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
                Text(
                  feature.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.status == FeatureLoadStatus.failure
                      ? snapshot.error?.message ?? '加载失败'
                      : '只读详情页面将在 FRB DTO 接入后展示。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    OutlinedButton(onPressed: onBack, child: const Text('返回')),
                    if (snapshot.status == FeatureLoadStatus.failure)
                      FilledButton(
                        onPressed: () => onRetry(),
                        child: const Text('重试'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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
};
