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
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

import StorageCipher from './StorageCipher';
import KeyCipher from './KeyCipher';
import { mergeUint8Arrays, splitUint8Array } from '../utils';

const TAG = 'SecureStorage::StorageCipher18Implementation'

export default class StorageCipher18Implementation implements StorageCipher {
  private SECRET_KEY_PREFERENCES_NAME: string = 'ubaa-plugin-keys-v2';
  protected random: cryptoFramework.Random = cryptoFramework.createRandom();
  protected ivSize: number = 16;
  private KEY_ALGORITHM: string = "AES256";
  protected cipher: cryptoFramework.Cipher | null = null;
  protected secretKey: cryptoFramework.Key | null = null;
  base64: util.Base64Helper = new util.Base64Helper();
  preferences: preferences.Preferences | null = null;
  rsaCipher: KeyCipher | null = null;
  context: Context | null = null;

  constructor(context: Context, rsaCipher: KeyCipher) {
    this.context = context;
    this.rsaCipher = rsaCipher;
  }

  async getAESSecretKey(allowCreate: boolean = true) {
    if (this.secretKey && this.preferences) {
      return;
    }

    this.preferences = preferences.getPreferencesSync(this.context, {
      name: this.SECRET_KEY_PREFERENCES_NAME
    });
    let aesPreferencesKey: string = this.getAESPreferencesKey();
    let aesKey: preferences.ValueType = this.preferences.getSync(aesPreferencesKey, null);
    if (aesKey != null && this.rsaCipher) {
      let encrypted: Uint8Array = this.base64.decodeSync(aesKey as string);
      this.secretKey = await this.rsaCipher.RSADecrypt(encrypted, this.KEY_ALGORITHM);
      return;
    }

    if (!allowCreate) throw new Error('unavailable');
    const generated = this.genSymKeyByData();
    const encryptedKey: Uint8Array | undefined = await this.rsaCipher?.RSAEncrypt(generated);
    if (encryptedKey === undefined) throw new Error('unavailable');
    let value: string = this.base64.encodeToStringSync(encryptedKey);
    if (!this.preferences) {
      throw new Error('unavailable');
    }
    this.preferences.putSync(aesPreferencesKey, value);
    await this.preferences.flush();
    this.secretKey = generated;
  }

  protected getAESPreferencesKey(): string {
    return "VGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK";
  }

  async removePreferencesKey() {
    this.preferences = preferences.getPreferencesSync(this.context, {
      name: this.SECRET_KEY_PREFERENCES_NAME
    });
    let aesPreferencesKey: string = this.getAESPreferencesKey();
    let aesKey: preferences.ValueType = this.preferences.getSync(aesPreferencesKey, null);
    if (aesKey) {
      this.preferences.deleteSync(aesPreferencesKey);
      await this.preferences.flush();
    }
  }

  protected getCipher(): cryptoFramework.Cipher {
    return cryptoFramework.createCipher("AES256|CBC|PKCS7");
  }

  async encrypt(input: cryptoFramework.DataBlob): Promise<cryptoFramework.DataBlob> {
    // 再次进入应用时, 需要重新获取 secretKey
    await this.getAESSecretKey();
    if (!this.cipher) {
      this.cipher = this.getCipher();
    }
    let ivParameterSpec: cryptoFramework.IvParamsSpec = this.getParameterSpec();
    this.cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.secretKey, ivParameterSpec);
    let cipherData: cryptoFramework.DataBlob = this.cipher.doFinalSync(input);
    let combined = mergeUint8Arrays(ivParameterSpec.iv.data, cipherData.data);
    return {
      data: combined
    };
  }

  async decrypt(cipherText: cryptoFramework.DataBlob): Promise<cryptoFramework.DataBlob> {
    await this.getAESSecretKey(false);
    if (!this.cipher) {
      this.cipher = this.getCipher();
    }
    let ivParameterSpec: cryptoFramework.IvParamsSpec = this.getParameterSpec();
    let data = splitUint8Array(cipherText.data, 0, this.ivSize);
    ivParameterSpec.iv = {
      data
    };
    let cipherData = splitUint8Array(cipherText.data, this.ivSize, cipherText.data.length);
    this.cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, this.secretKey, ivParameterSpec);
    let decryptData = this.cipher.doFinalSync({
      data: cipherData
    });
    return decryptData;
  }

  protected genSymKeyByData(): cryptoFramework.SymKey {
    let aesGenerator = cryptoFramework.createSymKeyGenerator(this.KEY_ALGORITHM);
    let symKey: cryptoFramework.SymKey = aesGenerator.generateSymKeySync();
    return symKey;
  }

  protected getParameterSpec(): cryptoFramework.IvParamsSpec {
    let ivBlob: cryptoFramework.DataBlob = this.getIvBlob();
    let ivParamsSpec: cryptoFramework.IvParamsSpec = {
      algName: "IvParamsSpec",
      iv: ivBlob
    };
    return ivParamsSpec;
  }

  getIvBlob(): cryptoFramework.DataBlob {
    return this.random.generateRandomSync(this.ivSize);
  }
}
