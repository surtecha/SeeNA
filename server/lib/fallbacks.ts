import type {
  ExplanationRequest,
  ExplanationResponse
} from "./schemas.js";

export function fallbackExplanation(input: ExplanationRequest): ExplanationResponse {
  const statuses = [input.rightEye?.status, input.leftEye?.status].filter(Boolean);
  const unreliable = statuses.length === 0 || statuses.includes("unreliableMeasurement");
  const boundary = statuses.includes("strongerThanSupportedRange");
  const nonnumeric = statuses.some(status => status?.startsWith("experimental"));
  const comparison: Record<ExplanationRequest["comparisonCode"], string> = {
    eyes_broadly_similar: "The two eyes showed broadly similar task performance.",
    eyes_noticeably_different: "The two eyes showed noticeably different task performance.",
    review_eyes_separately: "Your answers were recorded for both eyes.",
    repeat_needed: "One or more tasks need repeating."
  };

  return {
    headline: unreliable
      ? "Repeat needed."
      : boundary
        ? "At least one eye needs professional review."
        : "Tasks complete.",
    plainMeaning: unreliable
      ? "One or more tasks need repeating."
      : nonnumeric
        ? "Your answers were recorded for both eyes."
        : comparison[input.comparisonCode],
    limitations: [
      "This task is not an eyeglass prescription.",
      "It cannot diagnose eye conditions."
    ],
    nextSteps: ["Continue routine eye checks with an eye care professional."],
    disclaimer: "This task is not a diagnosis or glasses prescription.",
    verification: input.localIntegrityCode !== "consistent"
      ? "reviewRequired"
      : nonnumeric ? "notApplicable" : "consistent",
    usedFallback: true
  };
}
