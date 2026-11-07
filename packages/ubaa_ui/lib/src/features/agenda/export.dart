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
    final include = await showUiSheet<bool>(
      context,
      builder: (sheet) => bound(
        UiSheetBody(
          title: '导出日历',
          subtitle:
              '${agendaDate(selected.start)} 至 ${agendaDate(selected.end)}',
          children: [
            UiInfoRow(
              icon: Icons.info_outline,
              text: widget.term.trim().isEmpty
                  ? '还没有学期信息，只导出所选日期内你添加的日程。'
                  : '导出所选日期内的日程。',
            ),
          ],
          primaryAction: FilledButton(
            onPressed: () => Navigator.pop(sheet, false),
            child: const Text('仅未完成事项'),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(sheet, true),
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
          '$message · ${value.exportedCount}项${value.skippedUnknownTimeCount == 0 ? '' : '，${value.skippedUnknownTimeCount} 项时间未定，未导出'}',
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
