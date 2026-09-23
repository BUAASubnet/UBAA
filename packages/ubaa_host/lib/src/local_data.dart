part of 'ubaa_app_host.dart';

extension _UbaaAppHostLocalData on _UbaaAppHostState {
  Future<void> _logoutLocalOwner(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    await _controller.logout();
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

  Future<void> _logoutAndClearLocalData(LocalDataOwnerScope owner) async {
    owner.checkCurrent();
    await _controller.logout(
      clearSavedCredential: true,
      clearLocalData: () async {
        (Object, StackTrace)? failure;
        for (final identity in owner.identities) {
          for (final clear in [
            _gradeScoreStore.clearAccount,
            _reminderStore.clear,
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
  }
}
