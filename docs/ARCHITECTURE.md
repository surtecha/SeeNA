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
       pixel-aligned Landolt C row
                    |
      local score and threshold search
                    |
       local screening range/evidence
```

The backend owns bounded language operations only:

```text
iPhone .m4a -> /api/transcribe-block -> gpt-transcribe -> transcript
                                                    -> deterministic parser

qualitative facts -> /api/explain-result -> gpt-5.6-luna strict JSON
profile + fixture -> /api/adapt-content  -> gpt-5.6-luna strict JSON
```

The app sends no numeric measurement to the explanation model. This makes numeric integrity structural rather than prompt-dependent.

## iOS state and dependencies

`AppSession` owns route history, the active `ScreeningSession`, sensor presentation state, the accessibility answers/profile and cached language responses. Feature-local view models own onboarding interaction, permission orchestration, phone/gaze readiness, baseline calibration, threshold search and readability state. Views render those models and forward user intent; service side effects stay in the models. `AppDependencies` constructs the profile registry, protected session store, sensor coordinator, recorder, female spoken-prompt service, backend client and brightness restorer.

There are no global service singletons and no networking calls inside a SwiftUI `body`.

## Distance measurement

ARKit transforms the two eye anchors into world space, averages them and converts the eye centre back into camera coordinates. The perpendicular camera-space depth is the metric source. Projected inter-eye pixel distance supplies a relative-scale source anchored at the 40 cm baseline. A yaw correction reduces the apparent-width effect, then a conservative 72/28 metric/relative fusion is filtered through a 10–15 sample window, MAD outlier rejection and rolling median.

An exact-device affine fit applies:

```text
corrected distance = scale * fused distance + offset
```

No bundled profile is marked validated. A locally persisted profile requires 150 valid samples at each of 0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50 and 2.00 metres and must pass the acceptance rules in `VALIDATION.md`.

## Optotype and search

The renderer creates a 1x monochrome bitmap whose native dimensions equal the calculated physical pixels. Outer diameter is `H`, stroke and gap are `H/5`, and inner diameter is `3H/5`. `H` is rounded to a multiple of five and displayed at `H / nativeScale` points with interpolation disabled.

Each block generates seven random up/right/down/left targets. Exactly seven parsed responses are scored locally:

- 5–7 correct: pass.
- 0–3 correct: fail.
- 4 correct: repeat once.
- Invalid quality or count: discard/retry, then no reliable result after the retry budget.

The search moves through −0.50, −1.00, −1.50, −2.00 and −2.50 D candidate positions, tests a quarter-diopter midpoint after bracketing, and confirms the passing threshold. The displayed estimate uses the actual measured median distance, not the candidate label.

## Backend security

- OpenAI key exists only in server environment variables.
- Requests require `POST`, a timing-safe app-token comparison and a best-effort per-instance rate limit.
- Audio MIME, count and 5 MB size are bounded; temporary files are removed in `finally`.
- Text inputs and outputs use strict Zod schemas.
- Responses API calls set `store: false`, `tools: []` and strict JSON Schema.
- AI failures return deterministic, schema-valid content and never block local evidence/results.
- Responses are marked `no-store` and `nosniff`.

## Persistence and privacy

Completed sessions are encoded as schema-versioned JSON under Application Support with complete file protection and atomic writes. Stored data is limited to directions, responses, derived distances, quality decisions, result ranges and accessibility settings. Raw video, frames, meshes, images, audio and biometric templates are not retained.
