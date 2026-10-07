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

import { cryptoFramework } from '@kit.CryptoArchitectureKit';

import KeyCipher from './KeyCipher';
import StorageCipher18Implementation from './StorageCipher18Implementation';
import { mergeUint8Arrays, splitUint8Array } from '../utils';

const TAG = 'SecureStorage::StorageCipherGCMImplementation';

export default class StorageCipherGCMImplementation extends StorageCipher18Implementation {
  protected override ivSize: number = 12;
  protected authTagSize: number = 16;

  constructor(context: Context, rsaCipher: KeyCipher) {
    super(context, rsaCipher);
  }

  protected override getAESPreferencesKey(): string {
    return "VGhpcyBpcyB0aGUga2V5IGZvcihBIHNlY3XyZZBzdG9yYWdlIEFFUyBLZXkK";
  }

  protected override getCipher(): cryptoFramework.Cipher {
    return cryptoFramework.createCipher("AES256|GCM|NoPadding");
  }

  override async encrypt(input: cryptoFramework.DataBlob): Promise<cryptoFramework.DataBlob> {
    // 再次进入应用时, 需要重新获取 secretKey
    await this.getAESSecretKey();
    if (!this.cipher) {
      this.cipher = this.getCipher();
    }
    let gcmParamsSpec = this.getParameterSpec();
    this.cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, this.secretKey, gcmParamsSpec);
    let encryptUpdate = this.cipher.updateSync(input);
    let authTag = this.cipher.doFinalSync(null);
    let combined = mergeUint8Arrays(authTag.data, gcmParamsSpec.iv.data);
    combined = mergeUint8Arrays(combined, encryptUpdate.data);
    return {
      data: combined
    };
  }

  override async decrypt(cipherText: cryptoFramework.DataBlob): Promise<cryptoFramework.DataBlob> {
    // 再次进入应用时, 需要重新获取 secretKey
    await this.getAESSecretKey(false);
    if (!this.cipher) {
      this.cipher = this.getCipher();
    }
    let gcmParamsSpec = this.getParameterSpec();
    let authTagData = splitUint8Array(cipherText.data, 0, this.authTagSize);
    gcmParamsSpec.authTag = {
      data: authTagData
    };
    let ivPosition = this.authTagSize + this.ivSize;
    let ivData = splitUint8Array(cipherText.data, this.authTagSize, ivPosition);
    gcmParamsSpec.iv = {
      data: ivData
    };
    let cipherData = splitUint8Array(cipherText.data, ivPosition, cipherText.data.length);
    this.cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, this.secretKey, gcmParamsSpec);
    let decryptUpdate = this.cipher.updateSync({
      data: cipherData
    });
    // gcm模式解密doFinal时传入空，验证init时传入的tag数据，如果验证失败会抛出异常。
    let decryptData = this.cipher.doFinalSync(null);
    if (decryptData == null) {
    }
    return decryptUpdate;
  }

  protected override getParameterSpec(): cryptoFramework.GcmParamsSpec {
    let ivBlob: cryptoFramework.DataBlob = this.getIvBlob();
    let arr = [0, 0, 0, 0, 0, 0, 0, 0]; // 8 bytes
    let dataAad = new Uint8Array(arr);
    let aadBlob: cryptoFramework.DataBlob = {
      data: dataAad
    };
    arr = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; // 16 bytes
    let dataTag = new Uint8Array(arr);
    let tagBlob: cryptoFramework.DataBlob = {
      data: dataTag
    };

    return {
      iv: ivBlob,
      aad: aadBlob,
      authTag: tagBlob,
      algName: "GcmParamsSpec"
    };
  }

  getIvBlob(): cryptoFramework.DataBlob {
    return this.random.generateRandomSync(this.ivSize);
  }
}
