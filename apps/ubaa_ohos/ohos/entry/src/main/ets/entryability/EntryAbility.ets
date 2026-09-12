
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { AboutChannel } from '../platform/AboutChannel';
import { PhotoChannel } from '../platform/PhotoChannel';

export default class EntryAbility extends FlutterAbility {
  private aboutChannel?: AboutChannel;
  private photoChannel?: PhotoChannel;
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    this.aboutChannel = new AboutChannel(flutterEngine, this.context);
    this.photoChannel = new PhotoChannel(flutterEngine);
  }
  cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    this.aboutChannel?.dispose();
    this.aboutChannel = undefined;
    this.photoChannel?.dispose();
    this.photoChannel = undefined;
    super.cleanUpFlutterEngine(flutterEngine);
  }
}
