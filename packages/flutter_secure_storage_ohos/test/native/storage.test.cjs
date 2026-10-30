// 执行社区插件实际ArkTS源码；系统API用内存Preferences和Node加密实现替代。
// 证明插件流程、错误与密文边界，不代替OHOS设备上的HUKS证明。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.argv[2]);
const stores = new Map(), keys = new Map(), sessions = new Map();
let generationCount = 0, failFlush = false, failLookup = false;
const properties = new Proxy({}, { get: (_, key) => key });
const huks = {
  HuksTag: properties, HuksKeyAlg: properties, HuksKeySize: properties,
  HuksKeyPadding: properties, HuksKeyDigest: properties, HuksCipherMode: properties,
  HuksKeyPurpose: { HUKS_KEY_PURPOSE_ENCRYPT: 1, HUKS_KEY_PURPOSE_DECRYPT: 2 },
  async isKeyItemExist(alias) {
    if (failLookup) throw Error('合成拒绝');
    // 与系统 API 一致：此接口在密钥缺失时抛错，不返回 false。
    if (!keys.has(alias)) throw Object.assign(Error('密钥不存在'), { code: 12000011 });
    return true;
  },
  async hasKeyItem(alias) { if (failLookup) throw Error('合成拒绝'); return keys.has(alias); },
  async generateKeyItem(alias) {
    generationCount++;
    keys.set(alias, crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }));
  },
  async deleteKeyItem(alias) { keys.delete(alias); },
  async initSession(alias, options) {
    assert(keys.has(alias), '丢失密钥必须失败');
    const handle = Symbol(); sessions.set(handle, { alias, options }); return { handle };
  },
  async finishSession(handle, options) {
    const { alias } = sessions.get(handle); sessions.delete(handle);
    const purpose = options.properties.find(p => p.tag === 'HUKS_TAG_PURPOSE').value;
    const key = keys.get(alias);
    const settings = { padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' };
    return { outData: purpose === 1
      ? crypto.publicEncrypt({ ...settings, key: key.publicKey }, Buffer.from(options.inData))
      : crypto.privateDecrypt({ ...settings, key: key.privateKey }, Buffer.from(options.inData)) };
  },
  async abortSession(handle) { sessions.delete(handle); },
};
function preferences(name) {
  if (!stores.has(name)) stores.set(name, new Map());
  const values = stores.get(name);
  return {
    getSync: (key, fallback) => values.has(key) ? values.get(key) : fallback,
    putSync: (key, value) => { values.set(key, value); },
    hasSync: key => values.has(key), getAllSync: () => Object.fromEntries(values),
    async put(key, value) { values.set(key, value); },
    async delete(key) { values.delete(key); },
    async clear() { values.clear(); },
    async flush() { if (failFlush) throw Error('合成落盘失败'); },
  };
}
const symmetric = bytes => ({ getEncoded: () => ({ data: Uint8Array.from(bytes) }) });
const cryptoFramework = {
  CryptoMode: { ENCRYPT_MODE: 1, DECRYPT_MODE: 2 },
  createRandom: () => ({ generateRandomSync: n => ({ data: crypto.randomBytes(n) }) }),
  createSymKeyGenerator(algorithm) {
    assert.equal(algorithm, 'AES256');
    return { generateSymKeySync: () => symmetric(crypto.randomBytes(32)), convertKeySync: blob => symmetric(blob.data) };
  },
  createCipher(algorithm) {
    assert.equal(algorithm, 'AES256|GCM|NoPadding');
    let cipher, encrypt;
    return {
      initSync(mode, key, parameters) {
        encrypt = mode === 1;
        const args = ['aes-256-gcm', Buffer.from(key.getEncoded().data), Buffer.from(parameters.iv.data)];
        cipher = encrypt ? crypto.createCipheriv(...args) : crypto.createDecipheriv(...args);
        cipher.setAAD(Buffer.from(parameters.aad.data));
        if (!encrypt) cipher.setAuthTag(Buffer.from(parameters.authTag.data));
      },
      updateSync(blob) { return { data: cipher.update(Buffer.from(blob.data)) }; },
      doFinalSync() { const tail = cipher.final(); assert.equal(tail.length, 0); return { data: encrypt ? cipher.getAuthTag() : tail }; },
    };
  },
};
const dependencies = {
  '@kit.CryptoArchitectureKit': { cryptoFramework },
  '@kit.UniversalKeystoreKit': { huks },
  '@kit.ArkData': { preferences: { getPreferencesSync: (_, options) => preferences(options.name) } },
  '@kit.ArkTS': { util: {
    Base64Helper: class { encodeToStringSync(data) { return Buffer.from(data).toString('base64'); } decodeSync(text) { return new Uint8Array(Buffer.from(text, 'base64')); } },
    TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } },
    TextDecoder: { create: () => ({ decodeWithStream: data => new TextDecoder('utf-8', { fatal: true }).decode(data) }) },
  } },
};
const modules = new Map();
function load(filename) {
  if (!fs.existsSync(filename) || fs.statSync(filename).isDirectory()) filename = ['.ets', '.ts', '/index.ts'].map(ext => filename + ext).find(fs.existsSync);
  if (!filename) throw Error('测试依赖不存在');
  if (modules.has(filename)) return modules.get(filename);
  const mod = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText;
  vm.runInNewContext(code, { exports: mod.exports, module: mod, Uint8Array, Map, Object,
    console: { log() { throw Error('插件不得输出原始数据'); }, error() { throw Error('插件不得输出原始错误'); } },
    require(name) { return dependencies[name] ?? load(path.resolve(path.dirname(filename), name)); },
  });
  modules.set(filename, mod.exports); return mod.exports;
}
const Storage = load(path.resolve(__dirname, '../../ohos/src/main/ets/components/plugin/FlutterSecureStorage.ets')).default;
const fresh = () => new Storage({}, new Map());
(async () => {
  const first = fresh();
  assert.equal(await first.read('missing'), null);
  assert.equal(generationCount, 0, '无记录读取不创建密钥');
  await first.write('alpha', '合成凭据🔐');
  assert.equal(generationCount, 1, '首次写入创建一份 HUKS 密钥');
  const reopened = fresh();
  assert.equal(await reopened.read('alpha'), '合成凭据🔐');
  await reopened.write('beta', '');
  assert.equal(await fresh().read('beta'), '', '空值不能误当无记录');
  assert.equal((await fresh().readAll()).size, 2);
  const data = stores.get('ubaa-plugin-values-v2');
  const original = data.get('alpha');
  assert(!original.includes('合成凭据'));
  data.set('gamma', original);
  await assert.rejects(() => fresh().read('gamma'), /corrupt/);
  data.delete('gamma');
  const tampered = Buffer.from(original, 'base64'); tampered[0] ^= 1;
  data.set('alpha', tampered.toString('base64'));
  await assert.rejects(() => fresh().read('alpha'));
  data.set('alpha', original);
  await first.delete('beta');
  assert.equal(await reopened.read('beta'), null);
  assert.equal(await reopened.read('alpha'), '合成凭据🔐');
  failFlush = true;
  await assert.rejects(() => fresh().write('delta', '合成写入'), /落盘失败/);
  await assert.rejects(() => fresh().delete('alpha'), /落盘失败/);
  failFlush = false; data.set('alpha', original);
  failLookup = true;
  await assert.rejects(() => fresh().read('alpha'), /合成拒绝/);
  failLookup = false;
  const count = generationCount;
  keys.clear();
  await assert.rejects(() => fresh().read('alpha'), /unavailable/);
  await assert.rejects(() => fresh().write('alpha', '替换值'), /unavailable/);
  assert.equal(generationCount, count, '密钥丢失不生成替代密钥');
  assert.equal(data.get('alpha'), original, '读取失败不重置密文');
  stores.get('ubaa-plugin-keys-v2').clear();
  await assert.rejects(() => fresh().write('alpha', '替换值'), /unavailable/);
  assert.equal(generationCount, count);
  assert.equal(sessions.size, 0);
  console.log('OHOS原生源码合成验证通过：重开、Unicode、空值、篡改、键绑定、删除、落盘失败、HUKS拒绝、丢失密钥与密文保全。');
})().catch(error => { console.error(error); process.exitCode = 1; });
