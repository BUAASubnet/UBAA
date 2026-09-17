import huks from '@ohos.security.huks';
import cryptoFramework from '@ohos.security.cryptoFramework';
import preferences from '@ohos.data.preferences';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import { FlutterEngine, MethodChannel, MethodCall, MethodCallHandler, MethodResult } from '@ohos/flutter_ohos';

// HUKS 持有不可导出的包装密钥；Preferences 只保存随机 nonce 和认证密文。
export class SecureMaterialChannel implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;
  private queue: Promise<void> = Promise.resolve();
  private disposed: boolean = false;
  private readonly alias: string = 'ubaa.material.wrap.v1';

  constructor(engine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), 'cn.edu.buaa.ubaa/secure-material');
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'read' && call.method !== 'write' && call.method !== 'delete') {
      result.notImplemented();
      return;
    }
    this.queue = this.queue.then(async () => {
      try {
        if (this.disposed) { throw new Error('unavailable'); }
        const args = call.method === 'write' ? call.args as Map<string, string> : undefined;
        const key = args === undefined ? call.args as string : args.get('key');
        if (key === undefined || key.length > 280 || !/^ubaa\.material\.v1\.[a-zA-Z0-9._-]+$/.test(key)) {
          throw new Error('invalid');
        }
        const storage = await preferences.getPreferences(this.context, { name: 'ubaa-secure-material-v1' });
        const exists = await huks.isKeyItemExist(this.alias, { properties: [] });
        if (call.method === 'read') {
          const value = await storage.get(key, '');
          if (typeof value !== 'string') { throw new Error('invalid'); }
          if (value.length === 0) { result.success(null); return; }
          if (!exists) { throw new Error('unavailable'); }
          result.success(await this.decrypt(key, value));
          return;
        }
        if (call.method === 'delete') {
          await storage.delete(key);
          await storage.flush();
          result.success(null);
          return;
        }
        const value = args?.get('value');
        if (value === undefined || value.length > 8192) { throw new Error('invalid'); }
        if (!exists) {
          // 标记存在但密钥丢失时不生成替代密钥，不覆盖旧密文。
          if (await storage.get('key-established', false) === true) { throw new Error('unavailable'); }
          await huks.generateKeyItem(this.alias, { properties: this.baseProperties(
            huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT) });
          await storage.put('key-established', true);
          await storage.flush();
        }
        const sealed = await this.encrypt(key, value);
        if (this.disposed) { throw new Error('unavailable'); }
        await storage.put(key, sealed);
        await storage.flush();
        result.success(null);
      } catch (_) {
        result.error('secure_material_unavailable', '系统安全存储暂不可用', null);
      }
    });
  }

  private baseProperties(purpose: number): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM }
    ];
  }

  private async transform(properties: huks.HuksParam[], input: Uint8Array): Promise<Uint8Array> {
    const options: huks.HuksOptions = { properties: properties, inData: input };
    const session = await huks.initSession(this.alias, options);
    try {
      const result = await huks.finishSession(session.handle, options);
      if (result.outData === undefined) { throw new Error('unavailable'); }
      return result.outData;
    } catch (_) {
      try { await huks.abortSession(session.handle, { properties: [] }); } catch (_) {}
      throw new Error('unavailable');
    }
  }

  private async encrypt(key: string, value: string): Promise<string> {
    const nonce = cryptoFramework.createRandom().generateRandomSync(12).data;
    const properties = this.baseProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT);
    properties.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new util.TextEncoder().encodeInto(key) });
    const cipher = await this.transform(properties, new util.TextEncoder().encodeInto(value));
    const sealed = new Uint8Array(nonce.length + cipher.length);
    sealed.set(nonce);
    sealed.set(cipher, nonce.length);
    return new util.Base64Helper().encodeToStringSync(sealed);
  }

  private async decrypt(key: string, value: string): Promise<string> {
    const sealed = new util.Base64Helper().decodeSync(value);
    if (sealed.length < 28 || sealed.length > 32768) { throw new Error('invalid'); }
    const properties = this.baseProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
    properties.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: sealed.slice(0, 12) });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new util.TextEncoder().encodeInto(key) });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: sealed.slice(sealed.length - 16) });
    const plain = await this.transform(properties, sealed.slice(12, sealed.length - 16));
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(plain);
  }

  dispose(): void {
    this.disposed = true;
    this.channel.setMethodCallHandler(null);
  }
}
