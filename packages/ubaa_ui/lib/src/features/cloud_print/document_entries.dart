part of 'view.dart';

class _DocumentEntry {
  _DocumentEntry.single(PrintDocument file) : files = [file], name = file.name;
  _DocumentEntry.group(List<_ScanPage> pages)
    : files = [for (final page in pages) page.file],
      name = '${pages.first.stem}_${pages.first.device}.pdf';

  final List<PrintDocument> files;
  final String name;
  PrintDocument get first => files.first;
  String get id => first.id;
  bool get expired => first.expired;
  bool get merged => files.length > 1;

  int? get totalBytes {
    var total = 0;
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) return null;
      total += bytes;
    }
    return total;
  }
}

class _ScanPage {
  const _ScanPage(this.file, this.stem, this.sequence, this.device, this.time);

  final PrintDocument file;
  final String stem, device;
  final int sequence;
  final DateTime time;

  static final _name = RegExp(
    r'^(\p{L}+\d{10,14})_(\d{1,10})_(\d{1,12})\.pdf$',
    caseSensitive: false,
    unicode: true,
  );
  static final _date = RegExp(r'^\d{8}$');
  static final _time = RegExp(r'^\d{1,6}$');

  static _ScanPage? parse(PrintDocument file) {
    final match = _name.firstMatch(file.name);
    if (match == null ||
        !_date.hasMatch(file.date) ||
        !_time.hasMatch(file.time)) {
      return null;
    }
    final t = file.time.padLeft(6, '0');
    final date = file.date;
    final stamp = DateTime.tryParse('${date}T${t}Z');
    if (stamp == null ||
        stamp.month != int.parse(date.substring(4, 6)) ||
        stamp.day != int.parse(date.substring(6, 8)) ||
        stamp.hour != int.parse(t.substring(0, 2)) ||
        stamp.minute != int.parse(t.substring(2, 4)) ||
        stamp.second != int.parse(t.substring(4, 6))) {
      return null;
    }
    return _ScanPage(file, match[1]!, int.parse(match[2]!), match[3]!, stamp);
  }
}

List<_DocumentEntry> _scanEntries(List<PrintDocument> files) {
  final entries = <_DocumentEntry>[];
  final devices = <String, List<_ScanPage>>{};
  for (final file in files) {
    final page = _ScanPage.parse(file);
    if (page == null) {
      entries.add(_DocumentEntry.single(file));
    } else {
      (devices[page.device] ??= []).add(page);
    }
  }
  for (final pages in devices.values) {
    pages.sort((a, b) {
      final time = a.time.compareTo(b.time);
      if (time != 0) return time;
      final seq = a.sequence.compareTo(b.sequence);
      return seq != 0 ? seq : a.file.id.compareTo(b.file.id);
    });
    var group = <_ScanPage>[];
    void finish() {
      if (group.length == 1) {
        entries.add(_DocumentEntry.single(group.single.file));
      } else if (group.isNotEmpty) {
        entries.add(_DocumentEntry.group(group));
      }
      group = [];
    }

    for (final page in pages) {
      if (group.isNotEmpty) {
        final previous = group.last;
        if (page.sequence <= previous.sequence ||
            page.time.difference(previous.time) > const Duration(minutes: 1) ||
            page.file.expired != previous.file.expired) {
          finish();
        }
      }
      group.add(page);
    }
    finish();
  }
  return entries;
}
