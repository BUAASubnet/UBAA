part of 'bridge_backend.dart';

mixin BridgeBackendAppService {
  BridgeAppService? get _appService;
  BridgeContext get _context;
  BridgeClient get client;
  AgendaService get agenda;

  Future<AppServiceView> _appServiceView(
    Future<BridgeAppServiceState> Function(BridgeAppService) read,
  ) async {
    final service = _appService;
    return service == null || _context.closed
        ? AppServiceView.unavailable(bundledPrivacyPolicy.version)
        : bridgeAppServiceView(await read(service));
  }

  Future<AppServiceView> appServiceState() =>
      _appServiceView((service) => service.state());
  Future<AppServiceView> agreeAppService() =>
      _appServiceView((service) => service.agree());
  Future<AppServiceView> enterBasicAppService() =>
      _appServiceView((service) => service.enterBasic());
  Future<AppServiceView> setAppServiceTelemetry(bool enabled) =>
      _appServiceView((service) => service.setTelemetry(enabled: enabled));

  Future<void> refreshAppBootstrap({required bool force}) async {
    if (!_context.closed) await _appService?.refreshBootstrap(force: force);
  }

  Future<AppServiceView> markAppAnnouncementRead(String id) =>
      _appServiceView((service) => service.markAnnouncementRead(id: id));

  Future<AppServiceView> dismissAppUpdateAvailable(String latestVersion) =>
      _appServiceView(
        (service) =>
            service.dismissUpdateAvailable(latestVersion: latestVersion),
      );

  Future<AppServiceEraseOutcome> eraseAppService() async {
    final service = _appService;
    if (service == null || _context.closed)
      return AppServiceEraseOutcome.unavailable;
    return bridgeAppServiceErase(await service.erase());
  }

  void allowHostPrivacy() => _appService?.allowHostPrivacy();

  Future<void> uploadAppService({required bool force}) async {
    if (!_context.closed) await _appService?.upload(force: force);
  }

  Future<void> recordAppService(TelemetryRecord record) async {
    if (_appService case final service? when !_context.closed) {
      await bridgeRecordAppService(service, record);
    }
  }

  void confirmAppServiceAccount() {
    final scope = _context.nativeAccount;
    final binding = _context.sharedAccount;
    if (_context.closed || scope == null || binding == null) return;
    try {
      _appService?.bindAccount(
        scope: scope,
        expectedUsername: binding.account.username,
      );
    } on Object {
      // 统计账号绑定失败不改变登录、恢复和本机缓存的业务结果。
    }
  }

  void clearAppServiceAccount() {
    if (_context.closed) return;
    try {
      _appService?.clearAccount();
    } on Object {
      // Core 在入队时仍按共享代次校验账号。
    }
  }

  Future<void> bindSharedAccount(SharedAccountBinding binding) async {
    void check() {
      if (_context.closed)
        throw const BackendException(
          UbaaErrorCode.operationConflict,
          clientDisposed: true,
        );
    }

    check();
    if (binding.isRevocation)
      throw const BackendException(UbaaErrorCode.invalidInput);
    await binding.validate();
    check();
    final reopened = agenda.accountId != null;
    await agenda.close();
    check();
    _context.cache.generation++;
    await _context.cache.tail;
    check();
    final native = await BridgeSharedAccount.capture(
      directory: binding.directory,
      generation: BigInt.from(binding.generation),
      retainSession: binding.snapshot.state.canRestore,
    );
    var adopted = false;
    try {
      check();
      await client.bindSharedAccount(scope: native);
      check();
      await binding.validate();
      check();
      final oldCache = _context.cache.handle;
      BridgeOfflineCache? nextCache;
      if (oldCache != null &&
          _context.cache.account?.id == binding.account.id) {
        nextCache = await oldCache.withSharedAccount(scope: native);
        if (_context.closed) {
          nextCache.dispose();
          check();
        }
      } else if (oldCache != null) {
        await oldCache.close();
        check();
        _context.cache.account = null;
        _context.cache.targetAccountId = null;
      }
      final oldNative = _context.nativeAccount;
      _context.sharedAccount = binding;
      _context.nativeAccount = native;
      _context.cache.handle = nextCache;
      adopted = true;
      oldCache?.dispose();
      oldNative?.dispose();
      if (reopened) await agenda.openAccount(binding.account.id);
    } finally {
      if (!adopted) native.dispose();
    }
  }

  Future<void> logoutSharedAccount(
    SharedAccountBinding revoked, {
    required bool clearCache,
  }) async {
    clearAppServiceAccount();
    await agenda.close();
    return bridgeSharedLogout(_context, revoked, clearCache: clearCache);
  }
}
