import { readFileSync } from "node:fs";

type SessionContext = {
  sessionManager?: {
    getSessionId?: () => unknown;
    getSessionFile?: () => unknown;
  };
};

type ExtensionApi = {
  on: (
    event: string,
    handler: (payload: unknown, context: SessionContext) => void | Promise<void>,
  ) => void;
};

type HookCoordinates = {
  port: string;
  token: string;
  environment: string;
  version: string;
};

const HOOK_TIMEOUT_MS = 1000;
let warned = false;

function warnOnce(message: string): void {
  if (warned) return;
  warned = true;
  console.warn(`[orca-omp-status] ${message}`);
}

function readHookCoordinates(): HookCoordinates | null {
  const values: Record<string, string | undefined> = {
    ORCA_AGENT_HOOK_PORT: process.env.ORCA_AGENT_HOOK_PORT,
    ORCA_AGENT_HOOK_TOKEN: process.env.ORCA_AGENT_HOOK_TOKEN,
    ORCA_AGENT_HOOK_ENV: process.env.ORCA_AGENT_HOOK_ENV,
    ORCA_AGENT_HOOK_VERSION: process.env.ORCA_AGENT_HOOK_VERSION,
  };
  const endpoint = process.env.ORCA_AGENT_HOOK_ENDPOINT;
  if (endpoint) {
    try {
      for (const line of readFileSync(endpoint, "utf8").split(/\r?\n/)) {
        const match = line.match(/^(?:set\s+)?([A-Z0-9_]+)=(.*)$/);
        if (match) values[match[1]] = match[2].replace(/\r$/, "");
      }
    } catch (error) {
      warnOnce(`endpoint read failed: ${String(error)}`);
    }
  }

  const port = values.ORCA_AGENT_HOOK_PORT;
  const token = values.ORCA_AGENT_HOOK_TOKEN;
  if (!port || !token) return null;
  return {
    port,
    token,
    environment: values.ORCA_AGENT_HOOK_ENV ?? "",
    version: values.ORCA_AGENT_HOOK_VERSION ?? "",
  };
}

function sessionMetadata(context: SessionContext): Record<string, string> {
  const id = context.sessionManager?.getSessionId?.();
  const file = context.sessionManager?.getSessionFile?.();
  const metadata: Record<string, string> = {};
  if (typeof id === "string" && id) metadata.session_id = id;
  if (typeof file === "string" && file) metadata.session_file = file;
  return metadata;
}

async function postStatus(
  eventName: string,
  context: SessionContext,
  extra: Record<string, unknown> = {},
): Promise<void> {
  const coordinates = readHookCoordinates();
  const paneKey = process.env.ORCA_PANE_KEY;
  if (!coordinates || !paneKey) return;

  try {
    const response = await fetch(`http://127.0.0.1:${coordinates.port}/hook/omp`, {
      method: "POST",
      signal: AbortSignal.timeout(HOOK_TIMEOUT_MS),
      headers: {
        "Content-Type": "application/json",
        "X-Orca-Agent-Hook-Token": coordinates.token,
      },
      body: JSON.stringify({
        paneKey,
        launchToken: process.env.ORCA_AGENT_LAUNCH_TOKEN ?? "",
        tabId: process.env.ORCA_TAB_ID ?? "",
        worktreeId: process.env.ORCA_WORKTREE_ID ?? "",
        env: coordinates.environment,
        version: coordinates.version,
        payload: {
          hook_event_name: eventName,
          ...sessionMetadata(context),
          ...extra,
        },
      }),
    });
    if (!response.ok) warnOnce(`hook returned HTTP ${response.status}`);
  } catch (error) {
    warnOnce(`delivery failed: ${String(error)}`);
  }
}

function assistantText(payload: unknown): string {
  if (!payload || typeof payload !== "object" || !("message" in payload)) return "";
  const message = payload.message;
  if (
    !message ||
    typeof message !== "object" ||
    !("role" in message) ||
    message.role !== "assistant" ||
    !("content" in message) ||
    !Array.isArray(message.content)
  ) {
    return "";
  }

  return message.content
    .filter(
      (part): part is { type: "text"; text: string } =>
        Boolean(part) &&
        typeof part === "object" &&
        "type" in part &&
        part.type === "text" &&
        "text" in part &&
        typeof part.text === "string",
    )
    .map((part) => part.text)
    .join("\n");
}

export default function register(api: ExtensionApi): void {
  const ownerPid = process.env.ORCA_PI_STATUS_OWNED;
  const selfPid = String(process.pid);
  if (ownerPid && ownerPid !== selfPid) return;
  process.env.ORCA_PI_STATUS_OWNED = selfPid;

  // Orca can route a new chat tab before its terminal pane has mounted. Emit
  // an idle status as soon as OMP creates the provider session so the renderer
  // gets a second, authoritative chance to attach the chat overlay.
  api.on("session_start", async (_payload, context) => {
    await postStatus("agent_end", context);
  });

  api.on("before_agent_start", async (payload, context) => {
    const prompt =
      payload &&
      typeof payload === "object" &&
      "prompt" in payload &&
      typeof payload.prompt === "string"
        ? payload.prompt
        : "";
    await postStatus("before_agent_start", context, { prompt });
  });

  api.on("agent_start", async (_payload, context) => {
    await postStatus("agent_start", context);
  });

  api.on("message_end", async (payload, context) => {
    const text = assistantText(payload);
    if (text) await postStatus("message_end", context, { role: "assistant", text });
  });

  api.on("agent_end", async (_payload, context) => {
    await postStatus("agent_end", context);
  });
}
