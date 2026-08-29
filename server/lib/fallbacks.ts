import type {
  AdaptContentRequest,
  AdaptedContentResponse,
  ExplanationRequest,
  ExplanationResponse
} from "./schemas.js";

export function fallbackExplanation(input: ExplanationRequest): ExplanationResponse {
  const statuses = [input.rightEye?.status, input.leftEye?.status].filter(Boolean);
  const unreliable = statuses.length === 0 || statuses.includes("unreliableMeasurement");
  const boundary = statuses.includes("strongerThanSupportedRange");

  return {
    headline: unreliable
      ? "SEENA could not obtain a reliable numeric screening result."
      : boundary
        ? "At least one result was outside SEENA’s supported screening range."
        : "Your SEENA screening is ready to review.",
    plainMeaning: unreliable
      ? "Tracking, response, or device conditions were not consistent enough to calculate a defensible estimate."
      : input.comparison || "Review each eye separately together with its quality evidence.",
    limitations: [
      "This research prototype is not an eyeglass prescription.",
      "It does not assess hyperopia, astigmatism, or eye disease.",
      "SEENA v0 has not undergone clinical validation."
    ],
    nextSteps: ["Arrange a complete professional eye examination when accessible."],
    disclaimer: "Research prototype only — not a diagnosis or prescription.",
    verification: input.localMathConsistent ? "consistent" : "reviewRequired",
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
