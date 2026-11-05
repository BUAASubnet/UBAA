// 执行实际 ArkTS 插件，验证保存面板授权的路径和一次性选择。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const ts = require(process.env.UBAA_TYPESCRIPT);
const root = path.resolve(__dirname, '../../../..');
const sourcePath = path.join(root, 'apps/ubaa_ohos/ohos/entry/src/main/ets/platform/AgendaFilePlugin.ets');
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021},
}).outputText;
function fixture(t, mode = 'local') {
  const parent = path.join(root, '.ubaa_local/tests/ohos_files');
  fs.mkdirSync(parent, {recursive: true, mode: 0o700});
  const directory = fs.mkdtempSync(path.join(parent, 'save_'));
  const destination = path.join(directory, '报告.txt');
  const host = mode === 'media' ? 'media' : 'docs';
  const uri = 'file://' + host + encodeURI(destination) + (mode === 'remote' ? '?networkid=synthetic' : '');
  class FileUri {
    constructor(value) {this.url = new URL(value);}
    get path() {return decodeURIComponent(this.url.pathname);}
    get authority() {return this.url.host;}
    get scheme() {return this.url.protocol.slice(0, -1);}
    isRemoteUri() {return this.url.searchParams.has('networkid');}
  }
  const core = {fileIo: {}, fileUri: {FileUri}, picker: {
    DocumentSaveOptions: class {},
    DocumentViewPicker: class {async save(options) {assert.equal(options.autoCreateEmptyFile, false);return [uri];}},
  }};
  const moduleValue = {exports: {}};
  vm.runInNewContext(compiled, {module: moduleValue, exports: moduleValue.exports, require(name) {
    if (name === '@kit.CoreFileKit') return core;
    if (name === '@kit.ArkTS') return {util: {}};
    if (name === '@kit.AbilityKit') return {};
    if (name === '@ohos/flutter_ohos') return {MethodChannel: class {setMethodCallHandler() {}}};
    throw Error('未声明的平台依赖');
  }});
  const plugin = new moduleValue.exports.default({cacheDir: directory});
  plugin.onAttachedToEngine({getBinaryMessenger() {return {};}});
  t.after(() => {plugin.onDetachedFromEngine({});fs.rmSync(directory, {recursive: true, force: true});});
  async function invoke(method, args) {
    return new Promise((resolve, reject) => plugin.onMethodCall({method, args: new Map(Object.entries(args))}, {
      success(value) {resolve(value);},
      error(code) {reject(Object.assign(Error('原生文件授权失败'), {code}));},
      notImplemented() {reject(Error('未实现的入口'));},
    }));
  }
  return {
    destination,
    select: () => invoke('select', {name: '报告.txt', kind: 'binary'}),
    resolveFile: selection => invoke('resolveFile', {selection}),
  };
}
test('本机 docs URI 返回解码路径，未创建文件且选择只能消费一次', async t => {
  const f = fixture(t);
  const selection = await f.select();
  await assert.rejects(f.resolveFile('invalid-selection'), {code: 'expired'});
  assert.equal(await f.resolveFile(selection), f.destination);
  assert.equal(fs.existsSync(f.destination), false);
  await assert.rejects(f.resolveFile(selection), {code: 'expired'});
});
for (const mode of ['remote', 'media']) {
  test(`拒绝非本机 docs 保存 URI：${mode}`, async t => {
    const f = fixture(t, mode);
    await assert.rejects(f.resolveFile(await f.select()), {code: 'unsupported_destination'});
    assert.equal(fs.existsSync(f.destination), false);
  });
}
