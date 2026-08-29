import { describe, expect, it } from "vitest";
import { analyzeDirectionTranscript, parseChoice, parseDirections } from "../lib/direction-parser.js";

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

  it("requires one unambiguous constrained choice", () => {
    expect(parseChoice("I choose option two", "contrast")).toBe("two");
    expect(parseChoice("yes definitely", "readAloud")).toBe("yes");
    expect(parseChoice("larger please", "controls")).toBe("larger");
    expect(parseChoice("one or two", "simplified")).toBeNull();
  });
});
