// Local Pi adapter fix for context-mode 1.0.169. Installed by Nix, not npm.
import { stripVTControlCharacters } from "node:util";
import { Text } from "@earendil-works/pi-tui";

// Arguments are untrusted terminal text, not ANSI instructions.
const clean = value => stripVTControlCharacters(String(value ?? ""))
  .replace(/\r\n?/g, "\n").replace(/[\x00-\x08\x0b-\x1f\x7f]/g, "");

function submitted(args) {
  const lines = [];
  if (args.cwd) lines.push(`cwd: ${clean(args.cwd)}`);
  if (args.path) lines.push(`path: ${clean(args.path)}`);
  if (args.intent) lines.push(`intent: ${clean(args.intent)}`);
  if (typeof args.code === "string") lines.push(clean(args.code));
  else if (Array.isArray(args.commands)) {
    for (const [index, item] of args.commands.entries()) {
      lines.push(`${index + 1}. ${clean(item.label || "Command")}`, clean(item.command));
    }
  } else {
    for (const [key, value] of Object.entries(args)) {
      if (["cwd", "path", "intent", "language"].includes(key)) continue;
      lines.push(`${clean(key)}: ${clean(typeof value === "string" ? value : JSON.stringify(value))}`);
    }
  }
  return lines.join("\n").split("\n");
}

export function createContextModeCallRenderer(toolName) {
  return (args, theme, context) => {
    const params = args ?? {};
    const heading = toolName + (params.language ? ` · ${clean(params.language)}` : "");
    const lines = submitted(params);
    // Always show arguments before a result exists. Expansion controls arguments
    // as well as output. Text wraps instead of silently clipping long commands.
    const visible = context.expanded ? lines : lines.slice(0, 4);
    const hidden = lines.length - visible.length;
    const body = visible.map(line => theme.fg("toolOutput", line));
    if (hidden) body.push(theme.fg("muted", `… ${hidden} more lines (expand tools to view)`));
    const component = context.lastComponent instanceof Text ? context.lastComponent : new Text("", 0, 0);
    component.setText([theme.fg("toolTitle", theme.bold(heading)), ...body].join("\n"));
    return component;
  };
}

export function createContextModeResultRenderer(toolName) {
  return (result, { expanded, isPartial }, theme, context) => {
    const component = context.lastComponent instanceof Text ? context.lastComponent : new Text("", 0, 0);
    if (isPartial) {
      const elapsed = Math.floor((result.details?.elapsedMs ?? 0) / 1000);
      component.setText(theme.fg("warning", `Running · ${elapsed}s · waiting for result`));
      return component;
    }
    const output = (result.content ?? []).filter(c => c?.type === "text")
      .map(c => clean(c.text)).join("\n");
    const first = output.split("\n").find(line => line.trim())?.trim();
    const status = first && first.length <= 180 ? first : `${toolName} completed`;
    component.setText(theme.fg(context.isError ? "error" : "toolOutput", expanded ? output : status));
    return component;
  };
}

// Heartbeats carry only UI metadata. No stdout streaming, transcript messages,
// guessed subprocess status, or changes to context-mode's compressed results.
export function createContextModeExecutor(toolName, callTool) {
  return async (_toolCallId, params, signal, onUpdate) => {
    const started = Date.now();
    let timer;
    const stop = () => { clearInterval(timer); timer = undefined; };
    const update = () => onUpdate?.({ content: [], details: { elapsedMs: Date.now() - started } });
    try {
      signal?.throwIfAborted();
      if (onUpdate) {
        update();
        timer = setInterval(() => {
          // A disposed UI must not cause an uncaught timer exception.
          try { update(); } catch { stop(); }
        }, 1000);
        timer.unref?.();
        signal?.addEventListener("abort", stop, { once: true });
      }
      // Preserve the upstream bridge's cancellation/timeout semantics. Stopping
      // a heartbeat does NOT claim that a remote subprocess has been killed.
      const result = await callTool(toolName, params ?? {});
      const text = (result.content ?? []).filter(c => c?.type === "text" && typeof c.text === "string")
        .map(c => c.text).join("\n");
      if (result.isError) throw new Error(text || `${toolName} returned an error`);
      return { content: [{ type: "text", text }], details: {} };
    } finally {
      stop();
      signal?.removeEventListener("abort", stop);
    }
  };
}
