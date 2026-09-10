import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import { FlutterEngine, MethodChannel, MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';

// 关于页仅提供安装包版本及两个旧版公开链接；不使用学校会话。
export class AboutChannel implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;

  constructor(engine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'cn.edu.buaa.ubaa/about');
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'version') {
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
        .then((info: bundleManager.BundleInfo) => result.success(`${info.versionName}+${info.versionCode}`))
        .catch(() => result.success(null));
      return;
    }
    if (call.method === 'openLink') {
      const destination: string = call.args as string;
      let uri = '';
      if (destination === 'project') {
        uri = 'https://github.com/BUAASubnet/UBAA';
      } else if (destination === 'feedback') {
        uri = 'https://github.com/BUAASubnet/UBAA/issues';
      } else {
        result.success(false);
        return;
      }
      this.context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: uri
      }).then(() => result.success(true)).catch(() => result.success(false));
      return;
    }
    result.notImplemented();
  }

  dispose(): void {
    this.channel.setMethodCallHandler(null);
  }
}
