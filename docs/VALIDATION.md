# Validation protocol

Numeric screening must remain disabled until the exact physical iPhone completes this protocol. Simulator results, Apple specifications and another model’s calibration are not substitutes.

## Equipment and setup

- Exact iPhone to be demonstrated, running the candidate build.
- Rigid portrait stand at participant eye height.
- Rigid tape measure whose zero is aligned to the screen plane.
- Floor marks at 0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50 and 2.00 m.
- Even front lighting, quiet room and clear movement path.
- One consenting adult participant for calibration; multiple participants for comparison.

Record the hardware identifier, iOS version, build commit, room, stand and operator in the evidence notes.

## Distance calibration

1. Run a Debug build and open **Device compatibility → Open physical calibration tool**.
2. Lock the phone position. Do not move the stand until all distances complete.
3. Align the participant’s eye plane, not toes or face surface, with the active tape mark.
4. Centre one face, face the phone directly and wait for stationarity.
5. Collect 150 valid fused samples at that mark.
6. Repeat at all eight marks. Never substitute or copy a position.
7. Select **Fit, verify and enable this profile**.

The app fits one affine correction and rejects it unless every distance exists and:

- Median absolute error is at most 0.03 m at each point below 1.00 m.
- Median percentage error is at most 5% at each point at or above 1.00 m.
- At least 1,200 accepted samples exist.
- The validated range spans 0.40–2.00 m.

The evidence record stores the maximum per-distance median near error and maximum per-distance median far percentage error. A rejected fit never enables numeric screening.

Repeat the protocol after a major iOS/ARKit change, sensor implementation change, screen replacement, camera/stand geometry change or unexplained distance drift.

## iOS 26 POC simulator smoke test

Simulator checks validate app installation, launch stability and responsive SwiftUI rendering. They do not validate TrueDepth distance accuracy, microphone acoustics, Core Motion behavior or a physical device profile.

Build with Xcode 26, install on one representative iOS 26 iPhone simulator, launch the app and capture the onboarding, permissions, phone setup and calibration states. A pass requires a live process, responsive interaction and no crash through the core journey.

Do not use simulator success as evidence of TrueDepth distance accuracy, microphone acoustics, Core Motion stationarity or physical device calibration. The POC deployment target is iOS 26.0 so it can use native Liquid Glass controls without compatibility shims.

## Required physical tests

Record pass/fail, observed values, evidence screenshots and defects for each:

1. Tape-measure check at every validation distance after saving/relaunching.
2. Phone bump during a row: row is discarded and position must be restored.
3. Low camera luminance: row cannot be scored.
4. Head yaw/pitch beyond threshold: row cannot be scored.
5. Face leaves frame or a second face appears: row cannot be scored.
6. Network unavailable: one retry, operator input and deterministic explanation remain usable.
7. Quiet and deliberately noisy direction recordings: exact seven-word parsing or safe repeat.
8. Right-eye and left-eye completion with no copied/hardcoded responses.
9. Accessibility staircase, all four preferences and visible profile application.
10. Local history across relaunch, single-session deletion and delete-all.
11. Brightness restoration after completion, interruption and relaunch.
12. VoiceOver labels, Dynamic Type, contrast and 44-point minimum interactive targets.

## Accuracy comparison

Use consenting adults with recent professional prescriptions and uncomplicated myopia. They must not reveal the prescription until SEENA finishes. Remove contact lenses and distance glasses for an uncorrected screening. For cylinder, calculate the professional spherical equivalent only after the test:

```text
spherical equivalent = sphere + cylinder / 2
```

Record all eyes, including no-results. Report the difference between the professional spherical equivalent and the nearest edge/centre of SEENA’s range. Do not discard outliers, claim clinical validation, borrow accuracy figures from published studies or display a fabricated accuracy percentage.

Label the table **Informal hackathon comparison, not clinical validation**.

## Release gate

A demonstration build is not ready until:

- Swift, iOS, backend and live OpenAI checks pass on the exact commit.
- The physical calibration and all twelve physical tests above have dated evidence.
- Numeric screening remains locked on every unvalidated exact model.
- The deployed HTTPS backend and matching app token work from the physical phone.
- No API key, audio, face data or local session file is present in Git or the app bundle.
