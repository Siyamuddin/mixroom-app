# Test MixRoom on this Mac

This guide tests the local Python backend, browser voice companion, and native Mac app together. Start with English commands, wired headphones, and ten-second recordings. Allow about 30 minutes after the applications have built.

**Current runtime:** Docker's outbound networking stopped responding on this Mac, including connections to both AI providers. The Docker image is built, but the backend now runs directly on the Mac at `http://127.0.0.1:8766` so you can test. Docker still holds its old port 8765 even with this container stopped. Only MixRoom's container was stopped; its database was preserved and the other containers were left running. The Docker instructions below are for returning to that runtime once its networking works.

**Verification record, October 1, 2026:** the native Hackathon app built successfully, its code signature was verified, and the app was launched. The packaged app includes the new home screen with **New Project**. The canonical browser companion is running on port 5173, and its sign-in screen has been visually checked.

All nine final live OpenAI planning checks passed through the host backend on port 8766: a gain change (7.4 seconds), comparison before/after (3.3/3.6 seconds), ten-second recording (2.2 seconds), three humming requests (2.2–4.2 seconds), rejection of an unrelated mixed capture/edit request (3.4 seconds), and a note (2.4 seconds). ElevenLabs token issuance and TTS audio generation also passed through this backend. These are real provider calls using fixture project context; no native edit or recording was executed, and generated speech was not played. Backend/browser tests and earlier successful Docker protocol checks are recorded in [HACKATHON_IMPLEMENTATION.md](HACKATHON_IMPLEMENTATION.md).

**Still unchecked:** native window interaction, live microphone capture, audible A/B changes, and humming-to-MIDI acceptance. The GUI verification tool timed out after launch, so process startup does not establish that these work. The menu paths below were checked against source. Tick the checklist only after seeing and hearing the actual results.

The actual bundled Basic Pitch model and MixRoom note decoder have passed an isolated test using the generated melody below: all eight expected pitches were recovered, with note starts within 18 ms. This checks the model and decoder, not microphone capture or MIDI insertion in the native editor.

## 1. Start the three parts

Use this independent project folder:

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app
```

The browser companion, host backend, and native app have already been started for this session; use those instances if they are still open. Do not start a second host backend on port 8766 or a second browser development server on port 5173. The commands below are for starting them again when needed.

### Terminal 1: backend

The backend is already running for this session. If you need to start it again, first check its health URL; do not launch another instance if it responds:

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app
curl --fail --max-time 5 http://127.0.0.1:8766/health
test -f voice_backend/.env || python3 voice_backend/scripts/setup_env.py
```

Open `voice_backend/.env` in your editor. Preserve the existing values. Check these settings locally:

| Setting | Purpose |
| --- | --- |
| `MIXROOM_PASSWORD` | Your studio sign-in password. The setup script generates it. |
| `OPENAI_API_KEY` | Interprets spoken requests and plans edits. |
| `ELEVENLABS_API_KEY` | Command transcription and spoken replies. |
| `ELEVENLABS_VOICE_ID` | The voice used for replies. |
| `TYPESAFE_API_KEY` | Optional Jev classification; leave empty if not using Jev. |

The **studio password** is the value after `MIXROOM_PASSWORD=`. Enter that password in the browser later. Provider API keys belong only in this backend configuration; do not paste them into the browser, native pairing dialog, screenshots, or source code.

To restart the current host runtime after stopping the previous instance:

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app/voice_backend
MIXROOM_DATA_DIR="$PWD/data" .venv/bin/python -m uvicorn mixroom_backend.app:app \
  --env-file .env --host 127.0.0.1 --port 8766 --workers 1 \
  --no-access-log --no-proxy-headers
```

Leave that terminal open. This uses the already installed Python environment and the private `.env`; restart this process after changing its configuration. The health request returning JSON proves the server is reachable, not that provider calls or your microphone work.

**Docker alternative, after its network is repaired:** stop the host backend first, change the browser and native relay URLs to `http://127.0.0.1:8765/api/voice`, open Docker Desktop, then run these commands from the repository root:

```sh
python3 voice_backend/scripts/docker_local.py compose up -d --no-build
python3 voice_backend/scripts/docker_local.py compose ps
curl --fail http://127.0.0.1:8765/health
```

These commands use the existing built image. The helper runs Compose from the backend folder. On this Mac the default Docker proxy socket can hang; the helper probes it for five seconds, then tries Docker Desktop's working raw socket without changing global settings. It fixes CLI access only, not Docker's provider connectivity. Docker retains its own database volume; changes made in the host database after the copy are not automatically synchronized back. After switching runtimes, sign in and pair again if necessary. After editing `.env` in Docker mode, apply it with `python3 voice_backend/scripts/docker_local.py compose up -d --no-build --force-recreate`.

### Terminal 2: browser companion

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app/voice_companion
test -d node_modules || npm ci
test -f dist/index.html || npm run build
npm run preview -- --port 5173 --strictPort
```

Open **http://127.0.0.1:5173** in a browser on this same Mac. Keep this tab visible during voice tests. The current demo serves the built bundle. If port 5173 is already in use, use the existing server instead of starting a duplicate. Rebuild with `npm run build` after changing source or public configuration; developers can stop the preview and use `npm run dev` while editing. The default backend accepts the documented local browser origins.

On **Open your studio.**, enter:

- **Studio address:** `http://127.0.0.1:8766/api/voice`
- **Studio password:** the password from your private backend `.env`

Click **Open studio**. You should see **Pair your Mac**. “Mac offline” is normal before pairing.

### Open the built native Mac app

The native build and code signature have been confirmed, and the app has already launched. If its window is not open, launch the existing bundle:

```sh
open /Users/uddinsiyam/Desktop/digital-af/mixroom-app/build/macos/Build/Products/Debug-Hackathon/MixRoom.app
```

This launch command does not recompile the app, which helps on a Mac with limited free storage. If you later rebuild, wait for that build to finish successfully before opening the bundle.

This is the isolated **Hackathon** flavor. The app is named **MixRoom**, so use this exact bundle to avoid opening another installed copy. Its project storage is separate from the original app. Developer build commands are at the end of this guide.

## 2. Prepare a small project

Use a disposable test project with a short WAV or MP3 file you can recognize. A backing loop or your own previous recording works well. This Mac also has a generated eight-second mono melody fixture at `/tmp/mixroom-manual-melody.wav`; it contains no personal recording. In the file picker, press Command-Shift-G and enter `/tmp` to find it. Temporary files may disappear after a restart.

1. In the native home screen, click **New Project** in the header. An **Untitled Project** opens in the editor.
2. Click the settings gear next to the project title to open **Project Settings**. Set **Project Name** to `Voice Test`, then press Enter or close the popup to commit it.
3. Click the editor’s **+** button near the transport controls. On desktop, choose **Add Audio File** and select your test file. A waveform should appear. The alternative **File Browser** opens the sample browser. Library bundle import is for `.mixroom` projects, not ordinary WAV files.
4. Right-click the audio row’s name/header on the left. Choose **Rename Row**, enter `Backing`, and click **Save**.
5. Right-click that header again and choose **Insert Audio Row Below**. Rename the new empty row `Voice Take` using **Rename Row** → **Save**.
6. Click the `Voice Take` header to select it. Select one row for the first tests; avoid Command-click multi-selection. Clicking a waveform alone selects a clip and is not a reliable way to choose the recording row.
7. In **Project Settings**, choose the correct **Input Device**, **Input Channel**, and **Output Device**. For a simple test, use the Mac’s built-in microphone and wired headphones. For an audio interface, select the physical input you plugged into. Channel labels start with **Input 1**, **Input 2**, or a stereo pair, and may include device-provided names.
8. Allow microphone access for **MixRoom** and, when asked later, your browser. If denied, open macOS **System Settings → Privacy & Security → Microphone** and enable the relevant app. MixRoom may show **Allow access** or **Open settings** in its input settings.
9. Play the imported file with the native transport’s play button, then stop. Confirm you hear it through your headphones before adding voice control.

The browser microphone hears **commands**. The native app’s selected audio input records **your performance**. These are two separate input selections and permissions.

## 3. Pair the browser and Mac

1. In the browser, click **Pair your Mac**. Leave the displayed code visible.
2. In the native editor, find the **Voice session** panel in the upper-right corner and click **Connect**. This opens **Connect your voice session**.
3. Enter the browser’s code in **Pairing code**. Set **Voice relay URL** to `http://127.0.0.1:8766/api/voice`. Click **Connect**.
4. Wait for the browser to show **Mac connected**, your project name, and the selected track near **CONVERSATION**. Click a different native row and confirm this selected name updates; finish with `Voice Take` selected.

Codes last five minutes and are single-use. If one expires, end that browser session and create a fresh code. If the native **Voice session** panel is absent, check that you opened an editor project in the exact Hackathon app bundle above.

## 4. Check recording before interpreting speech

This button test isolates native recording and browser readiness from OpenAI request interpretation. ElevenLabs spoken preparation still needs to work.

1. Keep playback stopped and select `Voice Take` on the Mac.
2. In the browser’s **Catch the idea.** panel, click **Record 10 seconds**.
3. Wait through the spoken preparation and two-second countdown. Speak or sing only when **Your take is rolling.** appears. The browser says command listening is paused.
4. Wait for **Saving your take…** to finish. A new audio clip should appear on `Voice Take`. Play it on the Mac.

**Pass:** exactly one saved take is audible, approximately ten seconds long, and contains your performance rather than the assistant’s preparation speech. A transcript saying “recorded” without a real playable clip is not a pass.

If this fails, fix input selection, permissions, or connection before testing natural-language commands.

## 5. Test all five voice features

Click **Start conversation** and allow browser microphone access. Wait for **I’m listening.** Speak one request, then wait for its result before the next. The browser pauses command recognition during assistant playback and recording. It also stops the conversation when its tab becomes hidden; return and click **Start conversation** if needed.

The conversation log shows **Verified** only for a native-confirmed result. **Needs your answer**, **Not applied**, **Could not verify**, and **Check your project** are not successful edits. Verify changes in the native project as well as the browser log.

### A. Spoken mixing

1. Select `Backing` on the Mac. Click its header to expand the row controls; inspect the **Gain** dB readout in its volume controls and note the current value.
2. Say: **“Lower the Backing track by two decibels.”**
3. Wait for the response, then inspect that same native gain value and play the file.

**Pass:** the value is two dB lower, the backing is quieter, and unrelated tracks/clips remain unchanged. For example, 0.0 dB becomes −2.0 dB. Record the actual before/after values. If the assistant requests clarification, answer with the exact track name instead of treating it as an applied edit.

### B. Before/after and undo

Do this immediately after A, before recording, renaming rows, or other manual edits.

1. Say **“Play the before version.”** If playback is stopped, use the native play button to listen. The native gain should return to the value noted before A.
2. Say **“Play the after version.”** The gain should return to the revised value. You can also use the browser’s **Before** and **After** buttons under **Trust your ears.**
3. Say **“Keep the after version.”** The revised value should remain and the comparison should close.
4. Say **“Undo the last change.”** Check that the intended latest edit is reversed. The browser also has **↶ Undo**.

**Pass:** before/after restores actual native values, keeping a version commits that choice, and undo reverses the correct edit. A/B covers the latest eligible verified mix change; it is not an arbitrary history browser. If intervening edits invalidate it, a refusal or unavailable comparison is the correct outcome.

### C. Timed recording

1. Stop playback. Select `Voice Take` and position the playhead in an empty part of the timeline so the take is easy to find.
2. Say **“Record ten seconds on the selected track.”**
3. Wait for preparation, the two-second countdown, and **Your take is rolling.** Perform a short phrase. Wait for saving and play back the new clip.
4. Start another ten-second take. During capture, click the browser’s **Stop recording** or the native **Voice session → Stop recording** button after a few seconds.

**Pass:** the timed take stops and saves once; early stop produces a shorter saved take when audio has already been captured. **Do not say “stop” during capture as the only stop method:** command recognition is deliberately paused. Stopping before capture starts should cancel preparation without claiming a saved recording.

Omitting the duration defaults to ten seconds. The maximum is sixty seconds. Bar-based requests use the project’s tempo and time signature: four bars at 120 BPM in 4/4 is eight seconds. Start with seconds, then test **“Record four bars.”** with known project settings.

### D. Hum to an editable instrument part

1. Select the audio row `Voice Take` again, not an instrument lane. Keep the surroundings quiet.
2. Say **“Record ten seconds of humming and turn it into Warm Keys.”** Alternatively, click **Hum into keys**.
3. Wait for the countdown, then hum one clear note at a time: three or four sustained notes are easier than chords, lyrics, or a fast melody. Continue until the take ends.
4. Wait through **Finding the notes…**. Inspect the original audio take and the generated instrument/MIDI part, then play the result. Open the MIDI clip to inspect its note events.

**Pass:** the original audio is preserved and a separate, playable, editable MIDI part contains recognizably matching pitches/rhythm. The current default is the bundled **Warm Keys** instrument, not an acoustic-piano model. This converts a melody; it does not generate a full arrangement from a description.

Silence or unclear humming may produce no verified MIDI notes. In that case, the original take should remain and the app should explain the conversion failure without claiming it created music. First-use conversion may take longer than a regular recording.

### E. Spoken notes and persistence

1. Select `Backing` and place the playhead at a recognizable point. Say **“Remember: try a quieter backing track in the second verse.”**
2. Check **Leave yourself a note.** The text and timestamp should appear without changing track gain. Notes retain their project/track context.
3. Say **“Read my notes.”** or click **Read aloud**. Listen for the saved open note.
4. Click the circle beside that note to complete it. It should show a check and struck-through text; **Read aloud** should skip completed notes.
5. Add another note and leave it open. End the conversation, disconnect, close the project, then reopen it from the native library and pair again. Check that both the open note and completion state survive.

**Pass:** note content is saved with the local project, correctly read back, completed, and retained after reopening. A request to remember an edit is not itself permission to execute that edit.

## 6. Try the important failure cases

Use the disposable project. Check each actual outcome rather than expecting identical assistant wording.

| Try | Correct behavior |
| --- | --- |
| Ask for a 90-second recording. | Clarify/reject the duration; no over-sixty-second take starts. |
| Select an instrument lane, then request recording. | Ask for/select a valid audio track; do not overwrite MIDI or claim a take was saved. |
| Say “Add a note to lower Backing, and lower it now.” | Clarify the mixed note/edit intent; do not silently run both. |
| Make a voice mix change, then change a track control manually before requesting A/B. | The stale comparison is rejected or disabled; the manual edit is not silently overwritten. |
| Close the browser tab after the native panel shows capture is actually running. | The Mac continues the bounded take and saves it locally. Inspect the clip when finished. Disconnecting during preparation may instead cancel before capture. |
| Reload the browser while an edit is pending. | Recover/check the same command status. Never repeat the edit merely because the response was lost. If the outcome is unknown, inspect the Mac before issuing another request. |
| Disconnect the Mac, then speak a new request. | Show it as offline/unavailable; no invented successful edit or recording. |
| Let the assistant speak, without saying anything yourself. | Its reply must not appear as a new user command. Headphones help keep the two audio paths separate. |

An unknown outcome is different from “nothing happened.” **Check your project** means inspect the native timeline and values before retrying. Do not repeatedly resend a gain change or recording request while the previous result is unresolved.

## 7. Troubleshooting

| Symptom | First check |
| --- | --- |
| Studio will not open | Check the backend terminal, health URL, exact studio address, and studio password. In Docker mode also check the helper's `compose ps` command. Provider keys are not the sign-in password. |
| Browser reports a connection/origin error | Use `http://127.0.0.1:5173` and the documented backend URL. Changed ports or a hosted page need an exact allowed origin. |
| The website is blank | The earlier development server returned 504 for JavaScript after an environment reload. The demo now uses the built preview. Refresh the page and confirm you are using this Mac; `127.0.0.1` on a phone refers to the phone. |
| Mac stays offline | Check the code has not expired, the native relay URL includes `/api/voice`, and an editor project is open in the Hackathon app. |
| Browser hears no command | Allow its microphone permission, keep the tab visible, click **Start conversation**, and wait for **I’m listening.** |
| Recording cannot start | Select an audio row, choose an available native input/channel, allow MixRoom microphone access, and wait for spoken preparation to finish. |
| Recording is silent | Browser transcription working does not prove the native input is correct. Check the Mac input device/channel and test a short take again. |
| Preparation or spoken replies fail | Check the backend ElevenLabs key/voice configuration and internet access. A failed preparation should not start recording silently. |
| Speech is transcribed but edits fail | Check the backend OpenAI configuration and provider access. A successful health request alone does not test planning. |
| Hum converts poorly | Use a quiet room and a short monophonic melody. Verify the original audio is audible before diagnosing pitch conversion. |
| App build fails | Keep the terminal error, check free disk space and Flutter/Xcode setup, and stop duplicate builds. Do not delete projects or the Docker data volume to retry. |

For host-backend diagnostics, read its terminal output; this session's launch log is `/tmp/mixroom-host-backend.log`. For Docker mode, run this from the repository root. Share the error message without credentials or personal recordings:

```sh
python3 voice_backend/scripts/docker_local.py compose logs --tail 50 backend
```

**Session timing** in the browser currently reports transcript commit and response-audio header timings. These exclude native planning/execution and are not a complete end-to-end latency measurement.

## 8. Record the results and shut down

Save a screenshot or short screen recording showing the native result for each passed feature. Keep the backend `.env` closed while recording your screen.

- [ ] New project opens; imported audio plays through headphones.
- [ ] Browser and Mac show the same project and selected track.
- [ ] Button-started take records real input after preparation finishes.
- [ ] Spoken gain edit changes the exact intended native value.
- [ ] Before/after, keep, and undo restore the correct values.
- [ ] Timed take and early-stop take are saved and audible.
- [ ] Humming preserves its audio and creates useful editable MIDI.
- [ ] Notes survive reopening, including completion state.
- [ ] Offline/unknown results never claim an unverified successful edit.

Write down the test date, app revision, browser, audio device, actual results, and any failing step. Leave failed or untested items unchecked.

To finish, wait for recording/saving to end, click **End conversation**, then **Disconnect studio** and **Sign out**. Close the native app. Stop the browser development server and host backend with Control-C in their terminals if you started them there. In Docker mode, preserve backend data with:

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app
python3 voice_backend/scripts/docker_local.py compose stop
```

These steps test one browser on the same Mac. A published Lovable page or phone needs an HTTPS backend address and its exact allowed browser origin; see [backend setup](../voice_backend/README.md). Local success does not establish that the published hackathon demo is connected or ready.

### Developer build commands

Use these only when a native build is needed, with Flutter/Xcode installed and enough free disk space. Do not run them while another native build is active.

```sh
cd /Users/uddinsiyam/Desktop/digital-af/mixroom-app
./tool/run_hackathon.sh
```

That command builds and launches the debug Hackathon flavor. `./tool/build_hackathon.sh` makes a release build; `./tool/run_hackathon.sh --release` builds and launches in release mode. Provider API keys are not required in any build command.

To rebuild the backend after source changes, run `python3 voice_backend/scripts/docker_local.py compose up -d --build` from the repository root. Avoid rebuilding while another build is active or a performer is connected. Ordinary startup uses `--no-build` above.

### Source references for the menu paths

- [Hackathon home and New Project](../lib/screens/hackathon_home.dart)
- [Desktop Add menu labels](../lib/helpers/daw_add_menu_config.dart)
- [Row selection, context menu, and rename](../lib/screens/audio_timeline_pro.dart)
- [Project Settings and audio device controls](../lib/screens/audio_editor.dart)
- [Native Voice session panel and recording behavior](../lib/screens/audio_editor_voice.dart)
- [Native pairing dialog](../lib/voice/voice_pair_dialog.dart)
- [Browser sign-in](../voice_companion/src/App.tsx) and [voice studio controls](../voice_companion/src/voice/VoiceStudio.tsx)
