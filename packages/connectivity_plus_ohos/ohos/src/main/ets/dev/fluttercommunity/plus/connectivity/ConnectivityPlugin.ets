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
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import EventChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { ConnectivityBroadcastReceiver } from './ConnectivityBroadcastReceiver';
import { Connectivity } from './Connectivity';
import ConnectivityMethodChannelHandler from './ConnectivityMethodChannelHandler';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';

const TAG: string = "ConnectivityPlugin";

export default class ConnectivityPlugin implements FlutterPlugin {
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private receiver: ConnectivityBroadcastReceiver | null = null;
  private pluginBing: FlutterPluginBinding | null = null;

  getUniqueClassName(): string {
    return "ConnectivityPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {

    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/connectivity", StandardMethodCodec.INSTANCE);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "dev.fluttercommunity.plus/connectivity_status", StandardMethodCodec.INSTANCE);

    let connectivity = new Connectivity();
    let methodChannelHandler = new ConnectivityMethodChannelHandler(connectivity);
    this.receiver = new ConnectivityBroadcastReceiver(binding.getApplicationContext(), connectivity);
    this.methodChannel.setMethodCallHandler(methodChannelHandler);
    this.eventChannel.setStreamHandler(this.receiver);
    this.pluginBing = binding;
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);
    this.receiver?.onCancel();
    this.methodChannel = null;
    this.eventChannel = null;
    this.receiver = null;
    this.pluginBing = null;
  }
}
