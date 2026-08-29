import { z } from "zod";

export const statusSchema = z.enum([
  "validEstimate",
  "noMyopiaDetectedWithinRange",
  "strongerThanSupportedRange",
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
  comparison: z.string().max(400),
  actionCode: z.enum([
    "professional_exam_recommended",
    "routine_exam_recommended",
    "no_reliable_result",
    "accessibility_only"
  ]),
  limitations: z.array(z.string().min(1).max(120)).min(1).max(10)
}).strict();

export const explanationResponseSchema = z.object({
  headline: z.string().min(1).max(180),
  plainMeaning: z.string().min(1).max(500),
  limitations: z.array(z.string().min(1).max(220)).min(1).max(6),
  nextSteps: z.array(z.string().min(1).max(220)).min(1).max(5),
  disclaimer: z.string().min(1).max(160),
  usedFallback: z.boolean()
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

export const explanationJSONSchema = {
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
export type AdaptContentRequest = z.infer<typeof adaptContentRequestSchema>;
export type AdaptedContentResponse = z.infer<typeof adaptedContentResponseSchema>;
