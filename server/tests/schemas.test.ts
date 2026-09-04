import { describe, expect, it } from "vitest";
import {
  assertExplanationDraftHasNoMeasurements,
  containsInternalProductJargon,
  containsModelMeasurementLanguage,
  containsUnsupportedHealthClaimLanguage,
  qualitativeCandidateMatchesFacts,
  qualitativePlainMeaningIsSafe
} from "../lib/explanation-safety.js";
import { fallbackExplanation } from "../lib/fallbacks.js";
import {
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
      plainMeaning: "Your answers were recorded.",
      limitations: ["This is a screening, not a prescription."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    })).not.toThrow();
    expect(() => assertExplanationDraftHasNoMeasurements({
      headline: "Ready",
      plainMeaning: "Your estimate is two diopters.",
      limitations: ["This is a screening, not a prescription."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    })).toThrow("model_explanation_contains_measurement_language");
  });

  it("rejects measurement language in every model-controlled explanation field", () => {
    const safeDraft = {
      headline: "Ready",
      plainMeaning: "Your answers were recorded.",
      limitations: ["This is a screening, not a prescription."],
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

  it("rejects internal product and implementation jargon from user explanations", () => {
    for (const text of [
      "This prototype is ready.",
      "POC mode is active.",
      "This is simulated.",
      "Calibration is incomplete.",
      "The model validated it.",
      "An AI provider reviewed it."
    ]) {
      expect(containsInternalProductJargon(text)).toBe(true);
    }
    expect(containsInternalProductJargon("Your screening is ready to review.")).toBe(false);
    expect(() => assertExplanationDraftHasNoMeasurements({
      headline: "Ready",
      plainMeaning: "Your screening is ready to review.",
      limitations: ["This prototype is not a prescription."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "This is not a diagnosis.",
      usedFallback: false
    })).toThrow("model_explanation_contains_internal_product_jargon");
  });

  it("accepts only neutral qualitative task meaning and rejects health inference", () => {
    for (const text of [
      "All tasks are complete, and your responses were recorded for each eye.",
      "Your answers were recorded for both eyes."
    ]) {
      expect(qualitativePlainMeaningIsSafe(text)).toBe(true);
    }
    for (const text of [
      "Your visual acuity is normal.",
      "Your results suggest myopia.",
      "The model recommends a referral.",
      "Your answers were not recorded.",
      "The right eye performed better.",
      "Your task was complete at one metre.",
      "Your answers were recorded and everything looks clear."
    ]) {
      expect(qualitativePlainMeaningIsSafe(text)).toBe(false);
    }
    expect(containsUnsupportedHealthClaimLanguage("This suggests myopia.")).toBe(true);
    expect(containsUnsupportedHealthClaimLanguage("Your responses were recorded.")).toBe(false);
    expect(() => assertExplanationDraftHasNoMeasurements({
      headline: "Tasks complete",
      plainMeaning: "Your results suggest myopia.",
      limitations: ["This task is not a prescription."],
      nextSteps: ["Continue routine eye care."],
      disclaimer: "Not a diagnosis.",
      usedFallback: false
    })).toThrow("model_explanation_contains_unsupported_health_claim");
  });

  it("matches qualitative candidate prose to intact local facts before Luna verification", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "experimentalTaskCompleted", quality: "good" },
      leftEye: { status: "experimentalTaskCompleted", quality: "good" },
      comparisonCode: "review_eyes_separately",
      actionCode: "routine_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    });
    const draft = {
      headline: "Tasks complete",
      plainMeaning: "All tasks are complete, and your responses were recorded for each eye.",
      limitations: ["This task is not a prescription."],
      nextSteps: ["Continue routine eye care."],
      disclaimer: "Not a diagnosis.",
      usedFallback: false
    };

    expect(qualitativeCandidateMatchesFacts(input, draft)).toBe(true);
    expect(qualitativeCandidateMatchesFacts(
      { ...input, localIntegrityCode: "review_required" },
      draft
    )).toBe(false);
    expect(qualitativeCandidateMatchesFacts(
      { ...input, actionCode: "professional_exam_recommended" },
      draft
    )).toBe(false);
    expect(qualitativeCandidateMatchesFacts(
      input,
      { ...draft, plainMeaning: "Your responses suggest myopia." }
    )).toBe(false);
  });

  it("accepts only allow-listed qualitative result codes", () => {
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      rightEye: {
        status: "validEstimate",
        quality: "good"
      },
      comparisonCode: "eyes_noticeably_different",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    }).success).toBe(true);
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      rightEye: { status: "experimentalAdverseBoundary", quality: "good" },
      comparisonCode: "review_eyes_separately",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    }).success).toBe(true);
  });

  it("uses neutral numeric-not-applicable verification for nonnumeric fallback", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "experimentalFarthestTargetPassed", quality: "good" },
      leftEye: { status: "experimentalFarthestTargetPassed", quality: "good" },
      comparisonCode: "review_eyes_separately",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    });
    const fallback = fallbackExplanation(input);
    expect(fallback.verification).toBe("notApplicable");
    expect(fallback.headline).toBe("Tasks complete.");
    expect(fallback.plainMeaning).toBe("Your answers were recorded for both eyes.");
    expect(fallback.nextSteps).toEqual(["Continue routine eye checks with an eye care professional."]);
  });

  it("never turns an active qualitative task outcome into a score-based referral", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "experimentalAdverseBoundary", quality: "good" },
      leftEye: { status: "experimentalThresholdObserved", quality: "good" },
      comparisonCode: "review_eyes_separately",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    });
    const fallback = fallbackExplanation(input);
    const publicCopy = [
      fallback.headline,
      fallback.plainMeaning,
      ...fallback.limitations,
      ...fallback.nextSteps,
      fallback.disclaimer
    ].join(" ").toLowerCase();

    expect(fallback.verification).toBe("notApplicable");
    expect(fallback.headline).toBe("Tasks complete.");
    expect(fallback.plainMeaning).toBe("Your answers were recorded for both eyes.");
    for (const claim of [
      "visual acuity", "myopia detected", "contrast sensitivity", "clinical threshold",
      "professional review", "referral", "performance boundary", "farthest target",
      "strongest target"
    ]) {
      expect(publicCopy).not.toContain(claim);
    }
  });

  it("rejects free-form or numeric result facts at the request boundary", () => {
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      rightEye: { status: "validEstimate", quality: "good", displayedEstimate: -2 },
      comparisonCode: "eyes_noticeably_different",
      actionCode: "professional_exam_recommended",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent"
    }).success).toBe(false);
    expect(explanationRequestSchema.safeParse({
      locale: "en-AU",
      comparison: "Right and left eye results differ.",
      actionCode: "no_reliable_result",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "consistent",
      rightEye: { status: "validEstimate", quality: "good", displayedEstimateDiopter: -2 }
    }).success).toBe(false);
  });

  it("produces a schema-valid deterministic no-result fallback", () => {
    const input = explanationRequestSchema.parse({
      locale: "en-AU",
      rightEye: { status: "unreliableMeasurement", quality: "poor" },
      comparisonCode: "repeat_needed",
      actionCode: "no_reliable_result",
      limitations: ["not_a_prescription"],
      localIntegrityCode: "review_required"
    });
    const fallback = explanationResponseSchema.parse(fallbackExplanation(input));
    expect(fallback.headline).toBe("Repeat needed.");
    expect(fallback.plainMeaning).toBe("One or more tasks need repeating.");
    expect(fallback.verification).toBe("reviewRequired");
  });

  it("keeps verification schema-only, with no numeric result field", () => {
    expect(explanationResponseSchema.safeParse({
      headline: "Ready",
      plainMeaning: "Review the local result.",
      limitations: ["This is not a prescription."],
      nextSteps: ["Arrange an examination."],
      disclaimer: "Not a diagnosis.",
      verification: "consistent",
      usedFallback: false,
      displayedEstimateDiopter: -2
    }).success).toBe(false);
  });
});
