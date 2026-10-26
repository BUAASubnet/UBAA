part of 'reservation_flow.dart';

extension CgyyReservationSelection on CgyyReservationFlowState {
  Widget _selectionBar(
    BuildContext context,
    Map<String, CgyyReserveAction> actions,
  ) {
    final selected = _selected.map((key) => actions[key]).nonNulls.toList()
      ..sort((a, b) => a.timeOrdinal.compareTo(b.timeOrdinal));
    if (selected.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final colors = Theme.of(context).colorScheme;
    final summary = ConstrainedBox(
      key: const ValueKey('cgyy-selection-summary'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .22,
      ),
      child: SingleChildScrollView(
        child: Text(
          _selectionLabel(selected).replaceAll('\n', ' · '),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: () => _change(_selected.clear),
          child: const Text('清空选择'),
        ),
        FilledButton(
          onPressed: _busy || widget.onSubmit == null
              ? null
              : () => _continueSelection(context, selected),
          child: const Text('下一步'),
        ),
      ],
    );
    return Padding(
      padding: UbaaTheme.pageInsets(context, top: 8, bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return constraints.maxWidth >= 540 * scale
                  ? Row(
                      children: [
                        Expanded(child: summary),
                        const SizedBox(width: 16),
                        buttons,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        summary,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: buttons),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _continueSelection(
    BuildContext context,
    List<CgyyReserveAction> selected,
  ) async {
    final original = widget.snapshot;
    final input = await uiCollectCgyyReservation(
      context,
      selected.first,
      selected,
      formContext: widget.formContext,
      initialSelection: selected,
      selectionLabel: _selectionLabel(selected),
    );
    if (mounted && input != null && identical(original, widget.snapshot)) {
      await widget.onSubmit!(input);
    }
  }
}
