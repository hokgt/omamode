import { test } from "node:test";
import assert from "node:assert/strict";
import { decide } from "../pi/omamode.ts";

const status = (over: Record<string, unknown> = {}) => ({
  mode: "work",
  activity: "idle",
  error: null,
  server: "running",
  loaded: null,
  default: "A",
  ...over,
});

test("remote provider: skip", () => {
  assert.deepEqual(decide(status(), "kimi-coding", "k3"), { kind: "skip" });
});

test("omamode missing: skip", () => {
  assert.deepEqual(decide(null, "llama.cpp", "A"), { kind: "skip" });
});

test("pi's model is loaded: ok", () => {
  assert.deepEqual(decide(status({ loaded: { id: "A", sizeGB: 22 } }), "llama.cpp", "A"), { kind: "ok" });
});

test("nothing loaded in work mode: load or continue", () => {
  assert.deepEqual(decide(status(), "llama.cpp", "A"), {
    kind: "prompt", options: ["load", "continue"], model: "A", loaded: null, mode: "work",
  });
});

test("another model loaded: swap or continue", () => {
  assert.deepEqual(decide(status({ loaded: { id: "B", sizeGB: 20 } }), "llama.cpp", "A"), {
    kind: "prompt", options: ["swap", "continue"], model: "A", loaded: "B", mode: "work",
  });
});

test("gaming mode: switch to work and load, or continue", () => {
  assert.deepEqual(decide(status({ mode: "gaming" }), "llama.cpp", "A"), {
    kind: "prompt", options: ["work-load", "continue"], model: "A", loaded: null, mode: "gaming",
  });
});

test("no model id known: fall back to omamode's default", () => {
  const d = decide(status(), "llama.cpp", undefined);
  assert.equal(d.kind, "prompt");
  assert.equal((d as { model: string }).model, "A");
});

test("no model id and no default: skip", () => {
  assert.deepEqual(decide(status({ default: null }), "llama.cpp", undefined), { kind: "skip" });
});

import { waitForLoad } from "../pi/omamode.ts";

const seq = (items: Array<Record<string, unknown> | null>) => {
  let i = 0;
  return async () => (items[Math.min(i++, items.length - 1)] as any);
};
const fast = { intervalMs: 1, deadlineMs: 200 };

test("waitForLoad: loaded and idle", async () => {
  const r = await waitForLoad(seq([status({ activity: "loading" }), status({ loaded: { id: "A", sizeGB: 1 } })]), "A", fast);
  assert.equal(r.kind, "loaded");
});

test("waitForLoad: error reported", async () => {
  const r = await waitForLoad(seq([status({ activity: "loading" }), status({ error: "boom" })]), "A", fast);
  assert.deepEqual(r, { kind: "error", message: "boom" });
});

test("waitForLoad: job ended without loading the model", async () => {
  const r = await waitForLoad(seq([status({ activity: "loading" }), status({ loaded: { id: "B", sizeGB: 1 } })]), "A", fast);
  assert.equal(r.kind, "error");
});

test("waitForLoad: never started stops at the deadline", async () => {
  const r = await waitForLoad(seq([status()]), "A", fast);
  assert.equal(r.kind, "timeout");
});

import { syncLoadedModel } from "../pi/omamode.ts";

const fakePi = () => {
  const calls: any = { setModel: [] as unknown[] };
  return { calls, api: { setModel: async (m: unknown) => { calls.setModel.push(m); return true; } } };
};
const fakeCtx = (opts: { current?: string; known?: string[]; refreshFails?: boolean; noRegistry?: boolean } = {}) => {
  const log: any = { refresh: [] as unknown[] };
  const known = new Set(opts.known ?? []);
  const ctx: any = {
    model: opts.current ? { provider: "llama.cpp", id: opts.current } : undefined,
    modelRegistry: opts.noRegistry ? undefined : {
      refresh: async (o: any) => {
        log.refresh.push(o);
        if (opts.refreshFails) throw new Error("server down");
        known.add("Flash");
      },
      find: (provider: string, id: string) => (provider === "llama.cpp" && known.has(id) ? { provider, id } : undefined),
    },
  };
  return { ctx, log };
};

test("syncLoadedModel: refreshes pi's llama.cpp list, then selects the model", async () => {
  const p = fakePi(); const c = fakeCtx();
  assert.equal(await syncLoadedModel(p.api as any, c.ctx, "Flash"), true);
  assert.equal(c.log.refresh.length, 1);
  assert.deepEqual(c.log.refresh[0].providers, ["llama.cpp"]);
  assert.equal(c.log.refresh[0].allowNetwork, true);
  assert.ok(c.log.refresh[0].signal instanceof AbortSignal);
  assert.deepEqual(p.calls.setModel, [{ provider: "llama.cpp", id: "Flash" }]);
});

test("syncLoadedModel: already on that model, nothing to select", async () => {
  const p = fakePi(); const c = fakeCtx({ current: "Flash" });
  await syncLoadedModel(p.api as any, c.ctx, "Flash");
  assert.deepEqual(p.calls.setModel, []);
});

test("syncLoadedModel: a failing refresh never throws", async () => {
  const p = fakePi(); const c = fakeCtx({ refreshFails: true });
  assert.equal(await syncLoadedModel(p.api as any, c.ctx, "Flash"), false);
  assert.deepEqual(p.calls.setModel, []);
});

test("syncLoadedModel: no model registry, no error", async () => {
  const p = fakePi(); const c = fakeCtx({ noRegistry: true });
  assert.equal(await syncLoadedModel(p.api as any, c.ctx, "Flash"), false);
});

import { targetModel } from "../pi/omamode.ts";

const def = { provider: "llama.cpp", model: "Flash" };
const none = () => undefined;
const has = (id: string) => (p: string, m: string) => (p === "llama.cpp" && m === id ? { id } : undefined);

test("targetModel: pi is on its local default: use it", () => {
  assert.deepEqual(targetModel({ provider: "llama.cpp", id: "Flash" }, def, none, true), def);
});

test("targetModel: pi fell back to another local model because its default is missing", () => {
  assert.deepEqual(targetModel({ provider: "llama.cpp", id: "Qwen" }, def, none, true), def);
});

test("targetModel: pi fell back because its local default is missing from its list (seen live)", () => {
  assert.deepEqual(targetModel({ provider: "kimi-coding", id: "kimi-for-coding" }, def, none, true), def);
});

test("targetModel: pi knows its default but is on another model on purpose", () => {
  assert.deepEqual(targetModel({ provider: "kimi-coding", id: "k3" }, def, has("Flash"), true), { provider: "kimi-coding", model: "k3" });
});

test("targetModel: later runs follow pi's current model", () => {
  assert.deepEqual(targetModel({ provider: "kimi-coding", id: "k3" }, def, none, false), { provider: "kimi-coding", model: "k3" });
});

test("targetModel: no model yet: pi's configured default", () => {
  assert.deepEqual(targetModel(undefined, def, none, false), def);
});

import { sameServer } from "../pi/omamode.ts";

test("sameServer: same host and port", () => {
  assert.equal(sameServer("http://127.0.0.1:8090", "http://127.0.0.1:8090/"), true);
  assert.equal(sameServer("http://localhost:8090/v1", "http://127.0.0.1:8090"), true);
});

test("sameServer: a different port is a mismatch (seen live: 8080 vs 8090)", () => {
  assert.equal(sameServer("http://127.0.0.1:8080", "http://127.0.0.1:8090"), false);
});

test("sameServer: unknown addresses never warn", () => {
  assert.equal(sameServer(undefined, "http://127.0.0.1:8090"), true);
  assert.equal(sameServer("not a url", "http://127.0.0.1:8090"), true);
});
