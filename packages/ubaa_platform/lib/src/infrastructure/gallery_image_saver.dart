import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:gal/gal.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

import '../media.dart';

enum GalleryImageSaveResult { saved, cancelled }

enum GalleryImageSaveFailure { unsupported, permissionDenied, saveFailed }

/// 稳定的保存错误，不包含插件异常或本地路径。
final class GalleryImageSaveException implements Exception {
  const GalleryImageSaveException(this.failure);

  final GalleryImageSaveFailure failure;

  @override
  String toString() => 'GalleryImageSaveException(${failure.name})';
}

abstract interface class GalleryImageSaver {
  bool get isAvailable;
  Future<GalleryImageSaveResult> save(Uint8List png, {required String name});
}

final class UnavailableGalleryImageSaver implements GalleryImageSaver {
  const UnavailableGalleryImageSaver();

  @override
  bool get isAvailable => false;

  @override
  Future<GalleryImageSaveResult> save(
    Uint8List png, {
    required String name,
  }) async => throw const GalleryImageSaveException(
    GalleryImageSaveFailure.unsupported,
  );
}

/// HarmonyOS 通过宿主原生通道打开系统相册确认弹窗。
final class OhosGalleryImageSaver implements GalleryImageSaver {
  const OhosGalleryImageSaver();

  static const _channel = MethodChannel('cn.edu.buaa.ubaa/gallery-image');

  @override
  bool get isAvailable => true;

  @override
  Future<GalleryImageSaveResult> save(
    Uint8List png, {
    required String name,
  }) async {
    try {
      final saved = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': png,
        'name': name,
      });
      return switch (saved) {
        true => GalleryImageSaveResult.saved,
        false => GalleryImageSaveResult.cancelled,
        null => throw const GalleryImageSaveException(
          GalleryImageSaveFailure.saveFailed,
        ),
      };
    } on MissingPluginException {
      throw const GalleryImageSaveException(
        GalleryImageSaveFailure.unsupported,
      );
    } on PlatformException {
      throw const GalleryImageSaveException(GalleryImageSaveFailure.saveFailed);
    }
  }
}

/// 只添加到系统照片库，不请求相册读取或指定相簿的权限。
final class MobileGalleryImageSaver implements GalleryImageSaver {
  MobileGalleryImageSaver()
    : _permissions = CallbackPermissionGateway(
        request: (permission) async => permission != PlatformPermission.photoAdd
            ? PlatformPermissionStatus.unavailable
            : await Gal.requestPermission()
            ? PlatformPermissionStatus.granted
            : PlatformPermissionStatus.denied,
      );

  final PlatformPermissionGateway _permissions;

  @override
  bool get isAvailable => true;

  @override
  Future<GalleryImageSaveResult> save(
    Uint8List png, {
    required String name,
  }) async {
    final permission = await _permissions.request(PlatformPermission.photoAdd);
    if (permission != PlatformPermissionStatus.granted) {
      throw GalleryImageSaveException(
        permission == PlatformPermissionStatus.denied
            ? GalleryImageSaveFailure.permissionDenied
            : GalleryImageSaveFailure.saveFailed,
      );
    }
    try {
      // Gal 从 PNG 字节判断格式并添加扩展名。
      final stem = name.toLowerCase().endsWith('.png')
          ? name.substring(0, name.length - 4)
          : name;
      await Gal.putImageBytes(png, name: stem);
      return GalleryImageSaveResult.saved;
    } on Object {
      throw const GalleryImageSaveException(GalleryImageSaveFailure.saveFailed);
    }
  }
}

final class DesktopGalleryImageSaver implements GalleryImageSaver {
  const DesktopGalleryImageSaver({this.selectLocation});

  final Future<String?> Function(String name)? selectLocation;

  @override
  bool get isAvailable => true;

  @override
  Future<GalleryImageSaveResult> save(
    Uint8List png, {
    required String name,
  }) async {
    try {
      final target = selectLocation == null
          ? (await selector.getSaveLocation(
              suggestedName: name,
              acceptedTypeGroups: const [
                selector.XTypeGroup(
                  label: 'PNG 图片',
                  extensions: ['png'],
                  uniformTypeIdentifiers: ['public.png'],
                ),
              ],
            ))?.path
          : await selectLocation!(name);
      if (target == null) return GalleryImageSaveResult.cancelled;
      await selector.XFile.fromData(
        png,
        mimeType: 'image/png',
        name: name,
      ).saveTo(target);
      return GalleryImageSaveResult.saved;
    } on Object {
      throw const GalleryImageSaveException(GalleryImageSaveFailure.saveFailed);
    }
  }
}
