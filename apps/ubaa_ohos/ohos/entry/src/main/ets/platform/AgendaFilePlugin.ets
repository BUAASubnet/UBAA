import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

// 选择面板不接收日历内容。账号与路线核对通过后才创建并写入文件。
export default class AgendaFilePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private target: string | null = null;
  private selection: number = 0;
  private selecting: boolean = false;
  private pickedFiles: Set<string> = new Set<string>();
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) { this.context = context; }
  getUniqueClassName(): string { return 'AgendaFilePlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'cn.edu.buaa.ubaa/agenda-file');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.target = null;
    this.pickedFiles.forEach((path: string) => { try { fileIo.unlinkSync(path); } catch (_) {} });
    this.pickedFiles.clear();
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Map<string, Object>;
    if (call.method === 'pickFile') { this.pickFile(result); return; }
    if (call.method === 'releaseFile') {
      const path = args.get('path') as string;
      if (this.pickedFiles.delete(path)) { try { fileIo.unlinkSync(path); } catch (_) { result.error('cleanup_failed', '本机暂存文件未清理', null); return; } }
      result.success(null); return;
    }
    if (call.method === 'select') {
      this.select(args.get('name') as string, args.get('kind') === 'binary', result);
      return;
    }
    if (call.method !== 'write' && call.method !== 'writeFile' && call.method !== 'discard') {
      result.notImplemented(); return;
    }
    if (this.target === null || args.get('selection') !== this.selection.toString()) {
      result.error('expired', '保存位置已失效', null); return;
    }
    const uri = this.target;
    this.target = null;
    if (call.method === 'writeFile') {
      this.writeFile(args.get('path') as string, uri, result);
      return;
    }
    try {
      if (call.method === 'write') {
        const bytes = args.get('bytes') as Uint8Array;
        const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          const count = fileIo.writeSync(file.fd, bytes.buffer);
          if (count !== bytes.byteLength) throw new Error('incomplete');
        } finally { fileIo.closeSync(file); }
      }
      result.success(null);
    } catch (_) { result.error('write_failed', '日历文件未保存', null); }
  }
  private async pickFile(result: MethodResult): Promise<void> {
    if (this.selecting || this.target !== null) {result.error('busy', '请先结束当前文件选择', null); return;}
    this.selecting = true;
    let source: fileIo.File | null = null;
    let cached: string | null = null;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const locations = await new picker.DocumentViewPicker(this.context).select(options);
      if (locations.length === 0) {result.success(null); return;}
      if (this.channel === null) {result.error('closed', '文件选择已结束', null); return;}
      const name = new fileUri.FileUri(locations[0]).name;
      cached = this.context.cacheDir + '/bhpan_' + util.generateRandomUUID();
      source = await fileIo.open(locations[0], fileIo.OpenMode.READ_ONLY);
      await fileIo.copyFile(source.fd, cached);
      if (this.channel === null) {fileIo.unlinkSync(cached); cached = null; result.error('closed', '文件选择已结束', null); return;}
      this.pickedFiles.add(cached);
      result.success(new Map<string, Object>([['path', cached], ['name', name]]));
      cached = null;
    } catch (_) {result.error('read_failed', '所选文件无法读取', null);}
    finally {
      if (source !== null) fileIo.closeSync(source);
      if (cached !== null) {try {fileIo.unlinkSync(cached);} catch (_) {}}
      this.selecting = false;
    }
  }
  private async writeFile(path: string, uri: string, result: MethodResult): Promise<void> {
    let destination: fileIo.File | null = null;
    try {
      destination = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.copyFile(path, destination.fd);
      result.success(null);
    } catch (_) { result.error('write_failed', '文件未保存', null); }
    finally { if (destination !== null) fileIo.closeSync(destination); }
  }
  private async select(name: string, binary: boolean, result: MethodResult): Promise<void> {
    if (this.selecting || this.target !== null) {
      result.error('busy', '请先结束当前保存操作', null); return;
    }
    this.selecting = true;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      if (!binary) options.fileSuffixChoices = ['日历|.ics'];
      options.autoCreateEmptyFile = false;
      const locations = await new picker.DocumentViewPicker(this.context).save(options);
      if (this.channel === null) { result.error('closed', '保存面板已关闭', null); return; }
      this.target = locations.length === 0 ? null : locations[0];
      this.selection++;
      result.success(this.target === null ? null : this.selection.toString());
    } catch (_) { result.error('unavailable', '无法打开保存面板', null); }
    finally { this.selecting = false; }
  }
}
