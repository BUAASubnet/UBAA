import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'user_directory.dart';

/// 只报告协调状态，不包含材料、路径或平台异常正文。
final class MaterialCoordinationException implements Exception {
  const MaterialCoordinationException(this.uncertain);
  final bool uncertain;
  @override
  String toString() => uncertain ? '安全材料事务未完成，已阻止后续访问' : '安全材料协调暂不可用';
}

/// 声明顺序也是同一事务中允许升级的顺序。
enum MaterialMutation { probe, save, remove }

/// 固定材料域的短事务锁。锁文件永久保留，不能在释放时删除或替换。
/// Unix 使用 fd 级 flock，覆盖同进程不同 isolate；Windows 使用句柄级锁。
final class MaterialCoordinator {
  MaterialCoordinator({
    required Directory directory,
    this.waitLimit = const Duration(seconds: 5),
  }) : _resolve = (() async => directory);
  MaterialCoordinator.resolving(
    this._resolve, {
    this.waitLimit = const Duration(seconds: 5),
  });
  final Future<Directory> Function() _resolve;
  final Duration waitLimit;
  final Object _zoneKey = Object();
  final Object _operationKey = Object();

  /// 桌面固定在 OS 当前用户目录，忽略环境、配置与可执行名称。
  static Directory desktopDirectory() {
    try {
      return systemMaterialDirectory();
    } on Object {
      throw const MaterialCoordinationException(false);
    }
  }

  /// 恢复操作独占锁与材料事务锁分离。只按 recovery → materials 顺序取锁。
  /// 网络期间保留此 fd，退出或崩溃由 OS 释放，不留下持久的在途许可。
  Future<T> recovery<T>(
    Future<T> Function() action, {
    required bool Function() isCurrent,
  }) async {
    if (Zone.current[_zoneKey] != null)
      throw const MaterialCoordinationException(false);
    final directory = await _resolve();
    await directory.create(recursive: true);
    final root = Directory(await directory.resolveSymbolicLinks());
    if (!Platform.isWindows) _UnixLock.chmod(root.path, 448);
    final file = File('${root.path}/recovery.lock');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const MaterialCoordinationException(false);
    }
    final release = await _acquire(
      file,
      isCurrent: isCurrent,
      limit: const Duration(minutes: 2),
    );
    try {
      if (!isCurrent()) throw const MaterialCoordinationException(false);
      return await action();
    } finally {
      await release();
    }
  }

  /// 在已持有材料独占事务时发布只用于撤销的公开版本，不保存身份或凭据。
  Future<void> publishAccountGeneration(int generation) async {
    final lease = Zone.current[_zoneKey];
    if (lease is! _Lease || !lease.active || generation < 1)
      throw const MaterialCoordinationException(true);
    await beforeMutation(MaterialMutation.save);
    await lease.persistFile(
      File('${lease.state.parent.path}/account-generation.v1'),
      'UBAA1:$generation',
    );
  }

  /// 调用方须先在同一事务中核对权威安全索引；仅缺失版本记录允许首次建立。
  Future<String> accountGenerationDirectory(int generation) async {
    final lease = Zone.current[_zoneKey];
    if (lease is! _Lease || !lease.active)
      throw const MaterialCoordinationException(true);
    final file = File('${lease.state.parent.path}/account-generation.v1');
    try {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound)
        throw const MaterialCoordinationException(true);
      if (await file.readAsString() != 'UBAA1:$generation')
        throw const MaterialCoordinationException(true);
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2 &&
          !(Platform.isWindows && error.osError?.errorCode == 3))
        rethrow;
      await publishAccountGeneration(generation);
    }
    return lease.state.parent.path;
  }

  /// 只在启动时调用。B 的对账成功后，在释放独占锁前提交 C。
  Future<T?> reconcile<T>(Future<T> Function(MaterialMutation) action) =>
      _run<T?>((mutation) => action(mutation!), whenClean: () => null);

  bool get isReconciling => switch (Zone.current[_zoneKey]) {
    _Lease(active: true, reconciling: true) => true,
    _ => false,
  };

  /// 缺失、损坏或无法读取的记录不能作为撤销代次的依据。
  Future<int?> readGenerationForReconciliation() async {
    final lease = Zone.current[_zoneKey];
    if (lease is! _Lease || !isReconciling)
      throw const MaterialCoordinationException(true);
    final file = File('${lease.state.parent.path}/account-generation.v1');
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file)
        return null;
      final value = await file.readAsString();
      if (!value.startsWith('UBAA1:')) return null;
      final generation = int.tryParse(value.substring(6));
      return generation != null &&
              generation > 0 &&
              value == 'UBAA1:$generation'
          ? generation
          : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<T> run<T>(Future<T> Function() action) => _run((_) => action());

  Future<T> _run<T>(
    Future<T> Function(MaterialMutation?) action, {
    T Function()? whenClean,
  }) async {
    final borrowed = Zone.current[_zoneKey];
    if (borrowed is _Lease) {
      final parent = Zone.current[_operationKey];
      if (whenClean != null ||
          !borrowed.active ||
          parent is! _Operation ||
          !parent.accepting)
        throw const MaterialCoordinationException(true);
      // 同一父操作的并行分支排队，递归调用进入各自子 Zone，避免重入读改写竞态。
      final next = parent.tail.then(
        (_) => runZoned(
          () => _execute(() => action(null), _Operation()),
          zoneValues: {},
        ),
      );
      parent.tail = next.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (borrowed.dirty) borrowed.failed = true;
        },
      );
      return next;
    }
    final directory = await _resolve();
    await directory.create(recursive: true);
    final root = Directory(await directory.resolveSymbolicLinks());
    if (!Platform.isWindows) _UnixLock.chmod(root.path, 448);
    final lock = File('${root.path}/materials.lock');
    final state = File('${root.path}/transaction.v1');
    for (final file in [lock, state]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const MaterialCoordinationException(false);
      }
    }
    final unlock = await _acquire(lock);
    final lease = _Lease(state);
    try {
      String? marker;
      try {
        // exists/type 会把部分查询错误归为不存在，直接读取才能保留 OS 错误。
        marker = await state.readAsString();
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (code != 2 && !(Platform.isWindows && code == 3)) {
          throw const MaterialCoordinationException(true);
        }
      } on FormatException {
        throw const MaterialCoordinationException(true);
      }
      final clean = marker == null || marker == 'UBAA1:C';
      if (clean && whenClean != null) return whenClean();
      final mutation = switch (marker) {
        'UBAA1:B:probe' => MaterialMutation.probe,
        'UBAA1:B:save' => MaterialMutation.save,
        'UBAA1:B' || 'UBAA1:B:remove' => MaterialMutation.remove,
        _ => null,
      };
      if (!clean && (mutation == null || whenClean == null)) {
        throw const MaterialCoordinationException(true);
      }
      lease.reconciling = !clean;
      lease.mutation = mutation;
      return await runZoned(() async {
        final value = await _execute(() => action(mutation), _Operation());
        if (lease.failed) throw const MaterialCoordinationException(true);
        if (lease.dirty || lease.reconciling) await lease.persist('UBAA1:C');
        return value;
      }, zoneValues: {_zoneKey: lease});
    } finally {
      lease.active = false;
      await unlock();
    }
  }

  Future<T> _execute<T>(Future<T> Function() action, _Operation operation) =>
      runZoned(() async {
        late T value;
        Object? failure;
        StackTrace? failureStack;
        try {
          value = await action();
        } on Object catch (error, stack) {
          failure = error;
          failureStack = stack;
        }
        // 上层 timeout/遗漏 await 后仍排空已开始的子操作，再允许根事务释放锁。
        operation.accepting = false;
        await operation.tail;
        if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
        return value;
      }, zoneValues: {_operationKey: operation});

  /// 在变更前持久记录意图。更强的操作必须等新的标记落盘。
  Future<void> beforeMutation(MaterialMutation mutation) async {
    final lease = Zone.current[_zoneKey];
    if (lease is! _Lease || !lease.active) {
      throw const MaterialCoordinationException(true);
    }
    if (lease.mutation == null || mutation.index > lease.mutation!.index) {
      lease.mutation = mutation;
      lease.start = (lease.start ?? Future<void>.value()).then(
        (_) => lease.persist('UBAA1:B:${mutation.name}'),
      );
    }
    try {
      await lease.start;
    } on Object {
      lease.failed = true;
      rethrow;
    }
  }

  Future<Future<void> Function()> _acquire(
    File lock, {
    bool Function()? isCurrent,
    Duration? limit,
  }) async {
    final watch = Stopwatch()..start();
    if (!Platform.isWindows) {
      final fd = _UnixLock(lock.path);
      try {
        while (!fd.tryLock()) {
          if (isCurrent != null && !isCurrent())
            throw const MaterialCoordinationException(false);
          if (watch.elapsed >= (limit ?? waitLimit))
            throw const MaterialCoordinationException(false);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return () async {
          fd.close();
        };
      } on Object {
        fd.close();
        rethrow;
      }
    }
    final handle = await lock.open(mode: FileMode.append);
    try {
      while (true) {
        if (isCurrent != null && !isCurrent())
          throw const MaterialCoordinationException(false);
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          return () async {
            await handle.close();
          };
        } on FileSystemException {
          if (watch.elapsed >= (limit ?? waitLimit))
            throw const MaterialCoordinationException(false);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    } on Object {
      await handle.close();
      rethrow;
    }
  }
}

class _Operation {
  bool accepting = true;
  Future<void> tail = Future<void>.value();
}

class _Lease {
  _Lease(this.state);
  final File state;
  bool active = true;
  bool reconciling = false;
  MaterialMutation? mutation;
  bool get dirty => mutation != null;
  bool failed = false;
  Future<void>? start;
  Future<void> persist(String value) => persistFile(state, value);
  Future<void> persistFile(File file, String value) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file)
      throw const MaterialCoordinationException(true);
    // 不替换 inode。先 flush 未完成标记，再允许任何外部材料变更。
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeString(value);
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (!Platform.isWindows) _UnixLock.chmod(file.path, 384);
  }
}

final class _UnixLock {
  _UnixLock(String path) {
    final name = _string(path), mode = _string('a+');
    try {
      _stream = _fopen(name, mode);
    } finally {
      _free(name.cast());
      _free(mode.cast());
    }
    if (_stream == nullptr) throw const MaterialCoordinationException(false);
    try {
      if (_fcntl(_fileno(_stream), 2, 1) < 0)
        throw const MaterialCoordinationException(false);
      chmod(path, 384);
    } on Object {
      close();
      rethrow;
    }
  }
  late final Pointer<Void> _stream;
  bool _closed = false;
  bool tryLock() {
    if (_flock(_fileno(_stream), 6) == 0) return true;
    // EAGAIN/EWOULDBLOCK：只有锁竞争允许等待。
    final code = _errno().value;
    if (code != (Platform.isMacOS || Platform.isIOS ? 35 : 11)) {
      throw const MaterialCoordinationException(false);
    }
    return false;
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _fclose(_stream);
    }
  }

  static final _libc = DynamicLibrary.process();
  static final _malloc = _libc
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');
  static final _free = _libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  static final _fopen = _libc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>)
      >('fopen');
  static final _fileno = _libc
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fileno');
  static final _flock = _libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  static final _fcntl = _libc
      .lookupFunction<
        Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
        int Function(int, int, int)
      >('fcntl');
  static final _fclose = _libc
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('fclose');
  static final _chmod = _libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, int)
      >('chmod');
  static final _errno = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS || Platform.isIOS
            ? '__error'
            : Platform.isAndroid
            ? '__errno'
            : '__errno_location',
      );
  static Pointer<Uint8> _string(String value) {
    final bytes = utf8.encode(value);
    final result = _malloc(bytes.length + 1).cast<Uint8>();
    if (result == nullptr) throw const MaterialCoordinationException(false);
    result.asTypedList(bytes.length + 1).setAll(0, [...bytes, 0]);
    return result;
  }

  static void chmod(String path, int mode) {
    final name = _string(path);
    try {
      if (_chmod(name, mode) != 0)
        throw const MaterialCoordinationException(false);
    } finally {
      _free(name.cast());
    }
  }
}
