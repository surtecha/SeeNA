import OpenAI from "openai";
import {
  adaptedContentJSONSchema,
  adaptedContentResponseSchema,
  explanationJSONSchema,
  explanationResponseSchema,
  type AdaptContentRequest,
  type AdaptedContentResponse,
  type ExplanationRequest,
  type ExplanationResponse
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
say clearly that no reliable numeric result was obtained. Return only the requested JSON schema.`;

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
        schema: explanationJSONSchema
      }
    }
  });
  const parsed = explanationResponseSchema.parse(JSON.parse(response.output_text));
  return { ...parsed, usedFallback: false };
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
