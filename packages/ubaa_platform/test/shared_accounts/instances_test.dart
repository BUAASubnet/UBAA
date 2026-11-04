import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('两个独立账号对象同时保留同一账号得到同一别名', () async {
    final transport = _Transport();
    final material = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: transport,
    );
    await material.probe();
    final a = SecureLocalAccountStore(material);
    final b = SecureLocalAccountStore(material);
    final values = await Future.wait([
      a.retain('fixture-a', retainSession: true),
      b.retain('fixture-a', retainSession: true),
    ]);
    expect(values[0].account!.id, values[1].account!.id);
    expect((await a.read())!.generation, 2);
  });

  test('两个独立账号对象同时保留不同账号不丢条目', () async {
    final material = SecureMaterialStore(
      coordinator: _syntheticCoordinator(),
      transport: _Transport(),
    );
    await material.probe();
    final a = SecureLocalAccountStore(material);
    final b = SecureLocalAccountStore(material);
    final values = await Future.wait([
      a.retain('fixture-a', retainSession: true),
      b.retain('fixture-b', retainSession: true),
    ]);
    for (final value in values) {
      expect(await a.cacheKey(value.account!), hasLength(32));
    }
    expect((await a.read())!.generation, 2);
  });

  test('并发启动探测清理只删除各自的探测材料', () async {
    final transport = _ProbeSchedule();
    final coordinator = _syntheticCoordinator();
    final a = SecureMaterialStore(
      coordinator: coordinator,
      transport: transport,
    );
    final b = SecureMaterialStore(
      coordinator: coordinator,
      transport: transport,
    );
    await Future.wait([a.probe(), b.probe()]);
    expect(a.isAvailable, isTrue);
    expect(b.isAvailable, isTrue);
    expect(transport.values, isEmpty);
  });
}

class _Transport implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async {
    // 捕获后让出调度，复现两个对象读到同一旧索引。
    final value = values[key];
    await Future<void>.delayed(Duration.zero);
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _ProbeSchedule extends _Transport {
  int writes = 0;
  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (++writes == 2)
      await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

MaterialCoordinator _syntheticCoordinator() {
  final directory = Directory.systemTemp.createTempSync(
    'ubaa_synthetic_materials_',
  );
  // 普通异步用例已等待全部账号/材料操作，此时真实文件锁已释放。
  addTearDown(() => directory.delete(recursive: true));
  return MaterialCoordinator(directory: directory);
}
