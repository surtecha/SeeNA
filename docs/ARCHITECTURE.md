# SEENA architecture

## Trust boundary

The iPhone owns sensing, local quality evidence, task scoring, and every safety-critical calculation:

```text
ARKit + relative face scale + Core Motion
                    |
                    v
        filtered distance sample
                    |
          quality gate + screen profile
                    |
       large, pixel-aligned Landolt C target
                    |
      local score and answer evidence
                    |
     qualitative task outcome/evidence
```

The backend owns bounded language operations only:

```text
iPhone .m4a -> /api/transcribe-block -> gpt-transcribe -> transcript
                                                    -> deterministic parser

screening facts -> /api/explain-result -> gpt-5.6-luna explanation JSON
                                    -> independent consistency JSON
```

Explanation requests contain allow-listed qualitative codes only: no distances, diopters, uncertainty, repeatability or target measurements cross that boundary. The model cannot return a measurement field, and the backend rejects explanation text containing numbers or measurement units. If a future approved clinical protocol enables numeric output, narration and rendering stay local and on-device. The app falls back to deterministic local wording unless the independent pass returns `consistent`.

## iOS state and dependencies

`AppSession` owns route history, the active `ScreeningSession`, sensor presentation state and cached explanation. Feature-local view models own onboarding interaction, permission orchestration, device checks, phone and gaze readiness, baseline calibration, processing and save decisions, the one-target-at-a-time Landolt flow, and the Gabor orientation task. Views render those models and forward user intent; service side effects stay in the models. `AppDependencies` constructs the profile registry, protected session store, sensor coordinator, recorder, female spoken-prompt service, backend client and brightness restorer.

There are no global service singletons and no networking calls inside a SwiftUI `body`.

## Distance measurement

ARKit transforms the two eye anchors into world space, averages them and converts the eye centre back into camera coordinates. The perpendicular camera-space depth is the metric source. Projected inter-eye pixel distance supplies a relative-scale source anchored at the 40 cm baseline. A yaw correction reduces the apparent-width effect, then a conservative 72/28 metric/relative fusion is filtered through a 10 to 15 sample window, MAD outlier rejection and rolling median.

An exact-device affine fit applies:

```text
corrected distance = scale * fused distance + offset
```

No bundled profile is marked validated; every bundled `sampleCount` is zero. A locally persisted profile requires 150 valid samples at each of 0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50 and 2.00 metres and must pass the acceptance rules in `VALIDATION.md`. That calibration can establish only the distance-sensor behaviour on that exact setup. It cannot validate refractive inference.

The active phone task is deliberately release-locked to qualitative output. It uses one fixed 0.40 m position for both the Landolt C and Gabor blocks, so the participant does not walk between targets. Longer distances belong only to engineering calibration and a possible future clinical protocol; they are never active targets in this release.

`NumericResultEligibility` requires an approved protocol release, fixed five-arcminute geometry, no point-size clamping, a validated threshold model, sufficient responses per level, exact-device distance evidence, and session-quality gates. The approved release set is empty in this build, so no calibration profile or locally supplied data can unlock diopters. Completed sessions therefore retain qualitative task performance and answer evidence only. They cannot rule out myopia or any other eye condition.

Missing gaze data is unavailable, never centred. Gaze is a coaching signal, not a start or scoring gate, because availability and precision vary with face geometry, eyelids, and corrective lenses. Face count, head pose, lighting, distance, tracking coverage, and phone stability remain the objective conditions that can block or invalidate a task. The current gaze angles are conservative engineering settings, not clinical validation.

## Optotype and search

The renderer creates a 1x monochrome bitmap whose native dimensions equal the calculated physical pixels. Outer diameter is `H`, stroke and gap are `H/5`, and inner diameter is `3H/5`. `H` is rounded to a multiple of five and displayed at `H / nativeScale` points with interpolation disabled.

The active phone presentation uses a large, one-at-a-time Landolt C. Its point-size bounds are retained with each response so the rendered geometry is auditable. Each eye receives one block of eight targets, exactly two each of up, right, down, and left, with no adjacent repeats. It advances only after a response is accepted. The exact score is retained for answer review, but every structurally complete, quality-valid block receives the same neutral completion state. Invalid quality or count is discarded and retried, then recorded as repeat needed after the retry budget.

For four-choice random guessing, the exact probability of reaching the 6-of-8 pass threshold is `277 / 65,536 = 0.0042266845703125`. This describes only the score rule. It is not evidence of visual-acuity, refraction, or clinical accuracy.

The implementation retains exact visual-angle and distance conversions for calibration and future protocol work. In particular, `D = -1 / d` is exact dimensional optics only when `d` is a measured optical far point. A response to the current enlarged phone target is not an optical far-point measurement, so that identity is never used to create an eye-power result. The standard five-arcminute Landolt geometry remains a reference mode in the codebase but is not the active live presentation.

Gabor orientation is scored separately. Each eye receives one block of eight targets at a fixed 0.40 contrast, exactly four left and four right, in a shuffled order with no run of three. The exact score is retained for answer review, but every structurally complete, quality-valid block receives the same neutral completion state. For binary random guessing, the exact probability of reaching the internal 7-of-8 score threshold is `9 / 256 = 0.03515625`. This supports a deterministic answer audit only. The current display is not calibrated for luminance, gamma, contrast, or cycles per degree. It must not be interpreted as contrast sensitivity or used to derive refractive power.

## Backend security

- OpenAI key exists only in server environment variables.
- Requests require `POST`, a timing-safe static app-token comparison, endpoint-specific request and cost limits, and bounded request sizes.
- The static mobile app token is extractable and is not authentication, App Attest, or a short-lived session. This is a deployment risk that must be replaced before a production release.
- When configured, a shared REST key-value counter enforces a durable daily cost-unit ceiling and fails closed if that quota service is unavailable. Provider spend alerts and real attestation/session issuance remain deployment work.
- Audio MIME, count and 5 MB size are bounded; temporary files are removed in `finally`.
- Text inputs and outputs use strict Zod schemas.
- Responses API calls set `store: false`, `tools: []` and strict JSON Schema.
- AI failures return deterministic, schema-valid content and never block local evidence/results.
- Responses are marked `no-store` and `nosniff`.

## Persistence and privacy

Completed sessions are encoded as schema-versioned JSON under Application Support with complete file protection and atomic writes. Stored data is limited to directions, responses, derived distances, quality decisions and result ranges. Raw video, frames, meshes, images, audio and biometric templates are not retained.
