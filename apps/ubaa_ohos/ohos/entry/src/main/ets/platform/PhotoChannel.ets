import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { FlutterEngine, MethodChannel, MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';

class PhotoPayload {
  bytes: Uint8Array;
  fileName: string = '所选图片';
  mimeType: string;
  constructor(bytes: Uint8Array, mimeType: string) {
    this.bytes = bytes;
    this.mimeType = mimeType;
  }
}

// 只读取系统选择器授予的单张图片；URI、文件描述符与系统错误不交给Dart。
export class PhotoChannel implements MethodCallHandler {
  private channel: MethodChannel;
  private pending: MethodResult | undefined;
  private disposed: boolean = false;
  private readonly maxBytes: number = 10 * 1024 * 1024;

  constructor(engine: FlutterEngine) {
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'cn.edu.buaa.ubaa/platform');
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'photo.capability') { result.success(!this.disposed); return; }
    if (call.method === 'permission.request') {
      // 系统选择仍由用户确认；其他尚未接线的权限不会报告可用。
      result.success((call.args as string) === 'photos' ? 'granted' : 'unavailable');
      return;
    }
    if (call.method !== 'photo.pick') { result.notImplemented(); return; }
    if (this.pending !== undefined || this.disposed) {
      result.error('photo_busy', '图片选择器暂不可用', null);
      return;
    }
    this.pending = result;
    this.pick();
  }

  private async pick(): Promise<void> {
    try {
      const selected = await new photoAccessHelper.PhotoViewPicker().select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (this.disposed) { return; }
      if (selected.photoUris.length === 0) { this.finish(null); return; }
      const file = fs.openSync(selected.photoUris[0], fs.OpenMode.READ_ONLY);
      let bytes: Uint8Array;
      try {
        const size = fs.statSync(file.fd).size;
        if (size <= 0 || size > this.maxBytes) { throw new Error('invalid_image'); }
        bytes = new Uint8Array(size);
        let total = 0;
        while (total < size) {
          const chunk = new ArrayBuffer(Math.min(64 * 1024, size - total));
          const count = fs.readSync(file.fd, chunk);
          if (count <= 0) { throw new Error('invalid_image'); }
          bytes.set(new Uint8Array(chunk, 0, count), total);
          total += count;
        }
        if (fs.readSync(file.fd, new ArrayBuffer(1)) !== 0) { throw new Error('invalid_image'); }
      } finally { fs.closeSync(file); }
      const source = image.createImageSource(bytes.buffer as ArrayBuffer);
      try {
        const info = await source.getImageInfo();
        if (info.size.width <= 0 || info.size.height <= 0 || !info.mimeType.startsWith('image/')) {
          throw new Error('invalid_image');
        }
        this.finish(new PhotoPayload(bytes, info.mimeType));
      } finally { await source.release(); }
    } catch (_) {
      const reply = this.pending;
      this.pending = undefined;
      if (!this.disposed) { reply?.error('photo_read_failed', '无法读取图片，请选择不超过10MiB的图片', null); }
    }
  }

  private finish(value: PhotoPayload | null): void {
    const reply = this.pending;
    this.pending = undefined;
    if (!this.disposed) { reply?.success(value); }
  }

  dispose(): void {
    this.pending?.error('photo_unavailable', '图片选择已结束', null);
    this.pending = undefined;
    this.disposed = true;
    this.channel.setMethodCallHandler(null);
  }
}
