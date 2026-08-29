import OpenAI from "openai";
import { assertExplanationDraftHasNoMeasurements } from "./explanation-safety.js";
import {
  adaptedContentJSONSchema,
  adaptedContentResponseSchema,
  explanationDraftJSONSchema,
  explanationDraftResponseSchema,
  explanationResponseSchema,
  explanationVerificationJSONSchema,
  resultVerificationResponseSchema,
  type AdaptContentRequest,
  type AdaptedContentResponse,
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
experiments, validation, calibration, AI, models, providers, or internal codes.`;

const resultConsistencyInstruction = `You are a non-clinical consistency checker for a research prototype.
You cannot clinically validate the screening, diagnose, prescribe, assess eyesight, or claim accuracy.
You must not alter, calculate, invent, round, repeat, or introduce any numeric values.
Compare only the supplied allow-listed qualitative codes and the candidate explanation.
Return reviewRequired when localIntegrityCode is review_required or when the candidate contradicts a supplied code.
Return consistent only for numeric-capable statuses when the candidate is compatible with a consistent localIntegrityCode.
Return notApplicable when any status starts with experimental and localIntegrityCode is consistent; this means numeric
verification is not applicable, not that clinical validation succeeded.
Return only the requested JSON schema.`;

export async function generateExplanation(input: ExplanationRequest): Promise<ExplanationResponse> {
  const response = await openAIClient().responses.create({
    model: process.env.OPENAI_TEXT_MODEL ?? "gpt-5.6-luna",
    store: false,
    tools: [],
    max_output_tokens: 700,
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
  const draft = explanationDraftResponseSchema.parse(JSON.parse(response.output_text));
  assertExplanationDraftHasNoMeasurements(draft);
  const verification = await verifyExplanationConsistency(input, draft);
  return explanationResponseSchema.parse({ ...draft, verification, usedFallback: false });
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
    max_output_tokens: 80,
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

const adaptationInstruction = `Restructure only the supplied allow-listed public-service fixture for readability.
Do not add eligibility promises, legal claims, medical advice, new dates, new requirements, or personalised facts.
Preserve the deadline and required-document meaning. Return only the requested JSON schema.`;

export async function generateAdaptedContent(input: AdaptContentRequest): Promise<AdaptedContentResponse> {
  const source = {
    contentID: "medical-travel-support-v1",
    original: "Applicants seeking consideration under the regional transportation reimbursement framework are required to provide documentation substantiating their residence and appointment. Required evidence is photo identification, proof of address, and appointment confirmation. Submit before 14 September.",
    preferences: input
  };
  const response = await openAIClient().responses.create({
    model: process.env.OPENAI_TEXT_MODEL ?? "gpt-5.6-luna",
    store: false,
    tools: [],
    max_output_tokens: 700,
    instructions: adaptationInstruction,
    input: JSON.stringify(source),
    text: {
      format: {
        type: "json_schema",
        name: "seena_accessible_content",
        strict: true,
        schema: adaptedContentJSONSchema
      }
    }
  });
  const parsed = adaptedContentResponseSchema.parse(JSON.parse(response.output_text));
  return { ...parsed, usedFallback: false };
}
