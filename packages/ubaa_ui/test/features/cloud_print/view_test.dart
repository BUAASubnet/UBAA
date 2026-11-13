import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/cloud_print/view.dart';

void main() {
  testWidgets('窄屏不用横向滚动就能打开帮助', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CloudPrintView(service: _Service())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('帮助').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('上传与打印'), findsOneWidget);
  });

  testWidgets('同一设备短时间内序号递增的扫描件显示成一组', (tester) async {
    final folder = _Folder();
    final service = _Service(
      scanned: [
        for (final (id, time, sequence, device) in [
          ('4', '120100', 2, '2000'),
          ('3', '120100', 1, '1000'),
          ('2', '120059', 5, '1000'),
          ('1', '120000', 2, '1000'),
        ])
          PrintDocument(
            id: id,
            name: 'DOC1112${time}_${sequence}_$device.pdf',
            date: '20261112',
            time: time,
            expired: false,
            bytes: 1024 << int.parse(id),
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            pickFolder: (_) async => folder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描文档'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-12 12:00'), findsOneWidget);
    expect(find.text('2026-11-12 12:01'), findsNWidgets(2));
    expect(find.text('6.0 KiB'), findsOneWidget);
    await tester.longPress(find.text('2026-11-12 12:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(service.merges.single, ['1', '2']);
    expect(service.downloads, isEmpty);
    expect(folder.files.single.$1, 'DOC1112120000_1000.pdf');
    expect(folder.files.single.$2, [1, 2]);
  });

  testWidgets('中文扫描件在同一秒内按序号升序合并', (tester) async {
    final folder = _Folder();
    final service = _Service(
      scanned: [
        for (final (id, time, sequence) in [
          ('4', '102531', 9), // 超过一分钟，仍是独立文件。
          ('3', '102430', 7),
          ('2', '102430', 4),
          ('1', '102430', 2),
        ])
          PrintDocument(
            id: id,
            name: '扫描件0907${time}_${sequence}_4000.pdf',
            date: '20260907',
            time: time,
            expired: false,
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            pickFolder: (_) async => folder,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描文档'));
    await tester.pumpAndSettle();

    final group = find.text('2026-09-07 10:24');
    expect(group, findsOneWidget);
    expect(find.text('2026-09-07 10:25'), findsOneWidget);
    await tester.longPress(group);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    expect(service.merges.single, ['1', '2', '3']);
    expect(folder.files.single.$2, [1, 2, 3]);
  });

  testWidgets('扫描件多选后只选择一次目录，单项失败不阻断后续保存', (tester) async {
    final service = _Service();
    final folder = _Folder();
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            pickFolder: (_) async {
              selections++;
              return folder;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描文档'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(selections, 1);
    expect(service.downloads, ['3', '2', '1']);
    expect(folder.files.map((file) => file.$1), ['scan.pdf', 'scan.pdf']);
    expect(folder.files.map((file) => file.$2), [
      [3],
      [1],
    ]);
    expect(folder.closed, isTrue);
    expect(find.text('成功 2 / 3'), findsOneWidget);
  });

  testWidgets('待打印列表不可用时仍可多选、取消或提交上传', (tester) async {
    final service = _Service(queueUnavailable: true);
    var released = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            pickFiles: () async => [
              for (final name in ['a.pdf', 'b.jpg'])
                PrintSource(
                  path: name,
                  name: name,
                  release: () async {
                    released++;
                  },
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.batches, isEmpty);
    expect(released, 2);

    await tester.tap(find.byTooltip('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认上传'));
    await tester.pumpAndSettle();
    expect(service.batches, [
      ['a.pdf', 'b.jpg'],
    ]);
    expect(released, 4);
    expect(find.text('成功 1 / 2'), findsOneWidget);
  });

  testWidgets('纯图片上传直接使用单页设置', (tester) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            pickFiles: () async => const [
              PrintSource(path: 'sample.png', name: 'sample.PNG'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上传文件'));
    await tester.pumpAndSettle();
    expect(find.text('指定打印页码'), findsNothing);
    await tester.tap(find.text('确认上传'));
    await tester.pumpAndSettle();
    expect(service.batches.single, ['sample.PNG']);
  });

  testWidgets('队列在独立页面预览，返回后恢复列表', (tester) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('图书馆云打印')),
          body: CloudPrintView(service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('queue.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('图书馆云打印'), findsNothing);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(service.previews, [('print-job', 1), ('print-job', 2)]);
    expect(find.text('第 2 / 2 页'), findsOneWidget);
    await tester.tap(find.byTooltip('返回文档列表'));
    await tester.pumpAndSettle();
    expect(find.text('图书馆云打印'), findsOneWidget);
    expect(find.text('queue.pdf'), findsOneWidget);
  });

  testWidgets('扫描预览按连续页码翻页，打开原件后才扩展总页数', (tester) async {
    final service = _ScanPreviewService();
    final discovered = Completer<PrintPdfPage>();
    final renders = <(int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudPrintView(
            service: service,
            renderPdf: (bytes, page, _) async {
              final id = bytes.last;
              renders.add((id, page));
              if (id == 2 && page == 1) return discovered.future;
              return (totalPages: id == 2 ? 2 : 1, image: _fixturePng());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描文档'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-11-12 12:00'));
    await tester.pumpAndSettle();
    final next = find.byTooltip('下一页');
    expect(next, findsOneWidget);
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(service.downloads, ['1']);

    await tester.tap(next);
    await tester.pump();
    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: next, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );
    discovered.complete((totalPages: 2, image: _fixturePng()));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 4 页'), findsOneWidget);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 4 页'), findsOneWidget);
    expect(service.downloads, ['1', '2']);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('第 4 / 4 页'), findsOneWidget);
    expect(service.downloads, ['1', '2', '3']);
    expect(renders, [(1, 1), (2, 1), (2, 2), (3, 1)]);

    await tester.tap(find.byTooltip('上一页'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 4 页'), findsOneWidget);
    expect(renders.last, (2, 2));
  });

  testWidgets('桌面可用 Ctrl 点击多选，右键可打开文件的预览操作', (tester) async {
    final service = _Service();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(body: CloudPrintView(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    final file = find.text('queue.pdf');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(file, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(service.previews, isEmpty);

    await tester.tap(find.byTooltip('取消选择'));
    await tester.pumpAndSettle();
    await tester.tap(
      file,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(service.previews, [('print-job', 1)]);
  });
}

class _Service implements CloudPrintService {
  _Service({this.queueUnavailable = false, this.scanned});

  final bool queueUnavailable;
  final List<PrintDocument>? scanned;

  @override
  bool get isCurrent => true;

  final downloads = <String>[];
  final previews = <(String, int)>[];
  final batches = <List<String>>[];
  final merges = <List<String>>[];
  static const refused = UiError(
    code: UbaaErrorCode.businessUnavailable,
    title: '失败',
    message: '此文件不可用',
  );

  @override
  Future<List<PrintDocument>> documents({required bool scans}) async => scans
      ? scanned ??
            [
              for (final id in ['1', '2', '3', '4'])
                PrintDocument(
                  id: id,
                  name: 'scan.pdf',
                  date: '20261112',
                  time: '12000$id',
                  expired: id == '4',
                ),
            ]
      : queueUnavailable
      ? throw refused
      : const [
          PrintDocument(
            id: 'print-job',
            name: 'queue.pdf',
            date: '20261112',
            time: '120000',
            expired: false,
            pages: 2,
          ),
        ];

  @override
  Future<Uint8List> scan(String id) async {
    downloads.add(id);
    if (id == '2') throw refused;
    return Uint8List.fromList([int.parse(id)]);
  }

  @override
  Future<Uint8List> scanPdf(List<String> ids) async {
    merges.add(ids);
    return Uint8List.fromList(ids.map(int.parse).toList());
  }

  @override
  Future<Uint8List> preview(String id, int page) async {
    previews.add((id, page));
    return _fixturePng();
  }

  @override
  Future<List<UiError?>> upload(
    List<PrintSource> sources,
    PrintOptions options,
  ) async {
    batches.add([for (final source in sources) source.name]);
    return [null, refused];
  }

  @override
  Future<List<UiError?>> delete(List<String> ids, {required bool scans}) =>
      throw UnimplementedError();
  @override
  Future<List<PrintStation>> stations() => throw UnimplementedError();
  @override
  Future<PrintRecords> records(
    DateTime begin,
    DateTime end,
    PrintRecordKind kind,
    int page,
  ) => throw UnimplementedError();
}

Uint8List _fixturePng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/81sAAAAASUVORK5CYII=',
);

class _ScanPreviewService extends _Service {
  _ScanPreviewService()
    : super(
        scanned: [
          for (var page = 1; page <= 3; page++)
            PrintDocument(
              id: '$page',
              name: '扫描件1112120000_${page}_4000.pdf',
              date: '20261112',
              time: '120000',
              expired: false,
            ),
        ],
      );

  @override
  Future<Uint8List> scan(String id) async {
    downloads.add(id);
    return Uint8List.fromList([...ascii.encode('%PDF-'), int.parse(id)]);
  }
}

class _Folder implements PrintDownloadFolder {
  final files = <(String, List<int>)>[];
  bool closed = false;

  @override
  Future<String> save(
    String name,
    Uint8List bytes,
    bool Function() current,
  ) async {
    expect(current(), isTrue);
    files.add((name, bytes.toList()));
    return name;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
