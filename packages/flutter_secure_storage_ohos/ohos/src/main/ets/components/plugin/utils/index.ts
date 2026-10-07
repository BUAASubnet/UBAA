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

import { util } from '@kit.ArkTS';

export function StringToUint8Array(str: string): Uint8Array {
  let textEncoder = new util.TextEncoder('utf-8');
  let result = textEncoder.encodeInto(str);
  return result;
}

export function Uint8ArrayToString(fileData: Uint8Array): string {
  let dataString = '';
  let textDecoder = util.TextDecoder.create('utf-8');
  dataString = textDecoder.decodeWithStream(fileData);
  return dataString;
}

export function mergeUint8Arrays(arr1: Uint8Array, arr2: Uint8Array): Uint8Array {
  return Uint8Array.from([...arr1, ...arr2]);
}

export function splitUint8Array(array: Uint8Array, start: number, end: number): Uint8Array {
  if (start < 0 || end > array.length || start > end) {
    throw new Error('Invalid start or end index');
  }

  // 创建一个新的 Uint8Array，包含从 start 到 end 的元素
  const splitArray = new Uint8Array(end - start);
  splitArray.set(array.slice(start, end));

  return splitArray;
}
