import OpenAI from "openai";
import {
  assertExplanationDraftHasNoMeasurements,
  qualitativeCandidateMatchesFacts
} from "./explanation-safety.js";
import {
  explanationDraftJSONSchema,
  explanationDraftResponseSchema,
  explanationResponseSchema,
  explanationVerificationJSONSchema,
  resultVerificationResponseSchema,
  type ExplanationDraftResponse,
  type ExplanationRequest,
  type ExplanationResponse,
  type ResultVerification
} from "./schemas.js";

let client: OpenAI | undefined;

export function openAIClient(): OpenAI {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  client ??= new OpenAI({ apiKey, timeout: 22_000, maxRetries: 0 });
  return client;
}

const resultSafetyInstruction = `You are a communication and accessibility layer, not a clinician.
Explain only the deterministic screening facts supplied by the application.
Never diagnose, prescribe, alter or infer measurements, claim clinical validation, promise accuracy,
recommend treatment, or override the supplied action code. If a status is unreliableMeasurement,
say clearly that the task needs repeating. Do not quote, restate, round, or introduce
any numeric value; the application presents its deterministic numbers separately. Return only the
requested JSON schema. Use clear, professional, human language. Do not mention prototypes,
experiments, validation, calibration, AI, models, providers, or internal codes. When both supplied
statuses start with experimental and localIntegrityCode is consistent, use the headline "Tasks complete"
and use exactly "All tasks are complete, and your responses were recorded for each eye." for plainMeaning.
Do not interpret a target level or score, compare the eyes, or infer anything about vision or health.
For that qualitative case, populate every field and use these exact safety fields: limitations must be
["This task is not a glasses prescription.", "It cannot diagnose eye conditions."], nextSteps must be
["Continue routine eye checks with an eye care professional."], and disclaimer must be
"This task is not a diagnosis or glasses prescription." Never leave a required string or array empty.`;

const resultConsistencyInstruction = `You are a non-clinical consistency checker for a vision-screening workflow.
You cannot clinically validate the screening, diagnose, prescribe, assess eyesight, or claim accuracy.
You must not alter, calculate, invent, round, repeat, or introduce any numeric values.
Compare only the supplied allow-listed qualitative codes and the candidate explanation.
Return reviewRequired when localIntegrityCode is review_required or when the candidate contradicts a supplied code.
For experimental statuses, evaluate consistency instead of returning notApplicable automatically. Return consistent only
when localIntegrityCode is consistent, both eye tasks are present, the action code is routine_exam_recommended, and the
candidate says only that the tasks finished and answers or responses were recorded. It must not interpret scores, compare
the eyes, infer vision or health, recommend referral, or introduce any medical meaning. Return reviewRequired for any
contradiction, unsupported interpretation, missing eye task, non-routine action, or review_required local integrity.
The required negated diagnosis and prescription limitations are safety boundaries, not health inferences. The universal
routine eye-check next step is not a score-triggered referral. Do not mark either of those required fields for review.
Return notApplicable only when there is no candidate task meaning that can be checked. A consistent verdict confirms only
that prose matches the supplied task codes. It never means clinical validation, diagnostic review, or measurement accuracy.
Return only the requested JSON schema.`;

export async function generateExplanation(input: ExplanationRequest): Promise<ExplanationResponse> {
  const response = await openAIClient().responses.create({
    model: process.env.OPENAI_TEXT_MODEL ?? "gpt-5.6-luna",
    store: false,
    tools: [],
    max_output_tokens: 700,
    reasoning: { effort: "none" },
    instructions: resultSafetyInstruction,
    input: JSON.stringify(input),
    text: {
      format: {
        type: "json_schema",
        name: "seena_result_explanation",
        strict: true,
        schema: explanationDraftJSONSchema
      }
    }
  });
  const modelDraft = explanationDraftResponseSchema.parse(JSON.parse(response.output_text));
  assertExplanationDraftHasNoMeasurements(modelDraft);
  const statuses = [input.rightEye?.status, input.leftEye?.status].filter(Boolean);
  const isQualitative = statuses.some(status => status?.startsWith("experimental"));
  const candidate: ExplanationDraftResponse = isQualitative ? {
    headline: "Tasks complete",
    plainMeaning: modelDraft.plainMeaning,
    limitations: [
      "This task is not a glasses prescription.",
      "It cannot diagnose eye conditions."
    ],
    nextSteps: ["Continue routine eye checks with an eye care professional."],
    disclaimer: "This task is not a diagnosis or glasses prescription.",
    usedFallback: false
  } : { ...modelDraft, usedFallback: false };
  if (!qualitativeCandidateMatchesFacts(input, candidate)) {
    throw new Error("model_explanation_contradicts_qualitative_facts");
  }
  const verification = await verifyExplanationConsistency(input, candidate);
  return explanationResponseSchema.parse({ ...candidate, verification });
}

/**
 * A separate, schema-locked model pass that can only classify consistency.
 * It never gets an output shape capable of changing measurements or the
 * candidate explanation itself.
 */
async function verifyExplanationConsistency(
  input: ExplanationRequest,
  candidate: ExplanationDraftResponse
): Promise<ResultVerification> {
  const response = await openAIClient().responses.create({
    model: "gpt-5.6-luna",
    store: false,
    tools: [],
    max_output_tokens: 200,
    reasoning: { effort: "none" },
    instructions: resultConsistencyInstruction,
    input: JSON.stringify({ deterministicFacts: input, candidateExplanation: candidate }),
    text: {
      format: {
        type: "json_schema",
        name: "seena_result_consistency_verification",
        strict: true,
        schema: explanationVerificationJSONSchema
      }
    }
  });
  return resultVerificationResponseSchema.parse(JSON.parse(response.output_text)).verification;
}
