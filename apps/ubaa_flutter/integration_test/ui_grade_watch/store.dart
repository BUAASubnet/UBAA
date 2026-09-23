import 'dart:io';
import 'dart:typed_data';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 只接受固定合成账号；旧UI矩阵仍验证跨宿主磁盘基线，存储已改为真实Core加密。
class NativeGradeScoreStore implements GradeScoreStore {
  NativeGradeScoreStore(this.directory);
  final Directory directory;
  final caches = <String, Future<BridgeOfflineCache>>{};
  Future<BridgeOfflineCache> cache(String account) =>
      caches.putIfAbsent(account, () {
        final id = switch (account) {
          'grade-watch-fixture' => '0123456789abcdef0123456789abcdef',
          'another-grade-fixture' => 'abcdef0123456789abcdef0123456789',
          _ => throw StateError('该原生测试存储只接受固定合成账号'),
        };
        return BridgeOfflineCache.open(
          configDir: directory.path,
          accountId: id,
          expectedIdentity: account,
          key: Uint8List.fromList(List.filled(32, 19)),
        );
      });
  BridgeConnectionMode route(ConnectionMode value) =>
      value == ConnectionMode.direct
      ? BridgeConnectionMode.direct
      : BridgeConnectionMode.webVpn;
  GradeScoreBaseline? from(BridgeGradeScoreBaseline? value) => value == null
      ? null
      : GradeScoreBaseline(
          termCode: value.termCode,
          termName: value.termName,
          scores: value.scores
              .map(
                (e) => GradeScoreEntry(
                  key: e.key,
                  courseName: e.courseName,
                  courseCode: e.courseCode,
                  score: e.score,
                ),
              )
              .toList(),
        );
  Future<GradeScoreBaseline?> read(String account, ConnectionMode mode) async =>
      from(
        await (await cache(
          account,
        )).readGradeScoreBaseline(route: route(mode), term: '2026-2027-1'),
      );
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode mode,
    GradeScoreBaseline latest,
  ) async => from(
    await (await cache(account)).updateGradeScoreBaseline(
      route: route(mode),
      latest: BridgeGradeScoreBaseline(
        termCode: latest.termCode,
        termName: latest.termName,
        scores: latest.scores
            .map(
              (e) => BridgeGradeScoreEntry(
                key: e.key,
                courseName: e.courseName,
                courseCode: e.courseCode,
                score: e.score,
              ),
            )
            .toList(),
      ),
    ),
  );
  @override
  Future<void> clearAccount(String account) async =>
      (await cache(account)).clear();
}

/// 损坏旧文件清理失败仍由真实解析器证明，不伪造成功结果。
class LegacyClearGradeStore implements GradeScoreStore {
  LegacyClearGradeStore(this.file);
  final File file;
  final memory = MemoryGradeScoreStore();
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline latest,
  ) => memory.update(account, route, latest);
  @override
  Future<void> clearAccount(String account) =>
      FileGradeScoreStore(file).clearAccount(account);
}
