export const directions = ["up", "right", "down", "left"] as const;
export type Direction = (typeof directions)[number];

const directionSynonyms: Readonly<Record<string, Direction>> = {
  up: "up",
  top: "up",
  above: "up",
  north: "up",
  upward: "up",
  upwards: "up",
  right: "right",
  east: "right",
  rightward: "right",
  rightwards: "right",
  down: "down",
  bottom: "down",
  below: "down",
  south: "down",
  downward: "down",
  downwards: "down",
  left: "left",
  west: "left",
  leftward: "left",
  leftwards: "left"
};

const numberSynonyms: Readonly<Record<string, string>> = {
  "1": "one",
  first: "one",
  one: "one",
  "2": "two",
  second: "two",
  two: "two"
};

const yesSynonyms = new Set(["yes", "yeah", "yep"]);
const noSynonyms = new Set(["no", "nope", "nah"]);
const eligibilityYesSynonyms = new Set(["yes", "yeah", "yep"]);

// A deliberately small allow-list for natural single-answer speech. These
// tokens add no competing direction or negation, so they can be ignored without
// turning the parser into an open-ended language guesser.
const singleDirectionFillerTokens = new Set([
  "a",
  "answer",
  "at",
  "be",
  "believe",
  "c",
  "can",
  "circle",
  "d",
  "direction",
  "gap",
  "goes",
  "hand",
  "i",
  "is",
  "it",
  "landolt",
  "like",
  "looks",
  "maybe",
  "my",
  "on",
  "opening",
  "please",
  "pointing",
  "s",
  "say",
  "see",
  "side",
  "the",
  "think",
  "to",
  "toward",
  "towards",
  "would"
]);

const notVisibleAllowedTokens = new Set([
  "a",
  "able",
  "all",
  "am",
  "anything",
  "are",
  "at",
  "away",
  "barely",
  "because",
  "but",
  "blur",
  "blurred",
  "blurry",
  "c",
  "can",
  "cannot",
  "cant",
  "circle",
  "clear",
  "clearly",
  "could",
  "couldn",
  "couldnt",
  "dark",
  "direction",
  "discern",
  "do",
  "does",
  "doesn",
  "doesnt",
  "don",
  "dont",
  "everything",
  "enough",
  "faint",
  "far",
  "for",
  "from",
  "fuzzy",
  "gap",
  "hard",
  "hardly",
  "hazy",
  "here",
  "i",
  "identify",
  "image",
  "invisible",
  "is",
  "isn",
  "isnt",
  "it",
  "just",
  "landolt",
  "looks",
  "m",
  "make",
  "me",
  "never",
  "no",
  "not",
  "nothing",
  "one",
  "opening",
  "orientation",
  "out",
  "pattern",
  "please",
  "properly",
  "quite",
  "read",
  "really",
  "s",
  "see",
  "side",
  "shape",
  "sharp",
  "small",
  "sorry",
  "symbol",
  "stripe",
  "stripes",
  "t",
  "target",
  "tell",
  "the",
  "thing",
  "this",
  "tiny",
  "to",
  "too",
  "unable",
  "unclear",
  "very",
  "visible",
  "was",
  "wasn",
  "wasnt",
  "well",
  "which"
]);

const compactNegativeTokens = new Set([
  "cannot",
  "cant",
  "couldnt",
  "doesnt",
  "dont",
  "isnt",
  "never",
  "not",
  "unable",
  "wasnt"
]);

const splitNegativeStems = new Set(["can", "couldn", "doesn", "don", "isn", "wasn"]);
const visualActionTokens = new Set(["discern", "identify", "make", "read", "see", "tell"]);
const visualQualityTokens = new Set(["clear", "sharp", "visible"]);
const directVisibilityFailureTokens = new Set([
  "blur",
  "blurred",
  "blurry",
  "fuzzy",
  "hazy",
  "invisible",
  "unclear"
]);
const limitedVisibilityTokens = new Set(["dark", "faint", "far", "small", "tiny"]);

export type SingleDirectionAnswer =
  | { kind: "direction"; direction: Direction }
  | { kind: "notVisible" };

export function normalizedTokens(text: string): string[] {
  return text
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

export function parseDirections(text: string): Direction[] {
  return analyzeDirectionTranscript(text).directions;
}

/**
 * Returns one direction only when the transcript contains one deterministic
 * direction (or existing synonym) plus, optionally, harmless natural-speech
 * filler. Unsupported, negating, repeated, and conflicting words are rejected
 * instead of guessed.
 */
export function parseSingleDirection(text: string): Direction | null {
  const answer = parseSingleDirectionAnswer(text);
  return answer?.kind === "direction" ? answer.direction : null;
}

/**
 * Parses either one unambiguous direction or an explicit inability to see the
 * target. A not-visible phrase mixed with any direction is intentionally
 * rejected so uncertainty can never be scored as a directional answer.
 */
export function parseSingleDirectionAnswer(text: string): SingleDirectionAnswer | null {
  const analysis = analyzeDirectionTranscript(text);
  const tokens = normalizedTokens(text);
  const notVisible = isNotVisiblePhrase(tokens);

  if (notVisible) {
    return analysis.directions.length === 0 ? { kind: "notVisible" } : null;
  }

  const unsupportedTokens = analysis.unknownTokens.filter(
    (token) => !singleDirectionFillerTokens.has(token)
  );
  if (analysis.directions.length !== 1 || unsupportedTokens.length !== 0) {
    return null;
  }
  const direction = analysis.directions[0];
  return direction ? { kind: "direction", direction } : null;
}

function isNotVisiblePhrase(tokens: string[]): boolean {
  if (tokens.length === 0) return false;

  const nonDirectionTokens = tokens.filter((token) => directionSynonyms[token] === undefined);
  if (nonDirectionTokens.some((token) => !notVisibleAllowedTokens.has(token))) return false;

  const hasCompactNegative = tokens.some((token) => compactNegativeTokens.has(token));
  const hasSplitNegative = tokens.some(
    (token, index) => token === "t" && index > 0 && splitNegativeStems.has(tokens[index - 1]!)
  );
  const hasNegative = hasCompactNegative || hasSplitNegative;
  const hasVisualAction = tokens.some((token) => visualActionTokens.has(token));
  const hasVisualQuality = tokens.some((token) => visualQualityTokens.has(token));
  const hasDirectFailure = tokens.some(
    (token, index) => directVisibilityFailureTokens.has(token)
      && !isNegatedDescriptor(tokens, index)
  );
  const hasTooLimited = tokens.includes("too")
    && tokens.some(
      (token, index) => limitedVisibilityTokens.has(token)
        && !isNegatedDescriptor(tokens, index)
    );
  const seesNothing = tokens.includes("nothing")
    && (tokens.includes("see") || tokens.includes("visible"));
  const canBarelySee = (tokens.includes("barely") || tokens.includes("hardly"))
    && hasVisualAction;
  const hardToSee = tokens.includes("hard") && hasVisualAction;

  const hasNotVisibleMeaning = (hasNegative && (hasVisualAction || hasVisualQuality))
    || hasDirectFailure
    || hasTooLimited
    || seesNothing
    || canBarelySee
    || hardToSee;

  return hasNotVisibleMeaning;
}

function isNegatedDescriptor(tokens: string[], index: number): boolean {
  const nearby = tokens.slice(Math.max(0, index - 3), index);
  if (nearby.includes("no") || nearby.includes("not")) return true;
  if (index >= 2 && tokens[index - 1] === "t") {
    return splitNegativeStems.has(tokens[index - 2]!);
  }
  return false;
}

export function analyzeDirectionTranscript(text: string): {
  directions: Direction[];
  unknownTokens: string[];
} {
  const tokens = normalizedTokens(text);
  const parsed = tokens.flatMap((token) => {
    const parsed = directionSynonyms[token];
    return parsed ? [parsed] : [];
  });
  return {
    directions: parsed,
    unknownTokens: tokens.filter((token) => directionSynonyms[token] === undefined)
  };
}

export type ChoiceSetID = "contrast" | "controls" | "readAloud" | "simplified" | "eligibility";

export function parseChoice(text: string, choiceSetID: ChoiceSetID): string | null {
  const tokens = normalizedTokens(text);
  const normalized = tokens.map((token) => numberSynonyms[token] ?? token);

  switch (choiceSetID) {
    case "contrast":
    case "simplified": {
      const choices = normalized.filter((token) => token === "one" || token === "two");
      return choices.length === 1 ? choices[0] ?? null : null;
    }
    case "controls": {
      const choices = normalized.flatMap((token) => {
        if (["standard", "normal", "one"].includes(token)) return ["standard"];
        if (["larger", "large", "big", "two"].includes(token)) return ["larger"];
        return [];
      });
      return choices.length === 1 ? choices[0] ?? null : null;
    }
    case "readAloud": {
      const choices = normalized.flatMap((token) => {
        if (yesSynonyms.has(token)) return ["yes"];
        if (noSynonyms.has(token)) return ["no"];
        return [];
      });
      return choices.length === 1 ? choices[0] ?? null : null;
    }
    case "eligibility": {
      const hasApplyWord = normalized.some((token) => token === "apply" || token === "applies");
      const positive = normalized.some((token) => eligibilityYesSynonyms.has(token))
        || (hasApplyWord && normalized.some((token) => ["one", "something", "it"].includes(token)));
      const negative = normalized.some((token) => noSynonyms.has(token))
        || normalized.some((token) => token === "none" || token === "nothing" || token === "neither")
        || (hasApplyWord && normalized.some((token) => compactNegativeTokens.has(token)));
      if (positive === negative) return null;
      return positive ? "yes" : "no";
    }
  }
}
