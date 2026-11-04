import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';

// 选择面板不接收日历内容。账号与路线核对通过后才创建并写入文件。
export default class AgendaFilePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private target: string | null = null;
  private selection: number = 0;
  private selecting: boolean = false;
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
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Map<string, Object>;
    if (call.method === 'select') {
      this.select(args.get('name') as string, result);
      return;
    }
    if (call.method !== 'write' && call.method !== 'discard') {
      result.notImplemented(); return;
    }
    if (this.target === null || args.get('selection') !== this.selection.toString()) {
      result.error('expired', '保存位置已失效', null); return;
    }
    const uri = this.target;
    this.target = null;
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
  private async select(name: string, result: MethodResult): Promise<void> {
    if (this.selecting || this.target !== null) {
      result.error('busy', '请先结束当前保存操作', null); return;
    }
    this.selecting = true;
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      options.fileSuffixChoices = ['日历|.ics'];
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
