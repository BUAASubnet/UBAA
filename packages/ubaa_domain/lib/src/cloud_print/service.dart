import 'dart:typed_data';

import '../common/error.dart';

enum PrintPaper { original, a4, a3 }

enum PrintDuplex { single, longEdge, shortEdge }

enum PrintRecordKind { print, copy, scan }

class PrintOptions {
  const PrintOptions({
    required this.color,
    required this.paper,
    required this.duplex,
    required this.copies,
    this.from,
    this.to,
  });

  final bool color;
  final PrintPaper paper;
  final PrintDuplex duplex;
  final int copies;
  final int? from, to;
}

class PrintSource {
  const PrintSource({required this.path, required this.name, this.release});
  final String path, name;
  final Future<void> Function()? release;
}

class PrintDocument {
  const PrintDocument({
    required this.id,
    required this.name,
    required this.date,
    required this.time,
    required this.expired,
    this.bytes,
    this.pages,
    this.copies,
  });
  final String id, name, date, time;
  final bool expired;
  final int? bytes, pages, copies;
}

class PrintStation {
  const PrintStation(
    this.name,
    this.group,
    this.state,
    this.papers,
    this.capabilities,
  );
  final String name, state;
  final String? group;
  final List<String> papers, capabilities;
}

class PrintRecord {
  const PrintRecord(
    this.date,
    this.time,
    this.pages,
    this.paper,
    this.freeCents,
    this.cardCents,
    this.otherCents,
  );
  final String date, time;
  final int pages, freeCents, cardCents, otherCents;
  final String? paper;
}

typedef PrintRecords = ({List<PrintRecord> items, int totalPages});

abstract interface class CloudPrintService {
  bool get isCurrent;
  Future<List<PrintDocument>> documents({required bool scans});
  Future<Uint8List> preview(String id, int page);
  Future<Uint8List> scan(String id);
  Future<Uint8List> scanPdf(List<String> ids);
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  );
  Future<List<UiError?>> delete(List<String> ids, {required bool scans});
  Future<List<PrintStation>> stations();
  Future<PrintRecords> records(
    DateTime begin,
    DateTime end,
    PrintRecordKind kind,
    int page,
  );
}

abstract interface class CloudPrintProvider {
  CloudPrintService get cloudPrint;
}

/// A folder grant is scoped to one batch and released when it finishes.
abstract interface class PrintDownloadFolder {
  Future<String> save(String name, Uint8List bytes, bool Function() current);
  Future<void> close();
}

typedef PrintPdfPreview =
    Future<void> Function(Uint8List bytes, bool Function() current);

typedef PrintPdfPage = ({int totalPages, Uint8List image});
typedef PrintPdfRenderer =
    Future<PrintPdfPage> Function(
      Uint8List bytes,
      int page,
      bool Function() current,
    );
