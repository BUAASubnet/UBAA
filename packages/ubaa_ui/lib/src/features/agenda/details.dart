part of 'view.dart';

extension AgendaDetails on AgendaViewState {
  Future<AgendaEditScope?> chooseScope() => showDialog<AgendaEditScope>(
    context: context,
    builder: (context) => bound(
      SimpleDialog(
        title: const Text('处理重复事项'),
        children: [
          for (final entry in {
            AgendaEditScope.thisOccurrence: '仅此次',
            AgendaEditScope.thisAndFuture: '此次及以后',
            AgendaEditScope.all: '全部',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    ),
  );
  Future<void> complete(AgendaEntry entry, bool value) {
    final token = generation.value;
    return change(() async {
      final local = entry.local;
      final time = agendaTime(campusDate(DateTime.now()));
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
        UbaaFeedback.show(
          context,
          '事项读取失败，原数据已保留',
          kind: UbaaFeedbackKind.error,
        );
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
          agendaTime(campusDate(DateTime.now())),
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
        agendaTime(campusDate(DateTime.now())),
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
        agendaTime(campusDate(DateTime.now())),
      );
    });
  }

  Widget detailContent(AgendaEntry entry, VoidCallback close) {
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => bound(
        SafeArea(child: detailContent(entry, () => Navigator.pop(sheet))),
      ),
    );
  }
}
