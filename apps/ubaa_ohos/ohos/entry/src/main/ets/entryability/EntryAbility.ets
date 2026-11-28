import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import AgendaFilePlugin from '../platform/AgendaFilePlugin';
import GalleryImagePlugin from '../platform/GalleryImagePlugin';
import HomeCardPlugin from '../homecard/HomeCardPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(new AgendaFilePlugin(this.context));
    flutterEngine.getPlugins()?.add(new GalleryImagePlugin(this.context));
    flutterEngine.getPlugins()?.add(new HomeCardPlugin(this.context));
  }
}
