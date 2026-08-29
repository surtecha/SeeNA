# 90-second demonstration script

## Before the room opens

- Use the exact calibrated iPhone and verified build commit.
- Confirm the stand has not moved and floor marks remain correct.
- Run one tape point, one test recording and one backend health check.
- Ensure the participant can move safely and knows their test eye order.
- Keep operator fallback available; never use it without showing the `operator` evidence label.

## Script

**0–15 seconds — Product truth**

“SEENA is a one-iPhone research prototype for approximate myopia screening and personalised digital accessibility. It is not a prescription and returns no numeric result when the evidence is inadequate.”

Show eligibility, the calibrated exact-device check and the stationary-phone setup.

**15–35 seconds — Real measurement**

Open the live setup/evidence values. Move the participant so the raw, relative, fused and corrected distance values visibly change while the phone remains still.

“ARKit supplies camera-relative eye distance, facial scale extends the measurement, and Core Motion rejects phone movement. This exact device passed an eight-distance tape calibration.”

**35–55 seconds — Vision block**

Show a seven-target row. The participant speaks the seven openings. Show the transcript, local score, measured distance and valid quality gate.

“OpenAI transcribes only. Deterministic code parses and scores exactly seven directions. The app calculates power locally from actual measured distance.”

**55–70 seconds — Result and evidence**

Show the right/left screening range or a deliberate no-result case, then open evidence.

“Every target, response, distance, formula, retry and response source is reconstructable. The AI cannot modify a number because it never receives one.”

**70–90 seconds — Accessibility transformation**

Complete or open the saved readability profile. Toggle from the difficult service paragraph to the transformed page and play the female read-aloud voice.

“The separate near assessment sets real SwiftUI typography, contrast, controls and speech. Raw camera data is never uploaded or stored, and the entire local session can be deleted here.”

## Failure-safe wording

- Voice/network delay: “The bounded recording is retrying once. Operator entry preserves the same scoring and is visibly labelled.”
- Tracking failure: “This is the safety behavior: SEENA refuses to manufacture a number.”
- Outside range: “SEENA distinguishes a supported result from a boundary, not a diagnosis.”
- Uncalibrated phone: “Accessibility works, but numeric screening is correctly locked for this exact hardware.”
