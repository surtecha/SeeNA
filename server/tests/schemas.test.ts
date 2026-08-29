import { describe, expect, it } from "vitest";
import { fallbackAdaptedContent, fallbackExplanation } from "../lib/fallbacks.js";
import {
  adaptContentRequestSchema,
  adaptedContentResponseSchema,
  explanationRequestSchema,
  explanationResponseSchema
} from "../lib/schemas.js";

describe("strict contracts", () => {
  it("rejects extra or malformed result facts", () => {
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      rightEye: { status: "validEstimate", quality: "good", displayedEstimate: -2 },
      comparison: "Right and left eye results differ.",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"]
    }).success).toBe(false);
  });

  it("produces a schema-valid deterministic no-result fallback", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "unreliableMeasurement", quality: "poor" },
      comparison: "",
      actionCode: "no_reliable_result",
      limitations: ["not_a_prescription"]
    });
    expect(explanationResponseSchema.parse(fallbackExplanation(input)).headline).toContain("could not");
  });

  it("adapts only the allow-listed fixture and validates fallback shape", () => {
    const input = adaptContentRequestSchema.parse({
      locale: "en-AU",
      contentID: "medical-travel-support-v1",
      highContrast: true,
      readAloud: true,
      simplifiedContent: true
    });
    expect(adaptedContentResponseSchema.parse(fallbackAdaptedContent(input)).steps).toHaveLength(3);
    expect(adaptContentRequestSchema.safeParse({ ...input, contentID: "arbitrary" }).success).toBe(false);
  });
});
