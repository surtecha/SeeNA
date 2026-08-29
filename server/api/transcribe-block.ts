import { createReadStream } from "node:fs";
import { unlink } from "node:fs/promises";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import formidable, { type Fields, type Files } from "formidable";
import { z } from "zod";
import {
  analyzeDirectionTranscript,
  parseChoice,
  parseSingleDirectionAnswer,
  type ChoiceSetID
} from "../lib/direction-parser.js";
import { openAIClient } from "../lib/openai.js";
import { secureEndpoint } from "../lib/security.js";

export const config = { api: { bodyParser: false } };

const metadataSchema = z.object({
  mode: z.enum(["singleDirection", "directionBlock", "readabilityPhrase", "constrainedChoice"]),
  locale: z.string().min(2).max(20),
  phraseId: z.string().max(80).optional(),
  choiceSetId: z.enum(["contrast", "controls", "readAloud", "simplified"]).optional()
}).strict();

function first(fields: Fields, name: string): string | undefined {
  const value = fields[name];
  return Array.isArray(value) ? value[0] : value;
}

export default async function handler(req: VercelRequest, res: VercelResponse): Promise<void> {
  if (!secureEndpoint(req, res)) return;
  const form = formidable({
    allowEmptyFiles: false,
    maxFiles: 1,
    maxFileSize: 5 * 1024 * 1024,
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

    const transcription = await openAIClient().audio.transcriptions.create({
      file: createReadStream(audio.filepath),
      model: process.env.OPENAI_TRANSCRIBE_MODEL ?? "gpt-transcribe",
      stream: false,
      ...(metadata.locale.toLowerCase().startsWith("en") ? { language: "en" } : {}),
      ...(metadata.mode === "singleDirection"
        ? {
            prompt:
              "A speaker gives one Landolt C opening direction or says they cannot see the target. Expected direction vocabulary is up, right, down, or left; transcribe the short natural phrase."
          }
        : metadata.mode === "directionBlock"
          ? { prompt: "A speaker says exactly seven words chosen from up, right, down, and left." }
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

    if (metadata.mode === "directionBlock") {
      const analysis = analyzeDirectionTranscript(transcript);
      const valid = analysis.directions.length === 7 && analysis.unknownTokens.length === 0;
      res.status(200).json({
        valid,
        mode: metadata.mode,
        transcript,
        directions: valid ? analysis.directions : null,
        choice: null,
        failureReason: valid ? null : "exactly_seven_directions_required"
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

    res.status(200).json({
      valid: transcript.length > 0,
      mode: metadata.mode,
      transcript,
      directions: null,
      choice: null,
      failureReason: transcript.length > 0 ? null : "empty_transcript"
    });
  } catch (error) {
    const status = error instanceof z.ZodError ? 400 : 502;
    res.status(status).json({ error: status === 400 ? "invalid_request" : "transcription_unavailable" });
  } finally {
    const fileValues = Object.values(files).flatMap((value) => value ?? []);
    await Promise.all(fileValues.map((file) => unlink(file.filepath).catch(() => undefined)));
  }
}
