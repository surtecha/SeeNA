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

const yesSynonyms = new Set(["yes", "yeah", "yep", "sure"]);
const noSynonyms = new Set(["no", "nope", "nah"]);

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
  return normalizedTokens(text).flatMap((token) => {
    const parsed = directionSynonyms[token];
    return parsed ? [parsed] : [];
  });
}

export type ChoiceSetID = "contrast" | "controls" | "readAloud" | "simplified";

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
  }
}
