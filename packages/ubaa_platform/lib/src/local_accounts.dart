import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'material/secure_material_core.dart';

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

/// 同一材料域共用的本机账号索引；不得将业务快照保存在这里。
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

/// 持久代次快照只能由安全索引捕获；不接受文件或命令参数构造身份。
final class LocalAccountSnapshot {
  LocalAccountSnapshot._(this._owner, this.state);
  final SecureMaterialStore _owner;
  final LocalAccountState state;
  @override
  String toString() => 'LocalAccountSnapshot(generation: ${state.generation})';
}

final class LocalAccountConflict extends SecureMaterialException {
  const LocalAccountConflict();
  @override
  String toString() => '本机账号状态已变化';
}

/// 安全索引与随机缓存密钥分开保存；失去密钥不生成替代密钥覆盖旧数据。
final class SecureLocalAccountStore implements LocalAccountStore {
  SecureLocalAccountStore(this.materials);
  final SecureMaterialStore materials;
  static const _indexKey = 'account-index.v1';

  Future<T> _serial<T>(Future<T> Function() action) =>
      materials.coordinate(action);

  /// 仅捕获本机状态，不签发已核实的 Core 身份或学校写资格。
  Future<LocalAccountSnapshot?> capture() => _serial(() async {
    final index = await _load();
    return index == null
        ? null
        : LocalAccountSnapshot._(materials, index.state);
  });

  bool _matches(
    _AccountIndex? index,
    LocalAccountSnapshot snapshot,
    bool requireRestore,
  ) =>
      identical(snapshot._owner, materials) &&
      index != null &&
      index.generation == snapshot.state.generation &&
      index.state.account?.id == snapshot.state.account?.id &&
      index.canRestore == snapshot.state.canRestore &&
      (!requireRestore || index.state.canRestore);

  Future<bool> validate(
    LocalAccountSnapshot snapshot, {
    bool requireRestore = true,
  }) => _serial(() async => _matches(await _load(), snapshot, requireRestore));

  /// 只延续已允许恢复的同一账号；失效快照不能开启许可或切换账号。
  Future<LocalAccountSnapshot> refreshIfCurrent(
    LocalAccountSnapshot snapshot,
  ) => _serial(() async {
    final index = await _load();
    if (!_matches(index, snapshot, true)) throw const LocalAccountConflict();
    index!.advance();
    await _save(index);
    return LocalAccountSnapshot._(materials, index.state);
  });

  Future<LocalAccountState> revokeIfCurrent(LocalAccountSnapshot snapshot) =>
      _serial(() async {
        final index = await _load();
        if (!_matches(index, snapshot, false))
          throw const LocalAccountConflict();
        index!.canRestore = false;
        index.advance();
        await _save(index);
        return index.state;
      });

  @override
  Future<LocalAccountState?> read() =>
      _serial(() async => (await _load())?.state);

  /// 仅供显式登录验证身份后的宿主调用。恢复流程使用代次条件接口。
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
      index.accounts.add(account);
      index.pendingCacheKeys.add(id);
    }
    index.activeId = account.id;
    index.canRestore = retainSession;
    index.advance();
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
    if (!index.pendingCacheKeys.contains(account.id)) return _readKey(account);
    // 只有索引明确登记为从未打开缓存的新别名可以首次建密钥。
    // 先前写密钥后索引保存失败时，复用该密钥，避免覆盖已写材料。
    final encoded = await materials.read('cache-key.${account.id}');
    final key = encoded == null
        ? Uint8List.fromList(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          )
        : await _readKey(account);
    try {
      if (encoded == null) {
        await materials.write('cache-key.${account.id}', base64Encode(key));
      }
      index.pendingCacheKeys.remove(account.id);
      await _save(index);
      return key;
    } on Object {
      key.fillRange(0, key.length, 0);
      rethrow;
    }
  });

  @override
  Future<void> signOut() => _serial(() async {
    final index = await _load() ?? _AccountIndex();
    index.canRestore = false;
    index.advance();
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
    index.advance();
    await _save(index);
    await materials.delete('cache-key.$accountId');
    index.accounts.removeWhere((item) => item.id == accountId);
    index.pendingCacheKeys.remove(accountId);
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
      'version': 2,
      'generation': index.generation,
      'activeId': index.activeId,
      'canRestore': index.canRestore,
      'accounts': [
        for (final account in index.accounts)
          {
            'id': account.id,
            'username': account.username,
            'cacheKeyPending': index.pendingCacheKeys.contains(account.id),
          },
      ],
    }),
  );
}

class _AccountIndex {
  final accounts = <LocalAccount>[];
  final pendingCacheKeys = <String>{};
  String? activeId;
  bool canRestore = false;
  int generation = 0;
  void advance() {
    if (generation == 0x7fffffffffffffff) throw const SecureMaterialException();
    generation++;
  }

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
        (value['version'] != 1 && value['version'] != 2) ||
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
          (value['version'] == 2 && item['cacheKeyPending'] is! bool) ||
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
      if (value['version'] == 2 && item['cacheKeyPending'] == true) {
        index.pendingCacheKeys.add(item['id'] as String);
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
