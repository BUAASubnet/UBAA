/// 本地排障阶段。记录的是程序操作，不接收用户输入或业务目标。
enum DiagnosticOperation {
  crash,
  initialization,
  login,
  routeChange,
  logout,
  read,
  writePrepare,
  writeCommit,
  writeDiscard,
  readback,
  telemetry,
  disposal,
  cloudPrintDocuments('cloud_print'),
  cloudPrintPreview('cloud_print'),
  cloudPrintScan('cloud_print'),
  cloudPrintScanPdf('cloud_print'),
  cloudPrintUpload('cloud_print'),
  cloudPrintDelete('cloud_print'),
  cloudPrintStations('cloud_print'),
  cloudPrintRecords('cloud_print'),
  bhpanLogin('bhpan'),
  bhpanList('bhpan'),
  bhpanSize('bhpan'),
  bhpanSuggestName('bhpan'),
  bhpanShares('bhpan'),
  bhpanShareLink('bhpan'),
  bhpanDownloadPreparation('bhpan'),
  bhpanDownload('bhpan'),
  bhpanDelivery('bhpan'),
  ihomeList('ihome'),
  ihomeDetail('ihome'),
  ihomeConfig('ihome'),
  ihomeNotices('ihome'),
  ihomeNotice('ihome'),
  ihomeReaction('ihome'),
  portalIdentity('portal'),
  portalMetrics('portal'),
  networkUsage('network'),
  financeRefresh('finance');

  const DiagnosticOperation([this.serviceFeature]);
  final String? serviceFeature;

  static Iterable<String> get serviceFeatures =>
      values.map((operation) => operation.serviceFeature).whereType<String>();
}
