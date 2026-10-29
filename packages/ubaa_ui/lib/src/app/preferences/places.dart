part of '../shell.dart';

extension _ShellPlaces on _UbaaMainShellState {
  void _updatePlaces(UbaaMainShell oldWidget, bool accountChanged) {
    if (accountChanged ||
        oldWidget.placePreferences != widget.placePreferences) {
      _places
        ..clear()
        ..addAll(widget.placePreferences);
    }
  }

  void _savePlace(String key, String value) {
    if (!UiPlaceKeys.all.contains(key)) return;
    _places[key] = value;
    final save = widget.onSavePlacePreference;
    if (save != null) unawaited(save(key, value).catchError((Object _) {}));
  }
}
