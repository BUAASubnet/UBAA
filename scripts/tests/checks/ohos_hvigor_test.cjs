// Hvigor 配置只来自 local.properties，路径失效或缺项时明确失败，不沿用旧值。
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolveToolchain, requireDependencies, nativeArguments, applySigning, readLocalSigning } = require('../../tools/ohos_hvigor.cjs');

function sdk(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ubaa_hvigor_'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    const native = 'hmos/default/openharmony/native';
    for (const file of ['flutter/bin/flutter', 'flutter/bin/cache/dart-sdk/bin/dart',
        `${native}/llvm/bin/clang`, `${native}/build/cmake/ohos.toolchain.cmake`]) {
        fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
        fs.writeFileSync(path.join(root, file), '', { mode: 0o700 });
    }
    fs.mkdirSync(path.join(root, 'ohos'));
    return root;
}

function properties(root, text) {
    fs.writeFileSync(path.join(root, 'ohos/local.properties'), text);
}

test('从 local.properties 推出 Flutter 与 native SDK，并生成 CMake 参数', t => {
    const root = sdk(t);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/flutter\nflutter.versionCode=1\n`);
    const config = resolveToolchain(path.join(root, 'ohos'));
    assert.equal(config.flutterRoot, `${root}/flutter`);
    assert.equal(config.nativeSdkRoot, `${root}/hmos/default/openharmony/native`);
    assert.deepEqual(nativeArguments(config), [
        `-DCARGOKIT_FLUTTER_ROOT:PATH=${root}/flutter`,
        `-DCARGOKIT_OHOS_SDK_HOME:PATH=${root}/hmos/default/openharmony/native`]);
});

test('每次重新读取，路径变更后参数随之改变', t => {
    const first = sdk(t), second = sdk(t);
    properties(first, `hwsdk.dir=${first}/hmos\nflutter.sdk=${first}/flutter\n`);
    const before = nativeArguments(resolveToolchain(path.join(first, 'ohos')));
    properties(first, `hwsdk.dir=${second}/hmos\nflutter.sdk=${second}/flutter\n`);
    assert.notDeepEqual(before, nativeArguments(resolveToolchain(path.join(first, 'ohos'))));
});

test('环境变量不参与解析', t => {
    const root = sdk(t);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/flutter\n`);
    const saved = process.env.FLUTTER_ROOT;
    process.env.FLUTTER_ROOT = '/official/flutter';
    t.after(() => { if (saved === undefined) delete process.env.FLUTTER_ROOT; else process.env.FLUTTER_ROOT = saved; });
    assert.equal(resolveToolchain(path.join(root, 'ohos')).flutterRoot, `${root}/flutter`);
});

test('缺文件、缺项、含空白或 SDK 失效时给出准备命令', t => {
    const root = sdk(t);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /缺少 ohos\/local.properties.*pub get/);
    properties(root, `flutter.sdk=${root}/flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /缺少 hwsdk.dir/);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/my flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /空白/);
    properties(root, `hwsdk.dir=${root}/missing\nflutter.sdk=${root}/flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /llvm\/bin\/clang/);
});

test('缺少 Flutter 依赖配置时提示显式准备命令', t => {
    const root = sdk(t);
    assert.throws(() => requireDependencies(root), /pub get --enforce-lockfile/);
    fs.mkdirSync(path.join(root, '.dart_tool'));
    fs.writeFileSync(path.join(root, '.dart_tool/package_config.json'), '{}');
    requireDependencies(root);
});

function profile() {
    return { app: { signingConfigs: [{ name: 'tracked' }], products: [{ name: 'default', signingConfig: 'tracked' }] } };
}

test('环境签名覆盖本机文件并映射到 Hvigor 发布材料', t => {
    const root = sdk(t);
    fs.mkdirSync(path.join(root, '.sign/ohos'), { recursive: true });
    fs.writeFileSync(path.join(root, '.sign/ohos/hvigor-signing.json'), '{"release":{"name":"old"}}');
    const env = { OHOS_STORE_FILE: '/private/release.p12', OHOS_STORE_PASSWORD: 'synthetic-store',
        OHOS_KEY_ALIAS: 'release', OHOS_KEY_PASSWORD: 'synthetic-key',
        OHOS_CERT_FILE: '/private/release.cer', OHOS_PROFILE_FILE: '/private/release.p7b' };
    const local = readLocalSigning(root, env);
    assert.deepEqual(local.release, { name: 'default', type: 'HarmonyOS', material: {
        storeFile: env.OHOS_STORE_FILE, storePassword: env.OHOS_STORE_PASSWORD,
        keyAlias: env.OHOS_KEY_ALIAS, keyPassword: env.OHOS_KEY_PASSWORD,
        certpath: env.OHOS_CERT_FILE, profile: env.OHOS_PROFILE_FILE, signAlg: 'SHA256withECDSA' } });
    assert.equal(applySigning(profile(), 'release', local).app.products[0].signingConfig, 'default');
    assert.equal(readLocalSigning(root, {}).release.name, 'old');
    assert.throws(() => readLocalSigning(root, { OHOS_STORE_FILE: env.OHOS_STORE_FILE }), /OHOS_STORE_PASSWORD/);
    assert.equal(fs.readFileSync(path.join(root, '.sign/ohos/hvigor-signing.json'), 'utf8'), '{"release":{"name":"old"}}');
});

test('签名按构建模式注入，未提供本机配置时保持原样', () => {
    assert.deepEqual(applySigning(profile(), 'release', null), profile());
    const signed = applySigning(profile(), 'release', { release: { name: 'local-release' } });
    assert.deepEqual(signed.app.signingConfigs, [{ name: 'local-release' }]);
    assert.equal(signed.app.products[0].signingConfig, 'local-release');
});

test('Debug 缺配置时清空签名，Release 缺配置时失败', () => {
    const debug = applySigning(profile(), 'debug', { release: { name: 'local-release' } });
    assert.deepEqual(debug.app.signingConfigs, []);
    assert.equal('signingConfig' in debug.app.products[0], false);
    assert.throws(() => applySigning(profile(), 'release', { debug: { name: 'x' } }), /缺少当前构建模式/);
});

for (const fails of [false, true]) {
    test(`Flutter 构建期间可以读取实际签名，${fails ? '失败' : '成功'}后恢复配置`, async (t) => {
        const { withSigningProfile } = await import('../../release/platforms/ohos_profile.mjs');
        const parent = path.resolve('.ubaa_local/tests');
        fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
        const folder = fs.mkdtempSync(path.join(parent, 'ohos_profile_'));
        t.after(() => fs.rmSync(folder, { recursive: true, force: true }));
        const file = path.join(folder, 'build-profile.json5');
        const original = '{"app":{"signingConfigs": [],"products":[{"name":"default","signingConfig":"default"}]}}\n';
        fs.writeFileSync(file, original, { mode: 0o644 });
        const signing = { name: 'fixture-release', type: 'HarmonyOS', material: {
            storeFile: '/fixture/release.p12', storePassword: 'synthetic-$&-password',
            keyAlias: 'release', keyPassword: 'synthetic-key', certpath: '/fixture/release.cer',
            profile: '/fixture/release.p7b', signAlg: 'SHA256withECDSA' } };
        const build = async () => {
            const profile = JSON.parse(fs.readFileSync(file, 'utf8'));
            assert.deepEqual(profile.app.signingConfigs, [signing]);
            assert.equal(profile.app.products[0].signingConfig, signing.name);
            if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o600);
            if (fails) throw new Error('合成构建失败');
            return 0;
        };
        if (fails) await assert.rejects(withSigningProfile(file, signing, build), /合成构建失败/);
        else assert.equal(await withSigningProfile(file, signing, build), 0);
        assert.equal(fs.readFileSync(file, 'utf8'), original);
        if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o644);
    });
}

test('发布入口保留构建退出码，并在终止信号后恢复签名配置', async (t) => {
    const { spawnSync, spawn } = require('node:child_process');
    const { once } = require('node:events');
    const parent = path.resolve('.ubaa_local/tests');
    fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
    const root = fs.mkdtempSync(path.join(parent, 'ohos_command_'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    for (const relative of ['scripts/release/platforms/ohos_profile.mjs', 'scripts/tools/ohos_hvigor.cjs']) {
        fs.mkdirSync(path.dirname(path.join(root, relative)), { recursive: true });
        fs.copyFileSync(path.resolve(relative), path.join(root, relative));
    }
    fs.mkdirSync(path.join(root, 'apps/ubaa_ohos/ohos'), { recursive: true });
    const file = path.join(root, 'apps/ubaa_ohos/ohos/build-profile.json5');
    const original = '{"app":{"signingConfigs": []}}\n';
    fs.writeFileSync(file, original);
    const env = { ...process.env, OHOS_STORE_FILE: '/fixture/release.p12',
        OHOS_STORE_PASSWORD: 'synthetic-store', OHOS_KEY_ALIAS: 'release',
        OHOS_KEY_PASSWORD: 'synthetic-key', OHOS_CERT_FILE: '/fixture/release.cer',
        OHOS_PROFILE_FILE: '/fixture/release.p7b' };
    const script = path.join(root, 'scripts/release/platforms/ohos_profile.mjs');
    const result = spawnSync(process.execPath, [script, process.execPath, '-e', 'process.exit(7)'], { env });
    assert.equal(result.status, 7);
    assert.equal(fs.readFileSync(file, 'utf8'), original);
    if (process.platform === 'win32') return;
    const child = spawn(process.execPath, [script, process.execPath, '-e',
        'setInterval(() => {}, 1000); console.log("ready");'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    t.after(() => { if (child.exitCode === null) child.kill('SIGTERM'); });
    const closed = once(child, 'close');
    await once(child.stdout, 'data');
    assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).app.signingConfigs.length, 1);
    child.kill('SIGTERM');
    const [code] = await closed;
    assert.equal(code, 143);
    assert.equal(fs.readFileSync(file, 'utf8'), original);
});
