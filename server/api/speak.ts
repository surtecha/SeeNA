import type { VercelRequest, VercelResponse } from "@vercel/node";
import { z } from "zod";
import { openAIClient } from "../lib/openai.js";
import { chargeProviderBudget, secureEndpoint } from "../lib/security.js";

const requestSchema = z.object({
  text: z.string().trim().min(1).max(360),
  locale: z.string().min(2).max(20).default("en-AU")
}).strict();

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!await secureEndpoint(req, res, "speak")) return;
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    const input = requestSchema.parse(req.body);
    if (!await chargeProviderBudget(res, "speak")) return;
    const speech = await openAIClient().audio.speech.create({
      model: process.env.OPENAI_TTS_MODEL ?? "gpt-4o-mini-tts",
      voice: "marin",
      input: input.text,
      instructions: [
        "Speak as a warm adult female guide.",
        input.locale.toLowerCase().startsWith("en-au")
          ? "Use a natural, light Australian English accent."
          : "Use natural conversational English.",
        "Sound calm, friendly, and human, never theatrical or robotic.",
        "Use a brisk conversational pace with short natural pauses."
      ].join(" "),
      response_format: "wav"
    });

    const audio = Buffer.from(await speech.arrayBuffer());
    res.setHeader("Content-Type", "audio/wav");
    res.setHeader("Cache-Control", "private, max-age=86400");
    res.status(200).send(audio);
  } catch (error) {
    const status = error instanceof z.ZodError ? 400 : 502;
    res.status(status).json({ error: status === 400 ? "invalid_request" : "speech_unavailable" });
  }
}
