/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
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
import connection from '@ohos.net.connection'

const TAG = "Connectivity";

export class Connectivity {
  public static CONNECTIVITY_NONE = "none";
  private static CONNECTIVITY_WIFI = "wifi";
  private static CONNECTIVITY_MOBILE = "mobile";
  private static CONNECTIVITY_ETHERNET = "ethernet";
  private static CONNECTIVITY_BLUETOOTH = "bluetooth";
  private static CONNECTIVITY_VPN = "vpn";
  public networkType: string = Connectivity.CONNECTIVITY_NONE;

  constructor() {

  }

  async getNetworkType(): Promise<string> {
    //通过异步方式获取网络信息
    const netHandle = await connection.getDefaultNet();
    if (netHandle.netId == 0) {
      return Connectivity.CONNECTIVITY_NONE;
    }
    const capabilities = await connection.getNetCapabilities(netHandle);
    this.networkType = this.hasTransport(capabilities.bearerTypes);
    return this.networkType;
  }

  hasTransport(capabilities: Array<number>): string {
    //若数组为空返回CONNECTIVITY_NONE
    if (capabilities.length == 0) {
      return Connectivity.CONNECTIVITY_NONE;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_WIFI)) {
      return Connectivity.CONNECTIVITY_WIFI;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_ETHERNET)) {
      return Connectivity.CONNECTIVITY_ETHERNET;
    }
    if (capabilities.includes(connection.NetBearType.BEARER_CELLULAR)) {
      return Connectivity.CONNECTIVITY_MOBILE;
    }

    return Connectivity.CONNECTIVITY_NONE;
  }
}
