
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { AboutChannel } from '../platform/AboutChannel';

export default class EntryAbility extends FlutterAbility {
  private aboutChannel?: AboutChannel;
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.aboutChannel = new AboutChannel(flutterEngine, this.context);
  }
  cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    this.aboutChannel?.dispose();
    this.aboutChannel = undefined;
    super.cleanUpFlutterEngine(flutterEngine);
  }
}
