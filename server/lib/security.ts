import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";

const requestLog = new Map<string, number[]>();
const WINDOW_MS = 60_000;
const MAX_REQUESTS_PER_WINDOW = 30;

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

export function enforceRateLimit(req: VercelRequest, res: VercelResponse): boolean {
  const forwarded = req.headers["x-forwarded-for"];
  const ip = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(",")[0]?.trim() ?? "unknown";
  const now = Date.now();
  const recent = (requestLog.get(ip) ?? []).filter((timestamp) => now - timestamp < WINDOW_MS);
  if (recent.length >= MAX_REQUESTS_PER_WINDOW) {
    res.setHeader("Retry-After", "60");
    res.status(429).json({ error: "rate_limited" });
    return false;
  }
  recent.push(now);
  requestLog.set(ip, recent);
  return true;
}

export function secureEndpoint(req: VercelRequest, res: VercelResponse): boolean {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  return requirePost(req, res) && authenticate(req, res) && enforceRateLimit(req, res);
}
