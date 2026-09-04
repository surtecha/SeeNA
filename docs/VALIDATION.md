# Validation protocol

This document separates device-distance verification from clinical validation. Simulator results, Apple specifications, another model’s calibration, and a correct implementation of `D = -1 / d` are not evidence that the app can estimate refractive error. Numeric refractive output is disabled in the current release and remains disabled after this protocol.

The live phone journey uses one fixed 0.40 m position. The longer marks below exist only to characterize the sensor for engineering evidence and a possible future clinical protocol. They are not distances a participant is asked to use in the current flow.

## Equipment and setup

- Exact iPhone to be demonstrated, running the candidate build.
- Rigid portrait stand at participant eye height.
- Rigid tape measure whose zero is aligned to the screen plane.
- Floor marks at 0.40, 0.50, 0.67, 0.80, 1.00, 1.33, 1.50 and 2.00 m.
- Even front lighting, quiet room and clear movement path.
- One consenting adult participant for calibration; multiple participants for comparison.

Record the hardware identifier, iOS version, build commit, room, stand and operator in the evidence notes.

## Distance calibration

1. Add a temporary Debug-only host for `DeviceCalibrationHarnessView` in a local development branch, then run that build. Remove the host before producing the release candidate. The checked-in participant journey intentionally has no calibration-tool entry point.
2. Lock the phone position. Do not move the stand until all distances complete.
3. Align the participant’s eye plane, not toes or face surface, with the active tape mark.
4. Centre one face, face the phone directly and wait for stationarity.
5. Collect 150 valid fused samples at that mark.
6. Repeat at all eight marks. Never substitute or copy a position.
7. Select **Save distance-only calibration**.

The app fits one affine correction and rejects it unless every distance exists and:

- Median absolute error is at most 0.03 m at each point below 1.00 m.
- Median percentage error is at most 5% at each point at or above 1.00 m.
- At least 1,200 accepted samples exist.
- The validated range spans 0.40 to 2.00 m.

The evidence record stores the maximum per-distance median near error and maximum per-distance median far percentage error. A rejected fit must not mark the device profile as distance-validated. A passing fit verifies only this sensor setup. It cannot enable numeric refractive output or establish visual-acuity, contrast-sensitivity, or refraction accuracy.

Repeat the protocol after a major iOS/ARKit change, sensor implementation change, screen replacement, camera/stand geometry change or unexplained distance drift.

## iOS 26 simulator smoke test

Simulator checks validate app installation, launch stability and responsive SwiftUI rendering. They do not validate TrueDepth distance accuracy, microphone acoustics, Core Motion behavior or a physical device profile.

Build with Xcode 26, install on one representative iOS 26 iPhone simulator, launch the app and capture the onboarding, permissions, phone setup and calibration states. A pass requires a live process, responsive interaction and no crash through the core journey.

Do not use simulator success as evidence of TrueDepth distance accuracy, microphone acoustics, Core Motion stationarity, or physical device calibration. The deployment target is iOS 26.0 so the app can use the intended system components without compatibility shims.

## Required physical tests

Record pass/fail, observed values, evidence screenshots and defects for each:

1. Tape-measure check at every validation distance after saving/relaunching.
2. Phone bump during a task block: the block is discarded and position must be restored.
3. Low camera luminance: the block cannot be scored.
4. Head yaw or pitch beyond threshold: the block cannot be scored.
5. Face leaves frame or a second face appears: the block cannot be scored.
6. Network unavailable: one retry, operator input and deterministic explanation remain usable.
7. Quiet and deliberately noisy direction recordings: accept an expected natural response or safely repeat the same target without recording a guess.
8. Right-eye and left-eye completion with no copied/hardcoded responses.
9. Accessibility staircase, all four preferences and visible profile application.
10. Local history across relaunch, single-session deletion and delete-all.
11. Brightness restoration after completion, interruption and relaunch.
12. VoiceOver labels, Dynamic Type, contrast and 44-point minimum interactive targets.

Each recorded task block must contain exactly eight accepted answers. Landolt blocks must contain two targets for each of the four directions. Gabor blocks must contain four targets for each orientation. Invalid counts or unbalanced target schedules must fail integrity validation rather than being scored. These engineering checks do not confer clinical validation.

## Future clinical validation

The current enlarged phone Landolt task and Gabor pattern task do not support a refractive-accuracy comparison. Do not compare their outcomes with prescriptions, calculate an error in diopters, borrow accuracy figures from other products or studies, or display an accuracy percentage.

Before adding numeric refractive output, define and prospectively validate a separate protocol with clinical collaborators. At a minimum, it needs a fixed and calibrated target geometry, a prespecified threshold model, an independent comparison standard, an appropriate sample, masked analysis where feasible, all outcomes retained, and prospective reporting of agreement and repeatability. The study must also address accommodation, display calibration, response variability, and clinical model error. A successful distance calibration is not a substitute for this work.

## Release gate

A release candidate is not ready until:

- Swift, iOS, backend and live OpenAI checks pass on the exact commit.
- The physical calibration and all twelve physical tests above have dated evidence.
- Numeric refractive output remains locked unless a separately approved and clinically validated protocol has been integrated.
- The deployed HTTPS backend and matching app token work from the physical phone.
- No API key, audio, face data or local session file is present in Git or the app bundle.
