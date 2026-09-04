const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(__dirname, "SeeNA-Syncs-Hackathon-2026-Pitch.pptx");
const HERO = path.join(ROOT, "docs/assets/seena-hero.png");
const APP_ICON = path.join(ROOT, "SeeNA/Assets.xcassets/AppIcon.appiconset/SEENA-AppIcon.png");
const DEMO_VIDEO = path.join(__dirname, "SeeNA-Walkthrough-Voiceover-88s.mp4");
const SCREENS = {
  start: path.join(ROOT, "docs/assets/screens/01-start.jpg"),
  landolt: path.join(ROOT, "docs/assets/screens/02-landolt-c.jpg"),
  gabor: path.join(ROOT, "docs/assets/screens/03-gabor.jpg"),
  result: path.join(ROOT, "docs/assets/screens/04-result.jpg"),
  answers: path.join(ROOT, "docs/assets/screens/05-answer-review.jpg"),
};
const DEMO_COVER = `data:image/jpeg;base64,${fs.readFileSync(SCREENS.start).toString("base64")}`;

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
  addText(slide, "A voice-guided visual task companion.", {
    x: 0.8, y: 5.02, w: 4.7, h: 0.38,
    fontSize: 18, color: "E8E8E8",
  });
  addText(slide, "SeeNA  |  See Now and Always", {
    x: 0.8, y: 6.67, w: 3.4, h: 0.22,
    fontSize: 10.5, bold: true, color: C.lightGrey, charSpacing: 0.8,
  });
  addNotes(slide, "0:00 to 0:12", "Most eye checks begin with a clinic appointment. SeeNA begins with the iPhone already in your hand, making the first step simple, independent and understandable.");
}

// Slide 2: Problem
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  addSectionLabel(slide, "The missing first step", C.lightGrey);
  addText(slide, "For many people, the first eye check is already out of reach.", {
    x: 0.72, y: 1.02, w: 10.6, h: 1.18,
    fontSize: 39, bold: true, color: C.white,
  });
  addText(slide, "A simple need becomes a chain of barriers.", {
    x: 0.75, y: 2.45, w: 5.5, h: 0.36,
    fontSize: 18, color: C.lightGrey,
  });

  const barriers = [
    ["01", "DISTANCE", "The nearest check may be far away."],
    ["02", "DEPENDENCE", "Travel and unfamiliar tools can require help."],
    ["03", "DELAY", "Without an accessible first step, action is postponed."],
  ];
  barriers.forEach((item, i) => {
    const x = 0.74 + i * 4.05;
    const isKey = i === 1;
    slide.addShape(SH.roundRect, {
      x, y: 3.38, w: 3.68, h: 2.34,
      rectRadius: 0.08,
      fill: { color: isKey ? C.gold : "111111" },
      line: { color: isKey ? C.gold : "303030", width: 1 },
    });
    addText(slide, item[0], {
      x: x + 0.28, y: 3.68, w: 0.55, h: 0.28,
      fontSize: 11, bold: true, color: isKey ? C.black : C.gold,
    });
    addText(slide, item[1], {
      x: x + 0.28, y: 4.18, w: 3.05, h: 0.38,
      fontSize: 22, bold: true, color: isKey ? C.black : C.white,
      charSpacing: 0.7,
    });
    addText(slide, item[2], {
      x: x + 0.28, y: 4.78, w: 2.98, h: 0.55,
      fontSize: 13, color: isKey ? "292929" : C.lightGrey,
      valign: "top",
    });
  });
  addPageNumber(slide, 2, C.lightGrey);
  addNotes(slide, "0:12 to 0:32", "For older adults and remote communities, distance, transport and dependence can turn a simple check into a chain of barriers. People delay action not because vision does not matter, but because the first step is hard to reach. SeeNA reconnects that missing block without pretending to replace an optometrist.");
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
  addNotes(slide, "0:32 to 0:45", "One tap starts the experience. SeeNA speaks every instruction, guides positioning, shows one large target at a time and waits for a natural voice answer. No chart, typing or technical setup.");
}

// Slide 4: Embedded walkthrough with voiceover
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  slide.addShape(SH.roundRect, {
    x: 0.72, y: 0.36, w: 3.45, h: 6.88,
    rectRadius: 0.11,
    fill: { color: "141414" }, line: { color: "353535", width: 1.2 },
    shadow: makeShadow(0.38, 14, 3),
  });
  slide.addMedia({
    type: "video",
    path: DEMO_VIDEO,
    cover: DEMO_COVER,
    x: 0.84, y: 0.48, w: 3.21, h: 6.64,
    objectName: "SeeNA product walkthrough with voiceover",
  });
  addImageContain(slide, APP_ICON, 1.62, 2.64, 1.36, 1.36, "SeeNA video poster mark");
  addPill(slide, "1:28 PRODUCT WALKTHROUGH", 4.86, 0.68, 2.92, C.gold, C.black, C.gold);
  addText(slide, "The complete\nSeeNA journey.", {
    x: 4.84, y: 1.52, w: 6.7, h: 1.48,
    fontSize: 45, bold: true, color: C.white, breakLine: true, lineSpacingMultiple: 0.9,
  });
  const journey = [
    ["01", "Guided positioning"],
    ["02", "One target at a time"],
    ["03", "Summary and answer review"],
  ];
  journey.forEach((item, i) => {
    const y = 3.62 + i * 0.86;
    addText(slide, item[0], { x: 4.9, y: y + 0.03, w: 0.42, h: 0.24, fontSize: 11, bold: true, color: C.gold });
    addText(slide, item[1], { x: 5.55, y, w: 4.8, h: 0.34, fontSize: 20, bold: true, color: C.white });
    if (i < journey.length - 1) {
      slide.addShape(SH.line, { x: 5.55, y: y + 0.55, w: 4.7, h: 0, line: { color: "303030", width: 1 } });
    }
  });
  addText(slide, "Click the video frame to play with sound. 1:28.", {
    x: 4.9, y: 6.48, w: 5.7, h: 0.28,
    fontSize: 13, color: C.lightGrey,
  });
  addPageNumber(slide, 4, C.lightGrey);
  addNotes(slide, "0:45 to 2:13", "Presenter pauses. Play the embedded 1 minute 28.44 second walkthrough with sound. Do not add narration over the video.");
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
    [SCREENS.landolt, "01", "8 circles"],
    [SCREENS.gabor, "02", "8 patterns"],
    [SCREENS.result, "03", "Task summary"],
    [SCREENS.answers, "04", "Answer review"],
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
  addNotes(slide, "2:13 to 2:38", "Each eye completes eight Landolt C circles and eight Gabor patterns, one at a time. SeeNA asks for the opening or tilt, waits for every answer, and accepts ‘I cannot see it’ honestly instead of guessing. The user gets a clear task summary and can review every target, correct answer and accepted response.");
}

// Slide 6: Trust architecture, expressed through the product
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  addSectionLabel(slide, "Built for trust", C.lightGrey);
  addText(slide, "The summary comes from the task.\nNot the model.", {
    x: 0.72, y: 0.88, w: 9.2, h: 1.15,
    fontSize: 40, bold: true, color: C.white, breakLine: true, lineSpacingMultiple: 0.9,
  });
  addPhone(slide, SCREENS.result, 0.92, 2.2, 2.12, 4.61, "SeeNA qualitative task summary screen", C.white);

  const trust = [
    ["01", "Scored on the iPhone", "Landolt C and Gabor answers are scored locally."],
    ["02", "AI explains only", "Plain-language context, without changing local evidence."],
    ["03", "Private by design", "No raw camera frames or face mesh sent to OpenAI."],
  ];
  trust.forEach((item, i) => {
    const y = 2.2 + i * 1.54;
    slide.addShape(SH.roundRect, {
      x: 3.78, y, w: 8.5, h: 1.17,
      rectRadius: 0.06,
      fill: { color: i === 1 ? C.gold : "111111" },
      line: { color: i === 1 ? C.gold : "303030", width: 1 },
    });
    addText(slide, item[0], {
      x: 4.08, y: y + 0.2, w: 0.45, h: 0.22,
      fontSize: 10.5, bold: true, color: i === 1 ? C.black : C.gold,
    });
    addText(slide, item[1], {
      x: 4.75, y: y + 0.15, w: 3.25, h: 0.34,
      fontSize: 21, bold: true, color: i === 1 ? C.black : C.white,
    });
    addText(slide, item[2], {
      x: 8.05, y: y + 0.17, w: 3.75, h: 0.54,
      fontSize: 12.5, color: i === 1 ? C.black : C.lightGrey, valign: "mid",
    });
  });
  addPageNumber(slide, 6, C.lightGrey);
  addNotes(slide, "2:38 to 3:13", "The architecture separates local evidence from explanation. TrueDepth, motion, lighting, gaze and stillness checks run on the device to protect task quality. Landolt C and Gabor responses are scored deterministically on the iPhone. OpenAI transcription turns speech into text, and GPT-5.6 Luna explains the finished qualitative summary in plain language. AI never changes the local score, and raw camera frames and face-mesh data are not sent to OpenAI.");
}

// Slide 7: Product-focused impact using only real app screens
{
  const slide = pptx.addSlide();
  slide.background = { color: C.black };
  addSectionLabel(slide, "Why it matters", C.lightGrey);
  addText(slide, "Access starts with the phone already there.", {
    x: 0.72, y: 1.1, w: 6.2, h: 1.18,
    fontSize: 40, bold: true, color: C.white,
  });
  addText(slide, "SeeNA turns one tap into an independent first step.", {
    x: 0.75, y: 2.55, w: 4.95, h: 0.56,
    fontSize: 18, color: C.lightGrey,
  });
  addPill(slide, "AT HOME", 0.74, 3.55, 1.38, C.white, C.black, C.white);
  addPill(slide, "VOICE GUIDED", 2.32, 3.55, 1.72, C.white, C.black, C.white);
  addPill(slide, "REVIEWABLE", 4.24, 3.55, 1.6, C.gold, C.black, C.gold);

  slide.addShape(SH.line, {
    x: 6.15, y: 3.72, w: 0.78, h: 0,
    line: { color: C.gold, width: 2.3, endArrowType: "triangle" },
  });
  addText(slide, "START", {
    x: 6.65, y: 0.9, w: 1.1, h: 0.22,
    fontSize: 10.5, bold: true, color: C.gold, charSpacing: 1.7, align: "center",
  });
  addPhone(slide, SCREENS.start, 6.6, 1.3, 2.24, 4.88, "SeeNA start screen", C.white);
  addText(slide, "RESULT", {
    x: 9.57, y: 0.9, w: 1.1, h: 0.22,
    fontSize: 10.5, bold: true, color: C.gold, charSpacing: 1.7, align: "center",
  });
  addPhone(slide, SCREENS.result, 9.46, 1.3, 2.24, 4.88, "SeeNA qualitative task summary screen", C.white);
  slide.addShape(SH.line, {
    x: 8.92, y: 3.72, w: 0.38, h: 0,
    line: { color: C.gold, width: 2.3, endArrowType: "triangle" },
  });
  addText(slide, "One guided experience", {
    x: 7.42, y: 6.52, w: 3.4, h: 0.28,
    fontSize: 14, bold: true, color: C.white, align: "center",
  });
  addPageNumber(slide, 7, C.lightGrey);
  addNotes(slide, "3:13 to 3:37", "SeeNA supports the moment before access: an older adult at home, a family helping someone they love, or a remote community looking for a simpler first step. The phone already there becomes a guided, reviewable experience. SeeNA stays honest about its limits and keeps the next action clear: routine professional eye care still matters.");
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
  addNotes(slide, "3:37 to 4:00", "Our world is built from people, communities, and access. But when eye care becomes a missing block, distance and age can leave someone behind. SeeNA reconnects that block, turning the phone already in their hand into a first step toward clarity. Because everyone deserves to see their world, now and always.");
}

pptx.writeFile({ fileName: OUT, compression: true });
