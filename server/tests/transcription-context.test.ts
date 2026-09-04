import { describe, expect, it } from "vitest";
import { constrainedChoicePrompt, singleDirectionPrompt } from "../api/transcribe-block.js";

describe("single-answer transcription context", () => {
  it("uses task-specific context without asking the model to infer an answer", () => {
    const landolt = singleDirectionPrompt("landolt-single");
    const gabor = singleDirectionPrompt("gabor-single");

    expect(landolt).toContain("Landolt C");
    expect(landolt).toContain("up, right, down, left");
    expect(gabor).toContain("striped circle");
    expect(gabor).toContain("left, right");
    expect(landolt).toContain("Do not guess");
    expect(gabor).toContain("Do not guess");
  });

  it("gives safety answers narrow context without asking for inference", () => {
    const safety = constrainedChoicePrompt("eligibility");

    expect(safety).toContain("safety question");
    expect(safety).toContain("none apply");
    expect(safety).toContain("one applies");
    expect(safety).toContain("Do not infer");
  });
});
