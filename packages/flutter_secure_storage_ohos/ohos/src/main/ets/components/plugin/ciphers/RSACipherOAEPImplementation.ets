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

import RSACipher18Implementation from './RSACipher18Implementation';
import { huks } from '@kit.UniversalKeystoreKit';

const TAG = 'SecureStorage::RSACipherOAEPImplementation';

export default class RSACipherOAEPImplementation extends RSACipher18Implementation {
  constructor(context: Context) {
    super(context);
  }

  override async RSAEncrypt(key: cryptoFramework.Key): Promise<Uint8Array> {
    await this.createRSAKeysIfNeeded();
    let data: Uint8Array = key.getEncoded().data;
    let options: huks.HuksOptions = {
      properties: this.getRsaEncryptProperties(),
      inData: data,
    }
    return this.dataEncrypt(options);
  }

  override async RSADecrypt(wrappedKey: Uint8Array, algorithm: string): Promise<cryptoFramework.Key> {
    await this.createRSAKeysIfNeeded(false);
    let options: huks.HuksOptions = {
      properties: this.getRsaDecryptProperties(),
      inData: wrappedKey,
    }
    return this.dataDecrypt(options, algorithm);
  }

  /////////////////////////////////////////ohos.security.huks//////////////////////////////////////

  protected override getRsaGenerateProperties(): Array<huks.HuksParam> {
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

  protected override getRsaEncryptProperties(): Array<huks.HuksParam> {
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
      value: huks.HuksKeyPadding.HUKS_PADDING_OAEP
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256
    }];
    return properties;
  }

  protected override getRsaDecryptProperties(): Array<huks.HuksParam> {
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
      value: huks.HuksKeyPadding.HUKS_PADDING_OAEP
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_ECB
    }, {
      tag: huks.HuksTag.HUKS_TAG_DIGEST,
      value: huks.HuksKeyDigest.HUKS_DIGEST_SHA256
    }];
    return properties;
  }
}
