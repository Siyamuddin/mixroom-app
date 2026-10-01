# MixRoom: two-minute pitch

Use slides 1–6 for the pitch. Slides 7–8 are setup and questions appendices. The times below include a short live demonstration. Read the quoted text and use the other lines as stage directions.

## Slide 1 · 0:00–0:10

“We’re Sabera and Siyam. MixRoom lets musicians run a studio session by voice while their hands stay on the instrument.”

## Slide 2 · 0:10–0:25

“A solo musician is also the recording engineer. Starting a take or changing a track means reaching for the computer. We focus on that interruption.”

## Slide 3 · 0:25–0:40

“Five voice actions cover the session: mixing, before-and-after comparison with undo, timed recording, humming into editable notes, and project notes. The Mac confirms each successful edit.”

## Slide 4 · 0:40–1:25

Run this section live only after the native acceptance checklist passes. Open the test project, select an audio track, pair the browser, and put on headphones before starting the pitch.

Say: “Record ten seconds of humming and turn it into Warm Keys.”

Wait for the preparation and countdown. Hum a simple melody. Play the saved audio and resulting MIDI briefly.

Say: “Lower Backing by two decibels.” Then compare before/after and keep the version you prefer. Point to the actual native gain readout.

If any result is pending or fails, describe that state accurately. Do not repeat a request while its outcome is unknown. If live checks are incomplete, use the editable workflow diagram and say: “This is the intended workflow. Our live native audio acceptance is still pending.”

## Slide 5 · 1:25–1:45

“Lovable hosts the companion. ElevenLabs handles speech. Our local Python backend pairs the studio, OpenAI plans edits, and MixRoom executes them. Recording and Basic Pitch stay on the Mac.”

## Slide 6 · 1:45–2:00

“Our first customer hypothesis is musicians who record every week. Next, we want five observed sessions in Seoul to measure repeat use and willingness to pay. Pricing and paid demand are not validated yet.”

## Before presenting

- Team: **SABERA BANU (Leader)** and **UDDIN SIYAM**.
- Open [the published Lovable companion](https://mix-voice-studio.lovable.app). Its secure studio API address is prefilled. Sign in with the studio password, then choose **Pair your Mac**.
- In the native Mac app, use **Voice session → Connect**, enter the code, and set the native relay URL to `http://127.0.0.1:8766/api/voice`. The browser’s HTTPS address and this native local address reach the same backend.
- **Keep the Mac, Python backend, and secure tunnel running throughout the demo.** A Quick Tunnel restart may change its hostname. Headphones prevent spoken replies and music from feeding back into the microphone.
- Update slide 8 only when new checks actually pass. Provider and fixture checks do not establish live microphone success.
- The integrated Lovable site, public browser sign-in, pairing-code creation, honest waiting-for-Mac state, and session revocation have passed real browser checks. Native pairing, live microphone capture, humming conversion, and audible comparison still require manual acceptance. Jev is not configured.
- Keep the backend `.env` and provider credentials off-screen. The public setup addresses contain no keys.
- The slide text, feature table, workflow, and architecture are editable. The photograph and actual browser screenshot are embedded images. The deck has rendered previews and structural checks, but has not been inspected in Microsoft PowerPoint itself.

## Submission reminder

The team submits on BuilderBase by **October 1, 2026, 17:00 KST**. Include the project name and pitch, live Lovable URL, a demo video no longer than 120 seconds with audio on, the ElevenLabs description, and both team names. The deck is supporting material, not a replacement for the required video. [Submission copy and checklist](MixRoom-Submission.md).
