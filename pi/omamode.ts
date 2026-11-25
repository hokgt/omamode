/**
 * omamode pi extension.
 *
 * Before pi talks to the local llama.cpp server, check that the model pi
 * asks for is the one loaded. If not, offer to load it, swap to it, or
 * switch from gaming mode to work mode and load it. Does nothing when pi
 * uses a remote provider or omamode is not installed.
 *
 * Installed by `omamode setup` as ~/.pi/agent/extensions/omamode.ts.
 * https://github.com/hokgt/omamode
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const LOCAL_PROVIDER = "llama.cpp";

export interface Status {
  mode: string;
  activity: string;
  error: string | null;
  server: string;
  loaded: { id: string; sizeGB: number | null } | null;
  default: string | null;
  [key: string]: unknown;
}

export type Option = "load" | "swap" | "work-load" | "continue";

export type Decision =
  | { kind: "ok" }
  | { kind: "skip" }
  | { kind: "prompt"; options: Option[]; model: string; loaded: string | null; mode: "work" | "gaming" };

export function decide(status: Status | null, provider: string | undefined, modelId: string | undefined): Decision {
  if (provider !== LOCAL_PROVIDER) return { kind: "skip" };
  if (!status) return { kind: "skip" };
  const model = modelId || status.default || undefined;
  if (!model) return { kind: "skip" };
  const loaded = status.loaded?.id ?? null;
  if (loaded === model) return { kind: "ok" };
  const mode = status.mode === "gaming" ? "gaming" : "work";
  if (mode === "gaming") return { kind: "prompt", options: ["work-load", "continue"], model, loaded, mode };
  if (loaded === null) return { kind: "prompt", options: ["load", "continue"], model, loaded, mode };
  return { kind: "prompt", options: ["swap", "continue"], model, loaded, mode };
}

export function label(option: Option, model: string): string {
  switch (option) {
    case "load": return `Load ${model}`;
    case "swap": return `Swap to ${model}`;
    case "work-load": return `Switch to work mode and load ${model}`;
    case "continue": return "Continue without loading";
  }
}

export type LoadResult = { kind: "loaded" } | { kind: "error"; message: string } | { kind: "timeout" };

// Wait for omamode's load job to finish. Ends on success, on an error, when
// the job stops without loading the model, or at the deadline (the CLI's
// own load cap is 10 minutes), so pi is never blocked forever.
export async function waitForLoad(
  getStatus: () => Promise<Status | null>,
  model: string,
  opts: { intervalMs?: number; deadlineMs?: number; onDetail?: (detail: string) => void } = {},
): Promise<LoadResult> {
  const interval = opts.intervalMs ?? 2000;
  const deadline = Date.now() + (opts.deadlineMs ?? 12 * 60 * 1000);
  let seenBusy = false;
  while (Date.now() < deadline) {
    const s = await getStatus();
    if (!s) return { kind: "error", message: "omamode stopped responding" };
    if (s.loaded?.id === model && s.activity === "idle") return { kind: "loaded" };
    if (s.error) return { kind: "error", message: s.error };
    if (s.activity !== "idle") {
      seenBusy = true;
      if (s.detail && opts.onDetail) opts.onDetail(String(s.detail));
    } else if (seenBusy) {
      return { kind: "error", message: `the load ended without loading ${model}` };
    }
    await new Promise((r) => setTimeout(r, interval));
  }
  return { kind: "timeout" };
}

// Which model pi means to use. Normally pi's current model. At startup, if
// pi's configured default is a local model pi could not find in its cached
// list, pi silently falls back to another model; in that case the configured
// default is what the user wants. A default pi does know but is not using was
// changed on purpose (e.g. --model), so it is left alone.
export function targetModel(
  current: { provider?: string; id?: string } | undefined,
  configured: { provider?: string; model?: string },
  find: (provider: string, id: string) => unknown,
  atStart: boolean,
): { provider?: string; model?: string } {
  if (!current?.provider) return { provider: configured.provider, model: configured.model };
  const fellBack = atStart
    && configured.provider === LOCAL_PROVIDER
    && !!configured.model
    && !(current.provider === configured.provider && current.id === configured.model)
    && !find(LOCAL_PROVIDER, configured.model);
  return fellBack ? { provider: configured.provider, model: configured.model } : { provider: current.provider, model: current.id };
}

// True when two server addresses point at the same host and port (or when
// either is unknown, so a guess never produces a warning).
export function sameServer(a: string | undefined, b: string | undefined): boolean {
  const key = (u: string | undefined) => {
    if (!u) return null;
    try {
      const x = new URL(u);
      const host = x.hostname === "localhost" ? "127.0.0.1" : x.hostname;
      const port = x.port || (x.protocol === "https:" ? "443" : "80");
      return `${host}:${port}`;
    } catch {
      return null;
    }
  };
  const ka = key(a), kb = key(b);
  return ka === null || kb === null || ka === kb;
}

// The server address saved in pi's llama.cpp login (only that field is read;
// never the key). pi uses it before anything else.
function piLlamaUrl(): string | undefined {
  try {
    const auth = JSON.parse(readFileSync(join(homedir(), ".pi", "agent", "auth.json"), "utf8"));
    const url = auth?.[LOCAL_PROVIDER]?.env?.LLAMA_BASE_URL;
    return typeof url === "string" ? url : undefined;
  } catch {
    return undefined;
  }
}

// pi's llama.cpp provider reads its model list from a cache and refreshes it
// only inside /llama, so a model loaded by omamode stays invisible to pi.
// Refresh the list (it shows models the router has loaded), then select the
// model. Returns true when the model was found. Never throws.
export async function syncLoadedModel(pi: { setModel: (m: any) => Promise<boolean> }, ctx: any, model: string): Promise<boolean> {
  const registry = ctx?.modelRegistry;
  if (!registry?.refresh) return false;
  try {
    await registry.refresh({ providers: [LOCAL_PROVIDER], allowNetwork: true, signal: AbortSignal.timeout(15000) });
  } catch {
    return false;
  }
  const m = registry.find?.(LOCAL_PROVIDER, model);
  if (!m) return false;
  if (ctx.model?.provider !== LOCAL_PROVIDER || ctx.model?.id !== model) {
    try { await pi.setModel(m); } catch { /* keep pi usable */ }
  }
  return true;
}

function findOmamode(): string | null {
  const wrapper = join(homedir(), ".local", "bin", "omamode");
  if (existsSync(wrapper)) return wrapper;
  for (const dir of (process.env.PATH ?? "").split(":")) {
    if (dir && existsSync(join(dir, "omamode"))) return join(dir, "omamode");
  }
  return null;
}

// pi's configured default, used when no model is active yet (pi lists
// llama.cpp models only once they are loaded).
function piDefault(): { provider?: string; model?: string } {
  try {
    const s = JSON.parse(readFileSync(join(homedir(), ".pi", "agent", "settings.json"), "utf8"));
    return { provider: s.defaultProvider, model: s.defaultModel };
  } catch {
    return {};
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export default function (pi: ExtensionAPI) {
  let checking = false;
  let noticed = false;
  let warnedServer = false;

  function warnServerMismatch(ctx: any, st: Status | null): void {
    const serverUrl = typeof st?.serverUrl === "string" ? st.serverUrl : undefined;
    const piUrl = piLlamaUrl();
    if (warnedServer || sameServer(piUrl, serverUrl)) return;
    warnedServer = true;
    const msg = `omamode: pi's llama.cpp login points at ${piUrl}, but llama-server runs at ${serverUrl}. `
      + `In pi, run /login llama.cpp and enter ${serverUrl}.`;
    if (ctx.hasUI) ctx.ui.notify(msg, "warning");
    else console.error(msg);
  }

  async function status(cli: string): Promise<Status | null> {
    const r = await pi.exec(cli, ["status", "--json"], { timeout: 5000 });
    if (r.code !== 0) return null;
    try {
      return JSON.parse(r.stdout) as Status;
    } catch {
      return null;
    }
  }

  async function check(ctx: any, atStart: boolean): Promise<void> {
    if (checking) return;
    checking = true;
    try {
      const cli = findOmamode();
      if (!cli) return;
      const target = targetModel(ctx.model, piDefault(),
        (prov, id) => ctx.modelRegistry?.find?.(prov, id), atStart);
      const provider = target.provider;
      const modelId = target.model;
      const st = await status(cli);
      const d = decide(st, provider, modelId);
      if (provider === LOCAL_PROVIDER && st) warnServerMismatch(ctx, st);
      // pi's model is loaded: make sure pi's list has it (at startup, or when
      // pi could not select it yet).
      if (d.kind === "ok") {
        const loadedId = st?.loaded?.id;
        if (loadedId && (atStart || ctx.model?.provider !== LOCAL_PROVIDER || ctx.model?.id !== loadedId)) {
          await syncLoadedModel(pi, ctx, loadedId);
        }
        return;
      }
      if (d.kind !== "prompt") return;

      if (!ctx.hasUI) {
        if (!noticed) console.error(`omamode: ${d.model} is not loaded on the local llama.cpp server`);
        noticed = true;
        return;
      }
      const labels = d.options.map((o) => label(o, d.model));
      const title = d.mode === "gaming"
        ? `Gaming mode is on, so the local model ${d.model} is not loaded.`
        : d.loaded
          ? `pi uses ${d.model}, but ${d.loaded} is loaded.`
          : `The local model ${d.model} is not loaded.`;
      const choice = await ctx.ui.select(title, labels);
      const picked = d.options[labels.indexOf(choice)];
      if (!picked || picked === "continue") return;

      ctx.ui.setStatus("omamode", `Loading ${d.model}…`);
      if (picked === "work-load") {
        const w = await pi.exec(cli, ["work"], { timeout: 60000 });
        if (w.code !== 0) {
          ctx.ui.notify(`omamode: ${(w.stderr || w.stdout).trim() || "could not switch to work mode"}`, "error");
          return;
        }
        // Wait for the work-mode job (closing Steam) to finish.
        for (let i = 0; i < 40; i++) {
          const s = await status(cli);
          if (s && s.mode === "work" && s.activity === "idle") break;
          await sleep(1000);
        }
      }
      const r = await pi.exec(cli, ["load", d.model], { timeout: 15000 });
      if (r.code !== 0) {
        ctx.ui.notify(`omamode: ${(r.stderr || r.stdout).trim() || "could not load the model"}`, "error");
        return;
      }
      const res = await waitForLoad(() => status(cli), d.model, {
        onDetail: (detail) => ctx.ui.setStatus("omamode", detail),
      });
      if (res.kind === "loaded") {
        const found = await syncLoadedModel(pi, ctx, d.model);
        ctx.ui.notify(found
          ? `omamode: ${d.model} is loaded`
          : `omamode: ${d.model} is loaded; select it with /model if pi has not switched`, "info");
      } else if (res.kind === "error") {
        ctx.ui.notify(`omamode: ${res.message}`, "error");
      } else {
        ctx.ui.notify(`omamode: ${d.model} did not finish loading; check the omamode panel`, "error");
      }
    } catch (err) {
      try { ctx.ui?.notify?.(`omamode: ${String(err)}`, "error"); } catch { /* never break pi */ }
    } finally {
      try { ctx.ui?.setStatus?.("omamode", undefined); } catch { /* ignore */ }
      checking = false;
    }
  }

  pi.on("session_start", async (_event, ctx) => { await check(ctx, true); });
  pi.on("before_agent_start", async (_event, ctx) => { await check(ctx, false); });
}
