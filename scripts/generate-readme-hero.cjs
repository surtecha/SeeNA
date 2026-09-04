#!/usr/bin/env node

const path = require("node:path");
const sharp = require("sharp");

const repoRoot = path.resolve(__dirname, "..");
const assets = path.join(repoRoot, "docs", "assets");
const screens = path.join(assets, "screens");
const output = path.join(assets, "seena-hero.png");

const canvasWidth = 1920;
const canvasHeight = 1080;

function svgText() {
  return Buffer.from(`
    <svg width="${canvasWidth}" height="${canvasHeight}" viewBox="0 0 ${canvasWidth} ${canvasHeight}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <radialGradient id="spot" cx="78%" cy="48%" r="53%">
          <stop offset="0%" stop-color="#3b3b3f" stop-opacity="0.95"/>
          <stop offset="46%" stop-color="#171719" stop-opacity="0.78"/>
          <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="rule" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#ffffff" stop-opacity="0.72"/>
          <stop offset="100%" stop-color="#ffffff" stop-opacity="0.06"/>
        </linearGradient>
        <filter id="blur"><feGaussianBlur stdDeviation="42"/></filter>
      </defs>

      <rect width="1920" height="1080" fill="#000000"/>
      <rect width="1920" height="1080" fill="url(#spot)"/>
      <ellipse cx="1508" cy="535" rx="392" ry="488" fill="#ffffff" opacity="0.10" filter="url(#blur)"/>

      <rect x="122" y="858" width="760" height="2" fill="url(#rule)"/>

      <g fill="#ffffff" font-family="SF Pro Display, SF Pro Text, Helvetica Neue, Arial, sans-serif">
        <text x="390" y="474" font-size="142" font-weight="700" letter-spacing="-7">SeeNA</text>
        <text x="396" y="540" font-size="30" font-weight="520" letter-spacing="3.2" opacity="0.74">SEE NOW AND ALWAYS</text>
        <text x="124" y="700" font-size="55" font-weight="620" letter-spacing="-1.5">Eye screening.</text>
        <text x="124" y="765" font-size="55" font-weight="620" letter-spacing="-1.5">Guided by voice.</text>
        <text x="124" y="928" font-size="26" font-weight="650" letter-spacing="5" opacity="0.72">TAP  ·  LISTEN  ·  ANSWER</text>
      </g>

      <g transform="translate(124 186)">
        <rect width="226" height="80" rx="40" fill="#ffffff" opacity="0.10"/>
        <circle cx="42" cy="40" r="6" fill="#ffffff"/>
        <text x="67" y="49" fill="#ffffff" font-size="25" font-weight="650" font-family="SF Pro Text, Helvetica Neue, Arial, sans-serif" letter-spacing="1.2">VOICE FIRST</text>
      </g>
    </svg>
  `);
}

async function phone(imagePath, width, angle, frameTone) {
  const screenshot = await sharp(imagePath)
    .resize({ width, kernel: sharp.kernel.lanczos3 })
    .png()
    .toBuffer();

  const meta = await sharp(screenshot).metadata();
  const inset = 12;
  const phoneWidth = width + inset * 2;
  const phoneHeight = meta.height + inset * 2;
  const radius = Math.round(phoneWidth * 0.115);

  const frame = Buffer.from(`
    <svg width="${phoneWidth}" height="${phoneHeight}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="edge" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#f7f7f7"/>
          <stop offset="38%" stop-color="${frameTone}"/>
          <stop offset="72%" stop-color="#5b5b60"/>
          <stop offset="100%" stop-color="#f2f2f2"/>
        </linearGradient>
      </defs>
      <rect x="1" y="1" width="${phoneWidth - 2}" height="${phoneHeight - 2}" rx="${radius}" fill="url(#edge)"/>
      <rect x="7" y="7" width="${phoneWidth - 14}" height="${phoneHeight - 14}" rx="${radius - 6}" fill="#050505"/>
    </svg>
  `);

  return sharp({
    create: {
      width: phoneWidth,
      height: phoneHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([
      { input: frame, left: 0, top: 0 },
      { input: screenshot, left: inset, top: inset },
    ])
    .png()
    .rotate(angle, { background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .toBuffer();
}

async function main() {
  const [icon, gaborPhone, landoltPhone] = await Promise.all([
    sharp(path.join(repoRoot, "SeeNA", "Assets.xcassets", "AppIcon.appiconset", "SEENA-AppIcon.png"))
      .resize(226, 226)
      .png()
      .toBuffer(),
    phone(path.join(screens, "03-gabor.jpg"), 330, -7, "#b3b3b8"),
    phone(path.join(screens, "02-landolt-c.jpg"), 402, 5, "#d6d6da"),
  ]);

  const gaborMeta = await sharp(gaborPhone).metadata();
  const landoltMeta = await sharp(landoltPhone).metadata();

  await sharp(svgText())
    .composite([
      { input: icon, left: 122, top: 270 },
      { input: gaborPhone, left: 1050, top: 104 },
      {
        input: landoltPhone,
        left: canvasWidth - landoltMeta.width - 72,
        top: Math.round((canvasHeight - landoltMeta.height) / 2),
      },
    ])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(output);

  const metadata = await sharp(output).metadata();
  process.stdout.write(`Generated ${output} (${metadata.width}x${metadata.height})\n`);
  process.stdout.write(`Rear phone: ${gaborMeta.width}x${gaborMeta.height}; front phone: ${landoltMeta.width}x${landoltMeta.height}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
