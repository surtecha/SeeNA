# Real-app demonstration checklist

## Before the room opens

- Use the exact calibrated iPhone and verified build commit.
- Confirm the stand has not moved and the 40 cm position remains correct.
- Run one tape point, one test recording and one backend health check.
- Ensure the participant can move safely and knows their test eye order.
- Keep operator fallback available only as a recovery path; use voice responses for the demonstration.

## What to show

1. Open SeeNA and tap **Start**. The app is intentionally silent before this tap.
2. Complete permission, phone-stability, gaze and 40 cm setup using the spoken guide.
3. Cover the instructed eye. Wait for **Three, two, one, start**.
4. Answer eight Landolt C targets for each eye, one at a time, with up, down, left, right, or a natural phrase such as “I cannot see it.” The next symbol must not appear until the current response is accepted.
5. Answer eight pattern targets for each eye, one at a time, with left or right. The score is kept for answer review, while every complete, quality-valid block receives the same neutral completion state. This is not a clinical contrast threshold.
6. Repeat for the other eye and open the result. Show **See answers** to demonstrate that every target and accepted answer is reconstructable.
7. Open the answer evidence and show that scoring and accepted responses stay local. The constrained language layer explains the qualitative task summary but cannot change the local score or evidence.

## Failure-safe wording

- Voice/network delay: “The bounded recording is retrying once. If voice remains unavailable, the same answer can be entered on screen without changing the task.”
- Tracking failure: “This is the safety behavior: SeeNA repeats the task instead of keeping weak evidence.”
- Incomplete task: “SeeNA reports that the task needs repeating instead of guessing.”
- Result boundary: “This is a qualitative task summary, not an eye prescription or diagnosis.”
