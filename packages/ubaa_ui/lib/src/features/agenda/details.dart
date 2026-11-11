part of 'view.dart';

extension AgendaDetails on AgendaViewState {
  Future<AgendaEditScope?> chooseScope() => showUiSheet<AgendaEditScope>(
    context,
    builder: (sheet) => bound(
      UiSheetBody(
        title: '处理重复事项',
        children: [
          for (final (scope, label, icon) in [
            (AgendaEditScope.thisOccurrence, '仅此次', Icons.event_outlined),
            (AgendaEditScope.thisAndFuture, '此次及以后', Icons.redo),
            (AgendaEditScope.all, '全部', Icons.event_repeat_outlined),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(sheet, scope),
            ),
        ],
      ),
    ),
  );
  Future<void> complete(AgendaEntry entry, bool value) {
    final token = generation.value;
    return change(() async {
      final local = entry.local;
      final time = agendaTime(campusDate(clock.now()));
      if (local != null) {
        await service.complete(local.itemId, recurrenceAt(local), value, time);
      } else {
        final old = await service.overlay(entry.school!.key);
        if (!current(token)) return;
        await service.setOverlay(
          AgendaOverlayDraft(
            key: entry.school!.key,
            completedAt: value ? time : null,
            completionOverride: true,
            hidden: old?.value.hidden ?? entry.hidden,
            note: old?.value.note ?? entry.note,
          ),
          time,
        );
      }
    });
  }

  Future<AgendaItem?> detailItem(String id, int token) async {
    try {
      final item = await service.get(id);
      return current(token) ? item : null;
    } on Object {
      if (current(token))
        UbaaFeedback.show(context, '事项读取失败，请重试', kind: UbaaFeedbackKind.error);
      return null;
    }
  }

  Future<void> editEntry(AgendaEntry entry) async {
    final token = generation.value;
    final item = await detailItem(entry.local!.itemId, token);
    if (!current(token) || item == null) return;
    final scope = item.rrule == null
        ? AgendaEditScope.all
        : await chooseScope();
    if (scope != null && current(token))
      await edit(item: item, occurrence: entry.local, scope: scope);
  }

  Future<void> deleteEntry(AgendaEntry entry) async {
    final token = generation.value;
    final item = await detailItem(entry.local!.itemId, token);
    if (!current(token) || item == null) return;
    final scope = item.rrule != null
        ? await chooseScope()
        : await showDialog<AgendaEditScope>(
            context: context,
            builder: (dialog) => bound(
              AlertDialog(
                title: const Text('删除事项？'),
                content: Text(item.content.title),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: uiDangerButtonStyle(dialog),
                    onPressed: () => Navigator.pop(dialog, AgendaEditScope.all),
                    child: const Text('删除'),
                  ),
                ],
              ),
            ),
          );
    if (scope != null && current(token))
      await change(
        () => service.delete(
          item.id,
          scope,
          recurrenceAt(entry.local!),
          agendaTime(campusDate(clock.now())),
        ),
      );
  }

  Future<void> saveNote(AgendaEntry entry, String note) async {
    final token = generation.value;
    await change(() async {
      final old = await service.overlay(entry.school!.key);
      if (!current(token)) return;
      await service.setOverlay(
        AgendaOverlayDraft(
          key: entry.school!.key,
          completedAt: old?.value.completedAt,
          completionOverride: old?.value.completionOverride ?? false,
          hidden: entry.hidden,
          note: note,
        ),
        agendaTime(campusDate(clock.now())),
      );
    });
  }

  Future<void> toggleHidden(AgendaEntry entry) async {
    final token = generation.value;
    await change(() async {
      final old = await service.overlay(entry.school!.key);
      if (!current(token)) return;
      await service.setOverlay(
        AgendaOverlayDraft(
          key: entry.school!.key,
          completedAt: old?.value.completedAt,
          completionOverride: old?.value.completionOverride ?? false,
          hidden: !entry.hidden,
          note: old?.value.note ?? entry.note,
        ),
        agendaTime(campusDate(clock.now())),
      );
    });
  }

  Widget detailContent(
    AgendaEntry entry,
    VoidCallback close, {
    bool modal = false,
  }) {
    final token = generation.value;
    void action(VoidCallback run) {
      if (!current(token)) return;
      close();
      run();
    }

    return AgendaDetailContent(
      key: ValueKey('${agendaEntryKey(entry)}:${entry.note}'),
      entry: entry,
      displayEnd: agendaDisplayEnd(entry, result?.entries ?? []),
      conflicts: agendaEntryConflicts(entry, result?.entries ?? []),
      busy: busy,
      modal: modal,
      onClose: close,
      onEdit: () => action(() => unawaited(editEntry(entry))),
      onDelete: () => action(() => unawaited(deleteEntry(entry))),
      onComplete: () =>
          action(() => unawaited(complete(entry, !entry.completed))),
      onSaveNote: (note) => action(() => unawaited(saveNote(entry, note))),
      onHide: () => action(() => unawaited(toggleHidden(entry))),
      onOpenSchool: () => action(
        () => widget.onOpenSchool(agendaNavigation(entry.school!.navigation)),
      ),
    );
  }

  Future<void> details(AgendaEntry entry) async {
    await showUiSheet<void>(
      context,
      builder: (sheet) =>
          bound(detailContent(entry, () => Navigator.pop(sheet), modal: true)),
    );
  }
}
