import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fallbackAdaptedContent } from "../lib/fallbacks.js";
import { generateAdaptedContent } from "../lib/openai.js";
import { adaptContentRequestSchema } from "../lib/schemas.js";
import { secureEndpoint } from "../lib/security.js";

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!secureEndpoint(req, res)) return;
  const parsed = adaptContentRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "invalid_request" });
    return;
  }
  try {
    res.status(200).json(await generateAdaptedContent(parsed.data));
  } catch {
    res.status(200).json(fallbackAdaptedContent(parsed.data));
  }
}
