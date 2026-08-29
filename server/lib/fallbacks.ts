import type {
  AdaptContentRequest,
  AdaptedContentResponse,
  ExplanationRequest,
  ExplanationResponse
} from "./schemas.js";

export function fallbackExplanation(input: ExplanationRequest): ExplanationResponse {
  const statuses = [input.rightEye?.status, input.leftEye?.status].filter(Boolean);
  const unreliable = statuses.length === 0 || statuses.includes("unreliableMeasurement");
  const boundary = statuses.includes("strongerThanSupportedRange") || statuses.includes("experimentalAdverseBoundary");
  const nonnumeric = statuses.some(status => status?.startsWith("experimental"));
  const comparison: Record<ExplanationRequest["comparisonCode"], string> = {
    eyes_broadly_similar: "The two eyes showed broadly similar task performance.",
    eyes_noticeably_different: "The two eyes showed noticeably different task performance.",
    review_eyes_separately: "Review each eye separately because this screening cannot compare them.",
    repeat_needed: "One or both eyes need the visual task repeated."
  };

  return {
    headline: unreliable
      ? "SeeNA needs another attempt to complete this screening."
      : boundary
        ? "At least one eye needs professional review."
        : "Your SeeNA screening is ready to review.",
    plainMeaning: unreliable
      ? "Tracking, response, or device conditions were not consistent enough to support an outcome."
      : comparison[input.comparisonCode],
    limitations: [
      "This screening is not an eyeglass prescription.",
      "It does not assess hyperopia, astigmatism, or eye disease.",
      "Arrange an eye examination if you have concerns."
    ],
    nextSteps: ["Arrange a complete professional eye examination when accessible."],
    disclaimer: "Vision screening — not a diagnosis or prescription.",
    verification: input.localIntegrityCode !== "consistent"
      ? "reviewRequired"
      : nonnumeric ? "notApplicable" : "consistent",
    usedFallback: true
  };
}

export function fallbackAdaptedContent(input: AdaptContentRequest): AdaptedContentResponse {
  const summary = input.simplifiedContent
    ? "You may be able to get help travelling to a medical appointment."
    : "Regional applicants may request reimbursement support for eligible medical travel.";
  const steps = ["Prepare photo identification", "Add proof of address", "Add appointment confirmation"];
  return {
    title: "Medical Travel Support",
    summary,
    steps,
    deadline: "Submit before 14 September",
    primaryAction: "Start application",
    readAloudText: `${summary} You need ${steps.join(", ")}. Submit before 14 September.`,
    usedFallback: true
  };
}
