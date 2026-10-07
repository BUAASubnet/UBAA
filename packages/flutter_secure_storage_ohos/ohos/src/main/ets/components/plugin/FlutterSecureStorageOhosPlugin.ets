/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler,
  MethodChannel, MethodResult, BinaryMessenger, StandardMethodCodec } from '@ohos/flutter_ohos';
import FlutterSecureStorage from './FlutterSecureStorage';

// 基于社区插件修订：所有结果等待存储完成，失败不返回成功、不输出秘密。
export default class FlutterSecureStorageOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private secureStorage: FlutterSecureStorage | null = null;
  private attached: boolean = false;
  private generation: number = 0;
  private static queue: Promise<void> = Promise.resolve();

  public initInstance(messenger: BinaryMessenger, context: Context) {
    this.generation++;
    this.secureStorage = new FlutterSecureStorage(context, new Map());
    this.attached = true;
    this.channel = new MethodChannel(messenger, 'plugins.it_nomads.com/flutter_secure_storage', StandardMethodCodec.INSTANCE);
    this.channel.setMethodCallHandler(this);
  }

  getUniqueClassName(): string { return 'FlutterSecureStorageOhosPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.initInstance(binding.getBinaryMessenger(), binding.getApplicationContext());
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.generation++;
    this.attached = false;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.secureStorage = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const generation = this.generation;
    // 跨引擎共用队列，避免同一包装密钥初始化与值操作互相交错。
    FlutterSecureStorageOhosPlugin.queue = FlutterSecureStorageOhosPlugin.queue.then(async () => {
      try {
        if (!this.attached || generation !== this.generation || this.secureStorage === null) throw new Error('unavailable');
        const store = this.secureStorage;
        const args = call.args as Map<string, Object>;
        const options = args.get('options') as Map<string, Object>;
        if (options?.get('resetOnError') === 'true') throw new Error('unsupported');
        const rsa = options?.get('ohosKeyCipherAlgorithm');
        const aes = options?.get('ohosStorageCipherAlgorithm');
        if ((rsa !== undefined && rsa !== 'RSA_ECB_OAEPwithSHA_256andMGF1Padding') ||
          (aes !== undefined && aes !== 'AES_GCM_NoPadding')) throw new Error('unsupported');
        let value: Object | null = null;
        switch (call.method) {
          case 'write':
            await store.write(this.key(args), this.value(args));
            break;
          case 'read': value = await store.read(this.key(args)); break;
          case 'delete': await store.delete(this.key(args)); break;
          case 'containsKey': value = await store.containsKey(this.key(args)); break;
          case 'readAll': value = await store.readAll(); break;
          case 'deleteAll': await store.deleteAll(); break;
          default: result.notImplemented(); return;
        }
        if (!this.attached || generation !== this.generation) throw new Error('unavailable');
        result.success(value);
      } catch (_) {
        result.error('secure_storage_unavailable', '系统安全存储暂不可用', null);
      }
    });
  }

  private key(args: Map<string, Object>): string {
    const key = args.get('key');
    if (typeof key !== 'string' || key.length === 0 || key.length > 512) throw new Error('invalid');
    return key;
  }
  private value(args: Map<string, Object>): string {
    const value = args.get('value');
    if (typeof value !== 'string' || value.length > 65536) throw new Error('invalid');
    return value;
  }
}
