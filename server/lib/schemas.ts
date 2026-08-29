import { z } from "zod";

export const statusSchema = z.enum([
  "validEstimate",
  "noMyopiaDetectedWithinRange",
  "strongerThanSupportedRange",
  "experimentalThresholdObserved",
  "experimentalFarthestTargetPassed",
  "experimentalAdverseBoundary",
  "experimentalTaskCompleted",
  "unreliableMeasurement",
  "deviceUnsupported",
  "userIneligible"
]);

export const qualitySchema = z.enum(["good", "moderate", "poor", "unavailable"]);

export const eyeFactsSchema = z.object({
  status: statusSchema,
  quality: qualitySchema
}).strict();

export const explanationRequestSchema = z.object({
  locale: z.string().min(2).max(20),
  rightEye: eyeFactsSchema.nullable().optional(),
  leftEye: eyeFactsSchema.nullable().optional(),
  comparisonCode: z.enum([
    "eyes_broadly_similar",
    "eyes_noticeably_different",
    "review_eyes_separately",
    "repeat_needed"
  ]),
  actionCode: z.enum([
    "professional_exam_recommended",
    "routine_exam_recommended",
    "no_reliable_result",
    "accessibility_only"
  ]),
  limitations: z.array(z.enum([
    "not_a_prescription",
    "hyperopia_not_assessed",
    "clinical_accuracy_not_established",
    "phone_screen_far_point_poc_not_clinically_validated"
  ])).min(1).max(4),
  localIntegrityCode: z.enum(["consistent", "review_required"])
}).strict();

const explanationDraftShape = {
  headline: z.string().min(1).max(180),
  plainMeaning: z.string().min(1).max(500),
  limitations: z.array(z.string().min(1).max(220)).min(1).max(6),
  nextSteps: z.array(z.string().min(1).max(220)).min(1).max(5),
  disclaimer: z.string().min(1).max(160),
  usedFallback: z.boolean()
};

export const resultVerificationSchema = z.enum([
  "consistent",
  "reviewRequired",
  "notApplicable"
]);

export const resultVerificationResponseSchema = z.object({
  verification: resultVerificationSchema
}).strict();

export const explanationDraftResponseSchema = z.object(explanationDraftShape).strict();

export const explanationResponseSchema = z.object({
  ...explanationDraftShape,
  verification: resultVerificationSchema
}).strict();

export const adaptContentRequestSchema = z.object({
  locale: z.string().min(2).max(20),
  contentID: z.literal("medical-travel-support-v1"),
  highContrast: z.boolean(),
  readAloud: z.boolean(),
  simplifiedContent: z.boolean()
}).strict();

export const adaptedContentResponseSchema = z.object({
  title: z.string().min(1).max(100),
  summary: z.string().min(1).max(300),
  steps: z.array(z.string().min(1).max(160)).min(1).max(8),
  deadline: z.string().min(1).max(80),
  primaryAction: z.string().min(1).max(80),
  readAloudText: z.string().min(1).max(700),
  usedFallback: z.boolean()
}).strict();

export const explanationDraftJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["headline", "plainMeaning", "limitations", "nextSteps", "disclaimer", "usedFallback"],
  properties: {
    headline: { type: "string" },
    plainMeaning: { type: "string" },
    limitations: { type: "array", items: { type: "string" } },
    nextSteps: { type: "array", items: { type: "string" } },
    disclaimer: { type: "string" },
    usedFallback: { type: "boolean" }
  }
} as const;

export const explanationVerificationJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["verification"],
  properties: {
    verification: {
      type: "string",
      enum: ["consistent", "reviewRequired", "notApplicable"]
    }
  }
} as const;

export const adaptedContentJSONSchema = {
  type: "object",
  additionalProperties: false,
  required: ["title", "summary", "steps", "deadline", "primaryAction", "readAloudText", "usedFallback"],
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    steps: { type: "array", items: { type: "string" } },
    deadline: { type: "string" },
    primaryAction: { type: "string" },
    readAloudText: { type: "string" },
    usedFallback: { type: "boolean" }
  }
} as const;

export type ExplanationRequest = z.infer<typeof explanationRequestSchema>;
export type ExplanationResponse = z.infer<typeof explanationResponseSchema>;
export type ExplanationDraftResponse = z.infer<typeof explanationDraftResponseSchema>;
export type ResultVerification = z.infer<typeof resultVerificationSchema>;
export type AdaptContentRequest = z.infer<typeof adaptContentRequestSchema>;
export type AdaptedContentResponse = z.infer<typeof adaptedContentResponseSchema>;
