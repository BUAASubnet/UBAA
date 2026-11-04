/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

import 'util.dart';

class _Toolchain {
  _Toolchain(
    this.name,
    this.targets,
  );

  final String name;
  final List<String> targets;
}

class Rustup {
  List<String>? installedTargets(String toolchain) {
    final targets = _installedTargets(toolchain);
    return targets != null ? List.unmodifiable(targets) : null;
  }

  String resolveToolchain(String toolchain) {
    // UBAA：省略主机时遵循 Rustup 默认主机，不能由 Cargo --target 推断。
    if (['stable', 'beta', 'nightly'].contains(toolchain) ||
        RegExp(r'^\d+\.\d+\.\d+$').hasMatch(toolchain)) {
      return '$toolchain-$_defaultHost';
    }
    return toolchain;
  }

  void installToolchain(String toolchain) {
    final resolved = resolveToolchain(toolchain);
    log.info("Installing Rust toolchain: $resolved");
    runCommand("rustup", ['toolchain', 'install', resolved]);
    _installedToolchains
      ..clear()
      ..addAll(_getInstalledToolchains());
    if (_installedTargets(resolved) == null) {
      throw StateError('Rustup 安装后未找到工具链 $resolved');
    }
  }

  void installTarget(
    String target, {
    required String toolchain,
  }) {
    final resolved = resolveToolchain(toolchain);
    log.info("Installing Rust target: $target");
    runCommand("rustup", ['target', 'add', '--toolchain', resolved, target]);
    _installedTargets(resolved)?.add(target);
  }

  bool _didInstallZigBuild = false;

  void installZigBuild(String toolchain) {
    if (_didInstallZigBuild) {
      return;
    }

    log.info("Installing Zig build");
    runCommand("rustup", [
      'run',
      resolveToolchain(toolchain),
      'cargo',
      'install',
      '--locked',
      'cargo-zigbuild',
    ]);
    _didInstallZigBuild = true;
  }

  final List<_Toolchain> _installedToolchains;
  final String _defaultHost;

  Rustup()
      : _defaultHost = _getDefaultHost(),
        _installedToolchains = _getInstalledToolchains();

  static String _getDefaultHost() {
    final res = runCommand('rustup', ['show']);
    final pattern = RegExp(r'^Default host: ([A-Za-z0-9_.-]+)$');
    final matches = res.stdout
        .toString()
        .split('\n')
        .map((line) => pattern.firstMatch(line.trim()))
        .whereType<RegExpMatch>()
        .toList();
    if (matches.length != 1) {
      throw StateError('无法从 rustup show 读取唯一默认主机');
    }
    return matches.single.group(1)!;
  }

  List<String>? _installedTargets(String toolchain) => _installedToolchains
      .firstWhereOrNull(
        (e) => e.name == resolveToolchain(toolchain),
      )
      ?.targets;

  static List<_Toolchain> _getInstalledToolchains() {
    String extractToolchainName(String line) {
      // ignore (default) after toolchain name
      final parts = line.trim().split(' ');
      return parts[0];
    }

    final res = runCommand("rustup", ['toolchain', 'list']);

    // UBAA：同时识别已安装的精确版本，避免把版本工具链漏判为需要安装。
    final nonCustom = RegExp(r'^(stable|beta|nightly|\d+\.\d+\.\d+-)');
    final lines = res.stdout
        .toString()
        .split('\n')
        .where((e) => e.isNotEmpty && nonCustom.hasMatch(e))
        .map(extractToolchainName)
        .toList(growable: true);

    return lines
        .map(
          (name) => _Toolchain(
            name,
            _getInstalledTargets(name),
          ),
        )
        .toList(growable: true);
  }

  static List<String> _getInstalledTargets(String toolchain) {
    final res = runCommand("rustup", [
      'target',
      'list',
      '--toolchain',
      toolchain,
      '--installed',
    ]);
    final lines = res.stdout
        .toString()
        .split('\n')
        .where((e) => e.isNotEmpty)
        .toList(growable: true);
    return lines;
  }

  bool _didInstallRustSrcForNightly = false;

  void installRustSrcForNightly({String toolchain = 'nightly'}) {
    if (_didInstallRustSrcForNightly) {
      return;
    }
    // Useful for -Z build-std
    runCommand(
      "rustup",
      [
        'component',
        'add',
        'rust-src',
        '--toolchain',
        resolveToolchain(toolchain)
      ],
    );
    _didInstallRustSrcForNightly = true;
  }

  static String? executablePath() {
    final envPath = Platform.environment['PATH'];
    final envPathSeparator = Platform.isWindows ? ';' : ':';
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    final paths = [
      if (home != null) path.join(home, '.cargo', 'bin'),
      if (envPath != null) ...envPath.split(envPathSeparator),
    ];
    for (final p in paths) {
      final rustup = Platform.isWindows ? 'rustup.exe' : 'rustup';
      final rustupPath = path.join(p, rustup);
      if (File(rustupPath).existsSync()) {
        return rustupPath;
      }
    }
    return null;
  }
}
