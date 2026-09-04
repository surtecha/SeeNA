import { createReadStream } from "node:fs";
import { unlink } from "node:fs/promises";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import formidable, { type Fields, type Files } from "formidable";
import { z } from "zod";
import {
  parseChoice,
  parseSingleDirectionAnswer,
  type ChoiceSetID
} from "../lib/direction-parser.js";
import { openAIClient } from "../lib/openai.js";
import { chargeProviderBudget, secureEndpoint } from "../lib/security.js";

export const config = { api: { bodyParser: false } };

const metadataSchema = z.object({
  mode: z.enum(["singleDirection", "constrainedChoice"]),
  locale: z.string().min(2).max(20),
  phraseId: z.string().max(80).optional(),
  choiceSetId: z.enum(["contrast", "controls", "readAloud", "simplified", "eligibility"]).optional()
}).strict();

function first(fields: Fields, name: string): string | undefined {
  const value = fields[name];
  return Array.isArray(value) ? value[0] : value;
}

function isPayloadTooLarge(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  const details = error as { code?: unknown; httpCode?: unknown };
  if (Number(details.httpCode) === 413) return true;
  // Formidable 3.5.4 uses numeric codes for its size and count limits.
  return [1006, 1007, 1009, 1015, 1016].includes(Number(details.code));
}

export function singleDirectionPrompt(phraseId?: string): string {
  if (phraseId === "gabor-single") {
    return [
      "A speaker gives one answer about a striped circle: left, right, or a natural phrase saying the target is not visible.",
      "Transcribe the short phrase faithfully. Do not guess a direction and do not turn uncertainty into an answer."
    ].join(" ");
  }
  return [
    "A speaker gives one Landolt C opening direction: up, right, down, left, or a natural phrase saying the target is not visible.",
    "Transcribe the short phrase faithfully. Do not guess a direction and do not turn uncertainty into an answer."
  ].join(" ");
}

export function constrainedChoicePrompt(choiceSetId?: ChoiceSetID): string {
  switch (choiceSetId) {
    case "eligibility":
      return "A speaker answers one safety question with yes, no, or a brief natural phrase such as none apply or one applies. Transcribe faithfully. Do not infer an answer.";
    case "contrast":
    case "simplified":
      return "A speaker chooses one or two. Transcribe the short answer faithfully. Do not infer a choice.";
    case "controls":
      return "A speaker chooses standard or larger. Transcribe the short answer faithfully. Do not infer a choice.";
    case "readAloud":
      return "A speaker answers yes or no. Transcribe the short answer faithfully. Do not infer an answer.";
    default:
      return "Transcribe the short answer faithfully. Do not infer a choice.";
  }
}

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!await secureEndpoint(req, res, "transcribe")) return;
  const form = formidable({
    allowEmptyFiles: false,
    maxFiles: 1,
    maxFileSize: 5 * 1024 * 1024,
    maxTotalFileSize: 5 * 1024 * 1024,
    maxFieldsSize: 256 * 1024,
    maxFields: 8,
    multiples: false,
    keepExtensions: true,
    filter: ({ mimetype }) => ["audio/mp4", "audio/m4a", "audio/x-m4a"].includes(mimetype ?? "")
  });

  let files: Files = {};
  try {
    const parsedForm = await form.parse(req);
    const fields = parsedForm[0];
    files = parsedForm[1];
    const metadata = metadataSchema.parse({
      mode: first(fields, "mode"),
      locale: first(fields, "locale") ?? "en-AU",
      phraseId: first(fields, "phraseId"),
      choiceSetId: first(fields, "choiceSetId")
    });
    const audioValue = files.audio;
    const audio = Array.isArray(audioValue) ? audioValue[0] : audioValue;
    if (!audio) {
      res.status(400).json({ error: "invalid_audio" });
      return;
    }

    if (!await chargeProviderBudget(res, "transcribe")) return;

    const transcription = await openAIClient().audio.transcriptions.create({
      file: createReadStream(audio.filepath),
      model: process.env.OPENAI_TRANSCRIBE_MODEL ?? "gpt-transcribe",
      stream: false,
      ...(metadata.locale.toLowerCase().startsWith("en") ? { language: "en" } : {}),
      ...(metadata.mode === "singleDirection"
        ? {
            prompt: singleDirectionPrompt(metadata.phraseId)
          }
        : metadata.mode === "constrainedChoice"
          ? { prompt: constrainedChoicePrompt(metadata.choiceSetId) }
          : {})
    });
    const transcript = transcription.text.trim();

    if (metadata.mode === "singleDirection") {
      const answer = parseSingleDirectionAnswer(transcript);
      if (answer?.kind === "direction") {
        res.status(200).json({
          valid: true,
          mode: metadata.mode,
          transcript,
          directions: [answer.direction],
          choice: null,
          failureReason: null
        });
        return;
      }
      if (answer?.kind === "notVisible") {
        res.status(200).json({
          valid: true,
          mode: metadata.mode,
          transcript,
          directions: null,
          choice: "notVisible",
          failureReason: null
        });
        return;
      }
      res.status(200).json({
        valid: false,
        mode: metadata.mode,
        transcript,
        directions: null,
        choice: null,
        failureReason: "exactly_one_direction_required"
      });
      return;
    }

    if (metadata.mode === "constrainedChoice") {
      if (!metadata.choiceSetId) {
        res.status(400).json({ error: "choice_set_required" });
        return;
      }
      const choice = parseChoice(transcript, metadata.choiceSetId as ChoiceSetID);
      res.status(200).json({
        valid: choice !== null,
        mode: metadata.mode,
        transcript,
        directions: null,
        choice,
        failureReason: choice === null ? "one_unambiguous_choice_required" : null
      });
      return;
    }

    res.status(400).json({ error: "unsupported_mode" });
  } catch (error) {
    const status = error instanceof z.ZodError ? 400 : isPayloadTooLarge(error) ? 413 : 502;
    res.status(status).json({ error: status === 400 ? "invalid_request" : status === 413 ? "request_too_large" : "transcription_unavailable" });
  } finally {
    const fileValues = Object.values(files).flatMap((value) => value ?? []);
    await Promise.all(fileValues.map((file) => unlink(file.filepath).catch(() => undefined)));
  }
}
