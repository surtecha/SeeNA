const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(__dirname, "SeeNA-Syncs-Hackathon-2026-Pitch.pptx");
const HERO = path.join(ROOT, "docs/assets/seena-hero.png");
const CLOSING = path.join(ROOT, "DesignAssets/SeeNA-Pitch-Closing-Frame-v2.png");
const APP_ICON = path.join(ROOT, "SeeNA/Assets.xcassets/AppIcon.appiconset/SEENA-AppIcon.png");
const DEMO = path.join(__dirname, "SeeNA-Demo-60s.mp4");
const SCREENS = {
  start: path.join(ROOT, "docs/assets/screens/01-start.jpg"),
  landolt: path.join(ROOT, "docs/assets/screens/02-landolt-c.jpg"),
  gabor: path.join(ROOT, "docs/assets/screens/03-gabor.jpg"),
  result: path.join(ROOT, "docs/assets/screens/04-result.jpg"),
  answers: path.join(ROOT, "docs/assets/screens/05-answer-review.jpg"),
};

const pptx = new pptxgen();
pptx.layout = "LAYOUT_WIDE";
pptx.author = "Karthik Ramesh, Kishore Srinivasan, Suryateja Challa, Sujan Ramesh";
pptx.company = "SeeNA";
pptx.subject = "Syncs Hackathon 2026 product pitch";
pptx.title = "SeeNA: See Now and Always";
pptx.lang = "en-AU";
pptx.theme = {
  headFontFace: "Arial",
  bodyFontFace: "Arial",
  lang: "en-AU",
};
pptx.defineLayout({ name: "SEENA_WIDE", width: 13.333, height: 7.5 });
pptx.layout = "SEENA_WIDE";

const C = {
  black: "050505",
  ink: "111111",
  white: "FFFFFF",
  paper: "F7F7F4",
  soft: "ECECEA",
  grey: "757575",
  lightGrey: "BDBDBD",
  line: "D8D8D5",
  gold: "D6A66D",
  goldSoft: "F1E1CF",
};

const SH = pptx.ShapeType;
const FONT = "Arial";
const makeShadow = (opacity = 0.16, blur = 10, offset = 3) => ({
  type: "outer", color: "000000", opacity, blur, angle: 45, offset,
});

function addText(slide, text, opts = {}) {
  slide.addText(text, {
    fontFace: FONT,
    color: C.ink,
    margin: 0,
    breakLine: false,
    fit: "shrink",
    ...opts,
  });
}

function addImageCover(slide, imagePath, x, y, w, h, altText) {
  slide.addImage({
    path: imagePath,
    x, y, w, h,
    sizing: { type: "cover", w, h },
    altText,
  });
}

function addImageContain(slide, imagePath, x, y, w, h, altText) {
  slide.addImage({
    path: imagePath,
    x, y, w, h,
    sizing: { type: "contain", w, h },
    altText,
  });
}

function addPill(slide, text, x, y, w, fill, color, border = fill) {
  slide.addShape(SH.roundRect, {
    x, y, w, h: 0.42,
    rectRadius: 0.08,
    fill: { color: fill },
    line: { color: border, width: 0.8 },
  });
  addText(slide, text, {
    x, y: y + 0.02, w, h: 0.33,
    fontSize: 12.5, bold: true, align: "center", valign: "mid", color,
    charSpacing: 0.2,
  });
}

function addSectionLabel(slide, text, color = C.grey) {
  addText(slide, text.toUpperCase(), {
    x: 0.72, y: 0.38, w: 4.2, h: 0.28,
    fontSize: 10.5, bold: true, color, charSpacing: 2.6,
  });
}

function addPageNumber(slide, n, color = C.grey) {
  addText(slide, String(n).padStart(2, "0"), {
    x: 12.12, y: 6.96, w: 0.48, h: 0.2,
    fontSize: 10, bold: true, color, align: "right",
  });
}

function addPhone(slide, imagePath, x, y, w, h, altText, border = C.ink) {
  slide.addShape(SH.roundRect, {
    x: x - 0.08, y: y - 0.08, w: w + 0.16, h: h + 0.16,
    rectRadius: 0.1,
    fill: { color: C.black },
    line: { color: border, width: 1 },
    shadow: makeShadow(0.16, 10, 3),
  });
  addImageCover(slide, imagePath, x, y, w, h, altText);
}

function addSmallBlock(slide, x, y, w, h, title, subtitle, inverted = false) {
  slide.addShape(SH.roundRect, {
    x, y, w, h,
    rectRadius: 0.06,
    fill: { color: inverted ? C.black : C.white },
    line: { color: inverted ? "2E2E2E" : C.line, width: 1 },
    shadow: inverted ? undefined : makeShadow(0.08, 5, 1.5),
  });
  addText(slide, title, {
    x: x + 0.18, y: y + 0.18, w: w - 0.36, h: 0.34,
    fontSize: 16, bold: true, color: inverted ? C.white : C.ink,
  });
  if (subtitle) {
    addText(slide, subtitle, {
      x: x + 0.18, y: y + 0.57, w: w - 0.36, h: h - 0.68,
      fontSize: 11.5, color: inverted ? C.lightGrey : C.grey,
      valign: "top",
    });
  }
}

function addConnector(slide, x, y, w, color = C.gold) {
  slide.addShape(SH.line, {
    x, y, w, h: 0,
    line: { color, width: 2.4, endArrowType: "triangle" },
  });
}

function addNotes(slide, timing, script) {
  slide.addNotes(`TIMING: ${timing}\n\n${script}`);
}

// Slide 1: Hook
{
  const slide = pptx.addSlide();
  addImageCover(slide, HERO, 0, 0, 13.333, 7.5, "SeeNA hero image with the app and Landolt C symbol");
  slide.addShape(SH.rect, {
    x: 0, y: 0, w: 6.1, h: 7.5,
    fill: { color: C.black, transparency: 4 }, line: { color: C.black, transparency: 100 },
  });
  addPill(slide, "SYNCS HACKATHON 2026", 0.78, 0.58, 2.52, C.white, C.black, C.white);
  addText(slide, "See now.\nAlways.", {
    x: 0.78, y: 3.38, w: 4.9, h: 1.44,
    fontSize: 47, bold: true, color: C.white, breakLine: true,
    breakLineOnTextOverflow: false, lineSpacingMultiple: 0.9,
  });
  addText(slide, "A voice-guided vision screening companion.", {
    x: 0.8, y: 5.02, w: 4.7, h: 0.38,
    fontSize: 18, color: "E8E8E8",
  });
  addText(slide, "SeeNA  |  See Now and Always", {
    x: 0.8, y: 6.67, w: 3.4, h: 0.22,
    fontSize: 10.5, bold: true, color: C.lightGrey, charSpacing: 0.8,
  });
  addNotes(slide, "0:00 to 0:15", "Most eye tests begin in a clinic. SeeNA begins with the iPhone already in your hand. It is a voice-guided vision screening companion built to make the first eye check simple.");
}

// Slide 2: Problem
{
  const slide = pptx.addSlide();
  addImageCover(slide, CLOSING, 0, 0, 13.333, 7.5, "Older adult overlooking a remote community connected by illuminated blocks");
  slide.addShape(SH.rect, {
    x: 0, y: 0, w: 7.3, h: 7.5,
    fill: { color: C.black, transparency: 18 }, line: { color: C.black, transparency: 100 },
  });
  addSectionLabel(slide, "The missing first step", "E7D4BC");
  addText(slide, "The first eye check\nshould not depend\non distance.", {
    x: 0.72, y: 1.18, w: 5.65, h: 2.3,
    fontSize: 42, bold: true, color: C.white, breakLine: true,
    lineSpacingMultiple: 0.9,
  });
  addText(slide, "Age, access and complexity can turn a simple check into a barrier.", {
    x: 0.75, y: 3.85, w: 4.9, h: 0.66,
    fontSize: 18, color: "ECECEC",
  });
  slide.addShape(SH.line, {
    x: 0.75, y: 5.22, w: 1.1, h: 0,
    line: { color: C.gold, width: 4 },
  });
  addPageNumber(slide, 2, "D8C4AB");
  addNotes(slide, "0:15 to 0:45", "For many older adults and people in remote communities, eye care is not a simple appointment. Distance, transport, confusing interfaces and needing someone else to help can become missing blocks. We asked: could the phone connect that first block without pretending to replace a clinician? That became SeeNA.");
}

// Slide 3: Product reveal
{
  const slide = pptx.addSlide();
  slide.background = { color: C.paper };
  addSectionLabel(slide, "The product");
  addText(slide, "Press Start.\nSeeNA guides the rest.", {
    x: 0.72, y: 1.05, w: 5.05, h: 1.38,
    fontSize: 42, bold: true, breakLine: true, lineSpacingMultiple: 0.92,
  });
  addText(slide, "No charts. No typing. No technical setup.", {
    x: 0.75, y: 2.72, w: 4.9, h: 0.35,
    fontSize: 18, color: C.grey,
  });

  const steps = [
    ["01", "Listen"],
    ["02", "Look"],
    ["03", "Answer"],
  ];
  steps.forEach((step, i) => {
    const y = 3.53 + i * 0.86;
    slide.addShape(SH.ellipse, {
      x: 0.76, y, w: 0.46, h: 0.46,
      fill: { color: i === 0 ? C.gold : C.black }, line: { color: i === 0 ? C.gold : C.black },
    });
    addText(slide, step[0], {
      x: 0.76, y: y + 0.08, w: 0.46, h: 0.2,
      fontSize: 9, bold: true, align: "center", color: i === 0 ? C.black : C.white,
    });
    addText(slide, step[1], {
      x: 1.48, y: y + 0.04, w: 2.5, h: 0.32,
      fontSize: 21, bold: true,
    });
    if (i < steps.length - 1) {
      slide.addShape(SH.line, { x: 0.99, y: y + 0.5, w: 0, h: 0.38, line: { color: C.line, width: 2 } });
    }
  });

  slide.addShape(SH.roundRect, {
    x: 6.12, y: 0.53, w: 6.45, h: 6.35,
    rectRadius: 0.12,
    fill: { color: C.white }, line: { color: C.line, width: 1 },
  });
  addPhone(slide, SCREENS.start, 8.14, 0.78, 2.42, 5.27, "SeeNA start screen");
  addPill(slide, "VOICE STARTS AFTER TAP", 7.58, 6.26, 3.55, C.black, C.white, C.black);
  addPageNumber(slide, 3);
  addNotes(slide, "0:45 to 1:10", "The experience is deliberately simple. Press Start. SeeNA speaks every step, uses the front sensors to help the person get into position, then presents one large target at a time. The user answers naturally by voice, including ‘I cannot see it.’ No charts, typing or technical setup.");
}

// Slide 4: Embedded one-minute demo
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  addSectionLabel(slide, "SeeNA in action", C.lightGrey);
  addText(slide, "60 seconds.\nOne complete journey.", {
    x: 0.72, y: 1.2, w: 3.7, h: 1.5,
    fontSize: 39, bold: true, color: C.white, breakLine: true, lineSpacingMultiple: 0.92,
  });
  addText(slide, "Play the one-minute walkthrough.", {
    x: 0.74, y: 3.0, w: 3.2, h: 0.32,
    fontSize: 16, color: C.lightGrey,
  });

  const flow = ["Position", "Screen", "Understand", "Review"];
  flow.forEach((label, i) => {
    const y = 4.0 + i * 0.55;
    slide.addShape(SH.rect, {
      x: 0.76, y: y + 0.07, w: 0.22, h: 0.22,
      fill: { color: i === 0 ? C.gold : C.white }, line: { color: i === 0 ? C.gold : C.white },
    });
    addText(slide, label, {
      x: 1.22, y, w: 2.2, h: 0.29,
      fontSize: 15, bold: true, color: C.white,
    });
  });

  const cover = `data:image/jpeg;base64,${fs.readFileSync(SCREENS.start).toString("base64")}`;
  slide.addShape(SH.roundRect, {
    x: 5.02, y: 0.48, w: 3.32, h: 6.66,
    rectRadius: 0.11,
    fill: { color: "1B1B1B" }, line: { color: "333333", width: 1.2 },
    shadow: makeShadow(0.42, 15, 3),
  });
  slide.addMedia({
    type: "video", path: DEMO, cover,
    x: 5.13, y: 0.59, w: 3.10, h: 6.44,
    objectName: "SeeNA 60-second product demo",
  });
  addImageContain(slide, APP_ICON, 5.86, 2.3, 1.65, 1.65, "SeeNA play poster mark");
  addPill(slide, "PLAY 1:00", 5.69, 4.34, 2.0, C.white, C.black, C.white);

  slide.addShape(SH.roundRect, {
    x: 9.28, y: 1.35, w: 3.08, h: 4.75,
    rectRadius: 0.08,
    fill: { color: "111111" }, line: { color: "333333", width: 1 },
  });
  addText(slide, "ONE TARGET", { x: 9.66, y: 1.78, w: 2.3, h: 0.26, fontSize: 11, bold: true, color: C.gold, charSpacing: 2.1 });
  addText(slide, "One answer.", { x: 9.66, y: 2.14, w: 2.2, h: 0.4, fontSize: 24, bold: true, color: C.white });
  slide.addShape(SH.line, { x: 9.66, y: 2.82, w: 2.0, h: 0, line: { color: "3A3A3A", width: 1 } });
  addText(slide, "VOICE GUIDED", { x: 9.66, y: 3.18, w: 2.3, h: 0.26, fontSize: 11, bold: true, color: C.gold, charSpacing: 2.1 });
  addText(slide, "Hands free.", { x: 9.66, y: 3.54, w: 2.2, h: 0.4, fontSize: 24, bold: true, color: C.white });
  slide.addShape(SH.line, { x: 9.66, y: 4.22, w: 2.0, h: 0, line: { color: "3A3A3A", width: 1 } });
  addText(slide, "REVIEWABLE", { x: 9.66, y: 4.58, w: 2.3, h: 0.26, fontSize: 11, bold: true, color: C.gold, charSpacing: 2.1 });
  addText(slide, "Every answer.", { x: 9.66, y: 4.94, w: 2.3, h: 0.4, fontSize: 24, bold: true, color: C.white });
  addPageNumber(slide, 4, C.lightGrey);
  addNotes(slide, "1:10 to 2:10", "Here is the complete flow. After Start, SeeNA checks distance, gaze, lighting and stillness, guiding the user with human instructions. Once positioned, it counts down and begins. The first task is Landolt C: the person says where the circle opens. The second is a Gabor pattern: they say left or right. Each eye is screened separately, and the target waits for the answer. At the end, SeeNA returns an estimated screening result for each eye, explains it in plain language and lets the user inspect every prompt, correct answer and response. The goal is not to make a diagnosis from a phone. It is to provide a clear first signal and a better reason to seek a complete eye examination.");
}

// Slide 5: UX and evidence
{
  const slide = pptx.addSlide();
  slide.background = { color: C.paper };
  addSectionLabel(slide, "Designed for independence");
  addText(slide, "One target. One answer. Full transparency.", {
    x: 0.72, y: 0.82, w: 9.7, h: 0.54,
    fontSize: 34, bold: true,
  });

  const items = [
    [SCREENS.landolt, "01", "Circle"],
    [SCREENS.gabor, "02", "Pattern"],
    [SCREENS.result, "03", "Result"],
    [SCREENS.answers, "04", "Review"],
  ];
  const sw = 2.08;
  const sh = 4.52;
  const gap = 0.46;
  const total = sw * 4 + gap * 3;
  const startX = (13.333 - total) / 2;
  items.forEach((item, i) => {
    const x = startX + i * (sw + gap);
    addPhone(slide, item[0], x, 1.65, sw, sh, `${item[2]} screen`);
    addText(slide, item[1], {
      x, y: 6.45, w: 0.35, h: 0.22,
      fontSize: 10.5, bold: true, color: C.gold,
    });
    addText(slide, item[2], {
      x: x + 0.42, y: 6.4, w: 1.48, h: 0.29,
      fontSize: 15.5, bold: true,
    });
  });
  addPageNumber(slide, 5);
  addNotes(slide, "2:10 to 2:45", "Every design decision supports independence. Large targets remain visible at a practical distance. Voice begins only after Start. Prompts do not overlap or cut each other off. Positioning allows natural human movement. If the target is not visible, SeeNA accepts that as useful evidence instead of forcing a guess. Results are readable, and every answer remains reviewable.");
}

// Slide 6: Trust architecture
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  addSectionLabel(slide, "Built for trust", C.lightGrey);
  addText(slide, "The phone screens. AI explains.", {
    x: 0.72, y: 0.86, w: 8.0, h: 0.62,
    fontSize: 38, bold: true, color: C.white,
  });
  addText(slide, "The number never comes from a model.", {
    x: 8.75, y: 1.01, w: 3.82, h: 0.35,
    fontSize: 17, bold: true, color: C.gold, align: "right",
  });

  addText(slide, "ON IPHONE", { x: 0.78, y: 2.0, w: 2, h: 0.25, fontSize: 10.5, bold: true, color: C.gold, charSpacing: 2.2 });
  const blocks = [
    [0.78, "TrueDepth\n+ Motion"],
    [3.20, "Quality\ngates"],
    [5.62, "Landolt C\n+ Gabor"],
    [8.04, "Local\nestimate"],
  ];
  blocks.forEach((b, i) => {
    addSmallBlock(slide, b[0], 2.42, 1.88, 1.42, b[1], "", false);
    if (i < blocks.length - 1) addConnector(slide, b[0] + 1.94, 3.13, 0.34, C.gold);
  });

  addText(slide, "VOICE + EXPLANATION", { x: 0.78, y: 4.42, w: 2.8, h: 0.25, fontSize: 10.5, bold: true, color: C.gold, charSpacing: 2.2 });
  addSmallBlock(slide, 0.78, 4.84, 2.35, 1.25, "Voice answer", "Natural speech", true);
  addConnector(slide, 3.23, 5.46, 0.48, C.white);
  addSmallBlock(slide, 3.83, 4.84, 2.52, 1.25, "Transcription", "Text only", true);
  addConnector(slide, 6.45, 5.46, 0.48, C.white);
  addSmallBlock(slide, 7.05, 4.84, 2.72, 1.25, "Explanation", "Plain language", true);

  slide.addShape(SH.roundRect, {
    x: 10.4, y: 2.42, w: 2.15, h: 3.67,
    rectRadius: 0.08,
    fill: { color: C.gold }, line: { color: C.gold },
  });
  addText(slide, "NO RAW\nCAMERA\nFRAMES", {
    x: 10.73, y: 2.9, w: 1.5, h: 1.15,
    fontSize: 22, bold: true, color: C.black, align: "center", valign: "mid", breakLine: true,
  });
  addText(slide, "No face mesh\nsent to AI", {
    x: 10.73, y: 4.62, w: 1.5, h: 0.6,
    fontSize: 13, bold: true, color: C.black, align: "center", breakLine: true,
  });
  addPageNumber(slide, 6, C.lightGrey);
  addNotes(slide, "2:45 to 3:20", "Trust comes from separating screening from explanation. TrueDepth and motion signals enforce quality gates. Landolt C and Gabor responses are scored deterministically on the iPhone. OpenAI transcription converts speech to text, and GPT-5.6 Luna explains the result in plain language under a strict schema. AI never creates or changes the numeric estimate. Raw camera frames, face meshes and biometric data are not sent to OpenAI.");
}

// Slide 7: Impact
{
  const slide = pptx.addSlide();
  slide.background = { color: C.paper };
  addSectionLabel(slide, "Why it matters");
  addImageCover(slide, path.join(ROOT, "DesignAssets/SeeNA-Pitch-Closing-Frame.png"), 7.15, 0, 6.183, 7.5, "Older woman holding a phone with a vision target in a remote community");
  slide.addShape(SH.rect, {
    x: 6.85, y: 0, w: 0.58, h: 7.5,
    fill: { color: C.paper, transparency: 0 }, line: { color: C.paper, transparency: 100 },
  });
  addText(slide, "Access begins with what\npeople already have.", {
    x: 0.72, y: 1.18, w: 5.8, h: 1.32,
    fontSize: 40, bold: true, breakLine: true, lineSpacingMultiple: 0.92,
  });
  addText(slide, "A phone. A voice. A clear next step.", {
    x: 0.75, y: 2.83, w: 5.4, h: 0.36,
    fontSize: 18, color: C.grey,
  });

  const impact = [
    ["01", "Independent"],
    ["02", "Approachable"],
    ["03", "Actionable"],
  ];
  impact.forEach((it, i) => {
    const x = 0.75 + i * 1.93;
    const y = 4.34;
    slide.addShape(SH.roundRect, {
      x, y, w: 1.67, h: 1.22,
      rectRadius: 0.06,
      fill: { color: i === 1 ? C.black : C.white },
      line: { color: i === 1 ? C.black : C.line, width: 1 },
      shadow: i === 1 ? makeShadow(0.18, 9, 2) : undefined,
    });
    addText(slide, it[0], { x: x + 0.18, y: y + 0.18, w: 0.4, h: 0.2, fontSize: 9.5, bold: true, color: C.gold });
    addText(slide, it[1], { x: x + 0.18, y: y + 0.57, w: 1.35, h: 0.3, fontSize: 15.5, bold: true, color: i === 1 ? C.white : C.ink });
  });
  addPageNumber(slide, 7);
  addNotes(slide, "3:20 to 3:45", "SeeNA is for the moment before access: an older person screening independently, a family checking someone at home, or a remote community needing a first signal. It makes screening more approachable while keeping the next step clear: a complete eye examination when the result indicates concern.");
}

// Slide 8: Close
{
  const slide = pptx.addSlide();
  slide.background = { color: "000000" };
  addImageContain(slide, APP_ICON, 0.78, 0.62, 1.08, 1.08, "SeeNA app icon");
  addPill(slide, "SYNCS HACKATHON 2026", 10.05, 0.7, 2.5, C.white, C.black, C.white);
  addText(slide, "A first step toward clarity.\nFor anyone, anywhere.", {
    x: 0.78, y: 2.0, w: 8.9, h: 1.65,
    fontSize: 44, bold: true, color: C.white, breakLine: true, lineSpacingMultiple: 0.9,
  });
  addText(slide, "SeeNA", {
    x: 0.8, y: 4.1, w: 2.2, h: 0.58,
    fontSize: 33, bold: true, color: C.gold,
  });
  addText(slide, "See Now and Always", {
    x: 0.82, y: 4.72, w: 3.3, h: 0.32,
    fontSize: 16, color: C.lightGrey,
  });

  slide.addShape(SH.line, { x: 0.8, y: 5.62, w: 11.75, h: 0, line: { color: "2B2B2B", width: 1 } });
  addText(slide, "Karthik Ramesh", { x: 0.8, y: 6.05, w: 2.5, h: 0.3, fontSize: 14, bold: true, color: C.white });
  addText(slide, "Kishore Srinivasan", { x: 3.72, y: 6.05, w: 2.7, h: 0.3, fontSize: 14, bold: true, color: C.white });
  addText(slide, "Suryateja Challa", { x: 6.92, y: 6.05, w: 2.5, h: 0.3, fontSize: 14, bold: true, color: C.white });
  addText(slide, "Sujan Ramesh", { x: 9.96, y: 6.05, w: 2.2, h: 0.3, fontSize: 14, bold: true, color: C.white });
  addText(slide, "Because everyone deserves to see their world, now and always.", {
    x: 7.62, y: 4.28, w: 4.9, h: 0.64,
    fontSize: 20, color: C.white, align: "right", bold: true,
  });
  addNotes(slide, "3:45 to 4:00", "Technology should connect the blocks that access leaves missing. SeeNA turns the phone already in a person's hand into a first step toward clarity, because everyone deserves to see their world, now and always. We are SeeNA.");
}

pptx.writeFile({ fileName: OUT, compression: true });
