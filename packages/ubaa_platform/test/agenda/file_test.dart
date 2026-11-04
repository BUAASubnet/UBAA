import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/agenda-file');
  for (final os in ['android', 'ios', 'ohos']) {
    test('$os选择期间撤销不发送日历内容，已开始的写入单独报告', () async {
      final selected = Completer<String?>();
      final written = Completer<void>();
      final calls = <MethodCall>[];
      var current = true;
      var waiting = selected;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'select':
                return waiting.future;
              case 'write':
                await written.future;
                return null;
              case 'discard':
                return null;
            }
            throw PlatformException(code: 'unexpected');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final saver = SystemAgendaFileSaver(operatingSystem: os);
      final stale = saver.save('旧账号日历', '日程.ics', () => current);
      await Future<void>.delayed(Duration.zero);
      expect(calls.single.method, 'select');
      expect((calls.single.arguments as Map).containsKey('bytes'), isFalse);
      current = false;
      selected.complete('selection-1');
      expect(await stale, AgendaFileResult.superseded);
      expect(calls.map((call) => call.method), ['select', 'discard']);
      current = true;
      calls.clear();
      waiting = Completer<String?>()..complete('selection-2');
      final inProgress = saver.save('当前账号日历', '日程.ics', () => current);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['select', 'write']);
      expect((calls.last.arguments as Map)['bytes'], utf8.encode('当前账号日历'));
      current = false;
      written.complete();
      expect(await inProgress, AgendaFileResult.savedBeforeScopeChange);
    });
  }
  test('保存真正写出UTF8日历，取消和写失败不报告成功', () async {
    final dir = await Directory.systemTemp.createTemp(
      'synthetic_agenda_export_',
    );
    const ics = 'BEGIN:VCALENDAR\r\nSUMMARY:合成日程\r\nEND:VCALENDAR\r\n';
    try {
      final target = File('${dir.path}/日程.ics');
      final saver = SystemAgendaFileSaver(
        selectLocation: (_) async => target.path,
      );
      expect(
        await saver.save(ics, '日程.ics', () => true),
        AgendaFileResult.saved,
      );
      expect(await target.readAsBytes(), utf8.encode(ics));
      final cancelled = SystemAgendaFileSaver(
        selectLocation: (_) async => null,
      );
      expect(
        await cancelled.save(ics, '取消.ics', () => true),
        AgendaFileResult.cancelled,
      );
      final failed = SystemAgendaFileSaver(
        selectLocation: (_) async => dir.path,
      );
      await expectLater(
        failed.save(ics, '失败.ics', () => true),
        throwsA(isA<AgendaFileException>()),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('等待系统位置时账号撤销，交付前拒绝旧文件；权限错误向上传递', () async {
    final gate = Completer<String?>();
    var current = true, writes = 0;
    final saver = SystemAgendaFileSaver(
      selectLocation: (_) => gate.future,
      writeFile: (_, _) async {
        writes++;
      },
    );
    final saving = saver.save('synthetic', '日程.ics', () => current);
    current = false;
    gate.complete('/synthetic');
    expect(await saving, AgendaFileResult.superseded);
    expect(writes, 0);
    final denied = SystemAgendaFileSaver(
      selectLocation: (_) async => throw const FileSystemException('合成权限拒绝'),
    );
    await expectLater(
      denied.save('synthetic', '日程.ics', () => true),
      throwsA(isA<AgendaFileException>()),
    );
  });
}
