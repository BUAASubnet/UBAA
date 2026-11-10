part of 'ubaa_app_host.dart';

extension _UbaaAppHostLocalData on _UbaaAppHostState {
  void _migratePreferences(LocalDataOwnerScope owner) {
    if (_preferenceOwner != owner.accountKey) {
      _preferenceOwner = owner.accountKey;
      _preferenceAliases.clear();
    }
    for (final alias in owner.identities) {
      if (alias == owner.accountKey || !_preferenceAliases.add(alias)) continue;
      _preferenceMigration = _preferenceMigration.then((_) async {
        try {
          var changed = false;
          for (final store in <Object>[
            _placeStore,
            _recentFeatureStore,
            _bykcFilterStore,
            _reminderStore,
            _cgyyDefaultsStore,
          ]) {
            owner.checkCurrent();
            if (store is AccountPreferenceMigration) {
              changed =
                  await store.migrateAccount(alias, owner.accountKey) ||
                  changed;
            }
          }
          owner.checkCurrent();
          if (mounted && changed) {
            _preferencesChanged();
            await _restorePlaces(owner);
          }
        } on Object {
          if (_preferenceOwner == owner.accountKey)
            _preferenceAliases.remove(alias);
        }
      });
    }
  }

  Future<List<FeatureId>> _readRecentFeatures(LocalDataOwnerScope owner) async {
    await _preferenceMigration;
    owner.checkCurrent();
    final value = await _recentFeatureStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveRecentFeatures(
    LocalDataOwnerScope owner,
    List<FeatureId> value,
  ) async {
    await _preferenceMigration;
    owner.checkCurrent();
    await _recentFeatureStore.write(owner.accountKey, value);
    owner.checkCurrent();
  }

  Future<void> _logoutLocalOwner(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    await Future.wait([_controller.logout(), _revokeScheduleWidgets()]);
  }

  Future<YgdkReminderSettings> _readReminder(LocalDataOwnerScope owner) async {
    await _preferenceMigration;
    owner.checkCurrent();
    final value = await _reminderStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveReminder(
    LocalDataOwnerScope owner,
    YgdkReminderSettings value,
  ) async {
    await _preferenceMigration;
    owner.checkCurrent();
    // 存储同步入队；退出后的clear在同一串行store等待在途保存收尾。
    await _reminderStore.write(owner.accountKey, value);
    owner.checkCurrent();
  }

  Future<BykcCourseFilters?> _readBykcFilters(LocalDataOwnerScope owner) async {
    await _preferenceMigration;
    owner.checkCurrent();
    final value = await _bykcFilterStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveBykcFilters(
    LocalDataOwnerScope owner,
    BykcCourseFilters value,
  ) async {
    await _preferenceMigration;
    try {
      owner.checkCurrent();
    } on BackendException {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
    if (value.isDefault) {
      await _bykcFilterStore.clearAccount(owner.accountKey);
    } else {
      await _bykcFilterStore.write(owner.accountKey, value);
    }
    try {
      owner.checkCurrent();
    } on BackendException {
      throw UbaaErrorMapper.fromCode(UbaaErrorCode.operationConflict);
    }
  }

  Future<CgyyReservationDefaults?> _readCgyyDefaults(
    LocalDataOwnerScope owner,
  ) async {
    await _preferenceMigration;
    owner.checkCurrent();
    final value = await _cgyyDefaultsStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveCgyyDefaults(
    LocalDataOwnerScope owner,
    CgyyReservationDefaults value,
  ) async {
    await _preferenceMigration;
    owner.checkCurrent();
    await _cgyyDefaultsStore.write(owner.accountKey, value);
  }

  Future<void> _logoutAndClearLocalData(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    await Future.wait([
      _clearAccountLocalData(owner),
      _revokeScheduleWidgets(),
    ]);
  }

  Future<void> _clearAccountLocalData(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    try {
      await _controller.logout(
        clearSavedCredential: true,
        clearLocalData: () async {
          (Object, StackTrace)? failure;
          for (final identity in owner.identities) {
            for (final clear in [
              _gradeScoreStore.clearAccount,
              _reminderStore.clear,
              _bykcFilterStore.clearAccount,
              _cgyyDefaultsStore.clearAccount,
              _recentFeatureStore.clearAccount,
              _placeStore.clearAccount,
            ]) {
              try {
                await clear(identity);
              } on Object catch (error, stack) {
                failure ??= (error, stack);
              }
            }
          }
          if (failure != null) {
            Error.throwWithStackTrace(failure.$1, failure.$2);
          }
        },
      );
    } on Object {
      throw const UiError(
        code: UbaaErrorCode.internalError,
        kind: UbaaErrorKind.internal,
        title: '本机数据清除未完成',
        message: '部分本机数据未清除，请重试',
      );
    }
  }
}
