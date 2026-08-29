import { describe, expect, it } from "vitest";
import {
  analyzeDirectionTranscript,
  parseChoice,
  parseDirections,
  parseSingleDirection,
  parseSingleDirectionAnswer
} from "../lib/direction-parser.js";

describe("direction parser", () => {
  it("parses exactly the deterministic direction vocabulary", () => {
    expect(parseDirections("Up, left. RIGHT; below, south, above, west")).toEqual([
      "up", "left", "right", "down", "down", "up", "left"
    ]);
  });

  it("does not invent unknown or missing directions", () => {
    expect(parseDirections("up maybe left right")).toEqual(["up", "left", "right"]);
    expect(analyzeDirectionTranscript("up maybe left right").unknownTokens).toEqual(["maybe"]);
  });

  it("exposes extra unknown words so the endpoint can reject the entire row", () => {
    const analysis = analyzeDirectionTranscript("up left right down down up left banana");
    expect(analysis.directions).toHaveLength(7);
    expect(analysis.unknownTokens).toEqual(["banana"]);
  });

  it("accepts exactly one deterministic Landolt direction or synonym", () => {
    expect(parseSingleDirection("RIGHT")).toBe("right");
    expect(parseSingleDirection("above.")).toBe("up");
    expect(parseSingleDirection("west")).toBe("left");
    expect(parseSingleDirection("south")).toBe("down");
  });

  it("accepts one unambiguous direction in natural older-user speech", () => {
    expect(parseSingleDirection("Right, please.")).toBe("right");
    expect(parseSingleDirection("I think it's LEFT.")).toBe("left");
    expect(parseSingleDirection("The opening is up")).toBe("up");
    expect(parseSingleDirection("I can see the gap on the right-hand side.")).toBe("right");
    expect(parseSingleDirection("My answer would be below.")).toBe("down");
  });

  it("rejects empty, unknown, negated, repeated, or conflicting answers", () => {
    expect(parseSingleDirection("")).toBeNull();
    expect(parseSingleDirection("maybe")).toBeNull();
    expect(parseSingleDirection("banana right")).toBeNull();
    expect(parseSingleDirection("not right")).toBeNull();
    expect(parseSingleDirection("right right")).toBeNull();
    expect(parseSingleDirection("right left")).toBeNull();
    expect(parseSingleDirection("left or right")).toBeNull();
  });

  it("accepts deterministic natural-language not-visible answers", () => {
    const phrases = [
      "I can't see.",
      "It isn’t visible",
      "I don't see it",
      "I can’t make it out",
      "Too blurry",
      "It is blurred.",
      "unclear",
      "not visible",
      "I am unable to see the opening",
      "I can barely see it",
      "The target is too small",
      "I see nothing",
      "It looks blurry to me",
      "I just can't quite see this one, sorry",
      "It isn't clear enough"
    ];

    for (const phrase of phrases) {
      expect(parseSingleDirectionAnswer(phrase), phrase).toEqual({ kind: "notVisible" });
      expect(parseSingleDirection(phrase), phrase).toBeNull();
    }
  });

  it("rejects not-visible semantics mixed with a direction or conflicting content", () => {
    const phrases = [
      "I can't see, maybe right",
      "left but too blurry",
      "the opening is up but not visible",
      "I don't see it, perhaps down",
      "right is unclear",
      "not visible banana"
    ];

    for (const phrase of phrases) {
      expect(parseSingleDirectionAnswer(phrase), phrase).toBeNull();
    }
  });

  it("does not confuse affirmative visibility with a not-visible answer", () => {
    expect(parseSingleDirectionAnswer("I can see it")).toBeNull();
    expect(parseSingleDirectionAnswer("It is visible")).toBeNull();
    expect(parseSingleDirectionAnswer("The target is clear")).toBeNull();
    expect(parseSingleDirectionAnswer("No, I can see it")).toBeNull();
    expect(parseSingleDirectionAnswer("It is not blurry")).toBeNull();
    expect(parseSingleDirectionAnswer("The target is not too small")).toBeNull();
  });

  it("keeps filler words unknown to the strict seven-direction mode", () => {
    expect(analyzeDirectionTranscript("up please").unknownTokens).toEqual(["please"]);
  });

  it("requires one unambiguous constrained choice", () => {
    expect(parseChoice("I choose option two", "contrast")).toBe("two");
    expect(parseChoice("yes definitely", "readAloud")).toBe("yes");
    expect(parseChoice("larger please", "controls")).toBe("larger");
    expect(parseChoice("one or two", "simplified")).toBeNull();
  });
});
