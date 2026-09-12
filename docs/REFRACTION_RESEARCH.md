# Moving SeeNA towards eye-power estimation

Research review: 12 September 2026.

## What exists

Phone-only refractive estimation is a legitimate research direction. It is incorrect to say that no phone screen can support a refraction measurement.

Luo and colleagues describe a smartphone protocol that approaches from at least two metres to find the distance where a participant can identify targets. Their spherical-equivalent task uses Tumbling E targets and answer verification. Their astigmatism procedure uses separate directional and coloured grating tasks. It requires a helper moving the phone, rather than the fixed-position SeeNA journey. These are study-specific methods and results, not validation of SeeNA. [Original protocol, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC12093271/).

A second study investigates blue OLED stimuli, chromatic aberration, visual acuity and spherical refraction. Its display and optical assumptions must be evaluated before adopting such a method on different phones. A blue colour setting alone does not reproduce the experiment. [Original study, 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10654024/).

## Two separate experiences

SeeNA presents enlarged Landolt and Gabor targets at a fixed 0.40 metre position and records responses. A completed block is a task outcome. It does not locate the optical far point, measure an acuity threshold, or measure sphere, cylinder or axis. Gabor orientation answers are not an independent refraction measurement.

The separate **Eye-power estimate** entry now implements a helper-assisted, experimental Tumbling E clarity-endpoint workflow. It does not reuse the enlarged circles or convert their scores into diopters. The output is experimental endpoint vergence, presented as an approximate myopia estimate with explicit limitations. It is not established clinical refraction.

A 2026 feasibility study describes dynamically distance-scaled, 20/20 Tumbling E targets in a selected myopic population. It supports investigating this direction, not applying its reported accuracy to SeeNA. SeeNA's discrete search, manual measurements and engineering gates below are its own implementation choices. [Original feasibility study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12898938/).

The deterministic identity `D = -1 / d`, with `d` in metres, describes idealised myopic far-point vergence. Applying it to the setup distance would assign the same power to everyone. That would be a calculation error in the measurement model even if the division itself is exact.

Likewise, `sigma_D ≈ sigma_d / d²` propagates small distance uncertainty only. It omits accommodation, calibration bias, target geometry, response variability and model error. It must not be displayed as the total clinical error or a confidence interval for someone's prescription.

## Implemented experimental protocol v1

Protocol identifier: `seena-tumbling-e-endpoint-v1`.

- Adults with known short sight only. The introduction excludes known eye disease, recent surgery and new symptoms; glasses and contacts must be removed. A helper operates the phone while the participant stays seated. These are conservative scope restrictions, not clinically validated eligibility criteria.
- Each session begins with a ruler measurement of a 200-point screen line. This determines millimetres per point for that display configuration. It is a user-entered measurement, not automatically verified calibration.
- The helper measures each eye-to-screen distance with a tape. Readings must be within 5 mm of the requested position. The range is 0.40 to 2.00 metres. No near-range extrapolation or clamping supplies stronger-myopia numbers.
- One five-arcminute Tumbling E appears at a time. Its full height is `2d tan(theta/2)`. Arms and gaps occupy one fifth of the height. The renderer rejects less than two native pixels per stroke, rather than enlarging a target to help it pass. Rasterisation and display luminance still need physical characterisation.
- Three independently randomised directions are presented per level. All three must be correct for that level to pass. A complete spoken answer or helper-entered response is required before advancement. Not-visible responses are failures, not missing data. Silence, interrupted audio and invalid transcripts are not scored.
- Each sweep starts at 2 m, approaches in 0.50 D vergence steps, then bisects the first pass/fail bracket until its measured width is at most 0.25 D. Success at the far limit or failure at the near limit returns **Outside test range**, not a fabricated endpoint.
- Three independent sweeps run per eye. A spread greater than 0.50 D between bracket midpoints returns **Repeat needed**. This is an engineering repeatability gate, not an accuracy specification.
- The displayed centre is the median of the three bracket midpoints, rounded to 0.25 D. Bounds span the observed brackets, expanded by exact inverse-distance conversion of a 5 mm tape-reading allowance. Neither the rounding nor the interval represents clinical accuracy or a clinical confidence interval. Accommodation, astigmatism, screen calibration error, response bias and optical-model error are not estimated by this interval.
- Results retain the session date, protocol identifier, display measurements, every requested and entered distance, target and accepted answer. Saved results recompute outcomes from this evidence. They contain no model-generated or trusted cached power value.

These rules provide auditable engineering behaviour. They do **not** establish that the observed clarity boundary is an optical far point. The approximate result can differ materially from a clinician's refraction and must not be used to order glasses or contacts.

## Work still requiring people and physical devices

1. Have a clinical collaborator assess the protocol, population, exclusions and accommodation controls before a comparison study. Do not promise full prescriptions or hyperopia detection from a myopia-only protocol.
2. Physically characterise screen scale, rasterisation, lighting and tape alignment on each exact device. Exercise movement, interruptions and natural speech on real hardware. Simulator fixtures cannot establish these properties.
3. Compare the exact implementation against independently measured clinical refraction under a prespecified study plan. Report bias, agreement limits, repeatability, exclusions and failures, with participant-level analysis that accounts for two eyes belonging to one person. Correlation alone is not agreement.
4. Make only accuracy claims supported by that study and its tested population, devices and range. Experimental results must not be used to order glasses or substitute for an eye examination.

## Clinical boundary

There is no SeeNA clinician-comparison dataset, approved refraction protocol or verified near-endpoint calibration in this repository. These require physical measurements and human participation. Unit tests, simulator answers and an OpenAI response cannot supply them.

The fixed-distance Landolt/Gabor journey retains its numeric-output lock. The separate experimental endpoint flow can show a bounded approximation only after its own complete evidence checks. It does not set `numericResultsAllowed`, bypass the old lock, or claim clinical approval. Clinical comparison testing is explicitly outside this implementation request and remains necessary before any claim of prescription accuracy. The existing release-gate sample-count constants are conservative engineering policy, not a statistical sample-size calculation or a universal clinical standard.
