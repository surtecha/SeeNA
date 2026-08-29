import { describe, expect, it } from "vitest";
import {
  assertExplanationDraftHasNoMeasurements,
  containsModelMeasurementLanguage
} from "../lib/explanation-safety.js";
import { fallbackAdaptedContent, fallbackExplanation } from "../lib/fallbacks.js";
import {
  adaptContentRequestSchema,
  adaptedContentResponseSchema,
  explanationRequestSchema,
  explanationResponseSchema
} from "../lib/schemas.js";

describe("strict contracts", () => {
  it("rejects model number glyphs, number words, and measurement units before delivery", () => {
    expect(containsModelMeasurementLanguage("Your screening is ready to review.")).toBe(false);
    expect(containsModelMeasurementLanguage("Your result is in the supported range.")).toBe(false);
    expect(containsModelMeasurementLanguage("The estimate is -2.00 diopters.")).toBe(true);
    expect(containsModelMeasurementLanguage("The estimate is two diopters.")).toBe(true);
    expect(containsModelMeasurementLanguage("Stand half a metre away.")).toBe(true);
    expect(containsModelMeasurementLanguage("The contrast was 75%.")).toBe(true);
    expect(containsModelMeasurementLanguage("% contrast is not reported here.")).toBe(true);
    expect(containsModelMeasurementLanguage("The symbol was ١.")).toBe(true);
    expect(containsModelMeasurementLanguage("Two D is not reported here.")).toBe(true);

    expect(() => assertExplanationDraftHasNoMeasurements({
      headline: "Ready",
      plainMeaning: "Your screening is ready to review.",
      limitations: ["Research prototype only."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    })).not.toThrow();
    expect(() => assertExplanationDraftHasNoMeasurements({
      headline: "Ready",
      plainMeaning: "Your estimate is two diopters.",
      limitations: ["Research prototype only."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    })).toThrow("model_explanation_contains_measurement_language");
  });

  it("rejects measurement language in every model-controlled explanation field", () => {
    const safeDraft = {
      headline: "Ready",
      plainMeaning: "Your screening is ready to review.",
      limitations: ["Research prototype only."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    };
    const unsafeDrafts = [
      { ...safeDraft, headline: "Review at two metres." },
      { ...safeDraft, plainMeaning: "Review at two metres." },
      { ...safeDraft, limitations: ["Review at two metres."] },
      { ...safeDraft, nextSteps: ["Review at two metres."] },
      { ...safeDraft, disclaimer: "Review at two metres." }
    ];
    unsafeDrafts.forEach(draft => {
      expect(() => assertExplanationDraftHasNoMeasurements(draft)).toThrow(
        "model_explanation_contains_measurement_language"
      );
    });
  });

  it("accepts only finite deterministic result facts", () => {
    expect(explanationRequestSchema.safeParse({
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
      comparison: "Right and left eye results differ.",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localMathConsistent: true
    }).success).toBe(true);
  });

  it("rejects extra, non-finite, or incomplete result facts", () => {
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      rightEye: { status: "validEstimate", quality: "good", displayedEstimate: -2 },
      comparison: "Right and left eye results differ.",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localMathConsistent: true
    }).success).toBe(false);
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      comparison: "",
      actionCode: "no_reliable_result",
      limitations: ["not_a_prescription"],
      localMathConsistent: true,
      rightEye: { status: "validEstimate", quality: "good", displayedEstimateDiopter: Infinity }
    }).success).toBe(false);
  });

  it("produces a schema-valid deterministic no-result fallback", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "unreliableMeasurement", quality: "poor" },
      comparison: "",
      actionCode: "no_reliable_result",
      limitations: ["not_a_prescription"],
      localMathConsistent: false
    });
    const fallback = explanationResponseSchema.parse(fallbackExplanation(input));
    expect(fallback.headline).toContain("could not");
    expect(fallback.verification).toBe("reviewRequired");
  });

  it("keeps verification schema-only, with no numeric result field", () => {
    expect(explanationResponseSchema.safeParse({
      headline: "Ready",
      plainMeaning: "Review the local result.",
      limitations: ["Research prototype."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "Not a diagnosis.",
      verification: "consistent",
      usedFallback: false,
      displayedEstimateDiopter: -2
    }).success).toBe(false);
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
