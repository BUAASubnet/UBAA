part of 'ubaa_app_host.dart';

extension _UbaaAppHostLocalData on _UbaaAppHostState {
  Future<List<FeatureId>> _readRecentFeatures(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    final value = await _recentFeatureStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveRecentFeatures(
    LocalDataOwnerScope owner,
    List<FeatureId> value,
  ) async {
    owner.checkCurrent();
    await _recentFeatureStore.write(owner.accountKey, value);
    owner.checkCurrent();
  }

  Future<void> _logoutLocalOwner(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    await Future.wait([_controller.logout(), _revokeScheduleWidgets()]);
  }

  Future<YgdkReminderSettings> _readReminder(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    final value = await _reminderStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveReminder(
    LocalDataOwnerScope owner,
    YgdkReminderSettings value,
  ) async {
    owner.checkCurrent();
    // 存储同步入队；退出后的clear在同一串行store等待在途保存收尾。
    await _reminderStore.write(owner.accountKey, value);
    owner.checkCurrent();
  }

  Future<BykcCourseFilters?> _readBykcFilters(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    final value = await _bykcFilterStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveBykcFilters(
    LocalDataOwnerScope owner,
    BykcCourseFilters value,
  ) async {
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
    owner.checkCurrent();
    final value = await _cgyyDefaultsStore.read(owner.accountKey);
    owner.checkCurrent();
    return value;
  }

  Future<void> _saveCgyyDefaults(
    LocalDataOwnerScope owner,
    CgyyReservationDefaults value,
  ) async {
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
        message: '本机数据未能完全清除，请稍后重试。',
      );
    }
  }
}
