import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fallbackAdaptedContent } from "../lib/fallbacks.js";
import { generateAdaptedContent } from "../lib/openai.js";
import { adaptContentRequestSchema } from "../lib/schemas.js";
import { chargeProviderBudget, secureEndpoint } from "../lib/security.js";

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!await secureEndpoint(req, res, "adapt")) return;
  const parsed = adaptContentRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_request" });
    return;
  }
  if (!await chargeProviderBudget(res, "adapt")) return;
  try {
    res.status(200).json(await generateAdaptedContent(parsed.data));
  } catch {
    res.status(200).json(fallbackAdaptedContent(parsed.data));
  }
}
