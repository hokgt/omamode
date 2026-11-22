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

  async function status(cli: string): Promise<Status | null> {
    const r = await pi.exec(cli, ["status", "--json"], { timeout: 5000 });
    if (r.code !== 0) return null;
    try {
      return JSON.parse(r.stdout) as Status;
    } catch {
      return null;
    }
  }

  async function check(ctx: any): Promise<void> {
    if (checking) return;
    checking = true;
    try {
      const cli = findOmamode();
      if (!cli) return;
      const fallback = piDefault();
      const provider = ctx.model?.provider ?? fallback.provider;
      const modelId = ctx.model?.provider ? ctx.model?.id : fallback.model;
      const st = await status(cli);
      const d = decide(st, provider, modelId);
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
      for (;;) {
        await sleep(2000);
        const s = await status(cli);
        if (!s) break;
        if (s.loaded?.id === d.model && s.activity === "idle") {
          const m = ctx.modelRegistry?.find?.(LOCAL_PROVIDER, d.model);
          if (m && ctx.model?.id !== d.model) await pi.setModel(m);
          ctx.ui.notify(`omamode: ${d.model} is loaded`, "info");
          break;
        }
        if (s.error) {
          ctx.ui.notify(`omamode: ${s.error}`, "error");
          break;
        }
        if (s.detail) ctx.ui.setStatus("omamode", s.detail);
      }
    } catch (err) {
      try { ctx.ui?.notify?.(`omamode: ${String(err)}`, "error"); } catch { /* never break pi */ }
    } finally {
      try { ctx.ui?.setStatus?.("omamode", undefined); } catch { /* ignore */ }
      checking = false;
    }
  }

  pi.on("session_start", async (_event, ctx) => { await check(ctx); });
  pi.on("before_agent_start", async (_event, ctx) => { await check(ctx); });
}
