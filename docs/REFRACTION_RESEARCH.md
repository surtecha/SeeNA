# Moving SeeNA towards eye-power estimation

Research review: 12 September 2026.

## What exists

Phone-only refractive estimation is a legitimate research direction. It is incorrect to say that no phone screen can support a refraction measurement.

Luo and colleagues describe a smartphone protocol that approaches from at least two metres to find the distance where a participant can identify targets. Their spherical-equivalent task uses Tumbling E targets and answer verification. Their astigmatism procedure uses separate directional and coloured grating tasks. It requires a helper moving the phone, rather than the fixed-position SeeNA journey. These are study-specific methods and results, not validation of SeeNA. [Original protocol, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC12093271/).

A second study investigates blue OLED stimuli, chromatic aberration, visual acuity and spherical refraction. Its display and optical assumptions must be evaluated before adopting such a method on different phones. A blue colour setting alone does not reproduce the experiment. [Original study, 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10654024/).

## What the current app measures

SeeNA presents enlarged Landolt and Gabor targets at a fixed 0.40 metre position and records responses. A completed block is a task outcome. It does not locate the optical far point, measure an acuity threshold, or measure sphere, cylinder or axis. Gabor orientation answers are not an independent refraction measurement.

The deterministic identity `D = -1 / d`, with `d` in metres, describes idealised myopic far-point vergence. Applying it to the setup distance would assign the same power to everyone. That would be a calculation error in the measurement model even if the division itself is exact.

Likewise, `sigma_D ≈ sigma_d / d²` propagates small distance uncertainty only. It omits accommodation, calibration bias, target geometry, response variability and model error. It must not be displayed as the total clinical error or a confidence interval for someone's prescription.

## Proposed refraction workstream

This is a development proposal, not an implemented or validated test:

1. Choose the intended measurement with a clinical collaborator: initially myopic spherical-equivalent estimation in an explicitly defined adult population. Do not promise full prescriptions or hyperopia detection from a myopia-only protocol.
2. Specify the stimulus, angular size, pixel limits, approach direction, answer verification, occlusion and stopping rules. If adapting the published E procedure to Landolt circles, record it as a new protocol requiring validation.
3. Use helper-controlled phone movement so the participant can remain seated. Reconcile this mode with the existing fixed-stand motion checks. Reusing those checks unchanged would reject intentional movement.
4. Establish the actual supported near and far tracking range on each exact device. Never clamp an out-of-range endpoint into a plausible power. The present calibration range starts at 0.40 metres and must not be extrapolated to stronger-myopia near endpoints.
5. Repeat independently randomised endpoint measurements. Preserve the accepted answers, raw distance evidence, endpoint brackets and failed attempts. Agreement between repeats measures repeatability, not accuracy.
6. Calculate experimental endpoint vergence separately from the current task scores. Keep sensor uncertainty distinct from observed clinical agreement. AI may explain these records, but must not alter the measurement or supply missing values.
7. Compare the exact implementation against independently measured clinical refraction under a prespecified study plan. Report bias, agreement limits, repeatability, exclusions and failures, with participant-level analysis that accounts for two eyes belonging to one person. Correlation alone is not agreement.
8. Only make an accuracy claim supported by that study and its tested population, devices and range. Any participant-facing experimental result must clearly describe its limitations and must not be used to order glasses or substitute for an eye examination.

## Current blockers

There is no SeeNA clinician-comparison dataset, approved refraction protocol or verified near-endpoint calibration in this repository. These require physical measurements and human participation. Unit tests, simulator answers and an OpenAI response cannot supply them.

The current release therefore retains its numeric-output lock. The lock is not evidence that phone refraction is impossible; it prevents the existing task from being relabelled as a measurement it does not make. The existing release-gate sample-count constants are conservative engineering policy, not a statistical sample-size calculation or a universal clinical standard.
