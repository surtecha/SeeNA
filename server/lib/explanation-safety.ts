import type { ExplanationDraftResponse } from "./schemas.js";

// Model prose must never be the source of measurement information. This is
// deliberately conservative: if it looks like a number or measurement unit,
// the endpoint returns the deterministic local fallback instead.
const numericGlyph = /\p{N}/u;
const numberWord = /\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|dozen|score|half|quarter|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth)\b/i;
const measurementUnit = /\b(?:d|diopt(?:er|re)s?|met(?:er|re)s?|m|centimet(?:er|re)s?|cm|millimet(?:er|re)s?|mm|kilomet(?:er|re)s?|km|feet|foot|ft|inches|inch|degrees?|arcmin(?:ute)?s?|pixels?|px|percent(?:age)?)\b/i;
const measurementSymbol = /(?<!\w)(?:%|°)(?!\w)/u;

export function containsModelMeasurementLanguage(text: string): boolean {
  return numericGlyph.test(text)
    || numberWord.test(text)
    || measurementUnit.test(text)
    || measurementSymbol.test(text);
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
}
