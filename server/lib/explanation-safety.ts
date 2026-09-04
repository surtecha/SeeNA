import type { ExplanationDraftResponse, ExplanationRequest } from "./schemas.js";

// Model prose must never be the source of measurement information. This is
// deliberately conservative: if it looks like a number or measurement unit,
// the endpoint returns the deterministic local fallback instead.
const numericGlyph = /\p{N}/u;
const numberWord = /\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|dozen|score|half|quarter|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth)\b/i;
const measurementUnit = /\b(?:d|diopt(?:er|re)s?|met(?:er|re)s?|m|centimet(?:er|re)s?|cm|millimet(?:er|re)s?|mm|kilomet(?:er|re)s?|km|feet|foot|ft|inches|inch|degrees?|arcmin(?:ute)?s?|pixels?|px|percent(?:age)?)\b/i;
const measurementSymbol = /(?<!\w)(?:%|°)(?!\w)/u;
const internalProductJargon = /\b(?:poc|prototype|demo|simulated|simulation|validate|validated|validation|calibrate|calibrated|calibration|ai|model|provider)\b/i;
const unsupportedHealthClaim = /\b(?:diagnos\w*|prescri\w*|myopi\w*|refract\w*|acuity|contrast\w*|referr\w*|diseases?|treat\w*|cures?|curing|healthy|normal|abnormal|risks?|concerns?|conditions?|vision|eyesight|sight|power|clinical|medical|screening?|results?)\b/i;
const unsupportedTaskInference = /\b(?:pass(?:ed|es|ing)?|fail(?:ed|s|ing)?|better|worse|similar|different|difference|accur\w*|reliab\w*|consisten\w*|verif\w*|quality|good|poor|estimate\w*|detect\w*|suggest\w*|indicat\w*|imply\w*|mean(?:s|ing)?|likely|perhaps|possibly|not|no|never|repeat\w*|incomplete|missing|unavailable|unable|cannot|couldn['’]?t|didn['’]?t|doctor|optometrist|ophthalmologist|professional|appointment|examination|exam|review)\b/i;
const neutralTaskFact = /\b(?:answers?|responses?|tasks?)\b/i;
const neutralTaskOutcome = /\b(?:recorded|saved|complete|completed|finished)\b/i;
const allowedQualitativeWords = new Set([
  "all", "and", "answer", "answers", "are", "been", "both",
  "complete", "completed", "each", "eye", "eyes", "finished", "for",
  "from", "have", "is", "recorded", "response", "responses", "saved",
  "task", "tasks", "the", "these", "was", "we", "were", "you", "your"
]);

export function containsModelMeasurementLanguage(text: string): boolean {
  return numericGlyph.test(text)
    || numberWord.test(text)
    || measurementUnit.test(text)
    || measurementSymbol.test(text);
}

export function containsInternalProductJargon(text: string): boolean {
  return internalProductJargon.test(text);
}

export function containsUnsupportedHealthClaimLanguage(text: string): boolean {
  return unsupportedHealthClaim.test(text);
}

export function qualitativePlainMeaningIsSafe(text: string): boolean {
  const value = text.trim();
  if (value.length === 0 || value.length > 220) return false;
  if (/[^A-Za-z\s,.]/u.test(value)) return false;
  const words = value.toLowerCase().match(/[a-z]+/g) ?? [];
  return !containsModelMeasurementLanguage(value)
    && !containsInternalProductJargon(value)
    && !containsUnsupportedHealthClaimLanguage(value)
    && !unsupportedTaskInference.test(value)
    && words.length > 0
    && words.every(word => allowedQualitativeWords.has(word))
    && neutralTaskFact.test(value)
    && neutralTaskOutcome.test(value);
}

export function qualitativeCandidateMatchesFacts(
  input: ExplanationRequest,
  draft: ExplanationDraftResponse
): boolean {
  const statuses = [input.rightEye?.status, input.leftEye?.status].filter(
    (status): status is NonNullable<typeof status> => Boolean(status)
  );
  const hasQualitativeStatus = statuses.some(status => status.startsWith("experimental"));
  if (!hasQualitativeStatus) return true;

  return input.localIntegrityCode === "consistent"
    && input.actionCode === "routine_exam_recommended"
    && statuses.length === 2
    && statuses.every(status => status.startsWith("experimental"))
    && qualitativePlainMeaningIsSafe(draft.plainMeaning);
}

/** Throws before model-generated text can cross the API output boundary. */
export function assertExplanationDraftHasNoMeasurements(draft: ExplanationDraftResponse): void {
  const text = [
    draft.headline,
    draft.plainMeaning,
    ...draft.limitations,
    ...draft.nextSteps,
    draft.disclaimer
  ];
  if (text.some(containsModelMeasurementLanguage)) {
    throw new Error("model_explanation_contains_measurement_language");
  }
  if (text.some(containsInternalProductJargon)) {
    throw new Error("model_explanation_contains_internal_product_jargon");
  }
  if ([draft.headline, draft.plainMeaning].some(containsUnsupportedHealthClaimLanguage)) {
    throw new Error("model_explanation_contains_unsupported_health_claim");
  }
}
