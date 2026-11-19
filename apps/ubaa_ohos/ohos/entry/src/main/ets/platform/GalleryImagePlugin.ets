import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export default class GalleryImagePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'GalleryImagePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'cn.edu.buaa.ubaa/gallery-image');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'saveImage') {
      result.notImplemented();
      return;
    }
    this.saveImage(call.args as Map<string, Object>, result);
  }

  private async saveImage(args: Map<string, Object>, result: MethodResult): Promise<void> {
    try {
      const bytes = args.get('bytes') as Uint8Array;
      const name = args.get('name') as string;
      if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 ||
        typeof name !== 'string' || name.length <= 4 || !name.endsWith('.png')) {
        result.error('invalid_image', '图片或文件名不可用', null);
        return;
      }
      const buffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(buffer).set(bytes);
      result.success(await this.savePng(buffer, name.slice(0, -4)));
    } catch (_) {
      result.error('save_failed', '图片未能保存到相册', null);
    }
  }

  private async savePng(bytes: ArrayBuffer, title: string): Promise<boolean> {
    const helper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const path = `${this.context.cacheDir}/${util.generateRandomUUID()}.png`;
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: title,
      fileNameExtension: 'png',
      photoType: photoAccessHelper.PhotoType.IMAGE,
    };
    try {
      const temp = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      try {
        this.writePng(temp, bytes);
        const uris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [config]);
        if (uris.length === 0) {
          return false;
        }
        const target = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY);
        this.writePng(target, bytes);
        return true;
      } finally {
        fileIo.unlinkSync(path);
      }
    } finally {
      await helper.release();
    }
  }

  private writePng(file: fileIo.File, bytes: ArrayBuffer): void {
    try {
      if (fileIo.writeSync(file.fd, bytes) !== bytes.byteLength) {
        throw new Error('图片未完整写入');
      }
    } finally {
      fileIo.closeSync(file);
    }
  }
}
