# MixRoom submission packet

Submit on [BuilderBase](https://builderbase.com/event/digital-af-seoul-hackathon) by **Thursday, October 1, 2026, 17:00 KST**. The event schedule reserves **16:45** for recording the demo video.

## Copy for the submission form

**Project name**

MixRoom

**One-line pitch**

A voice-controlled studio companion that lets solo musicians record takes, shape their mix, and save ideas while their hands stay on the instrument.

**Live Lovable link**

[https://mix-voice-studio.lovable.app](https://mix-voice-studio.lovable.app)

The published companion uses studio-password sign-in. A real studio demo requires the Mac, Python backend, and secure tunnel to remain running; arrange supervised judge access without publishing credentials.

**Demo video**

PENDING: paste an accessible video link here. Maximum length: **2 minutes**, with **audio on**.

**How we use ElevenLabs**

MixRoom uses ElevenLabs Scribe Realtime to transcribe spoken studio commands. ElevenLabs streaming text-to-speech delivers recording preparation prompts and native-confirmed outcomes, while command recognition pauses during assistant playback and performance recording.

**Team members**

- SABERA BANU — Leader
- UDDIN SIYAM

**Existing foundation and hackathon work**

We reused the existing MixRoom native DAW as the recording and audio-processing foundation. The new work adds a Lovable browser voice companion, a local Python backend, session pairing, and voice workflows for mixing, comparison and undo, timed recording, humming-to-MIDI, and project notes.

## Voice is essential to this product

The product centers on a musician who is holding an instrument and cannot operate the computer during the session. Speaking is the main interface for that workflow: the musician requests a take, changes the mix, compares versions, and saves an idea without putting the instrument down. The underlying native DAW retains manual controls; the claim is that voice enables the hands-free companion workflow.

## Required before submission

- [x] Project name and one-line pitch are ready above.
- [x] The two-sentence ElevenLabs description is ready above. Real ElevenLabs provider checks have passed.
- [x] The integrated companion is published on Lovable at the link above. Both **Lovable and ElevenLabs are required** by the event brief and are used in this implementation.
- [x] The public Lovable page, studio-password login, pairing-code creation, waiting-for-Mac state, and session revocation passed real browser checks.
- [ ] Connect the actual native Mac project and complete the manual audio acceptance run. Public browser checks do not establish native recording or editing success.
- [ ] Verify the actual native actions you plan to show: live microphone capture, audible mix comparison, and the complete native humming workflow still need acceptance checks. Keep the Mac, backend, and secure tunnel running during judging.
- [ ] Record an honest demo of the working application, **120 seconds or less**, with spoken commands, assistant replies, and relevant musical output audible. Check the finished video’s duration and sound.
- [ ] Add the video link and test viewer access. Keep passwords, provider keys, and private configuration out of the recording.
- [x] Team members confirmed: SABERA BANU (Leader) and UDDIN SIYAM.
- [ ] Paste the completed fields into BuilderBase and submit before **17:00 KST**. Confirm the platform shows the submission as received.

The deck and script support the presentation. Paste the live Lovable URL into its submission field; the required video link is still missing. The team is responsible for submitting the completed form.

## Demo materials

- [Editable PowerPoint](MixRoom-Demo.pptx): six main pitch/demo slides and two setup/status appendices.
- [Two-minute presenter script](MixRoom-Presenter-Script.md): timing, example commands, and fallback wording for anything unverified.
- [Manual testing guide](../docs/MANUAL_TESTING.md): native setup and the five feature acceptance tests.
- [Implementation status](../docs/HACKATHON_IMPLEMENTATION.md): current evidence and remaining work.
- [Lovable authoring project](https://lovable.dev/projects/9f999e25-9d24-4f94-9560-34ca0b28be84): connected to the GitHub voice repository; the integrated site has been published and verified.

## Optional fields

**Repository:** [Siyamuddin/mixroom-app](https://github.com/Siyamuddin/mixroom-app). This repository is private. Include it only with an appropriate judge-access arrangement; the link alone does not grant access. Repository access is optional in the event brief.

**Screenshots:** use actual application screens. The current deck contains the real published sign-in page. Label an offline or waiting-for-pairing screen accurately; browser screenshots do not establish that a native edit or recording succeeded.

## Final accuracy check

OpenAI handles planning. ElevenLabs handles command transcription and spoken replies. The local Python service coordinates requests, and native MixRoom handles music processing, including Basic Pitch. Jev is not configured for this demo. Customer demand, pricing, and revenue remain hypotheses; no user or revenue traction is claimed.

Judging weights from the event brief: **voice essential 30%, execution 30%, usefulness 25%, demo 15%**. Prioritize a small working sequence that shows the native result clearly.

Preparing this packet does not submit the project. The team must submit it on BuilderBase and confirm receipt.
