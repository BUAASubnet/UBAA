import assert from "node:assert/strict";
import test from "node:test";
import { createRenderer } from "vue";

const renderer = createRenderer({
  createComment: () => ({}),
  insert() {},
  remove() {},
  parentNode() {},
  nextSibling() {},
});

async function setup(t) {
  const module = await import(`../components/use_release.js?test=${encodeURIComponent(t.name)}`);
  const mount = () => {
    let state;
    const app = renderer.createApp({
      setup() {
        state = module.useRelease();
        return () => null;
      },
    });
    app.mount({});
    t.after(() => app.unmount());
    return state;
  };
  return mount;
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const manifest = { version: "2.0.0", build: "2007", platforms: {} };

test("首页与下载页同时挂载时只请求一次发布清单", async (t) => {
  let finish;
  const send = t.mock.method(globalThis, "fetch", () => new Promise((resolve) => { finish = resolve; }));
  const mount = await setup(t);
  const first = mount();
  const second = mount();
  assert.equal(first.loading.value, true);
  assert.equal(first.release.value, null);
  assert.equal(send.mock.callCount(), 1);
  finish(Response.json(manifest));
  await settle();
  assert.deepEqual(first.release.value, manifest);
  assert.deepEqual(second.release.value, manifest);
  assert.equal(first.loading.value, false);
});

test("一分钟内再次进入下载页复用清单", async (t) => {
  const send = t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  const mount = await setup(t);
  mount();
  await settle();
  const state = mount();
  assert.equal(send.mock.callCount(), 1);
  assert.deepEqual(state.release.value, manifest);
  assert.equal(state.loading.value, false);
});

test("缓存到期重新获取清单，刷新失败时保留下载入口", async (t) => {
  let now = 1000;
  t.mock.method(Date, "now", () => now);
  const send = t.mock.method(globalThis, "fetch", async () => Response.json(manifest));
  const mount = await setup(t);
  const state = mount();
  await settle();
  now += 60_001;
  send.mock.mockImplementation(async () => { throw new Error("网络不可用"); });
  mount();
  await settle();
  assert.equal(send.mock.callCount(), 2);
  assert.deepEqual(state.release.value, manifest);
  assert.equal(state.loading.value, false);
  send.mock.mockImplementation(async () => Response.json({ ...manifest, build: "2008" }));
  mount();
  await settle();
  assert.equal(send.mock.callCount(), 3);
  assert.equal(state.release.value.build, "2008");
});

test("首次请求失败后结束加载，下次进入页面可以重试", async (t) => {
  const send = t.mock.method(globalThis, "fetch", async () => new Response(null, { status: 404 }));
  const mount = await setup(t);
  const state = mount();
  await settle();
  assert.equal(state.release.value, null);
  assert.equal(state.loading.value, false);
  send.mock.mockImplementation(async () => Response.json(manifest));
  mount();
  await settle();
  assert.equal(send.mock.callCount(), 2);
  assert.deepEqual(state.release.value, manifest);
});
