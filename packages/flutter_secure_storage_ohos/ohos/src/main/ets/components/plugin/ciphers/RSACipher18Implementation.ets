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
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';

const TAG = 'SecureStorage::RSACipher18Implementation';

export default class RSACipher18Implementation implements KeyCipher {
  private SECRET_RSA_KEY_ALIAS: string = 'ubaa.flutter.secure-storage.v2.rsa';
  protected context: Context | null = null;
  base64: util.Base64Helper = new util.Base64Helper();

  constructor(context: Context) {
    this.context = context;
  }

  async RSAEncrypt(key: cryptoFramework.Key): Promise<Uint8Array> {
    await this.createRSAKeysIfNeeded();
    let data: Uint8Array = key.getEncoded().data;
    let options: huks.HuksOptions = {
      properties: this.getRsaEncryptProperties(),
      inData: data,
    }
    return this.dataEncrypt(options);
  }

  protected async dataEncrypt(options: huks.HuksOptions): Promise<Uint8Array> {
    return this.transform(options);
  }

  private async transform(options: huks.HuksOptions): Promise<Uint8Array> {
    const session = await huks.initSession(this.SECRET_RSA_KEY_ALIAS, options);
    try {
      const result = await huks.finishSession(session.handle, options);
      if (result.outData === undefined) throw new Error('unavailable');
      return result.outData;
    } catch (_) {
      try { await huks.abortSession(session.handle, { properties: [] }); } catch (_) {}
      throw new Error('unavailable');
    }
  }

  async RSADecrypt(wrappedKey: Uint8Array, algorithm: string): Promise<cryptoFramework.Key> {
    await this.createRSAKeysIfNeeded(false);
    let options: huks.HuksOptions = {
      properties: this.getRsaDecryptProperties(),
      inData: wrappedKey,
    }
    return this.dataDecrypt(options, algorithm);
  }

  protected async dataDecrypt(options: huks.HuksOptions, algorithm: string): Promise<cryptoFramework.Key> {
    return this.getKey({ data: await this.transform(options) }, algorithm);
  }

  // 把 DataBlob 转为 Key
  protected getKey(keyBlob: cryptoFramework.DataBlob, algorithm: string): cryptoFramework.Key {
    let symKeyGenerator = cryptoFramework.createSymKeyGenerator(algorithm);
    let symKey: cryptoFramework.Key = symKeyGenerator.convertKeySync(keyBlob);
    return symKey;
  }

  protected async createRSAKeysIfNeeded(allowCreate: boolean = true) {
    const exists = await huks.isKeyItemExist(this.SECRET_RSA_KEY_ALIAS, { properties: [] });
    if (exists) return;
    if (!allowCreate) throw new Error('unavailable');
    await this.generateKeyItem();
  }

  async removePreferencesKey() {
    await huks.deleteKeyItem(this.SECRET_RSA_KEY_ALIAS, { properties: [] });
  }

  protected getRsaGenerateProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }];
    return properties;
  }

  protected getRsaEncryptProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_PKCS1_V1_5
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
    }];
    return properties;
  }

  protected getRsaDecryptProperties(): Array<huks.HuksParam> {
    let properties: Array<huks.HuksParam> = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_RSA
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_RSA_KEY_SIZE_2048
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_PKCS1_V1_5
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_NONE
    }];
    return properties;
  }

  /**
   * 生成密钥
   */
  protected async generateKeyItem() {
    await huks.generateKeyItem(this.SECRET_RSA_KEY_ALIAS, { properties: this.getRsaGenerateProperties() });
  }
}
