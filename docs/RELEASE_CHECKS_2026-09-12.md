# Release checks: 12 September 2026

App implementation commit: `060904af5a13ee13cd7e389700c7d53cef75889c`.

## Passed

- 204 Swift tests. The experimental search test sweeps 199 idealised threshold cases. These are synthetic arithmetic and state-machine tests, not clinical participants.
- GitHub Actions: Swift tests, Debug/Release iPhone builds, backend contract/type checks and production dependency audit. [Run 34677353733](https://github.com/surtecha/SeeNA/actions/runs/34677353733).
- Local Debug and Release iOS simulator builds without compiler warnings.
- Both-eye circle and Gabor journey, processing, results and answer review on the iPhone 16 Pro Max iOS 26.5 simulator, using its opt-in sensor/answer QA fixture.
- Invalid ruler entry rejected in the normal measurement UI; a valid synthetic ruler entry advanced to a separate, blank tape-reading field.
- Both-eye experimental E search completed through the real view model and engine using the simulator-only fixture. It produced approximately -1.25 D and -1.75 D from synthetic response boundaries, not preset result values.
- Explicit save, history navigation, answer review and reopening the unchanged date/evidence after reinstalling the Release build.
- Largest accessibility text: welcome actions remained scrollable; saved estimate text wrapped without truncation. This was a focused check, not a complete accessibility audit.
- New launch film: exactly 90.000 seconds, 1920 × 1080, 30 fps, one original instrumental stereo soundtrack with chapter-synchronised effects and no voiceover. Exported chapter frames inspected for readable captions and matching app content. See the adjacent media manifest for SHA-256 and source audio levels.

## Not established by these checks

- Clinical agreement with a clinician's refraction, accuracy of an individual's estimate, or suitability for ordering glasses.
- Physical iPhone ruler/tape calibration, TrueDepth performance, real-room microphone acoustics, haptics or end-to-end natural voice reliability in the new helper flow.
- Universal device compatibility or freedom from every possible defect.

Clinical comparison testing was explicitly excluded from this implementation request. The experimental result keeps its limitations visible. Fixed-distance circle and Gabor scores cannot generate eye-power values.

## Media provenance

The launch film uses new recordings of the app. Basic checks use `-SEENA_USE_MOCK_SENSORS -SEENA_AUTOMATE_VOICE_RESPONSES`. The experimental flow uses `-SEENA_AUTOMATE_REFRACTION`, compiled only for Debug simulators. Recorded results are synthetic QA examples. Timing is edited for the product film and does not represent physical test duration.

`scripts/RenderLaunchFilm.swift` composes an explicit JSON shot list into a silent 90-second video and creates the README GIF preview. `scripts/ScoreLaunchFilm.swift` adds original procedural music and transition effects, without external samples or speech, and verifies the final duration and audio-track count. `scripts/InspectLaunchMedia.swift` extracts selected frames and checks decoded audio for silence and sample clipping. The shorter animated preview is an index to the full film, not a second full-length video.

## Interaction-quality follow-up

- A single voice state now distinguishes preparation, listening and transcription. Listen cannot cancel an answer that is already being checked; a helper answer can deliberately replace it through the existing cancellation guard.
- Retry clears stale errors. Completion from an old cancelled voice task cannot reset a newer task's state.
- Opening the exit dialog pauses voice. A visible Keep measuring action returns to the same step; leaving during an active save is disabled.
- Estimate history shows loading instead of a premature empty state, serialises load/delete interactions, supports refresh and announces errors to VoiceOver.
- All 208 Swift tests passed after the final change. Four new tests cover the pure interaction policy and source wiring; the latter are not microphone simulations.
- Final Debug and Release iOS simulator builds passed without warnings. Release UI checks covered dated history reopening, pausing while entering the exit dialog, and the explicit Keep measuring action retaining screen setup.
- No optical formula or eligibility rule changed in this follow-up. End-to-end real-microphone reliability and physical sensing remain unverified; the processing label is covered by policy/wiring checks, not a new live spoken-answer trial.
