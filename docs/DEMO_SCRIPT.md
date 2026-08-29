# Real-app demonstration checklist

## Before the room opens

- Use the exact calibrated iPhone and verified build commit.
- Confirm the stand has not moved and floor marks remain correct.
- Run one tape point, one test recording and one backend health check.
- Ensure the participant can move safely and knows their test eye order.
- Keep operator fallback available; never use it without showing the `operator` evidence label.

## What to show

1. Open SeeNA and tap **Start**. The app is intentionally silent before this tap.
2. Complete permission, phone-stability, gaze and 40 cm setup using the spoken guide.
3. Cover the instructed eye. Wait for **Three, two, one, start**.
4. Answer one Landolt C at a time with up, down, left, right, or a natural phrase such as “I cannot see it.” The next symbol must not appear until the current response is accepted.
5. Answer one Gabor orientation at a time. This is recorded only as a completed orientation task, not a clinical contrast threshold.
6. Repeat for the other eye and open the result. Show **See answers** to demonstrate that every target and accepted answer is reconstructable.
7. Open measurement evidence and state that the phone calculates the screening range locally. The constrained AI layer explains the result but cannot change or render the numbers.

The separately published `seena-mock` repository is the scripted one-minute hackathon backup. Never present its simulated result as a real measurement.

## Failure-safe wording

- Voice/network delay: “The bounded recording is retrying once. Operator entry preserves the same scoring and is visibly labelled.”
- Tracking failure: “This is the safety behavior: SEENA refuses to manufacture a number.”
- Outside range: “SEENA distinguishes a supported result from a boundary, not a diagnosis.”
- Uncalibrated phone: “Accessibility works, but numeric screening is correctly locked for this exact hardware.”
