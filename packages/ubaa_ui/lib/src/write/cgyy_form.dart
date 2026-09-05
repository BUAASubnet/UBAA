part of '../widgets.dart';

extension _CgyyWriteForm on _FeatureDetailListState {
  Future<void> _showCgyyReservationForm(
    BuildContext context,
    CgyyReserveAction target,
    List<CgyyReserveAction> availableActions,
  ) async {
    final phone = TextEditingController();
    final theme = TextEditingController();
    final purpose = TextEditingController();
    final joinerNum = TextEditingController(text: '1');
    final content = TextEditingController();
    final joiners = TextEditingController();
    final selectedKeys = <String>{_cgyyActionKey(target)};
    final actionsByKey = <String, CgyyReserveAction>{
      for (final action in <CgyyReserveAction>[target, ...availableActions])
        _cgyyActionKey(action): action,
    };
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
                      '站点 ${target.venueSiteId} · ${target.reservationDate.trim()}',
                    ),
                    const SizedBox(height: 8),
                    Text('空间 ${target.spaceId} · 时段 ${target.timeId}'),
                    if (actionsByKey.length > 1) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '选择预约时段（已选 ${selectedKeys.length} 个）',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: actionsByKey.entries
                            .map((entry) {
                              final action = entry.value;
                              return FilterChip(
                                label: Text(
                                  '空间 ${action.spaceId} · 时段 ${action.timeId}',
                                ),
                                selected: selectedKeys.contains(entry.key),
                                onSelected: (selected) => setState(() {
                                  if (!selected) {
                                    selectedKeys.remove(entry.key);
                                    return;
                                  }
                                  _selectCgyyAction(
                                    selectedKeys,
                                    actionsByKey,
                                    entry.key,
                                  );
                                }),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ],
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
                      decoration: const InputDecoration(labelText: '参与人说明'),
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
                  if (selectedKeys.isEmpty ||
                      phone.text.trim().isEmpty ||
                      theme.text.trim().isEmpty ||
                      content.text.trim().isEmpty ||
                      joiners.text.trim().isEmpty ||
                      parsedPurpose == null ||
                      parsedPurpose <= 0 ||
                      parsedJoinerNum == null ||
                      parsedJoinerNum <= 0) {
                    setState(() => error = '请选择时段并完整填写预约信息。');
                    return;
                  }
                  final actions =
                      selectedKeys
                          .map((key) => actionsByKey[key]!)
                          .toList(growable: false)
                        ..sort(
                          (left, right) =>
                              left.timeOrdinal.compareTo(right.timeOrdinal),
                        );
                  Navigator.of(dialogContext).pop(
                    CgyySubmitInput(
                      actions: actions,
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

  void _selectCgyyAction(
    Set<String> selectedKeys,
    Map<String, CgyyReserveAction> actionsByKey,
    String nextKey,
  ) {
    final next = actionsByKey[nextKey]!;
    final current = selectedKeys
        .map((key) => actionsByKey[key]!)
        .toList(growable: false);
    if (current.length == 1 &&
        _sameCgyyTarget(current.single, next) &&
        (current.single.timeOrdinal - next.timeOrdinal).abs() == 1) {
      selectedKeys.add(nextKey);
      return;
    }
    selectedKeys
      ..clear()
      ..add(nextKey);
  }

  bool _sameCgyyTarget(CgyyReserveAction left, CgyyReserveAction right) =>
      left.venueSiteId == right.venueSiteId &&
      left.reservationDate.trim() == right.reservationDate.trim() &&
      left.spaceId == right.spaceId &&
      left.venueSpaceGroupId == right.venueSpaceGroupId;

  String _cgyyActionKey(CgyyReserveAction action) =>
      '${action.venueSiteId}:${action.reservationDate.trim()}:${action.spaceId}:'
      '${action.venueSpaceGroupId ?? ''}:${action.timeId}:${action.timeOrdinal}';
}
