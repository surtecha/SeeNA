import { describe, expect, it } from "vitest";
import { createReadStream } from "node:fs";
import { parseDirections } from "../lib/direction-parser.js";
import { generateAdaptedContent, generateExplanation, openAIClient } from "../lib/openai.js";

const live = process.env.SEENA_RUN_LIVE_TESTS === "1";

describe.skipIf(!live)("OpenAI live contracts", () => {
  it("returns strict non-clinical explanation JSON and a Luna consistency classification", async () => {
    const result = await generateExplanation({
      locale: "en-AU",
      rightEye: {
        status: "validEstimate",
        quality: "good",
        displayedEstimateDiopter: -2,
        thresholdDistanceMetres: 0.5,
        lastFailDiopter: -2.25,
        firstPassDiopter: -2,
        sensorUncertaintyDiopter: 0.12,
        repeatabilityDiopter: 0.25
      },
      leftEye: { status: "unreliableMeasurement", quality: "poor" },
      comparison: "The right-eye screening completed; the left-eye screening did not produce a reliable result.",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription", "hyperopia_not_assessed", "clinical_accuracy_not_established"],
      localMathConsistent: true
    });
    expect(result.usedFallback).toBe(false);
    expect(result.disclaimer.toLowerCase()).toMatch(/prototype|prescription|diagnos/);
    expect(["consistent", "reviewRequired", "notApplicable"]).toContain(result.verification);
  }, 30_000);

  it("returns strict accessible fixture content", async () => {
    const result = await generateAdaptedContent({
      locale: "en-AU",
      contentID: "medical-travel-support-v1",
      highContrast: true,
      readAloud: true,
      simplifiedContent: true
    });
    expect(result.usedFallback).toBe(false);
    expect(result.steps.length).toBeGreaterThan(0);
    expect(result.deadline).toContain("14 September");
  }, 30_000);

  it.skipIf(!process.env.SEENA_TEST_AUDIO)("transcribes seven female-voice directions for deterministic parsing", async () => {
    const transcription = await openAIClient().audio.transcriptions.create({
      file: createReadStream(process.env.SEENA_TEST_AUDIO!),
      model: process.env.OPENAI_TRANSCRIBE_MODEL ?? "gpt-transcribe",
      stream: false,
      language: "en",
      prompt: "A speaker says exactly seven words chosen from up, right, down, and left."
    });
    expect(parseDirections(transcription.text)).toEqual([
      "up", "left", "right", "down", "down", "up", "left"
    ]);
  }, 30_000);
});
