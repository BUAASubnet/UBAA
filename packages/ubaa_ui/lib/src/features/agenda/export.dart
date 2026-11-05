part of 'view.dart';

extension AgendaFileExport on AgendaViewState {
  Future<void> export() async {
    final token = generation.value;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: from,
        end: to.subtract(const Duration(days: 1)),
      ),
      helpText: '选择日历导出日期范围',
      builder: (_, child) => bound(child!),
    );
    if (!current(token) || selected == null) return;
    final include = await showDialog<bool>(
      context: context,
      builder: (dialog) => bound(
        SimpleDialog(
          title: const Text('导出范围快照'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.term.trim().isEmpty
                    ? '尚无学校学期信息，本次仅导出已选日期内的本机事项。'
                    : '导出已选日期内的每次发生。学校内容使用本机缓存，缺失的数据不会联网补齐。',
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('仅未完成事项'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('包含已完成事项'),
            ),
          ],
        ),
      ),
    );
    if (!current(token) || include == null) return;
    update(() => busy = true);
    try {
      final value = await service.exportIcs(
        query(
          start: selected.start,
          end: selected.end.add(const Duration(days: 1)),
        ),
        includeCompleted: include,
      );
      if (!current(token)) return;
      final saver = widget.onSaveFile;
      if (saver == null) {
        UbaaFeedback.show(
          context,
          '当前平台暂不能保存日历文件',
          kind: UbaaFeedbackKind.error,
        );
        return;
      }
      final message = await saver(
        value,
        'UBAA-${agendaDate(selected.start)}-${agendaDate(selected.end)}.ics',
        () => current(token),
      );
      if (current(token) && message != null)
        UbaaFeedback.show(
          context,
          '$message · ${value.exportedCount}项${value.skippedUnknownTimeCount == 0 ? '' : '，跳过${value.skippedUnknownTimeCount}项未知时段'}',
        );
    } on Object {
      if (current(token))
        UbaaFeedback.show(
          context,
          '日历文件未保存，请检查位置与权限后重试',
          kind: UbaaFeedbackKind.error,
        );
    } finally {
      if (mounted) update(() => busy = false);
    }
  }
}
