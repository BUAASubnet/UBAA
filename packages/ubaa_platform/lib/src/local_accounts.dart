import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'secure_material.dart';

/// 随机内部别名与已核实的账号；只保存在系统安全材料层。
final class LocalAccount {
  const LocalAccount({required this.id, required this.username});
  final String id;
  final String username;
  @override
  String toString() => 'LocalAccount([REDACTED])';
}

/// 首页启动所需的最小本机状态，不包含密码、Cookie 或业务正文。
final class LocalAccountState {
  const LocalAccountState({
    required this.account,
    required this.canRestore,
    required this.generation,
  });
  final LocalAccount? account;
  final bool canRestore;
  final int generation;
  @override
  String toString() =>
      'LocalAccountState(canRestore: $canRestore, generation: $generation)';
}

/// 由一个宿主拥有的本机账号索引；不得将业务快照保存在这里。
abstract interface class LocalAccountStore {
  Future<LocalAccountState?> read();
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  });
  Future<Uint8List> cacheKey(LocalAccount account);
  Future<void> signOut();
  Future<void> removeAccount(String accountId);
}

/// 安全索引与随机缓存密钥分开保存；失去密钥不生成替代密钥覆盖旧数据。
final class SecureLocalAccountStore implements LocalAccountStore {
  SecureLocalAccountStore(this.materials);
  final SecureMaterialStore materials;
  Future<void> _tail = Future<void>.value();
  static const _indexKey = 'account-index.v1';

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<LocalAccountState?> read() =>
      _serial(() async => (await _load())?.state);

  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => _serial(() async {
    final normalized = username.trim();
    if (normalized.isEmpty || normalized.length > 128)
      throw const SecureMaterialException();
    final index = await _load() ?? _AccountIndex();
    LocalAccount? account;
    for (final known in index.accounts) {
      if (known.username == normalized) {
        account = known;
        break;
      }
    }
    if (account == null) {
      if (index.accounts.length >= 16) throw const SecureMaterialException();
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      account = LocalAccount(id: id, username: normalized);
      final key = Uint8List.fromList(
        List.generate(32, (_) => random.nextInt(256)),
      );
      await materials.write('cache-key.$id', base64Encode(key));
      key.fillRange(0, key.length, 0);
      index.accounts.add(account);
    } else {
      // 检查旧材料确实存在；密钥丢失必须由用户明确清除旧账号后重建。
      final key = await _readKey(account);
      key.fillRange(0, key.length, 0);
    }
    index.activeId = account.id;
    index.canRestore = retainSession;
    index.generation++;
    await _save(index);
    return index.state;
  });

  @override
  Future<Uint8List> cacheKey(LocalAccount account) => _serial(() async {
    final index = await _load();
    if (index == null ||
        !index.accounts.any(
          (item) => item.id == account.id && item.username == account.username,
        )) {
      throw const SecureMaterialException();
    }
    return _readKey(account);
  });

  @override
  Future<void> signOut() => _serial(() async {
    final index = await _load() ?? _AccountIndex();
    index.canRestore = false;
    index.generation++;
    await _save(index);
  });

  /// 先持久关闭恢复，再删除密钥；失败时保留禁止恢复状态并返回错误。
  /// 调用方必须先完成 Core 缓存清除，再调用此方法。
  @override
  Future<void> removeAccount(String accountId) => _serial(() async {
    final index = await _load() ?? _AccountIndex();
    if (!_AccountIndex.validId(accountId))
      throw const SecureMaterialException();
    index.canRestore = false;
    index.generation++;
    await _save(index);
    await materials.delete('cache-key.$accountId');
    index.accounts.removeWhere((item) => item.id == accountId);
    if (index.activeId == accountId) index.activeId = null;
    await _save(index);
  });

  Future<Uint8List> _readKey(LocalAccount account) async {
    try {
      final encoded = await materials.read('cache-key.${account.id}');
      if (encoded == null) throw const SecureMaterialException();
      final key = base64Decode(encoded);
      if (key.length != 32) throw const SecureMaterialException();
      return key;
    } on Object {
      throw const SecureMaterialException();
    }
  }

  Future<_AccountIndex?> _load() async {
    try {
      final raw = await materials.read(_indexKey);
      if (raw == null) return null;
      return _AccountIndex.decode(jsonDecode(raw));
    } on Object {
      throw const SecureMaterialException();
    }
  }

  Future<void> _save(_AccountIndex index) => materials.write(
    _indexKey,
    jsonEncode({
      'version': 1,
      'generation': index.generation,
      'activeId': index.activeId,
      'canRestore': index.canRestore,
      'accounts': [
        for (final account in index.accounts)
          {'id': account.id, 'username': account.username},
      ],
    }),
  );
}

class _AccountIndex {
  final accounts = <LocalAccount>[];
  String? activeId;
  bool canRestore = false;
  int generation = 0;
  static bool validId(String value) =>
      RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
  LocalAccountState get state {
    LocalAccount? active;
    for (final account in accounts) {
      if (account.id == activeId) active = account;
    }
    return LocalAccountState(
      account: active,
      canRestore: canRestore && active != null,
      generation: generation,
    );
  }

  static _AccountIndex decode(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['generation'] is! int ||
        (value['generation'] as int) < 0 ||
        value['canRestore'] is! bool ||
        value['accounts'] is! List ||
        (value['accounts'] as List).length > 16 ||
        (value['activeId'] != null && value['activeId'] is! String)) {
      throw const SecureMaterialException();
    }
    final index = _AccountIndex()
      ..generation = value['generation'] as int
      ..canRestore = value['canRestore'] as bool
      ..activeId = value['activeId'] as String?;
    for (final item in value['accounts'] as List) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          !validId(item['id'] as String) ||
          item['username'] is! String ||
          (item['username'] as String).trim().isEmpty ||
          (item['username'] as String).length > 128 ||
          index.accounts.any(
            (old) => old.id == item['id'] || old.username == item['username'],
          )) {
        throw const SecureMaterialException();
      }
      index.accounts.add(
        LocalAccount(
          id: item['id'] as String,
          username: item['username'] as String,
        ),
      );
    }
    if ((index.activeId != null &&
            !index.accounts.any((a) => a.id == index.activeId)) ||
        (index.canRestore && index.activeId == null)) {
      throw const SecureMaterialException();
    }
    return index;
  }
}
