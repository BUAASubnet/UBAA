import path from 'path'
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosModuleContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { flutterHvigorPlugin } from 'flutter-hvigor-plugin';

const { resolveToolchain, requireDependencies, nativeArguments, applySigning, readLocalSigning } =
    require('../../../scripts/tools/ohos_hvigor.cjs');

// DevEco 直接构建时没有 just 导出的环境变量；SDK 路径从 local.properties 读取，
// 只作为 CMake 参数传给 Cargokit 子进程，不修改 Hvigor daemon 的环境。
hvigor.nodesEvaluated(() => {
    requireDependencies(path.dirname(__dirname));
    const toolchain = resolveToolchain(__dirname);
    hvigor.getRootNode().subNodes(node => {
        if (node.getNodeName() !== 'ubaa_bindings') return;
        const context = node.getContext(OhosPluginId.OHOS_HAR_PLUGIN) as OhosModuleContext;
        const profile = context.getBuildProfileOpt();
        const native = profile.buildOption?.externalNativeOptions;
        if (!native) throw new Error('ubaa_bindings 缺少 externalNativeOptions');
        const existing = native.arguments;
        native.arguments = [...(Array.isArray(existing) ? existing : existing ? [existing] : []),
            ...nativeArguments(toolchain)];
        context.setBuildProfileOpt(profile);
    });
});

// 签名材料位于 Git 忽略的 .sign/ohos/hvigor-signing.json，只在内存中按构建模式注入。
hvigor.nodesEvaluated(() => {
    const local = readLocalSigning(path.resolve(__dirname, '../../..'));
    if (!local) return;
    const context = hvigor.getRootNode().getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    context.setBuildProfileOpt(applySigning(context.getBuildProfileOpt(), context.getBuildMode(), local));
});

export default {
    system: appTasks,  /* Hvigor 内置 app plugin，不得替换。 */
    plugins:[flutterHvigorPlugin(path.dirname(__dirname))]         /* 注入锁定 Flutter OH 构建 plugin。 */
}
