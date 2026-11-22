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
