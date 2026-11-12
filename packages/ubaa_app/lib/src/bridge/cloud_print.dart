import 'dart:typed_data';

import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../controller/error_mapper.dart';
import 'context.dart';
import 'support/mapping.dart';

final class BridgeCloudPrintService implements CloudPrintService {
  const BridgeCloudPrintService(this.context);
  final BridgeContext context;

  @override
  bool get isCurrent => true;

  UiError _error(BridgeError error) {
    final mapped = UbaaErrorMapper.fromException(bridgeMapError(error));
    return UiError(
      code: mapped.code,
      kind: mapped.kind,
      title: mapped.title,
      message: error.message,
      resolvedRoute: mapped.resolvedRoute,
      retryable: mapped.retryable,
    );
  }

  Future<T> _run<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on BridgeError catch (error) {
      throw _error(error);
    }
  }

  @override
  Future<List<PrintDocument>> documents({required bool scans}) => _run(
    () async => [
      for (final row in await context.client.cloudPrintDocuments(scans: scans))
        PrintDocument(
          id: row.id,
          name: row.name,
          date: row.date,
          time: row.time,
          expired: row.expired,
          bytes: row.bytes?.toInt(),
          pages: row.pages,
          copies: row.copies?.toInt(),
        ),
    ],
  );

  @override
  Future<Uint8List> preview(String id, int page) =>
      _run(() => context.client.cloudPrintPreview(id: id, page: page));

  @override
  Future<Uint8List> scan(String id) =>
      _run(() => context.client.cloudPrintScan(id: id));

  @override
  Future<Uint8List> scanPdf(List<String> ids) =>
      _run(() => context.client.cloudPrintScanPdf(ids: ids));

  @override
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  ) => _run(
    () async => _results(
      await context.client.cloudPrintUpload(
        files: [
          for (final source in sources)
            BridgePrintFile(path: source.path, name: source.name),
        ],
        options: BridgePrintOptions(
          color: options.color,
          paper: BridgePrintPaper.values[options.paper.index],
          duplex: BridgePrintDuplex.values[options.duplex.index],
          copies: options.copies,
          fromPage: options.from,
          toPage: options.to,
        ),
      ),
    ),
  );

  @override
  Future<List<UiError?>> delete(List<String> ids, {required bool scans}) =>
      _run(
        () async => _results(
          await context.client.cloudPrintDelete(scans: scans, ids: ids),
        ),
      );

  List<UiError?> _results(List<BridgeError?> values) => [
    for (final value in values)
      if (value == null) null else _error(value),
  ];

  @override
  Future<List<PrintStation>> stations() => _run(
    () async => [
      for (final row in await context.client.cloudPrintStations())
        PrintStation(
          row.name,
          row.group,
          row.state,
          row.papers,
          row.capabilities,
        ),
    ],
  );

  @override
  Future<PrintRecords> records(
    DateTime begin,
    DateTime end,
    PrintRecordKind kind,
    int page,
  ) => _run(() async {
    final result = await context.client.cloudPrintRecords(
      begin: _date(begin),
      end: _date(end),
      kind: BridgePrintRecordKind.values[kind.index],
      page: page,
    );
    return (
      totalPages: result.totalPages,
      items: [
        for (final row in result.items)
          PrintRecord(
            row.date,
            row.time,
            row.pages.toInt(),
            row.paper,
            row.freeCents.toInt(),
            row.cardCents.toInt(),
            row.otherCents.toInt(),
          ),
      ],
    );
  });

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}
