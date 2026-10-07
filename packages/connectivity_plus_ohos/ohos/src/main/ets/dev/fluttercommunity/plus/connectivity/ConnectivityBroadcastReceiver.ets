/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
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
import { StreamHandler, EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import connection from '@ohos.net.connection';
import { Connectivity } from './Connectivity';

// 社区系统事件实现的生命周期修订：每次监听独立连接，迟到回调不能进入新订阅。
export class ConnectivityBroadcastReceiver implements StreamHandler {
  private connectivity: Connectivity;
  private events: EventSink | null = null;
  private subscription: connection.NetConnection | null = null;
  private generation: number = 0;
  constructor(context: Context, connectivity: Connectivity) { this.connectivity = connectivity; }
  onListen(args: Object, events: EventSink): void {
    this.onCancel();
    this.events = events;
    const generation = this.generation;
    const subscription = connection.createNetConnection();
    this.subscription = subscription;
    const refresh = (): void => {
      this.connectivity.getNetworkType().then((value: string) => {
        if (generation === this.generation) this.events?.success([value]);
      }).catch(() => {
        if (generation === this.generation) this.events?.error('unavailable', '系统网络信息暂不可用', null);
      });
    };
    subscription.on('netAvailable', refresh);
    subscription.on('netCapabilitiesChange', refresh);
    subscription.on('netConnectionPropertiesChange', refresh);
    subscription.on('netLost', refresh);
    subscription.on('netUnavailable', refresh);
    subscription.register((error) => {
      if (generation !== this.generation) return;
      if (error) this.events?.error('unavailable', '系统网络监听暂不可用', null);
      else refresh();
    });
  }
  onCancel(args?: Object): void {
    this.generation++;
    this.events = null;
    const subscription = this.subscription;
    this.subscription = null;
    if (subscription !== null) subscription.unregister(() => {});
  }
}
