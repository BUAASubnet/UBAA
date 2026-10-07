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

import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import RSACipherOAEPImplementation from './ciphers/RSACipherOAEPImplementation';
import StorageCipherGCMImplementation from './ciphers/StorageCipherGCMImplementation';
import { StringToUint8Array, Uint8ArrayToString } from './utils';

interface StoredValue { key: string; value: string; }

// 保留社区HUKS包装密钥与AES-GCM实现，修正初始化、错误传播及密钥丢失行为。
export default class FlutterSecureStorage {
  private context: Context;
  private dataPreferences: preferences.Preferences | null = null;
  private cipher: StorageCipherGCMImplementation;
  private base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: Context, options: Map<string, Object>) {
    this.context = context;
    this.cipher = new StorageCipherGCMImplementation(context, new RSACipherOAEPImplementation(context));
  }

  private store(): preferences.Preferences {
    if (this.dataPreferences === null) {
      this.dataPreferences = preferences.getPreferencesSync(this.context, { name: 'ubaa-plugin-values-v2' });
    }
    return this.dataPreferences;
  }

  public async write(key: string, value: string): Promise<void> {
    const store = this.store();
    // 有密文时不为丢失的包装材料生成替代密钥。
    await this.cipher.getAESSecretKey(Object.keys(store.getAllSync()).length === 0);
    const record: StoredValue = { key: key, value: value };
    const encrypted = await this.cipher.encrypt({ data: StringToUint8Array(JSON.stringify(record)) });
    await store.put(key, this.base64.encodeToStringSync(encrypted.data));
    await store.flush();
  }

  public async read(key: string): Promise<string | null> {
    const store = this.store();
    if (!store.hasSync(key)) return null;
    const raw = store.getSync(key, '');
    if (typeof raw !== 'string' || raw.length === 0 || raw.length > 1048576) throw new Error('corrupt');
    await this.cipher.getAESSecretKey(false);
    const bytes = this.base64.decodeSync(raw);
    if (bytes.length < 28) throw new Error('corrupt');
    const decrypted = await this.cipher.decrypt({ data: bytes });
    const record = JSON.parse(Uint8ArrayToString(decrypted.data)) as StoredValue;
    // 将键和正文一同认证，复制另一键的合法密文也必须拒绝。
    if (record.key !== key || typeof record.value !== 'string') throw new Error('corrupt');
    return record.value;
  }

  public async containsKey(key: string): Promise<boolean> { return this.store().hasSync(key); }
  public async delete(key: string): Promise<void> {
    const store = this.store();
    await store.delete(key);
    await store.flush();
  }
  public async readAll(): Promise<Map<string, string>> {
    const result = new Map<string, string>();
    for (const key of Object.keys(this.store().getAllSync())) {
      const value = await this.read(key);
      if (value !== null) result.set(key, value);
    }
    return result;
  }
  public async deleteAll(): Promise<void> {
    // 仅清本插件值，保留HUKS包装密钥；不访问应用的其他Preferences。
    await this.store().clear();
    await this.store().flush();
  }
}
