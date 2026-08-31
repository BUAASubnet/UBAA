import path from 'path'
import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';

export default {
    system: appTasks,  /* Hvigor 内置 app plugin，不得替换。 */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* 注入锁定 Flutter OH 构建 plugin。 */
}
