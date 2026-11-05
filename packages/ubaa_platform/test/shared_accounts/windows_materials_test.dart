import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ubaa_platform/shared_accounts.dart';
import 'package:ubaa_platform/src/material/windows_dpapi.dart';

void main() {
  late Directory root;
  late File file;
  late _Codec codec;
  late WindowsFileMaterials backend;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ubaa_synthetic_windows_');
    file = File('${root.path}/flutter_secure_storage.dat');
    codec = _Codec();
    backend = WindowsFileMaterials(file: () async => file, codec: codec);
  });
  tearDown(() async => root.delete(recursive: true));

  test('原生 Windows DPAPI 首次创建后可替换和读取密文', () async {
    final native = WindowsFileMaterials(
      file: () async => file,
      codec: const WindowsDpapiCodec(),
      replace: replaceWindowsMaterial,
    );
    expect(await native.read('fixture'), isNull);
    await native.write('fixture', '合成材料');
    expect(await native.read('fixture'), '合成材料');
    await native.write('fixture', '更新后的合成材料');
    expect(await native.read('fixture'), '更新后的合成材料');
    await native.delete('fixture');
    expect(await native.read('fixture'), isNull);
  }, skip: !Platform.isWindows);

  test('Windows 查询失败必须保留原材料并阻断首次创建', () async {
    await file.writeAsString('synthetic-original');
    final pending = File('${file.path}.synthetic.pending');
    await pending.writeAsString('synthetic-new');
    await expectLater(
      replaceWindowsMaterial(
        pending,
        file,
        queryTarget: (_) => (attributes: 0xffffffff, errorCode: 5),
      ),
      throwsA(isA<SecureMaterialException>()),
    );
    expect(await file.readAsString(), 'synthetic-original');
    expect(await pending.readAsString(), 'synthetic-new');
  });

  test('Windows 只允许明确缺失首次创建，目标后来出现时不覆盖或重试', () async {
    for (final code in [2, 3]) {
      final pending = File('${file.path}.synthetic.pending');
      await pending.writeAsString('synthetic-new');
      var moves = 0;
      await replaceWindowsMaterial(
        pending,
        file,
        queryTarget: (_) => (attributes: 0xffffffff, errorCode: code),
        moveNew: (source, target, flags) {
          moves++;
          expect(flags, 8); // MOVEFILE_WRITE_THROUGH，不含 REPLACE_EXISTING。
          source.renameSync(target.path);
          return 1;
        },
      );
      expect(moves, 1);
      expect(await file.readAsString(), 'synthetic-new');
      await file.delete();
      await pending.writeAsString('synthetic-next');
      moves = 0;
      await expectLater(
        replaceWindowsMaterial(
          pending,
          file,
          queryTarget: (_) => (attributes: 0xffffffff, errorCode: code),
          moveNew: (_, target, flags) {
            moves++;
            expect(flags, 8);
            target.writeAsStringSync('synthetic-concurrent');
            return 0; // 合成 MoveFileExW 目标已存在。
          },
        ),
        throwsA(isA<SecureMaterialException>()),
      );
      expect(moves, 1);
      expect(await file.readAsString(), 'synthetic-concurrent');
      expect(await pending.readAsString(), 'synthetic-next');
      await pending.delete();
      await file.delete();
    }
  });

  test('Windows 拒绝目录和重解析点，未知查询错误不调用移动', () async {
    final pending = File('${file.path}.synthetic.pending');
    await pending.writeAsString('synthetic-new');
    for (final query in [
      (attributes: 0xffffffff, errorCode: 32),
      (attributes: 0xffffffff, errorCode: 0),
      (attributes: 0x10, errorCode: 0),
      (attributes: 0x400, errorCode: 0),
    ]) {
      await expectLater(
        replaceWindowsMaterial(
          pending,
          file,
          queryTarget: (_) => query,
          moveNew: (_, _, _) => fail('查询失败后不得移动'),
          replaceExisting: (_, _, _, _) => fail('查询失败后不得替换'),
        ),
        throwsA(isA<SecureMaterialException>()),
      );
      expect(await pending.readAsString(), 'synthetic-new');
    }
  });

  test('实际文件层替换中途失败保留旧alias、key备份和B，重开明确阻断', () async {
    final materials = SecureMaterialStore(
      transport: backend,
      coordinator: MaterialCoordinator(
        directory: Directory('${root.path}/lock'),
      ),
    );
    await materials.probe();
    final accounts = SecureLocalAccountStore(materials);
    final saved = await accounts.retain(
      'synthetic-school',
      retainSession: true,
    );
    final key = await accounts.cacheKey(saved.account!);
    final original = await file.readAsBytes();
    File? backup;
    var replacements = 0;
    final failing = WindowsFileMaterials(
      file: () async => file,
      codec: codec,
      replace: (pending, target) => replaceWindowsMaterial(
        pending,
        target,
        queryTarget: (_) => (attributes: 0x20, errorCode: 0),
        replaceExisting: (_, target, previous, flags) {
          replacements++;
          expect(flags, 0);
          target.renameSync(previous.path);
          backup = previous;
          return 0; // 合成 ReplaceFileW 已移动原件后失败。
        },
      ),
    );
    final failingStore = SecureMaterialStore(
      transport: failing,
      coordinator: MaterialCoordinator(
        directory: Directory('${root.path}/lock'),
      ),
    );
    await failingStore.probe();
    expect(failingStore.isAvailable, isFalse);
    expect(replacements, 1);
    expect(await backup!.readAsBytes(), original);
    final raw =
        jsonDecode(utf8.decode(codec.decrypt(await backup!.readAsBytes())))
            as Map;
    expect(
      raw['ubaa.material.v2.account-index.v1'],
      contains(saved.account!.id),
    );
    expect(
      raw['ubaa.material.v2.cache-key.${saved.account!.id}'],
      base64Encode(key),
    );
    expect(
      await File('${root.path}/lock/transaction.v1').readAsString(),
      'UBAA1:B',
    );
    await expectLater(accounts.read(), throwsA(isA<SecureMaterialException>()));
    await materials.probe();
    expect(materials.isAvailable, isFalse);
    expect(await backup!.readAsBytes(), original);
  });

  test('DPAPI、UTF-8、JSON、未知条目失败保留原密文，读写删除均不覆盖', () async {
    for (final bytes in <List<int>>[
      [0], // 合成解密失败。
      [1, 255], // 非法 UTF-8。
      [1, ...utf8.encode('{broken')],
      [1, ...utf8.encode('[]')],
      [1, ...utf8.encode('{"known":"value","unknown":1}')],
    ]) {
      await file.writeAsBytes(bytes, flush: true);
      for (final operation in <Future<Object?> Function()>[
        () => backend.read('fixture'),
        () => backend.write('fixture', 'synthetic'),
        () => backend.delete('fixture'),
      ]) {
        await expectLater(operation(), throwsA(isA<Exception>()));
        expect(await file.readAsBytes(), bytes);
      }
    }
  });

  test('读取权限失败和替换失败均保留原件，不改为空map或自动重试', () async {
    await backend.write('original', 'synthetic');
    final original = await file.readAsBytes();
    final unreadable = WindowsFileMaterials(
      file: () async => _UnreadableFile(file),
      codec: codec,
    );
    await expectLater(
      unreadable.write('new', 'value'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), original);
    var replacements = 0;
    final failing = WindowsFileMaterials(
      file: () async => file,
      codec: codec,
      replace: (_, _) async {
        replacements++;
        throw const FileSystemException('synthetic replacement failure');
      },
    );
    await expectLater(
      failing.write('new', 'value'),
      throwsA(isA<FileSystemException>()),
    );
    expect(replacements, 1);
    expect(await file.readAsBytes(), original);
    expect(await root.list().length, 1);
  });

  test('旧账号索引与密钥经过重开和新键写入仍保持，读取不改文件', () async {
    final original = codec.encrypt(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'ubaa.material.v2.account-index.v1': 'synthetic-existing-index',
            'ubaa.material.v2.cache-key.fixture': 'synthetic-existing-key',
          }),
        ),
      ),
    );
    await file.writeAsBytes(original);
    expect(
      await backend.read('ubaa.material.v2.cache-key.fixture'),
      'synthetic-existing-key',
    );
    expect(await file.readAsBytes(), original);
    await backend.write('synthetic-new', 'synthetic-value');
    final reopened = WindowsFileMaterials(file: () async => file, codec: codec);
    expect(
      await reopened.read('ubaa.material.v2.account-index.v1'),
      'synthetic-existing-index',
    );
    expect(
      await reopened.read('ubaa.material.v2.cache-key.fixture'),
      'synthetic-existing-key',
    );
    await reopened.delete('synthetic-new');
    expect(await backend.read('synthetic-new'), isNull);
  });

  test('加密失败或读取非普通文件不会覆盖原件或产生空库', () async {
    await backend.write('original', 'synthetic');
    final original = await file.readAsBytes();
    codec.failEncrypt = true;
    await expectLater(backend.write('new', 'value'), throwsA(isA<Exception>()));
    expect(await file.readAsBytes(), original);
    expect(await root.list().length, 1);
    await file.delete();
    await Directory(file.path).create();
    await expectLater(backend.write('new', 'value'), throwsA(isA<Exception>()));
    expect(await Directory(file.path).exists(), isTrue);
  });
}

/// 仅合成编码，用首字节模拟 DPAPI 格式与解密失败，不是生产 fallback。
class _Codec implements WindowsMaterialCodec {
  bool failEncrypt = false;
  @override
  Uint8List decrypt(Uint8List bytes) {
    if (bytes.isEmpty || bytes.first != 1)
      throw const FormatException('synthetic');
    return Uint8List.fromList(bytes.skip(1).toList());
  }

  @override
  Uint8List encrypt(Uint8List bytes) {
    if (failEncrypt) throw const FormatException('synthetic');
    return Uint8List.fromList([1, ...bytes]);
  }
}

class _UnreadableFile implements File {
  _UnreadableFile(this.source);
  final File source;
  @override
  String get path => source.path;
  @override
  Future<Uint8List> readAsBytes() async => throw FileSystemException(
    'synthetic denied',
    path,
    const OSError('synthetic', 13),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
