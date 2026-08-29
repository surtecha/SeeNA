# SeeNA

SeeNA (See Now and Always) is a native iPhone research prototype for guided myopia screening. The phone stays stationary while the participant moves. ARKit face tracking, relative facial scale and Core Motion estimate eye-to-screen distance; a pixel-controlled Landolt C preserves an approximately five-arcminute visual angle; deterministic local code scores both eyes. A separate Gabor orientation task records whether each pattern was identified, without claiming a clinical contrast-sensitivity result.

SeeNA reports an **approximate myopia screening range**, never an eyeglass prescription or diagnosis. A matched iPhone 14–16 display/TrueDepth profile can run the POC using raw ARKit distance; results remain explicitly unvalidated until that exact physical device passes the tape-measure calibration protocol. Unsupported, inconsistent or poor-quality conditions return no numeric result.

## What works

- Native SwiftUI iOS 26 POC, iPhone/portrait only, using a feature-level MVVM architecture.
- Purposeful interactive onboarding, restrained Liquid Glass actions, gaze feedback, haptics and Reduce Motion support.
- Eligibility and urgent-symptom safety stop, evaluated locally.
- Camera and microphone permission flow with explicit privacy language.
- Exact-hardware capability and screen-profile verification.
- ARKit eye-centre distance, relative-scale fusion, MAD rejection, rolling median and affine correction.
- Core Motion stationarity with attitude, rotation and rolling acceleration RMS gates.
- Eight-distance, 1,200-sample physical calibration harness with conservative acceptance limits.
- Core Graphics Landolt C rendering with integer five-part geometry and no bitmap interpolation.
- One answer-gated Landolt C at a time, right and left eye flows, coarse/fine/confirmation search and no-result boundaries.
- One answer-gated Gabor orientation at a time, reported only as completed or repeat needed.
- Bounded `.m4a` recording, live `gpt-transcribe`, deterministic direction/choice parsing and operator fallback.
- A serialized female voice channel for movement guidance, countdowns and responses, with no onboarding speech before Start.
- A review sheet showing every target, the accepted answer and the response source.
- Strict `gpt-5.6-luna` Responses API explanation and independent consistency passes using `store: false`, no tools and Zod validation.
- Deterministic fallback wording; OpenAI cannot create, alter or render a measurement number.
- Protected local JSON history, evidence mode, sharing and deletion.

## Repository

```text
SeeNA/       SwiftUI iPhone application
SeeNATests/  Pure measurement/state-engine XCTest suite
server/      TypeScript Vercel Functions and tests
docs/        Architecture, validation and demonstration procedures
```

## Run the iPhone app

Requirements:

- Xcode 26.6 or another compatible current Xcode.
- iOS 26 or later.
- A physical Face ID iPhone for face tracking and numeric calibration. The simulator supports UI/fallback testing only.

Open `SeeNA.xcodeproj`, select the `SeeNA` scheme and run on an iOS 26 simulator or physical iPhone. The simulator supports UI QA through explicit DEBUG-only mock flags. On a matched physical iPhone 14–16, the real sensor flow can produce an explicitly unvalidated POC range; an unknown display profile or inadequate evidence produces no number.

Before a device/backend test, configure the deployed HTTPS backend and matching prototype token without adding either value to Git:

```bash
SEENA_BACKEND_URL=https://your-backend.vercel.app \
SEENA_APP_TOKEN=your-64-character-token \
./scripts/configure-local-secrets.sh
```

Xcode loads the generated, ignored `Config/Secrets.xcconfig` for Debug and Release builds. The same command creates an ignored `SeeNA/Secrets.plist` resource so the values are available at runtime. A clean clone continues to use an intentionally invalid placeholder until this command is run.

The OpenAI key must never be added to the Xcode project, app bundle or mobile source.

## Run the backend

```bash
cd server
npm ci
npm run check
```

Copy `.env.example` to an ignored local env file and configure:

```text
OPENAI_API_KEY
OPENAI_TEXT_MODEL=gpt-5.6-luna
OPENAI_TRANSCRIBE_MODEL=gpt-transcribe
SEENA_APP_TOKEN
```

Deploy the `server` directory as the Vercel project root. Add the same environment variables in Vercel and use the HTTPS deployment URL in the iOS build setting.

## Verification

Pure Swift engines:

```bash
swift test
```

Full iOS compile:

```bash
xcodebuild \
  -project SeeNA.xcodeproj \
  -scheme SeeNA \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For this POC, simulator verification is deliberately narrow: compile once with Xcode 26, then install, launch and capture the core journey on one representative iOS 26 iPhone simulator. Physical TrueDepth, motion, microphone and distance accuracy still require a real device.

Backend contracts, types and security:

```bash
cd server
npm run check
npm audit --omit=dev
```

Physical accuracy cannot be established in the simulator. Follow [docs/VALIDATION.md](docs/VALIDATION.md) on every exact demonstration model before making any accuracy comparison; until then, the app marks the output as an unvalidated research POC.

## Privacy and truthfulness

Raw camera frames, face meshes, eye coordinates and biometric templates are never stored or sent to OpenAI. Only bounded response audio, non-identifying qualitative result facts and an allow-listed service-content fixture can leave the phone. Sessions remain in protected local storage and can be deleted in-app.

SeeNA v0 has not undergone clinical validation. It does not assess hyperopia, astigmatism, presbyopia or eye disease and is not a replacement for professional eye care.
