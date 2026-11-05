// 执行实际 ArkTS 插件，以真实合成文件验证交付、失败清理与目标所有权。
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
function fixture(t, mode = 'success') {
  const parent = path.join(root, '.ubaa_local/tests/ohos_files');
  fs.mkdirSync(parent, {recursive: true, mode: 0o700});
  const directory = fs.mkdtempSync(path.join(parent, 'save_'));
  const source = path.join(directory, 'source');
  const destination = path.join(directory, '报告.txt');
  const body = Buffer.from('abcdefghij');
  fs.writeFileSync(source, body, {mode: 0o600});
  const uri = 'file://docs' + encodeURI(destination) + (mode === 'remote' ? '?networkid=synthetic' : '');
  const events = [], opened = new Set();
  const fileIo = {
    OpenMode: {READ_WRITE: 2, CREATE: 64, TRUNC: 512},
    async access(value) {assert.ok(!value.includes('://'));return fs.existsSync(value);},
    async open(value, flags) {
      assert.equal(value, uri);events.push('open');
      const nativeFlags = fs.constants.O_RDWR | (flags & 64 ? fs.constants.O_CREAT : 0) | (flags & 512 ? fs.constants.O_TRUNC : 0);
      const fd = fs.openSync(destination, nativeFlags, 0o600);opened.add(fd);return {fd};
    },
    async copyFile(input, output) {
      assert.equal(input, source);events.push('copy');fs.ftruncateSync(output, 0);
      const fail = mode === 'partial' || mode === 'cleanup';
      fs.writeSync(output, fail ? body.subarray(0, 3) : body);
      if (fail) throw Object.assign(new Error('合成复制 I/O 失败'), {code: 13900005});
    },
    closeSync(file) {events.push('close');fs.closeSync(file.fd);opened.delete(file.fd);},
    unlinkSync(value) {
      assert.ok(!value.includes('://'));assert.equal(opened.size, 0);events.push('unlink');
      if (mode === 'cleanup') throw Error('合成清理失败');
      fs.unlinkSync(value);
    },
  };
  class FileUri {
    constructor(value) {this.url = new URL(value);}
    get path() {return decodeURIComponent(this.url.pathname);}
    get authority() {return this.url.host;}
    get scheme() {return this.url.protocol.slice(0, -1);}
    isRemoteUri() {return this.url.searchParams.has('networkid');}
  }
  const core = {fileIo, fileUri: {FileUri}, picker: {
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
  t.after(() => {plugin.onDetachedFromEngine({});for (const fd of opened) fs.closeSync(fd);fs.rmSync(directory, {recursive: true, force: true});});
  async function invoke(method, args) {
    return new Promise((resolve, reject) => plugin.onMethodCall({method, args: new Map(Object.entries(args))}, {
      success(value) {events.push('success');resolve({value, openFiles: opened.size});},
      error(code) {events.push('error');reject(Object.assign(Error('原生文件交付失败'), {code}));},
      notImplemented() {reject(Error('未实现的入口'));},
    }));
  }
  async function deliver() {
    const selection = (await invoke('select', {name: '报告.txt', kind: 'binary'})).value;
    events.length = 0;
    return invoke('writeFile', {selection, path: source});
  }
  return {source, destination, body, events, deliver};
}
test('部分复制失败先关闭再清理本次新文件', async t => {
  const f = fixture(t, 'partial');
  await assert.rejects(f.deliver(), {code: 'write_failed'});
  assert.equal(fs.existsSync(f.destination), false);
  assert.deepEqual(f.events.slice(-3), ['close', 'unlink', 'error']);
});
test('完整复制关闭后才回调成功并保留最终正文', async t => {
  const f = fixture(t);
  assert.equal((await f.deliver()).openFiles, 0);
  assert.deepEqual(fs.readFileSync(f.destination), f.body);
  assert.deepEqual(f.events.slice(-2), ['close', 'success']);
});
test('已有目标拒绝交付并保留原文件', async t => {
  const f = fixture(t);fs.writeFileSync(f.destination, 'original');
  await assert.rejects(f.deliver(), {code: 'exists'});
  assert.equal(fs.readFileSync(f.destination, 'utf8'), 'original');
  assert.deepEqual(f.events, ['error']);
});
test('清理失败明确报告部分文件未清理', async t => {
  const f = fixture(t, 'cleanup');
  await assert.rejects(f.deliver(), {code: 'cleanup_failed'});
  assert.equal(fs.statSync(f.destination).size, 3);
});
test('远端URI在本机目标操作前拒绝', async t => {
  const f = fixture(t, 'remote');
  await assert.rejects(f.deliver(), {code: 'unsupported_destination'});
  assert.equal(fs.existsSync(f.destination), false);
  assert.deepEqual(f.events, ['error']);
});
