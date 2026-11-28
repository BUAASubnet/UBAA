import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { binding, formIds, saveSnapshot } from './HomeCardStore';

export default class HomeCardPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'HomeCardPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      'cn.edu.buaa.ubaa/home-card',
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'publish') {
      result.notImplemented();
      return;
    }
    try {
      const args = call.args as Map<string, Object>;
      const payload: Object | undefined = args.get('payload');
      if (typeof payload !== 'string' || payload.length > 64000) {
        result.success(null);
        return;
      }
      saveSnapshot(this.context, payload);
      this.refresh();
      result.success(null);
    } catch (_) {
      result.success(null);
    }
  }

  private refresh(): void {
    const data = binding(this.context);
    for (const id of formIds(this.context)) {
      formProvider.updateForm(id, data).catch(() => {});
    }
  }
}
