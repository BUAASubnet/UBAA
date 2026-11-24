part of 'bridge_backend.dart';

mixin BridgeBackendRead {
  BridgeAppService? get _appService;
  BridgeContext get _context;
  BridgeClient get client;
  Future<void>? get _closing;
  set _closing(Future<void>? value);

  Future<SigninQr> fetchSigninQr(String courseId, Duration offset) =>
      bridgeFetchSigninQr(_context, courseId, offset);

  String exportRawDiagnostics() => _context.client.exportRawDiagnostics();

  Future<CgyyLockDisplaySession> openLockDisplay() async {
    try {
      return BridgeLockDisplaySession(
        client,
        await client.openCgyyLockDisplay(),
      );
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  Future<int> beginHomeRecoveryBatch() async {
    try {
      return client.contractVersion() < 55
          ? 0
          : await client.beginReadRecoveryBatch();
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  Future<void> endHomeRecoveryBatch(int batch) async {
    if (batch == 0) return;
    try {
      await client.endReadRecoveryBatch(batch: batch);
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  Future<void> invalidateHomeRecoveryBatch() async {
    try {
      if (client.contractVersion() >= 55) {
        await client.invalidateReadRecoveryBatch();
      }
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  Future<HomeTodoProjection> projectHomeTodos(HomeTodoRequest request) =>
      bridgeWithOfflineRead(
        _context,
        () => _homeAgenda.projectHomeTodos(request),
      );
  late final BridgeAgendaBackend _homeAgenda = BridgeAgendaBackend(_context);
  late final AgendaService agenda = AgendaService(_homeAgenda);
  late final FinanceService finance = BridgeFinanceService(
    _context,
    () => BridgeRequiredSessionBackend(
      _context.client,
    ).recoverTargetSession(RecoveryTarget.finance),
  );

  late final IhomeService ihome = BridgeIhomeService(_context.client);
  late final SpocFilesService? spocFiles = client.contractVersion() < 82
      ? null
      : BridgeSpocFilesService(client);

  ReadHealthCloud? get healthCloud => client.contractVersion() < 74
      ? null
      : (year) => bridgeHealthCloudPage(_context.client, year);
  late final BhpanService bhpan = BridgeBhpanService(_context);

  late final CloudPrintService cloudPrint = BridgeCloudPrintService(_context);
  late final CampusAccountService campusAccount = BridgeCampusAccountService(
    _context,
  );
  Future<FeatureResult> readAfterWriteOnRoute(
    WriteOperation operation, {
    required ConnectionMode route,
    FeatureQuery? query,
  }) => bridgePinnedWriteReadback(_context, operation, route, query);

  List<LibraryLoan> _mapLibraryLoans(BridgeLibraryLoans data) => [
    for (final loan in data.entries)
      LibraryLoan(
        id: loan.id,
        title: loan.title,
        author: loan.author,
        loanDate: loan.loanDate,
        dueDate: loan.dueDate,
        renewTimes: loan.renewTimes,
        canRenewTimes: loan.canRenewTimes,
        status: LibraryLoanStatus.values.byName(loan.status.name),
        location: loan.location,
      ),
  ];

  Future<List<LibraryLoan>> readLibraryLoans() async {
    try {
      final result = await client.currentLibraryLoans();
      return _mapLibraryLoans(result.data);
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }

  Future<LibraryLoanRouteRead> readLibraryLoansOnRoute({
    required ConnectionMode route,
  }) async {
    try {
      final result = await client.currentLibraryLoansOnRoute(
        route: bridgeToBridgeConnectionMode(route),
      );
      return LibraryLoanRouteRead(
        loans: _mapLibraryLoans(result.data),
        resolvedRoute: bridgeToConnectionMode(result.pinnedRoute),
      );
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }

  Future<CacheUsageSummary> cacheUsage({required String accountId}) =>
      bridgeCacheUsage(_context, accountId);
  Future<CacheClearOutcome> clearBusinessCache({required String accountId}) =>
      bridgeClearBusinessCache(_context, accountId);

  Future<CacheClearOutcome> clearOrRebuildBusinessCache({
    required LocalAccount account,
    required List<int> key,
  }) => bridgeClearOrRebuildBusinessCache(_context, account, key);

  Future<void> openOfflineAccount(LocalAccount account, List<int> key) =>
      bridgeOpenOfflineAccount(_context, account, key);
  Future<OfflineHomeRead> readCachedHome(RoutePolicy policy) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeReadCachedHome(_context, policy),
      );
  Future<OfflineQueryRead> readCachedQuery(
    FeatureId feature,
    FeatureQuery query,
    RoutePolicy policy,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeReadCachedQuery(_context, feature, query, policy),
  );
  Future<void> deactivateOfflineAccount() {
    _context.cache.generation++;
    return bridgeOfflineSerial(_context, () async {
      if (_context.sharedAccount == null)
        await _context.cache.handle?.deactivate();
      _context.cache.targetAccountId = null;
    });
  }

  Future<void> clearOfflineAccount({required String accountId}) {
    _context.cache.generation++;
    _context.cache.targetAccountId = null;
    return bridgeOfflineSerial(_context, () async {
      final handle = _context.cache.handle;
      if (handle == null || _context.cache.account?.id != accountId) {
        throw const BackendException(
          UbaaErrorCode.internalError,
          cacheFailure: CacheMaintenanceFailure.unavailable,
        );
      }
      await handle.clear();
      _context.cache.handle = null;
      _context.cache.account = null;
    });
  }

  Future<FeatureResult> readLibbookAfterWrite(FeatureQuery query) =>
      bridgeLoadLibbookFeature(
        _context,
        FeatureId.libbook,
        query,
        bridgeDateOnly(query.date ?? DateTime.now()),
        useCache: false,
      );

  Future<FeatureResult> readCgyyAfterWrite(FeatureQuery query) =>
      bridgeLoadCgyyFeature(
        _context,
        FeatureId.cgyy,
        query,
        bridgeDateOnly(query.date ?? DateTime.now()),
        useCache: false,
      );

  Future<FeatureResult> readBykcAfterWrite(FeatureQuery query) =>
      bridgeLoadBykcFeature(_context, FeatureId.bykc, query, useCache: false);

  Future<FeatureResult> readSigninAfterWrite() =>
      bridgeLoadSigninHome(_context, const FeatureQuery(), useCache: false);

  Future<ScheduleImportTask> beginScheduleImport(String term) =>
      bridgeWithOfflineRead(
        _context,
        () => bridgeBeginScheduleImport(_context, term),
      );

  Future<FeatureReadTask?> beginAccountFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
    LocalAccount account,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeBeginProgressiveRead(
      _context,
      feature,
      query,
      expectedAccount: account,
    ),
  );

  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeBeginProgressiveRead(_context, feature, query),
  );

  Future<FeatureResult> loadFeature(FeatureId feature) => bridgeWithOfflineRead(
    _context,
    () => bridgeLoadFeatureQuery(
      _context,
      feature,
      const FeatureQuery(),
      loadYgdkRecords: false,
    ),
  );

  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) => bridgeWithOfflineRead(
    _context,
    () => bridgeLoadFeatureQuery(_context, feature, query),
  );

  Future<FeatureResult> loadCgyyOrdersOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => bridgeLoadCgyyOrdersOnRoute(
    _context,
    route: route,
    page: page,
    size: size,
  );

  Future<FeatureResult> loadCgyyOrderDetailOnRoute({
    required ConnectionMode route,
    required int orderId,
  }) => bridgeLoadCgyyOrderDetailOnRoute(
    _context,
    route: route,
    orderId: orderId,
  );

  Future<FeatureResult> loadYgdkOverviewOnRoute({
    required ConnectionMode route,
  }) => bridgeLoadYgdkOverviewOnRoute(_context, route: route);

  Future<FeatureResult> loadYgdkRecordsOnRoute({
    required ConnectionMode route,
    required int page,
    required int size,
  }) => bridgeLoadYgdkRecordsOnRoute(
    _context,
    route: route,
    page: page,
    size: size,
  );

  Future<FeatureResult> loadEvaluationOnRoute({
    required ConnectionMode route,
  }) => bridgeLoadEvaluationOnRoute(_context, route: route);

  Future<void> dispose() {
    if (_closing != null) return _closing!;
    _context.closed = true;
    _appService?.dispose();
    _context.cache.generation++;
    _context.cache.targetAccountId = null;
    final agendaClosed = agenda.dispose();
    final clientClosed = bridgeDispose(_context);
    final cacheClosed = bridgeOfflineSerial(_context, () async {
      await _context.cache.handle?.close();
      _context.cache.handle?.dispose();
      _context.cache.handle = null;
      _context.cache.account = null;
      _context.nativeAccount?.dispose();
      _context.nativeAccount = null;
    });
    return _closing = Future.wait([
      agendaClosed,
      clientClosed,
      cacheClosed,
    ]).then((_) {});
  }
}
