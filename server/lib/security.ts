import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";

export type Endpoint = "speak" | "transcribe" | "explain";

const requestLog = new Map<string, { timestamp: number; cost: number }[]>();
const WINDOW_MS = 60_000;
const endpointPolicy: Record<Endpoint, { requests: number; cost: number; maxBytes: number }> = {
  speak: { requests: 12, cost: 6, maxBytes: 2_000 },
  transcribe: { requests: 18, cost: 4, maxBytes: 5_300_000 },
  explain: { requests: 8, cost: 2, maxBytes: 4_000 }
};
const MAX_COST_PER_MINUTE = 72;

export function requirePost(req: VercelRequest, res: VercelResponse): boolean {
  if (req.method === "POST") return true;
  res.setHeader("Allow", "POST");
  res.status(405).json({ error: "method_not_allowed" });
  return false;
}

export function authenticate(req: VercelRequest, res: VercelResponse): boolean {
  const expected = process.env.SEENA_APP_TOKEN;
  const suppliedHeader = req.headers["x-seena-app-token"];
  const supplied = Array.isArray(suppliedHeader) ? suppliedHeader[0] : suppliedHeader;
  if (!expected || !supplied) {
    res.status(401).json({ error: "unauthorized" });
    return false;
  }
  const expectedBuffer = Buffer.from(expected);
  const suppliedBuffer = Buffer.from(supplied);
  const valid = expectedBuffer.length === suppliedBuffer.length
    && timingSafeEqual(expectedBuffer, suppliedBuffer);
  if (!valid) res.status(401).json({ error: "unauthorized" });
  return valid;
}

type DurableQuotaConfiguration =
  | { kind: "disabled" }
  | { kind: "invalid" }
  | { kind: "configured"; url: string; token: string; maximum: number };

/**
 * Internet-facing deployments must use the durable provider-spend guardrail.
 * The only disabled mode is an explicit local-development opt-in.
 */
export function durableQuotaConfiguration(): DurableQuotaConfiguration {
  const url = process.env.SEENA_KV_REST_API_URL;
  const token = process.env.SEENA_KV_REST_API_TOKEN;
  const maximumRaw = process.env.SEENA_DAILY_COST_UNIT_LIMIT;
  const values = [url, token, maximumRaw].map((value) => value?.trim() ?? "");
  const localDevelopment = process.env.SEENA_DEPLOYMENT_MODE === "local-development";
  if (values.every((value) => value.length === 0)) {
    return localDevelopment ? { kind: "disabled" } : { kind: "invalid" };
  }
  if (values.some((value) => value.length === 0)) return { kind: "invalid" };
  const maximum = Number(maximumRaw);
  if (!Number.isSafeInteger(maximum) || maximum <= 0) return { kind: "invalid" };
  return { kind: "configured", url: url!.trim(), token: token!.trim(), maximum };
}

async function enforceDurableDailyQuota(key: string, cost: number): Promise<boolean> {
  const configuration = durableQuotaConfiguration();
  if (configuration.kind === "disabled") return true;
  if (configuration.kind === "invalid") return false;

  try {
    const day = new Date().toISOString().slice(0, 10);
    const quotaKey = `seena:quota:${day}:${key}`;
    const response = await fetch(configuration.url, {
      method: "POST",
      headers: { Authorization: `Bearer ${configuration.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(["INCRBY", quotaKey, cost])
    });
    if (!response.ok) return false;
    const payload = await response.json() as { result?: number };
    const total = Number(payload.result);
    if (total === cost) {
      void fetch(configuration.url, {
        method: "POST",
        headers: { Authorization: `Bearer ${configuration.token}`, "Content-Type": "application/json" },
        body: JSON.stringify(["EXPIRE", quotaKey, 172800])
      }).catch(() => undefined);
    }
    return Number.isFinite(total) && total <= configuration.maximum;
  } catch {
    // A quota store outage must fail closed as a documented 503, not leak as a
    // provider-specific 500/502 from whichever endpoint attempted the charge.
    return false;
  }
}

function parsedBodySize(req: VercelRequest): number | null {
  const body = req.body;
  if (body === undefined || body === null) return 0;
  if (Buffer.isBuffer(body)) return body.byteLength;
  if (typeof body === "string") return Buffer.byteLength(body);
  try {
    return Buffer.byteLength(JSON.stringify(body));
  } catch {
    return null;
  }
}

/**
 * JSON endpoints are bounded from their parsed body even if Content-Length is
 * missing or false. Multipart transcription is bounded by formidable's total
 * file and field limits after this gateway check.
 */
export function requestBodyIsWithinLimit(req: VercelRequest, endpoint: Endpoint): boolean {
  const policy = endpointPolicy[endpoint];
  const lengthHeader = req.headers["content-length"];
  const rawLength = Array.isArray(lengthHeader) ? lengthHeader[0] : lengthHeader;
  if (rawLength !== undefined) {
    if (!/^\d+$/.test(rawLength) || Number(rawLength) > policy.maxBytes) return false;
  }
  if (endpoint === "transcribe") return true;
  const actualSize = parsedBodySize(req);
  return actualSize !== null && actualSize <= policy.maxBytes;
}

export async function enforceRateLimit(
  req: VercelRequest,
  res: VercelResponse,
  endpoint: Endpoint
): Promise<boolean> {
  const forwarded = req.headers["x-forwarded-for"];
  const ip = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(",")[0]?.trim() ?? "unknown";
  const now = Date.now();
  const policy = endpointPolicy[endpoint];
  const key = `${endpoint}:${ip}`;
  const recent = (requestLog.get(key) ?? []).filter((entry) => now - entry.timestamp < WINDOW_MS);
  const totalCost = recent.reduce((sum, entry) => sum + entry.cost, 0);
  if (recent.length >= policy.requests || totalCost + policy.cost > MAX_COST_PER_MINUTE) {
    res.setHeader("Retry-After", "60");
    res.status(429).json({ error: "rate_limited" });
    return false;
  }
  if (!requestBodyIsWithinLimit(req, endpoint)) {
    res.status(413).json({ error: "request_too_large" });
    return false;
  }
  recent.push({ timestamp: now, cost: policy.cost });
  requestLog.set(key, recent);
  return true;
}

/** Charge only after schema validation and immediately before a provider call. */
export async function chargeProviderBudget(res: VercelResponse, endpoint: Endpoint): Promise<boolean> {
  const policy = endpointPolicy[endpoint];
  // Global key prevents distribution across endpoints or source IPs from
  // bypassing the configured provider-spend ceiling.
  if (await enforceDurableDailyQuota("global", policy.cost)) return true;
  res.status(503).json({ error: "quota_unavailable_or_exhausted" });
  return false;
}

export async function secureEndpoint(
  req: VercelRequest,
  res: VercelResponse,
  endpoint: Endpoint
): Promise<boolean> {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  return requirePost(req, res)
    && authenticate(req, res)
    && await enforceRateLimit(req, res, endpoint);
}
