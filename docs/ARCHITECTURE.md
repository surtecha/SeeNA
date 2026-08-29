# SEENA architecture

## Trust boundary

The iPhone owns every measurement and number:

```text
ARKit + relative face scale + Core Motion
                    |
                    v
        filtered distance sample
                    |
          quality gate + screen profile
                    |
       pixel-aligned Landolt C target
                    |
      local score and threshold search
                    |
       local screening range/evidence
```

The backend owns bounded language operations only:

```text
iPhone .m4a -> /api/transcribe-block -> gpt-transcribe -> transcript
                                                    -> deterministic parser

screening facts -> /api/explain-result -> gpt-5.6-luna explanation JSON
                                    -> independent consistency JSON
```

Explanation requests contain allow-listed qualitative codes only: no distances, diopters, uncertainty, repeatability or target measurements cross that boundary. The model cannot return a measurement field, and the backend rejects explanation text containing numbers or measurement units. If a future exact-device calibration unlocks numeric output, narration and rendering stay local/on-device. The app falls back to deterministic local wording unless the independent pass returns `consistent`.

## iOS state and dependencies

`AppSession` owns route history, the active `ScreeningSession`, sensor presentation state and cached explanation. Feature-local view models own onboarding interaction, permission orchestration, device checks, phone/gaze readiness, baseline calibration, processing/save decisions, the Landolt threshold search and the non-clinical Gabor orientation task. Views render those models and forward user intent; service side effects stay in the models. `AppDependencies` constructs the profile registry, protected session store, sensor coordinator, recorder, female spoken-prompt service, backend client and brightness restorer.

There are no global service singletons and no networking calls inside a SwiftUI `body`.

## Distance measurement

ARKit transforms the two eye anchors into world space, averages them and converts the eye centre back into camera coordinates. The perpendicular camera-space depth is the metric source. Projected inter-eye pixel distance supplies a relative-scale source anchored at the 40 cm baseline. A yaw correction reduces the apparent-width effect, then a conservative 72/28 metric/relative fusion is filtered through a 10–15 sample window, MAD outlier rejection and rolling median.

An exact-device affine fit applies:

```text
corrected distance = scale * fused distance + offset
```

No bundled profile is marked validated; every bundled `sampleCount` is zero. A locally persisted profile requires 150 valid samples at each of 0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50 and 2.00 metres and must pass the acceptance rules in `VALIDATION.md`. Numeric generation also requires second-person detection. Until every gate passes, completed rows are reduced to nonnumeric experimental task performance and cannot rule out myopia.

Missing gaze data is unavailable, never centred. Setup, calibration, countdown and each scored block use one shared hysteretic gaze-readiness policy and a minimum coverage gate. The current POC angles and coverage limits are conservative provisional settings; they have not been clinically validated.

## Optotype and search

The renderer creates a 1x monochrome bitmap whose native dimensions equal the calculated physical pixels. Outer diameter is `H`, stroke and gap are `H/5`, and inner diameter is `3H/5`. `H` is rounded to a multiple of five and displayed at `H / nativeScale` points with interpolation disabled.

Each block generates seven random up/right/down/left targets and presents only one at a time. A target changes only after its voice response is accepted. Exactly seven parsed responses are scored locally:

- 5–7 correct: pass.
- 0–3 correct: fail.
- 4 correct: repeat once.
- Invalid quality or count: discard/retry, then no reliable result after the retry budget.

The search starts at the closest supported point and moves outward through −2.50, −1.25 and −0.50 D. Once it brackets the first pass/fail transition it tests quarter-diopter midpoints and confirms the passing threshold. The displayed estimate uses the actual measured median distance, not the candidate label. A complete, symmetric locator ring helps the participant find the screen centre but is never scored; the small inner C retains the approximately five-arcminute geometry.

## Backend security

- OpenAI key exists only in server environment variables.
- Requests require `POST`, a timing-safe prototype app-token comparison, endpoint-specific request/cost limits and bounded request sizes.
- The static mobile app token is extractable and is not authentication, App Attest or a short-lived session. This remains a documented POC risk.
- When configured, a shared REST key-value counter enforces a durable daily cost-unit ceiling and fails closed if that quota service is unavailable. Provider spend alerts and real attestation/session issuance remain deployment work.
- Audio MIME, count and 5 MB size are bounded; temporary files are removed in `finally`.
- Text inputs and outputs use strict Zod schemas.
- Responses API calls set `store: false`, `tools: []` and strict JSON Schema.
- AI failures return deterministic, schema-valid content and never block local evidence/results.
- Responses are marked `no-store` and `nosniff`.

## Persistence and privacy

Completed sessions are encoded as schema-versioned JSON under Application Support with complete file protection and atomic writes. Stored data is limited to directions, responses, derived distances, quality decisions and result ranges. Raw video, frames, meshes, images, audio and biometric templates are not retained.
