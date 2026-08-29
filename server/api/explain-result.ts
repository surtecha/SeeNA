import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fallbackExplanation } from "../lib/fallbacks.js";
import { generateExplanation } from "../lib/openai.js";
import { explanationRequestSchema } from "../lib/schemas.js";
import { chargeProviderBudget, secureEndpoint } from "../lib/security.js";

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!await secureEndpoint(req, res, "explain")) return;
  const parsed = explanationRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_request" });
    return;
  }
  if (!await chargeProviderBudget(res, "explain")) return;
  try {
    res.status(200).json(await generateExplanation(parsed.data));
  } catch {
    res.status(200).json(fallbackExplanation(parsed.data));
  }
}
