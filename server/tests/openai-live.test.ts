import { describe, expect, it } from "vitest";
import { qualitativePlainMeaningIsSafe } from "../lib/explanation-safety.js";
import { generateExplanation } from "../lib/openai.js";

const live = process.env.SEENA_RUN_LIVE_TESTS === "1";

describe.skipIf(!live)("OpenAI live contracts", () => {
  it("returns safe qualitative prose with a consistent Luna classification", async () => {
    const result = await generateExplanation({
      locale: "en-AU",
      rightEye: {
        status: "experimentalTaskCompleted",
        quality: "good"
      },
      leftEye: { status: "experimentalTaskCompleted", quality: "good" },
      comparisonCode: "review_eyes_separately",
      actionCode: "routine_exam_recommended",
      limitations: ["not_a_prescription", "hyperopia_not_assessed", "clinical_accuracy_not_established"],
      localIntegrityCode: "consistent"
    });
    expect(result.usedFallback).toBe(false);
    expect(qualitativePlainMeaningIsSafe(result.plainMeaning)).toBe(true);
    expect(result.disclaimer.toLowerCase()).toMatch(/prescription|diagnos/);
    expect(result.verification).toBe("consistent");
  }, 30_000);
});
