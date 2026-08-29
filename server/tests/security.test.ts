import { afterEach, describe, expect, it, vi } from "vitest";
import { PassThrough } from "node:stream";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import speak from "../api/speak.js";
import transcribeBlock from "../api/transcribe-block.js";
import {
  chargeProviderBudget,
  durableQuotaConfiguration,
  enforceRateLimit,
  requestBodyIsWithinLimit
} from "../lib/security.js";

function request(ip: string, contentLength?: number, body?: unknown): VercelRequest {
  return {
    headers: {
      "x-forwarded-for": ip,
      ...(contentLength === undefined ? {} : { "content-length": String(contentLength) })
    },
    body
  } as unknown as VercelRequest;
}

function response() {
  const result = { statusCode: 200, body: undefined as unknown };
  const value = {
    setHeader: () => value,
    status(code: number) {
      result.statusCode = code;
      return value;
    },
    json(body: unknown) {
      result.body = body;
      return value;
    }
  } as unknown as VercelResponse;
  return { value, result };
}

function multipartRequest(body: Buffer, boundary: string): VercelRequest {
  const stream = new PassThrough();
  Object.assign(stream, {
    method: "POST",
    headers: {
      "x-forwarded-for": `multipart-${Date.now()}`,
      "x-seena-app-token": "test-token",
      "transfer-encoding": "chunked",
      "content-type": `multipart/form-data; boundary=${boundary}`
    }
  });
  stream.end(body);
  return stream as unknown as VercelRequest;
}

afterEach(() => {
  vi.unstubAllGlobals();
  delete process.env.SEENA_KV_REST_API_URL;
  delete process.env.SEENA_KV_REST_API_TOKEN;
  delete process.env.SEENA_DAILY_COST_UNIT_LIMIT;
  delete process.env.SEENA_DEPLOYMENT_MODE;
  delete process.env.SEENA_APP_TOKEN;
});

describe("endpoint abuse controls", () => {
  it("rejects a request larger than its endpoint budget", async () => {
    const res = response();
    expect(await enforceRateLimit(request("size-case", 2_001), res.value, "speak")).toBe(false);
    expect(res.result.statusCode).toBe(413);
  });

  it("applies endpoint-specific request ceilings", async () => {
    const ip = `adapt-${Date.now()}`;
    for (let index = 0; index < 6; index += 1) {
      expect(await enforceRateLimit(request(ip, 200), response().value, "adapt")).toBe(true);
    }
    const blocked = response();
    expect(await enforceRateLimit(request(ip, 200), blocked.value, "adapt")).toBe(false);
    expect(blocked.result.statusCode).toBe(429);
  });

  it("uses the parsed JSON size when Content-Length is missing or dishonest", () => {
    const largeBody = { text: "x".repeat(2_100) };
    expect(requestBodyIsWithinLimit(request("body-case", undefined, largeBody), "speak")).toBe(false);
    expect(requestBodyIsWithinLimit(request("body-case", 1, largeBody), "speak")).toBe(false);
    expect(requestBodyIsWithinLimit(request("body-case", undefined, { text: "ok" }), "speak")).toBe(true);
  });

  it("treats quota configuration as atomic and does not charge it during gateway checks", async () => {
    process.env.SEENA_KV_REST_API_URL = "https://quota.invalid";
    expect(durableQuotaConfiguration().kind).toBe("invalid");

    const gateway = response();
    expect(await enforceRateLimit(request("partial-config", 200, { value: "valid" }), gateway.value, "explain")).toBe(true);
    expect(gateway.result.statusCode).toBe(200);

    const charged = response();
    expect(await chargeProviderBudget(charged.value, "explain")).toBe(false);
    expect(charged.result.statusCode).toBe(503);
  });

  it("requires durable quota outside an explicit local-development mode", async () => {
    expect(durableQuotaConfiguration().kind).toBe("invalid");
    const publicDeployment = response();
    expect(await chargeProviderBudget(publicDeployment.value, "explain")).toBe(false);
    expect(publicDeployment.result.statusCode).toBe(503);

    process.env.SEENA_DEPLOYMENT_MODE = "local-development";
    expect(durableQuotaConfiguration().kind).toBe("disabled");
    expect(await chargeProviderBudget(response().value, "explain")).toBe(true);
  });

  it("charges the endpoint-specific provider cost only at the provider boundary", async () => {
    process.env.SEENA_KV_REST_API_URL = "https://quota.example";
    process.env.SEENA_KV_REST_API_TOKEN = "token";
    process.env.SEENA_DAILY_COST_UNIT_LIMIT = "100";
    const calls: string[] = [];
    vi.stubGlobal("fetch", vi.fn(async (_url: string, init?: RequestInit) => {
      calls.push(String(init?.body));
      return new Response(JSON.stringify({ result: 6 }), { status: 200 });
    }));

    const res = response();
    expect(await chargeProviderBudget(res.value, "speak")).toBe(true);
    expect(calls[0]).toContain("INCRBY");
    expect(calls[0]).toContain(",6]");
  });

  it("normalizes a quota-store outage to 503 at an endpoint before provider access", async () => {
    process.env.SEENA_APP_TOKEN = "test-token";
    process.env.SEENA_KV_REST_API_URL = "https://quota.example";
    process.env.SEENA_KV_REST_API_TOKEN = "token";
    process.env.SEENA_DAILY_COST_UNIT_LIMIT = "100";
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("store unavailable"); }));
    const res = response();
    const req = {
      method: "POST",
      headers: {
        "x-forwarded-for": `quota-${Date.now()}`,
        "x-seena-app-token": "test-token",
        "content-length": "30"
      },
      body: { text: "Hello", locale: "en-AU" }
    } as unknown as VercelRequest;

    await speak(req, res.value);
    expect(res.result.statusCode).toBe(503);
    expect(res.result.body).toEqual({ error: "quota_unavailable_or_exhausted" });
  });

  it("returns 413 for a chunked multipart file over Formidable's total limit", async () => {
    process.env.SEENA_APP_TOKEN = "test-token";
    const boundary = "----seena-limit";
    const body = Buffer.concat([
      Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="mode"\r\n\r\nsingleDirection\r\n--${boundary}\r\nContent-Disposition: form-data; name="locale"\r\n\r\nen-AU\r\n--${boundary}\r\nContent-Disposition: form-data; name="audio"; filename="sample.m4a"\r\nContent-Type: audio/m4a\r\n\r\n`),
      Buffer.alloc(5 * 1024 * 1024 + 1, 1),
      Buffer.from(`\r\n--${boundary}--\r\n`)
    ]);
    const res = response();

    await transcribeBlock(multipartRequest(body, boundary), res.value);
    expect(res.result.statusCode).toBe(413);
    expect(res.result.body).toEqual({ error: "request_too_large" });
  });
});
