part of '../widgets.dart';

/// 资料在个人页本地展开，离开或更新身份即销毁联系人显示状态。
class _ProfileIdentityCard extends StatefulWidget {
  const _ProfileIdentityCard({required this.user});
  final UserSummary? user;
  @override
  State<_ProfileIdentityCard> createState() => _ProfileIdentityCardState();
}

class _ProfileIdentityCardState extends State<_ProfileIdentityCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ProfileIdentityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.user, widget.user)) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = _nonBlank(user?.preferredName) ?? '未登录';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 28,
              child: Text(name.characters.first),
            ),
            title: Text(name),
            subtitle: Text(user?.username ?? ''),
          ),
          if (user != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.badge_outlined,
                ),
                label: Text(_expanded ? '收起账号资料' : '查看账号资料'),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _AccountProfileDetails(user: user),
              ),
          ],
        ],
      ),
    );
  }
}

class _AccountProfileDetails extends StatelessWidget {
  const _AccountProfileDetails({required this.user});
  final UserSummary user;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_nonBlank(user.schoolId) case final schoolId?)
        _DetailField(label: '学校标识', value: schoolId),
      if (_nonBlank(user.idCardTypeName) case final kind?)
        _DetailField(label: '证件类型', value: kind),
      if (_nonBlank(user.email) case final email?)
        _ProfileContact(
          key: const ValueKey('profile-email'),
          label: '邮箱',
          value: email,
        ),
      if (_nonBlank(user.phone) case final phone?)
        _ProfileContact(
          key: const ValueKey('profile-phone'),
          label: '手机',
          value: phone,
        ),
      if ([
        user.schoolId,
        user.idCardTypeName,
        user.email,
        user.phone,
      ].every((value) => _nonBlank(value) == null))
        const Text('当前未提供其他资料。'),
    ],
  );
}

class _ProfileContact extends StatefulWidget {
  const _ProfileContact({super.key, required this.label, required this.value});
  final String label;
  final String value;
  @override
  State<_ProfileContact> createState() => _ProfileContactState();
}

class _ProfileContactState extends State<_ProfileContact> {
  bool _visible = false;
  @override
  void didUpdateWidget(covariant _ProfileContact oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _visible = false;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              // 隐藏时不构建原文，语义树也不包含完整联系信息。
              Text(_visible ? widget.value : '••••••'),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _visible = !_visible),
          child: Text('${_visible ? '隐藏' : '显示'}${widget.label}'),
        ),
      ],
    ),
  );
}
