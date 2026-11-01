import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:ubaa_platform/shared_accounts.dart';

/// 私有合成材料仍使用真实协调器，清理前等待所有已开始的事务释放锁。
SyntheticMaterials syntheticMaterials(
  SecureMaterialTransport transport, {
  WidgetTester? tester,
}) {
  final directory = Directory.systemTemp.createTempSync(
    'ubaa_synthetic_materials_',
  );
  final materials = SyntheticMaterials._(directory, transport);
  addTearDown(() async {
    if (tester != null) {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(materials.close);
    } else {
      await materials.close();
    }
  });
  return materials;
}

class SyntheticMaterials extends SecureMaterialStore {
  SyntheticMaterials._(this._directory, SecureMaterialTransport transport)
    : super(
        coordinator: MaterialCoordinator(directory: _directory),
        transport: transport,
      );

  final Directory _directory;
  final _pending = <Future<void>>{};
  bool _closed = false;

  @override
  Future<T> coordinate<T>(Future<T> Function() action) {
    if (_closed) throw StateError('合成材料已经清理');
    final operation = super.coordinate(action);
    late final Future<void> tracked;
    tracked = operation.then<void>(
      (_) => _pending.remove(tracked),
      onError: (Object error, StackTrace stack) {
        _pending.remove(tracked);
      },
    );
    _pending.add(tracked);
    return operation;
  }

  Future<void> close() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
    _closed = true;
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}
