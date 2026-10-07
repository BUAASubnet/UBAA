import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../common/detail_fields.dart' show DetailField;
import '../shared/schedule_values.dart' show uiSavedScheduleTime;
import '../shared/text.dart' show uiNonBlank;

/// 资料在个人页本地展开，离开或更新身份即销毁联系人显示状态。
class ProfileIdentityCard extends StatefulWidget {
  const ProfileIdentityCard({required this.user});
  final UserSummary? user;
  @override
  State<ProfileIdentityCard> createState() => _ProfileIdentityCardState();
}

class _ProfileIdentityCardState extends State<ProfileIdentityCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ProfileIdentityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.user, widget.user)) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = uiNonBlank(user?.preferredName) ?? '未登录';
    final source = switch (user?.profileRoute) {
      ConnectionMode.direct => 'Direct',
      ConnectionMode.webvpn => 'WebVPN',
      null => '来源未定',
    };
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
          if (user?.profileEvidence case final evidence?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                evidence.origin == DataOrigin.persisted
                    ? '资料上次保存 ${uiSavedScheduleTime(evidence.fetchedAt)} · $source，连接后核对更新'
                    : '资料更新于 ${uiSavedScheduleTime(evidence.fetchedAt)} · $source',
              ),
            ),
          if (user?.profileNotice case final notice?)
            Padding(padding: const EdgeInsets.all(16), child: Text(notice)),
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
      if (uiNonBlank(user.schoolId) case final schoolId?)
        DetailField(label: '学校标识', value: schoolId),
      if (uiNonBlank(user.idCardTypeName) case final kind?)
        DetailField(label: '证件类型', value: kind),
      if (uiNonBlank(user.email) case final email?)
        _ProfileContact(
          key: const ValueKey('profile-email'),
          label: '邮箱',
          value: email,
        ),
      if (uiNonBlank(user.phone) case final phone?)
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
      ].every((value) => uiNonBlank(value) == null))
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
