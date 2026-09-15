# Mixroom Technical System Documentation

**Document type:** Technical architecture, AI assurance, and implementation overview  
**Audience:** Government technology programs, technical evaluators, partners, auditors, research organizations, and engineering stakeholders  
**Product:** Mixroom  
**Repository version reviewed:** Application version 1.3.5+53  
**Documentation snapshot:** 26 August 2026  
**Primary emphasis:** Artificial intelligence architecture, controls, data handling, model lifecycle, and technical limitations  
**Status:** Repository-grounded technical disclosure

## 1. Purpose and scope

Mixroom is an AI-assisted digital audio workstation, or DAW. It combines a cross-platform Flutter application, a native JUCE audio engine, local audio-analysis and machine-learning models, cloud language-model planning, and serverless backend services.

This document explains how those systems work together. It focuses on the technical properties that matter when evaluating whether Mixroom uses AI meaningfully, understands the technology it operates, controls the risks created by probabilistic models, and can provide evidence for its claims.

The document covers three major areas:

1. The AI system, including language-model planning, project context, local audio analysis, deterministic mixing logic, ONNX refinement models, stem separation, audio-to-MIDI transcription, training-data capture, evaluation, privacy, and safety.
2. The DAW and native JUCE engine, including project state, the audio graph, real-time processing, clips, MIDI, effects, automation, recording, routing, and export.
3. The backend, including authentication, AI proxying, entitlements, cloud projects, data stores, model distribution, observability, and operational controls.

This is an implementation document, not a marketing description. Claims use the following confidence labels:

- **Implemented:** Directly represented in the reviewed source code or infrastructure templates.
- **Implemented with limited verification:** A complete code path exists, but repository evidence does not establish production performance or quality across all conditions.
- **Shadow or experimental:** Implemented for measurement but not allowed to control the user-visible production result.
- **Designed:** An accepted architecture or planned boundary exists, but the complete production implementation is not active.
- **Externally unverified:** The repository describes the configuration, but live cloud state, provider dashboards, deployed versions, or operating procedures were not independently inspected for this document.

The repository is the source of truth for this review. When a model's internal training algorithm or the deployed cloud configuration cannot be proven from repository artifacts, this document says so explicitly.

## 2. Executive technical summary

Mixroom uses a hybrid AI architecture rather than asking one general-purpose model to directly manipulate audio.

For a normal AI-assisted DAW request, the system works as follows:

1. The Flutter application captures authoritative project state and creates a structured project context.
2. The user's original request and that context go to an authenticated Mixroom AI proxy.
3. A cloud language model performs semantic and musical planning and returns a strict, versioned plan composed only of supported command types.
4. The application parses the plan and rejects malformed, stale, unsupported, excessive, or factually impossible work.
5. Command-specific preparation converts the plan into existing editor operations without allowing the language model to mutate the project directly.
6. High-level mixing goals pass through Mixroom's deterministic local mixing model. That model examines roles, audio statistics, overlap, effects, requested scope, intensity, and reference constraints to propose concrete mix actions.
7. Optional learned ONNX models refine each proposed mix action. One estimates whether the action should apply. The other predicts an action-strength scale.
8. The complete local operation bundle executes through one transaction where the supported path provides atomic execution, readback, rollback, and a single Undo entry.
9. The assistant reports success only from execution receipts, not from the language model's claim that work succeeded.

This separation is important. The cloud model interprets intent and produces typed plans. It does not receive unrestricted access to the editor, the file system, plugins, or the real-time audio thread. Flutter remains the execution authority. JUCE remains the audio-processing authority.

The current authenticated AI V3 production route is a one-shot planner with 54 typed commands. A compact adaptive planner can request one bounded batch of read-only facts from an immutable snapshot, but that adaptive route remains detached and shadow-only because evaluation has not yet justified activation. Older released clients retain the legacy V1 route. The client does not silently send a failed V3 request to V1 for reinterpretation.

The current chat planning path sends structured text context, not raw audio files. Local analysis produces compact facts such as loudness, spectral balance, transient density, stereo characteristics, role probabilities, and overlap relationships. Separate user-invoked local pipelines may process raw audio on the device for stem separation and transcription.

## 3. System boundaries and major components

### 3.1 Flutter application

Flutter owns the product workflow and authoritative editable state. Its responsibilities include:

- project, row, clip, MIDI, automation, effect, and selection state;
- project persistence, migrations, recovery, and Undo coordination;
- user authentication and account workflows;
- constructing AI context and sending authenticated requests;
- strict parsing and factual preparation of AI plans;
- transaction coordination and user-facing execution status;
- calling the JUCE engine through a typed Dart interface;
- analytics, crash reporting, privacy settings, and consent state.

Relevant implementation areas include `lib/ai/`, `lib/models/`, `lib/helpers/`, `lib/screens/audio_editor.dart`, and `lib/screens/audio_timeline_pro.dart`.

### 3.2 Native JUCE audio engine

The native engine performs work that should not run in Dart or on the UI thread. It owns:

- low-latency audio-device callbacks;
- the JUCE `AudioProcessorGraph` and its row, group, and master routing;
- audio and MIDI clip rendering;
- effect processing and hosted plugin behavior where supported;
- metering, automation playback, recording, metronome, and transport synchronization;
- offline track and mix rendering;
- device selection and mobile audio-route behavior;
- native audio analysis used to build AI facts.

The Dart/native contract uses method channel `juce_audio_engine` and event channel `juce_audio_engine/events`.

### 3.3 AI proxy

The AI proxy is an AWS SAM serverless application. It authenticates the user, enforces usage and prompt limits, selects server-controlled model settings, calls the configured language-model provider, records usage metadata, and exposes the learned mix-refinement endpoint.

Its primary routes are:

- `POST /v1/llm/responses` for the legacy AI path;
- `POST /v1/llm/v3/responses` for authenticated one-shot V3 planning;
- `GET /v1/llm/limits` for user-visible AI limits;
- `POST /v1/llm/conversation-events` for compact execution-result memory where enabled;
- `POST /v1/mix/resolve` for remote ONNX mix refinement.

### 3.4 Application backend

The application API is a separate AWS SAM system. It handles app-user authentication, profiles, entitlements, billing, feature flags, feedback, producer-training uploads, organization and workspace metadata, cloud-project document access, administration, and provider webhooks.

### 3.5 External services

The implementation supports or references OpenAI, Anthropic Claude, and Google Gemini through a provider abstraction, with OpenAI-specific conversation-state support. The deployed provider and model are controlled by backend configuration. Authentication and billing integrations include platform identity providers, Apple App Store, Google Play, Paddle, and Toss. PostHog and Sentry provide analytics and error monitoring when configured and permitted.

These services are outside the application's trust boundary. Mixroom therefore keeps credentials on the backend, validates provider responses, restricts outbound payloads, and does not give the language model direct editor authority.

> **Diagram placeholder 1: Whole-system deployment architecture**
>
> Create a deployment diagram with four trust zones: user device, Mixroom AWS account, AI provider, and third-party identity/billing/observability services. Within the device, show Flutter, project storage, local ONNX Runtime, and the JUCE engine. Within AWS, show API Gateway, Lambda functions, DynamoDB, SQS, object storage, Secrets Manager or SSM Parameter Store, CloudWatch, and WAF. Label every network boundary, authentication mechanism, and whether the data crossing it contains raw audio, structured project facts, credentials, billing events, or model files.

# Part I. Artificial intelligence system

## 4. AI design principles

Mixroom's AI architecture follows six central principles.

### 4.1 One semantic planner

One language model owns semantic and musical interpretation of the original request. The architecture avoids mandatory chains of intent models, selector models, critics, and repair models that could independently reinterpret or narrow the same request.

The original request remains intact. It is not reduced to a lossy intermediate label before planning.

### 4.2 Typed, bounded authority

The planner can return only a strict result with one of four outcomes:

- `plan` for an executable command list;
- `respond` for a non-mutating answer;
- `clarify` when ambiguity materially changes the result;
- `unsupported` when the product cannot perform the request.

Executable plans contain versioned, operation-specific commands. They do not contain arbitrary code, generic plugin scripts, shell commands, filesystem paths, or free-form mutation instructions.

### 4.3 Deterministic execution outside the model

The language model chooses meaning, targets, and supported operations. Flutter checks facts and executes. Command preparation can resolve exact IDs, verify resources, check limits, convert units, and calculate expected readback. It cannot substitute a different target, delete a model command, choose a different creative strategy, or silently repair the plan.

### 4.4 Stable identities and stale-state protection

Rows, clips, effects, assets, groups, and transaction-created resources use stable identities. Names and display indices help the model understand context but do not become the final authority where a stable ID exists.

Every plan binds to a project-state digest. If the project changes between planning and execution, the prepared plan fails as stale instead of applying against an unintended state.

### 4.5 Transactional mutation and evidence-based success

The V3 local execution path prepares the complete command bundle, rechecks state, executes through one transaction, performs targeted readback, and rolls back if execution or verification fails. Successful mutation messages come from receipts produced after readback.

This prevents a common agentic-system failure where a model says an action succeeded merely because it emitted a plausible tool call.

### 4.6 Explicit limits

The architecture does not claim that strict JSON guarantees musical correctness. Contract validation proves shape. Preparation proves factual executability. Readback proves that the intended properties changed. Human listening and audio-level evaluation remain necessary to judge taste and sonic quality.

## 5. AI request lifecycle

### 5.1 Request intake

The user enters natural-language text in the DAW assistant. The chat pipeline keeps a bounded recent conversation. The implementation limits its local conversation buffer to 24 messages and 12,000 characters before further request shaping. V3 context builders apply their own deterministic bounds.

The request may be a factual question, tutorial request, exact edit, compound edit, mix instruction, MIDI operation, sample request, or advanced audio workflow. The system does not assume every prompt should mutate the project.

### 5.2 Authoritative context construction

Flutter constructs context from current editor state. Depending on the active planner path, this may include:

- project ID and state digest;
- BPM, meter, key, estimated key, playhead, and timeline facts;
- selected row and clip identities;
- row identities, names, lane types, groups, instruments, gains, pans, mute and solo state;
- clip identities, types, labels, start positions, lengths, and source identities;
- effect instances and supported effect metadata;
- automation targets;
- audio-analysis summaries and role probabilities;
- resource and catalog availability;
- pending plan state when the user modifies a proposal;
- bounded conversation history and client context.

The production one-shot context uses a bounded V3 core representation. The adaptive design additionally creates one immutable `PlanningSnapshotV3`, then projects a smaller `CompactCoreV3` from it.

### 5.3 Backend authentication and policy

The client sends a bearer access token to the AI proxy. The proxy validates Mixroom app authentication, checks account and entitlement state where applicable, enforces request-size and usage limits, resolves server-managed runtime configuration, and loads the provider key from secure backend configuration.

Client model override is disabled by default. V3 has a server kill switch, server-owned model choice, and server-owned reasoning effort. Infrastructure defaults in the reviewed template set the V3 model to `gpt-5.6-luna` with low reasoning effort, but this is a deployment default rather than proof of the live production value.

### 5.4 Strict model call

The V3 planner receives:

- the original request;
- authoritative structured context;
- a principle-focused system instruction;
- the strict `submit_plan_v3` tool schema containing supported command variants.

The provider call must return the required function-call structure. Parallel tool calls are disabled for the adaptive protocol. The system rejects missing calls, extra calls, invalid JSON, unknown command types, unexpected fields, invalid values, too many commands, or an inconsistent outcome.

### 5.5 Plan preparation

The command preparer simulates the command sequence against symbolic state. This allows later commands to target a row or clip created earlier in the same plan. Preparation validates every operation before any local mutation occurs.

Examples of preparation checks include:

- exact row, clip, group, effect, and asset existence;
- destination capacity and row limits;
- numeric ranges, finite values, and enum membership;
- clip timing and valid beat ranges;
- MIDI-note limits and valid pitches, velocities, positions, and lengths;
- effect availability and parameter semantics;
- processing target and reference target separation;
- conflicts between direct effect operations and a mix goal;
- required waveform, onset, or tempo analysis;
- expected before-and-after values for readback.

Plans can contain at most 16 commands. Model-authored generated MIDI is bounded to 256 notes per plan. Runtime-authoritative MIDI input has a separate 1,024-note bound. Automation commands are bounded to 128 points in the active contract.

### 5.6 Mix-goal materialization

A `mix.apply_goal` command does not directly expose low-level parameter mutations from GPT. It creates a typed `GoalVector` and passes it to the local mixing materializer. The materializer runs Mixroom's deterministic mixing model, optionally refines the resulting actions with learned models, verifies that the output remains inside the permitted target set, and converts it into the same concrete editor action system used by normal operations.

### 5.7 Execution and readback

Prepared local work uses the V3 transaction boundary. The current 54 commands are classified `auto_apply` because they are intended to be reversible through the local Undo and rollback mechanisms. The policy table supports a future `confirm` classification for irreversible or external work. An unclassified command fails safely.

Execution generates factual receipts. The user-facing completion is derived from those receipts after verification.

> **Diagram placeholder 2: AI plan and execution sequence**
>
> Create a sequence diagram with User, Flutter Chat Pipeline, Context Builder, Mixroom AI Proxy, Language Model Provider, V3 Parser, Command Preparer, Local Mixing Model, ONNX Refiner, Transaction Coordinator, DAW State, and JUCE Engine. Show the state digest at capture and pre-commit, strict plan output, full preparation before mutation, optional mix materialization, commit, targeted readback, rollback branch, and receipt-derived response. Use a red boundary around every probabilistic component and a green boundary around deterministic validation and execution.

## 6. Current V3 command surface

The active V3 contract contains 54 typed commands. This count comes from the code-level `aiV3CommandTypes` set.

### 6.1 Project and transport

- Set project tempo, with explicit audio time-stretch and pitch-preservation choices.
- Start or stop transport.
- Restart transport.
- Enable or disable the metronome.
- Enable or disable looping.
- Set project tempo from an analyzed clip.

### 6.2 Rows and groups

- Adjust or set row gain.
- Adjust or set row pan.
- Set mute or solo.
- Rename or select a row.
- Set row color.
- Set an instrument.
- Set or clear a role override.
- Create or delete a row.
- Apply the defined phone-microphone cleanup chain.
- Create a group, remove a row from a group, or set group collapse state.

### 6.3 Audio clips

- Move, trim, split, duplicate, or delete clips.
- Glue compatible audio clips.
- Separate a clip into vocal and instrumental stems.
- Convert audio to MIDI.
- Set or adjust pitch in semitones.
- Set or scale visible timeline length.
- Set source-tempo metadata.
- Set tempo-follow mode.
- Align clip tempo with the project.
- trim silence;
- align the first audible sound to a destination.

### 6.4 MIDI

- Transpose notes.
- Create a MIDI clip.
- Replace, append, or rhythmically chop notes.

### 6.5 Effects and automation

- Ensure and configure a supported effect instance.
- Remove an effect instance.
- Set effect bypass state.
- Create a gain fade.
- Set or clear automation points.

### 6.6 Samples and mixing

- Place a sample.
- Replace a sample-backed clip.
- Apply a high-level Mixroom mixing goal.

The code-level common set contains 17 commands because it includes four transport commands in addition to the 13 everyday project, row, and clip edits described in the adaptive architecture report. This distinction is documentation terminology, not a hidden command discrepancy.

## 7. Language-model planning

### 7.1 What the language model does

The language model performs tasks for which probabilistic semantic reasoning is useful:

- interprets natural language and multilingual phrasing;
- distinguishes informational requests from edit requests;
- resolves user intent across recent conversation and current selection;
- chooses supported operations and exact stable targets;
- converts qualitative musical language into structured goals;
- orders compound operations;
- decides whether an ambiguity is material enough to clarify;
- writes a preview-oriented user message.

### 7.2 What the language model does not do

The language model does not:

- execute arbitrary code;
- access the user's file system;
- receive a direct reference to mutable Flutter state;
- write directly into the JUCE graph;
- run on the real-time audio thread;
- choose its own backend credentials or production model;
- bypass authentication, quotas, schema validation, preparation, or readback;
- determine whether execution technically succeeded;
- silently replace unsupported commands with guessed alternatives.

### 7.3 Strict structured output

`PlanV3` uses a discriminated, versioned schema. Every command includes a unique command ID, one recognized type, and operation-specific arguments. Exact-key checks reject both missing and unexpected fields. Numeric fields must be finite and remain within command-specific bounds. Outcome and command-list consistency is enforced.

Strict output reduces malformed-plan risk, but it does not prove that an existing project contains a referenced entity. That remains the preparer's responsibility.

### 7.4 Prompt strategy

The accepted V3 design keeps the core system prompt short and principle-focused. Operation details belong in typed schemas and command-owned metadata. This reduces the tendency to accumulate fragile prompt patches, language-specific regular expressions, and request-specific exceptions.

The legacy V1 route contains a substantially larger prompt and normalization surface. It remains for older clients, but V3 deliberately moves away from legacy generic action maps and duplicated alias repair.

### 7.5 Conversation state

Current project state remains authoritative. Conversation supplies continuity but cannot override fresh editor facts. Where OpenAI conversation-state mode is enabled, the backend can store a mapping from a hashed Mixroom user, project, feature, and session identity to an OpenAI conversation ID. Compact execution-result events can be appended as developer messages. They contain action types, failure types, applied status, and a short summary, not a fresh replacement for project state.

## 8. Adaptive planner and bounded retrieval

The adaptive planner addresses the cost and latency created by serializing every clip, note, effect definition, plugin, and sample on every request.

### 8.1 Status

The adaptive planner is **implemented as a detached shadow path**. It can be evaluated against the active planner but cannot supply or execute the user-visible plan. This is an important maturity control: promising token reductions have not been treated as sufficient evidence for activation.

### 8.2 Immutable snapshot

One `PlanningSnapshotV3` captures all available authoritative facts before the first model call. Retrieval reads only this immutable object. If live state changes while the model is working, the finished plan still points to the old digest and fails preparation.

The snapshot is held only for the planning turn. It is not itself part of persisted project data. Sanitized debug captures require the existing capture controls.

### 8.3 Compact core

The compact core always includes project identity, state digest, tempo and meter, key information, playhead, selection, row capacity, all lightweight rows within the current 32-row limit, and a bounded clip index. It includes no more than 64 clip summaries and reports `total_count`, `returned_count`, and `has_more` whenever a collection is bounded.

Detailed note arrays, audio vectors, effect parameter definitions, full catalogs, filesystem paths, and complete automation are excluded from the initial core.

### 8.4 Retrieval protocol

On the first call, the same planner may either submit a final plan or request one batch of facts. A batch can contain at most four typed queries. The application performs deterministic lookup against the immutable snapshot, then gives the results to the same planner for one final call. No third planner call is allowed.

Supported fact domains include project structure, advanced clips, MIDI, samples, effects, automation, mixing, music generation, files and plugins, external audio, and tutorial/UI facts.

Initial retrieval limits include:

- 64 clip summaries;
- 512 MIDI notes;
- 32 library results per query and 64 total;
- 64 effect instances;
- 128 parameter definitions;
- 512 automation points;
- 32 file, plugin, or preset results per query and 64 total;
- mix facts for 32 rows plus master and groups.

Retrieval cannot perform network access, mutation, arbitrary file reads, plugin execution, or semantic target substitution.

### 8.5 Evaluation evidence

Repository evaluation records show material input-token reductions in several shadow suites. They also show higher latency from the second model call and recurring misses involving relative versus absolute operations, insufficient MIDI retrieval, and false clarification. For that reason, the adaptive route remains shadow-only. This is the correct interpretation of the evidence: the approach scales context more efficiently, but it has not yet demonstrated equal or better reliability across the activation gate.

## 9. Project and audio understanding

The AI does not rely only on filenames or the user's description. Mixroom builds a structured `ProjectState` from editor state and local audio analysis.

### 9.1 Row and clip representation

The project-state builder represents rows, clips, effects, mixer settings, role overrides, and overlap. It combines timeline occupancy with available analysis. It maintains bounded persistent analysis caches so repeated prompts do not unnecessarily decode and analyze the same clips.

### 9.2 Audio features

The native and Dart analysis paths derive features including:

- approximate RMS and crest factor;
- short-term RMS mean, high percentile, variability, and transient density;
- spectral centroid, bandwidth, rolloff, slope, flatness, and flux;
- zero-crossing rate;
- high-frequency RMS;
- low, low-mid, mid, and high-band energy;
- sibilance and bassiness proxies;
- true-peak estimate and clipping ratio;
- integrated and short-term LUFS estimates;
- loudness-range estimate;
- silence and activity ratios;
- onset-rate estimate;
- noise-floor estimate;
- stereo phase correlation, side ratio, and imbalance;
- twelve-bin key chroma used in key estimation.

These are compact engineering measurements and proxies. They are not represented as laboratory-certified mastering measurements.

### 9.3 Temporal overlap and masking context

Mixroom calculates whether rows overlap in time and estimates overlap ratios. The mixing feature builder derives project-level values such as overlap density, masking-pair ratio, centroid-collision ratio, role-overlap ratio, relative RMS pressure, and band-specific collision measures.

This matters because two tracks with similar spectra are only likely to mask each other when they play at the same time.

### 9.4 Role understanding with YAMNet

The local `yamnet.onnx` classifier consumes mono floating-point audio at 16 kHz. It samples up to three approximately 0.975-second frames from the beginning, middle, and end regions of a clip, pads short clips, runs ONNX Runtime, averages output scores, and maps selected AudioSet/YAMNet classes into Mixroom roles:

- vocals;
- guitar;
- bass;
- drums;
- synth or keys;
- other.

The mapping aggregates selected YAMNet class indices, normalizes the role scores, and provides a fallback distribution when the model is disabled, unavailable, or inference fails. A role override supplied by the user remains a separate authoritative signal.

YAMNet supports context construction. It is not itself a mixing model and cannot directly modify the project.

## 10. Deterministic local mixing model

`LocalMixingModel` is the primary rule-based mix-planning engine. It converts a structured goal and project facts into concrete `MixAction` objects.

### 10.1 Inputs

The model considers:

- requested scope: automatic, row, group, or master;
- requested intent families such as gain, pan, balance, EQ, compression, limiting, clipping, reverb, delay, de-essing, or distortion;
- direction and qualitative descriptors;
- requested intensity and audibility;
- execution profile: producer-safe, creative-bold, or experimental-extreme;
- whether destructive behavior is permitted;
- row roles and explicit overrides;
- current gain, pan, effect, and master state;
- audio statistics and cross-track overlap;
- reference-track target and matching mode where requested.

### 10.2 Output actions

The deterministic engine can propose concrete actions including:

- row or master gain and pan changes;
- ensuring or deleting a supported effect;
- setting or adjusting an effect parameter by name;
- resetting row or master effect chains.

The V3 materializer permits a defined action set and rejects any action outside it. It also checks that row-targeted operations remain within the requested row or group, that master-only goals do not leak into rows, and that a reference row remains protected from mutation.

### 10.3 Reference mixing

Reference mixing distinguishes the processing target from the reference target. The local model can compare tone, loudness, width, glue, or a fuller combination. It protects the reference row from the resulting actions and checks that the two targets are different.

Reference suitability remains a quality-sensitive area. The structural safeguards are implemented, but whether a particular source is a musically appropriate reference still requires listening evaluation.

### 10.4 Why deterministic logic remains important

The deterministic layer provides a stable baseline when learned models are unavailable. It also makes the supported action space inspectable, enforces product-specific units and ranges, and prevents a learned model from inventing new target identities or processor types.

## 11. Learned mix refinement

Mixroom includes two learned ONNX models that refine deterministic candidate actions.

### 11.1 Apply classifier

The apply classifier answers: **Should this proposed action be retained?**

For every proposed action, it receives a 77-value feature vector containing project context, goal context, aggregate audio characteristics, overlap and masking measurements, action magnitude, target scope, and one-hot action type indicators. It outputs an apply score.

The client uses two thresholds:

- below 0.15, a non-strict and non-audibility-protected action may be dropped;
- below the configured apply threshold, default 0.5, the action is attenuated rather than treated as fully confident.

Strict execution and explicit audibility profiles can preserve a minimum action scale so the refinement layer does not erase a clear user request.

### 11.2 Magnitude regressor

The magnitude regressor answers: **How strongly should the retained action apply?**

Its scalar output is clamped to a scale from 0 to 3. The system applies goal-dependent minimum floors and scales the action relative to the current state. For an absolute gain, pan, or effect target, scaling interpolates between the current value and proposed target. For a delta operation, it scales the delta. Parameter ranges are clamped after scaling.

### 11.3 The 77-feature contract

The feature order is an explicit compatibility contract shared by client inference, backend inference, and training conversion. It includes:

- goal intensity, strictness, BPM normalization, and audio-row ratio;
- median RMS and counts of gain, pan, effect, and master operations;
- target-scope and intent-kind indicators;
- median crest, RMS spread, centroid, zero-crossing, sibilance, bassiness, and high-frequency RMS;
- short-term dynamics and transient density;
- temporal overlap, masking, spectral collision, RMS pressure, and role overlap;
- true peak, LUFS, loudness range, clip ratio, flatness, rolloff, slope, flux, bandwidth, silence, onset rate, and noise floor;
- phase correlation, side ratio, and stereo imbalance;
- band-specific overlap collision values;
- proposed action magnitude, master targeting, and action-type indicators.

A feature-count mismatch causes a safe fallback to the deterministic actions.

### 11.4 Local and remote inference

The same logical refinement is available in two forms:

- **Local:** Flutter ONNX Runtime loads bundled models or a verified downloaded model bundle.
- **Remote:** The authenticated `/v1/mix/resolve` backend runs ONNX Runtime and returns refined actions plus observability metadata.

The remote path preserves the proposed action targets. It is not another language-model planning call.

### 11.5 Fallback behavior

Refinement falls back to the deterministic actions when:

- learned magnitudes are disabled;
- the model is not ready;
- model loading fails;
- the feature contract does not match;
- inference returns invalid output;
- remote transport fails;
- refinement times out;
- the execution profile intentionally bypasses refinement;
- reference-guided mixing uses the deterministic protected path.

The fallback reason is included in observability metadata.

### 11.6 Model-type limitation

The repository proves that one artifact is an apply classifier and one is a magnitude regressor. It does not contain reliable metadata proving the original training estimator family, such as neural network, gradient-boosted tree, or linear model. This document therefore does not claim an unverified internal estimator type.

> **Diagram placeholder 3: Hybrid mixing model**
>
> Draw a dataflow diagram from GoalVector and ProjectState into LocalMixingModel, producing candidate MixActions. Branch each candidate into a shared 77-feature builder, then into Apply Classifier and Magnitude Regressor. Show thresholding, audibility floors, interpolation from current to proposed value, target containment validation, and output concrete MixActions. Add a fallback arrow from every model failure to the unchanged deterministic candidate list.

## 12. Model packaging, distribution, and activation

Bundled ONNX assets include YAMNet, Basic Pitch, two Spleeter stem models, and multiple generations of apply-classifier and magnitude-regressor artifacts.

The mix-refinement model manager supports bundled and remotely distributed models. The remote distribution flow uses a manifest and downloaded files. The manager records model source, bundle version, apply-model version, magnitude-model version, and references for observability. If remote model loading fails, it marks activation failure and returns to the bundled selection.

The reviewed flags currently support preferring bundled models. A CDN infrastructure template and publishing scripts exist for controlled magnitude-model delivery.

Government or enterprise evidence should include the signed or checksummed model manifest, artifact hashes, training run identity, evaluation report, activation date, rollback version, and approval owner. The runtime has the technical seams for versioned activation, but the repository alone does not establish a complete organizational model registry or approval process.

## 13. Stem separation

Mixroom's two-stem separation path is local and uses separate FP16 ONNX models for vocals and accompaniment.

### 13.1 Signal path

The separator converts input audio into model-compatible stereo PCM at 44.1 kHz. It uses a 4,096-sample FFT, 1,024-sample hop, 2,049 FFT bins, 1,024 model bins, and 512-frame processing chunks. It constructs time-frequency model inputs, runs vocal and accompaniment inference, reconstructs stereo audio, and writes derived PCM WAV files.

### 13.2 Model availability

The separator first ensures usable model files. It can copy bundled assets and supports download fallback. It rejects unexpectedly small model files and exposes progress stages.

### 13.3 Execution semantics

Stem separation is asynchronous and creates files plus new DAW state. The legacy path supports the workflow, but file creation and project insertion do not yet share the same complete atomic guarantee as ordinary V3 property mutations. The V3 architecture therefore classifies separation as staged external or asynchronous work, even when inference occurs locally:

1. validate and plan;
2. start the job with progress and cancellation;
3. receive the generated files;
4. revalidate current project state;
5. preview or prepare insertion;
6. apply the result in a separate local transaction.

This is a disclosed boundary, not a claim that a long-running file job can be rolled back as if it were a single gain change.

## 14. Audio-to-MIDI transcription

Basic Pitch transcription runs locally through `basic_pitch_nmp.onnx`.

The transcriber accepts mono audio at 16 kHz, resamples it to the model's 22,050 Hz input rate, and processes overlapping two-second windows. Its main constants include a 256-sample FFT hop, approximately 86 annotation frames per second, 88 note bins, 264 contour bins, and MIDI offset 21.

The model produces note, onset, and contour-related tensors. Deterministic post-processing augments onset candidates, decodes polyphonic notes, applies minimum-duration and energy rules, converts model frames to time, and returns MIDI pitch, start, end, and confidence information. The editor then prepares a MIDI destination and inserts notes.

As with stem separation, transcription quality and compound source-to-destination rollback require audio-level and end-to-end evaluation. The model's existence does not guarantee musically perfect transcription.

## 15. Phone-microphone cleanup

The defined `phone_mic_cleanup_v1` path applies a canonical effect chain:

- Parametric EQ;
- De-Esser;
- Dynamic Softener;
- Compressor;
- Limiter.

It also records enhancement metadata and can warm a rendered cache in the background. Effect insertion is reversible through the editor path. Restoration of every metadata field and removal of every asynchronously generated cache file is not yet represented as one universal rollback operation, so the capability remains partially transactional.

## 16. Music generation architecture

The accepted design does not assume that a language model should emit hundreds of raw MIDI notes for every composition request.

`MusicSpecV3` defines a provider-neutral brief containing project digest, placement, length, key, scale, meter, tempo, style and mood tags, sections, roles, instrumentation constraints, harmony, groove, relationships to existing material, and an optional deterministic seed.

A realization provider would return `GeneratedMusicBundleV3`, containing exact bounded events, destination bindings, provider identity and version, provenance, seed, warnings, and preview information. The design allows comparison among:

1. GPT-authored compact patterns with deterministic expansion;
2. curated or deterministic pattern realization;
3. a hybrid language-model brief with provider-owned realization.

This boundary is implemented as architecture and supporting code, but the production realization provider has not been selected. Selection requires blind musical evaluation. Exact user-requested MIDI edits remain direct typed commands and should not be routed through a generative provider.

### 16.1 Standalone video-editor AI

Mixroom also contains a lightweight video sequencer with a separate AI contract. It is not part of the DAW V1-to-V3 command migration and does not use the mixing, audio-analysis, or ONNX-refinement stack.

The video AI receives a structured snapshot of video and audio tracks, clip IDs, source-relative and timeline timing, volume and mute state, transitions, playhead, and selection. Its cloud language-model prompt exposes two tools: a non-mutating informational response and a bounded `video_editor_actions` result.

Supported video actions are clip split, trim, move, duplicate, delete, mute, unmute, volume change, transition add, transition remove, transition duration, transition type, and playhead movement. The prompt explicitly rejects unsupported claims such as captions, masking, color grading, motion tracking, keyframes, cropping, AI media generation, and true speed ramping.

The Flutter video sequencer remains the execution authority. It resolves stable clip, track, and transition IDs and applies the structured actions to its local timeline model. Video export builds an FFmpeg composition from the current clips, transitions, and audio mix. This is a smaller, separate agent surface and should be evaluated independently from the DAW V3 transactional assurance claims.

## 17. Training-data capture and conversion

Mixroom contains an opt-in producer-data system intended to learn from real editing outcomes.

### 17.1 Consent and isolation

Capture is disabled unless enabled under the producer-training consent flow. The collector identifies its capture and consent schema versions. Capture errors are designed not to interrupt editing, saving, playback, or AI execution.

### 17.2 Episode model

The collector creates an append-only event journal and a materialized episode view. It can record:

- AI request and proposed actions;
- sanitized state before and after an AI step;
- subsequent manual corrections;
- Undo or Redo rejection signals;
- whether changes survived the next playback;
- producer review labels and quality ratings;
- relevant playback and diagnostic context.

Continuous parameter edits are coalesced so a drag gesture does not become a large number of independent training decisions. Session limits bound paired audio and review candidates.

### 17.3 Privacy-oriented sanitization

The collector sanitizes snapshots, uses a per-session salt for stable internal references, and redacts defined sensitive keys. Upload is a separate state machine with pending, uploading, uploaded, and retry-needed states.

An organizational review should still verify the exact consent copy, retention period, deletion procedure, bucket policy, and access log. Those policy facts cannot be inferred solely from the collector implementation.

### 17.4 Deterministic dataset conversion

The backend converter turns consented capture-v4 bundles into sharded JSONL examples. It imports the production mix feature builder so training examples use the same ordered 77 features as inference.

The converter:

- streams one bundle at a time;
- deduplicates examples;
- keeps all examples from one session in one deterministic train, validation, or test split;
- writes checksummed shards and a manifest;
- creates apply labels from accepted, rejected, or producer-reviewed outcomes;
- assigns sample weights and label provenance;
- creates magnitude targets only when a meaningful proposal-to-result ratio exists;
- preserves unsupported action types for diagnosis without contaminating current objectives.

Manual-only actions can train action selection and direct targets. Magnitude training is limited to cases where the system can compare an AI proposal with the producer's resulting magnitude.

### 17.5 What is not proven by the repository

The repository does not contain a complete model-training script for the current official ONNX artifacts, a model card with dataset size and demographic or genre distribution, or final accuracy metrics for those artifacts. A formal application package should add those items before making quantitative performance claims.

## 18. AI evaluation and release gates

Mixroom's V3 records define stronger evidence than schema validity alone.

### 18.1 Required correctness dimensions

Evaluation should score:

- correct interpretation and target selection;
- completion of every requested operation;
- preservation of explicitly protected state;
- absence of unintended mutation;
- preparation and execution success;
- exact readback;
- Undo and rollback behavior;
- false clarification and false unsupported rates;
- invalid-plan rates;
- latency, input/output tokens, cache use, and cost;
- repeated-run stability;
- human listening quality for creative output.

### 18.2 Prototype and production gates

The accepted architecture calls for a sealed 30-case prototype set and a separate unseen 75-case production holdout. It requires zero critical wrong-target or protected-state mutations and no partial compound commits. A small prompt demonstration is explicitly insufficient to claim superiority.

### 18.3 Current evidence posture

The repository contains unit tests, integration tests, contract tests, captured planner comparisons, genuine-project shadow runs, input profiling, and capability inventories. It also records misses rather than hiding them. Examples include relational MIDI retrieval failures, relative-versus-absolute operation errors, and adaptive latency penalties.

The capability inventory uses conservative status labels. Many paths are `implemented_unverified` or `partial`, not `verified`, because model output or mock execution does not prove correct real-editor mutation and audible quality.

### 18.4 Recommended external evidence package

For a government review, attach:

- frozen application and backend commit hashes;
- hashes and model cards for every ONNX artifact;
- training-data lineage and consent version;
- train, validation, and untouched test partition methodology;
- per-capability evaluation tables and confidence intervals;
- wrong-target and preservation-violation reports;
- blinded listening protocol and inter-rater agreement;
- latency and cost distributions by device and project size;
- rollback, stale-state, malformed-plan, and service-outage tests;
- production monitoring dashboards with sensitive values removed;
- documented model approval and rollback decisions.

## 19. AI privacy and data handling

### 19.1 Data sent in cloud chat planning

The current chat path can send:

- the latest user request;
- bounded recent conversation;
- structured project and selection facts;
- row and clip names or labels;
- mixer and effect summaries;
- audio-analysis summaries and role probabilities;
- overlap relationships;
- pending-plan state;
- project and feature identifiers;
- optional analytics context such as app version, platform, locale, device/distinct/session identifiers when analytics is enabled.

### 19.2 Data not sent in the current chat path

The reviewed chat-planning path does not send:

- raw audio files or PCM buffers;
- rendered stems;
- full waveform data;
- the complete project file;
- arbitrary filesystem paths in adaptive retrieval;
- opaque plugin-state blobs;
- local ONNX weights or inference tensors.

This statement applies to chat planning. A separate cloud-project upload, producer-training upload, feedback attachment, or future remote audio job has its own data path and consent or product contract.

### 19.3 Logs and telemetry

Backend request logs are designed around metadata rather than full request bodies. AI usage tables record prompt counts, token usage, feature, model and provider context, timing, and related accounting facts. PostHog and Sentry integrations are configurable.

Debug and evaluation captures can contain richer sanitized context. They must remain disabled or consent-gated in normal production use and need an explicit retention and access policy.

### 19.4 Provider retention

Provider-side retention and training use depend on the commercial account and API settings used in deployment. The repository cannot prove those dashboard settings. A formal disclosure must attach the provider data-processing agreement and a screenshot or exported configuration showing retention and training controls.

## 20. AI threat model and safety controls

### 20.1 Principal risks

The important risks are:

- prompt misunderstanding;
- wrong-target selection;
- hallucinated project resources;
- stale plans applied to changed state;
- malformed or excessively large plans;
- partial compound execution;
- model or prompt version drift;
- provider outage or rate limiting;
- sensitive data in prompts, logs, or captures;
- adversarial text embedded in filenames or project labels;
- model-generated claims of success without execution;
- low-quality but structurally valid musical decisions.

### 20.2 Existing controls

The implementation addresses these risks through:

- authenticated backend access;
- server-side model and reasoning configuration;
- request-size, prompt, and token limits;
- strict typed output with exact-field validation;
- stable IDs and no arbitrary tool execution;
- one semantic planner rather than an uncontrolled agent loop;
- bounded command, note, point, context, and retrieval sizes;
- immutable planning snapshots for adaptive work;
- state-digest validation before execution;
- full preparation before mutation;
- target containment for mix actions;
- protected reference targets;
- deterministic execution policy;
- transaction rollback and targeted readback;
- receipt-derived success messages;
- explicit unsupported and failure results;
- no silent V3-to-V1 semantic fallback;
- local deterministic fallback when learned mix refinement fails;
- shadow deployment and measured activation gates.

### 20.3 Residual risks

These controls do not eliminate musical-quality risk. A typed and correctly executed EQ move can still sound undesirable. Human confirmation policy, Undo, listening evaluation, and gradual rollout remain essential.

Prompt injection through project-provided text has limited authority because output remains constrained to the typed command schema and factual preparation. It can still influence the planner's target or creative decision, so filenames and labels should be clearly delimited as untrusted data in prompts and included in adversarial evaluation.

# Part II. DAW and JUCE audio engine

## 21. DAW architecture

Mixroom separates interaction and persistent editing state from real-time audio processing.

Flutter holds the editor model and user workflow. The native plugin holds the audio graph and device state. Flutter synchronizes changes across the method-channel boundary. This allows a cross-platform product interface while keeping low-latency DSP in C++.

The project model can contain metadata, tempo and key, rows, audio and MIDI clips, automation, effects, source and generated files, waveform and analysis data, Undo and recovery metadata, AI conversation context, and optional cloud-sync state.

### 21.1 Project persistence and recovery

Each local audio project uses a project directory with `project.json` as its structured state authority and project-owned media and generated files alongside it. Saves encode state away from the UI thread where appropriate, write a temporary file with flushing, and rename it over the primary file. Autosave and checkpoint modes retain timestamped fallback versions. On open, the persistence layer can recover from a fallback when the primary project document cannot be read.

The shareable `.mixroom` document is an archive containing project metadata and required project files. Import stages and validates the archive, rejects path traversal outside the destination directory, resolves project-name collisions, strips source cloud-sync identity, and copies media into a new local project. Compatibility inspection identifies projects that depend on plugins or features unavailable on the current device.

Undo history, explicit project versions, autosave, and file-level recovery serve different purposes. Undo reverses editing operations within a session. Version and checkpoint files recover durable state. Neither should be described as a substitute for cloud backup.

## 22. Native graph and routing

The engine uses JUCE `AudioProcessorGraph` nodes and explicit connections. Conceptually, each row has an input stage, its clip sources, row processing, automation, pan and gain, effect chain, and meter. Rows can feed groups. Groups and ungrouped rows feed the master chain. The master chain feeds the selected audio device and offline renderer.

The engine supports graph-mutation batching. Project load can bracket clip and graph operations to avoid repeated partial rewiring. Row creation, deletion, order changes, group configuration, effect insertion, removal, and reordering trigger controlled graph updates.

Clip schedules are published as snapshots. The audio thread reads stable schedule pointers while control-thread mutations build and publish replacements. Retired schedules and processors remain alive long enough to avoid use-after-free while an audio block may still reference them.

> **Diagram placeholder 4: JUCE audio graph**
>
> Draw three rows, one group bus, and the master bus. For each row show Audio/MIDI Clip Sources, Track Input, Clip Gain/Pan/Fades, Instrument for MIDI, Row Gain Automation, Row Pan, Insert FX Chain, Meter Tap, and Row Output. Route two rows into the group chain and one directly to master. Show Master FX, Master Gain/Pan/Automation, Output Safety Guard, Master Meter, Device Output, and Offline Export sink. Mark which parameters use atomics and which graph changes occur on the control thread.

## 23. Real-time processing model

The audio callback must finish within the hardware buffer deadline. It cannot wait for network calls, UI rendering, model downloads, project serialization, or long file operations.

The engine uses:

- atomics for transport, play state, automation overrides, metering, and other frequently read scalar state;
- preallocated scratch buffers for routed clips;
- immutable or snapshot-style data for automation points and clip schedules;
- separate background or control-thread work for decoding, scanning, rendering setup, analysis, and graph mutation;
- deferred retirement of objects that may still be observed by the audio thread.

The code defines a real-time scratch capacity of 32,768 samples. Routed clip schedules use four-second buckets with an additional MIDI tail window. These are implementation details intended to bound per-block search and allocation behavior.

## 24. Audio clips

Audio clips carry timeline start, visible length, source offset, source path or decoded asset, gain, pan, mute, fades, pitch, reverse, stretch behavior, and row routing.

The engine includes static and timeline-aware clip processors. A processor determines whether the current audio block intersects the clip, reads the required source frames, performs interpolation or resampling where required, applies clip gain and stereo balance, applies fade curves, and mixes the result into the row buffer.

Fade-in and fade-out support linear and shaped curves. Clip pan uses a stereo balance law with unity at center, avoiding repeated center attenuation when multiple pan stages are chained.

Timeline editing changes Flutter state first through the editor operation, then synchronizes the corresponding native clip state. Batch update calls reduce bridge overhead for multi-clip changes.

## 25. MIDI and instruments

MIDI clips contain stable note IDs, pitch, velocity, start, and duration. Timeline MIDI processors schedule note-on and note-off events against the same transport clock used for audio clips.

The engine supports live MIDI clip playback, event updates, live MIDI input targeting, preview notes, plugin parameter control, plugin automation, and plugin state serialization.

Bundled instruments use SFZ definitions and sample assets. The repository includes the VSCO 2 Community Edition-based catalog and Mixroom-specific drum mappings. On Android, large instrument assets can be delivered through an asset pack. The engine exposes the bundled instrument root and mounts sample packs before use.

Desktop plugin hosting uses platform-appropriate formats. The Windows build enables VST3 hosting. iOS build settings enable AU hosting. Exact plugin availability and editor support remain platform-dependent.

## 26. Effects processing

Mixroom includes native JUCE processors for:

- Gain;
- three-band and parametric EQ;
- Compressor;
- Dynamic Softener;
- Transient Shaper;
- Limiter;
- Clipper;
- De-Esser;
- Distortion and Degrade;
- Delay and Reverb;
- Pitch Shift and Pitch Corrector;
- Chorus and Vibrato;
- Stereo and Stereo Pro;
- Volume Shaper and Time Shaper.

Each processor follows the JUCE lifecycle: construction and parameter registration, `prepareToPlay`, real-time `processBlock`, reset or resource release, parameter/state serialization, and bus-layout validation.

Effects can exist on rows and master. The bridge supports insertion, removal, order changes, bypass, parameter discovery, normalized parameter setting, state get/set, automation, and native plugin editors where the platform supports them.

The AI does not receive unrestricted arbitrary plugin control. V3 currently exposes a bounded built-in effect command surface with factual preparation. Hosted plugin discovery and arbitrary parameter semantics remain broader than the typed AI surface.

## 27. Automation

Automation can target row gain, row pan, effect parameters, master gain, master pan, and master effect parameters. The broader editor also supports automation clips and templates.

The native volume automation processor stores sorted point snapshots. The audio thread reads a stable snapshot and interpolates values using current block transport time. Publishing a new point set swaps the pointer atomically and retires the prior snapshot only after an audio-render generation grace period.

This design keeps mutable collection operations off the audio callback while preserving sample-level or block-aware playback behavior.

## 28. Metering and analysis

Row and master meter taps calculate peak and RMS values for left and right channels. Values pass to Flutter through atomics and polling. Master clipping has a latched indicator that remains set until explicitly cleared.

Specialized processors expose compressor reduction, EQ waveform, stereo scope, shaper curve, softener frames, and transient-shaper visual data. These are visualization and monitoring outputs, not authority for project persistence.

The native analysis path decodes bounded mono 16 kHz windows and calculates the AI features described earlier. Stereo analysis separately derives phase correlation, side ratio, and imbalance.

## 29. Recording and audio routes

Recording is implemented as a native real-time WAV capture path. Flutter requests input preparation, device configuration, monitoring state, and a row monitor target before starting capture.

The native engine:

- selects or reopens a device with the required input channels;
- supports mono fallback where necessary;
- routes live input to a row for monitoring;
- captures input in the audio callback without blocking file workflows;
- exposes recording peak and estimated latency;
- finalizes or discards the capture;
- restores the intended playback route after recording.

Mobile audio routing has additional coordinators for playback, recording, Bluetooth duplex, and Android legacy SCO behavior. Route transitions expose explicit snapshots and results so the app can explain and recover from platform-specific route limitations.

An output safety guard applies a fade-in after route or device changes and protects against invalid or excessive output. This reduces bursts and discontinuities during device reconfiguration.

## 30. Transport and metronome

The engine maintains transport time in seconds and exposes seek, play, pause, restart, and position queries. Audio clips, MIDI clips, automation, video audio, and the metronome use the shared transport basis.

The metronome has enabled state, volume, BPM, time signature, and transport position. Flutter remains responsible for editing tempo and meter state and then synchronizing the native engine.

## 31. Export and offline rendering

The public engine interface exposes mix, track, and group export plus progress polling. Flutter gathers format and destination choices, then the native engine performs offline rendering through the graph.

Offline rendering should reproduce the relevant clip, instrument, automation, row/group, effect, and master state without depending on the hardware callback. Output naming, destination selection, sharing, and post-export user workflow remain Flutter responsibilities.

Export is validated through integration support and a repository audio-export analyzer. Final format support and platform save behavior should be stated from the release being evaluated, because platform and licensing differences can change the available container and codec set.

## 32. Flutter/native bridge contract

The Dart API exposes initialization, shutdown, transport, clip, row, group, effect, automation, MIDI, recording, device, routing, metering, analysis, plugin scan, and export calls.

Payloads use maps with explicit keys for non-trivial operations. The channel boundary is treated as an API:

- channel names remain stable;
- Dart and native implementations change together;
- missing keys and unknown enum values return recoverable errors where possible;
- tokens, credentials, and private content must not enter native logs;
- platform behavior requires direct tests on each supported target.

The engine supports iOS, Android, macOS, and Windows integration. Platform capability is not identical. Plugin formats, file access, Bluetooth routes, sandbox rules, and audio-device behavior differ.

# Part III. Backend and cloud architecture

## 33. Serverless deployment model

Both backend systems use AWS SAM. API Gateway receives HTTPS requests and invokes Python 3.12 Lambda functions. DynamoDB stores operational state. SQS decouples billing projection. S3 or Cloudflare R2 stores larger project or training objects. Secrets Manager and SSM Parameter Store supply credentials. CloudWatch collects logs, metrics, and alarms.

Serverless components provide managed regional redundancy and scale without long-lived application servers. They do not remove the need for recovery drills, concurrency controls, regional strategy, or dependency monitoring.

## 34. Authentication and account security

Mixroom app auth supports email/password and native social-provider flows. Native platform SDKs obtain provider identity material. The app API validates that material and returns Mixroom access and refresh tokens.

The backend stores account and session records in DynamoDB. Access tokens have a default one-hour lifetime and refresh tokens a default 30-day lifetime in the reviewed infrastructure parameters. Refresh rotation and sign-out invalidation are covered by backend and live-smoke tooling.

Passwords are salted and hashed server-side. Public auth actions use a dedicated rate-limit store. The client normally stores tokens in OS-backed secure storage. The current client has a less-secure SharedPreferences fallback if secure storage fails; production mobile hardening should fail closed for session secrets instead.

Employee and admin authentication is separate from app-user authentication and uses Cognito plus an application allowlist and role checks.

## 35. Authorization, entitlements, and billing

Entitlements are projected from canonical billing events rather than inferred only from the client. Supported provider paths include Apple, Google, Paddle, and Toss. Webhook verification, purchase-token records, customer links, subscriptions, and current entitlement state have separate tables.

Billing projection uses an SQS queue and dead-letter queue. Event handling is designed to be idempotent, and stale event revisions should not overwrite newer entitlement snapshots.

The client cannot establish a paid entitlement merely by changing local state. Store receipts or signed provider events require backend verification.

## 36. Cloud projects and collaboration

Organization, workspace, project membership, invitation, and metadata state live in a collaboration table. Larger project documents use object storage and signed upload/download URLs. The implementation supports S3 and Cloudflare R2 behind a provider abstraction.

Cloud project updates use optimistic locking with an expected revision. This prevents a stale client from silently overwriting a newer document. Local project files and cloud collaboration metadata remain separate responsibilities.

## 37. AI usage and runtime administration

The AI proxy has separate DynamoDB tables for user usage state, detailed usage events, prompt-limit settings, and OpenAI conversation mappings. The application backend exposes authorized administrative controls for AI runtime and prompt limits.

Usage reservation and settlement reduce race conditions around concurrent requests. The proxy records prompt, completion, total, and cached token counts when the provider supplies them, together with model, feature, and timing metadata.

Provider 429 responses are exposed to clients as service-unavailable errors rather than user-quota errors so the application does not tell a user that their personal limit was exhausted when the upstream provider was throttled.

## 38. Secrets and configuration

Provider API keys, app signing secrets, social credentials, webhook secrets, email credentials, and billing credentials are backend-only. Runtime code supports SSM Parameter Store and Secrets Manager references with short in-memory cache lifetimes.

Infrastructure parameters marked `NoEcho` reduce accidental console display but do not substitute for storing production secrets only in a dedicated secret store. Raw secrets should not be passed as ordinary deployment parameters when a secret ARN or secure parameter is available.

## 39. Data durability and protection

The current templates declare retained stateful tables with deletion protection and point-in-time recovery. Several tables use on-demand billing. Object buckets and queue resources have lifecycle and retention behavior defined in infrastructure.

This proves the desired infrastructure configuration, not the live deployment state. A previous repository security report dated March 2026 recorded that sampled production tables lacked point-in-time recovery and deletion protection at that time. The templates now contain those controls. A current government submission should attach fresh AWS configuration evidence and a restore-drill record rather than relying on either historical state or template intent.

## 40. Network and abuse controls

The templates define API Gateway throttles, maximum request sizes, optional WAF association, application-level authentication, auth rate limiting, and alarms for API 5xx errors, Lambda errors, and throttles.

WAF has a separate production template and deployment scripts. Because WAF attachment is parameterized, repository presence does not prove that a WebACL is attached to the live APIs. Deployment evidence should include the active WebACL ARN, managed-rule groups, rate-based rules, logging destination, and tested exception policy.

## 41. Observability and incident response

The backend uses structured logging helpers, CloudWatch alarms, Sentry, and PostHog. The client has analytics and crash-reporting services with privacy preferences. The native engine sends explicit log and event data through its bridge.

Useful AI observability includes:

- prompt trace ID;
- route and planner architecture;
- model and reasoning effort;
- request and response token counts;
- cache use;
- planner, retrieval, preparation, refinement, and total latency;
- plan outcome and command types;
- preparation and execution error codes;
- refinement model source and version;
- fallback reason;
- rollback and verification result.

Logs should avoid request bodies, raw audio, credentials, and full personal content by default. Rich diagnostic captures require explicit handling because they may reveal filenames, project structure, or user prompts even when audio is absent.

> **Diagram placeholder 5: Backend data and control plane**
>
> Show App API and AI Proxy as separate API Gateway and Lambda groups. Connect App API to auth, user, billing, entitlement, collaboration, feature flag, feedback, project telemetry, and training tables. Connect billing ingestion to SQS and its dead-letter queue. Connect AI Proxy to usage, prompt-limit, conversation-state tables, the external model provider, and the mix-model CDN or manifest. Show secret stores, CloudWatch, Sentry, PostHog, WAF, S3/R2 project documents, and producer-training storage. Label retention, encryption, and IAM scope for every store.

# Part IV. End-to-end technical workflows

## 42. Example: “Make the vocals clearer”

1. Flutter captures rows, clips, selection, mixer state, effect instances, audio summaries, overlap, and role probabilities.
2. The authenticated V3 planner receives the original request and typed command schema.
3. The planner returns `mix.apply_goal` with a vocal-row stable target and clarity-related mix intents.
4. The parser validates the plan shape and command bounds.
5. Preparation proves that the row exists, contains usable material, and is inside the allowed target set.
6. `LocalMixingModel` evaluates vocal role, current spectral balance, sibilance, masking overlap, effects, and requested intensity.
7. It proposes actions such as gain adjustment, parametric EQ, compression, or de-essing within supported policy.
8. The apply classifier scores each candidate and the magnitude regressor scales retained changes unless the learned layer is bypassed or unavailable.
9. The materializer confirms that every concrete action still targets the vocal row and does not mutate a protected reference.
10. The editor applies the bundle, JUCE updates row effects and parameters, and the transaction reads back the affected state.
11. If readback differs, the transaction rolls back. If it matches, one Undo entry and factual receipts are created.
12. Chat reports what changed from the receipts.

## 43. Example: “Split the vocals and lower them by 2 dB”

This combines asynchronous file generation with a local mixer change. It cannot honestly be one atomic real-time transaction.

The source clip must first resolve exactly. The local Spleeter job generates vocal and accompaniment files. When the job completes, the app revalidates the project, prepares new rows and clips, and applies them as a local insertion transaction. A subsequent verified row-gain operation can lower the generated vocal row. If separation fails, no claim of completed row gain should be made against a nonexistent target.

The accepted V3 architecture treats this as a staged job with separate receipts for job start, result creation, and result application.

## 44. Example: exact clip edit

For “move clip 42 two beats later,” the language model selects `clip.move_by_beats` and the stable clip ID. Preparation verifies that the clip exists and calculates its expected new position. No mixing model is involved. The transaction performs the move and reads the clip's new beat position. This path demonstrates why not every AI operation should pass through a learned audio model.

## 45. Example: reference mix

For “make my mix closer to the reference track,” the planner must identify separate processing and reference targets. Preparation rejects identical targets or an unusable reference. The local mixing model computes changes for tone, loudness, width, glue, or the requested mode. The materializer rejects any concrete action aimed at the protected reference. Only processing-target readback can satisfy the operation.

# Part V. Engineering quality, limitations, and roadmap

## 46. Testing strategy

The repository contains:

- Dart and Flutter unit tests;
- JUCE plugin API and audio-route tests;
- Python backend unit and handler tests;
- AI contract and routing tests;
- V3 context, snapshot, retrieval, preparation, transaction, mix-materialization, and evaluation-fixture tests;
- integration tests for atomic transactions, automation, project flows, audio export, MIDI preview, and engine stress;
- live backend smoke scripts;
- documentation freshness checks;
- build and deployment scripts.

The recommended baseline is static analysis, Flutter tests, targeted backend tests, integration suites, direct platform tests, and audio-level verification appropriate to the change.

For AI mutation changes, tests must cover parse rejection, stale digest, exact targets, full preparation, no pre-commit mutation, execution, readback, Undo, rollback, duplicate Apply, timeout, and failure messaging.

## 47. Known limitations

The following limitations should remain visible to evaluators:

1. The language model can still misunderstand musical intent even when its output is structurally valid.
2. Learned mixing is a refinement layer over deterministic candidates, not an end-to-end neural system that directly renders a final mix.
3. The official ONNX model artifacts lack a complete public model card and reproducible training script in the reviewed repository.
4. Audible quality for reference mixing, creative generation, separation, transcription, and broad polish requires listening tests.
5. Adaptive retrieval is shadow-only and has not passed activation gates.
6. Legacy V1 actions do not all share V3's universal typed, atomic, and readback semantics.
7. Asynchronous file-producing operations require staged transactions and may leave cleanup work if a later stage fails.
8. Hosted plugin discovery is broader than the current safe AI effect surface.
9. Platform capabilities differ across iOS, Android, macOS, and Windows.
10. Repository infrastructure expresses intended security settings but does not prove live cloud configuration.
11. Local audio measurements are useful engineering estimates, not accredited broadcast or mastering measurements.
12. Current context and command limits can cause an explicit unsupported or clarification outcome on unusually large projects.

## 48. Technical maturity assessment

Mixroom demonstrates meaningful AI engineering in four ways.

First, it separates probabilistic interpretation from deterministic execution. The language model has bounded planning authority rather than direct editor access.

Second, it combines symbolic project context with locally derived audio facts. The system reasons about actual track state, spectral and dynamic summaries, roles, and temporal overlap instead of using prompt text alone.

Third, it uses specialized local models for different tasks: classification, mix-action selection, mix magnitude, stem separation, and transcription. It does not present one general model as a universal solution.

Fourth, it records limitations and negative evaluation results in its architecture documents. The adaptive planner remains shadow-only despite token savings because reliability and latency evidence are not yet sufficient.

The largest remaining maturity gap is model governance evidence. The implementation has versioning, fallback, observability, consented capture, deterministic dataset conversion, and evaluation design. A formal external review still needs signed artifact provenance, model cards, quantitative evaluation reports, live security evidence, data-retention policy, and documented approval and rollback ownership.

## 49. Recommended next technical milestones

1. Produce model cards for YAMNet usage, Basic Pitch, Spleeter, the apply classifier, and the magnitude regressor.
2. Add a reproducible training and ONNX-export pipeline for official mix-refinement artifacts.
3. Freeze an unseen evaluation corpus with genre, language, device, project-size, and task coverage.
4. Run and publish the 75-case V3 holdout with confidence intervals and failure taxonomy.
5. Conduct blinded listening tests for mix quality and reference matching.
6. Complete staged-job semantics and cleanup for stem separation, transcription, and rendered enhancement.
7. Prove live WAF, PITR, deletion protection, secret configuration, alert delivery, and restore procedures.
8. Remove insecure mobile token-storage fallback in release builds.
9. Add adversarial prompt and untrusted-project-label testing.
10. Formalize model approval, canary activation, rollback, retention, and incident-response procedures.

## 50. Evidence map

The principal repository evidence for this document is:

| Subject | Primary implementation evidence |
| --- | --- |
| AI V3 architecture | `docs/engineering/adr/0002-ai-v3-architecture.md` |
| Adaptive planner | `docs/engineering/ai_v3_adaptive_planner.md` |
| Capability inventory | `docs/engineering/ai_v3_capability_matrix.md`, `tool/ai_v3_eval/v3_capabilities.yaml` |
| V3 plan schema | `lib/ai/v3/ai_v3_contract.dart` |
| Context and snapshots | `lib/ai/v3/ai_v3_context.dart`, `ai_v3_planning_snapshot.dart`, `ai_v3_compact_core.dart` |
| Retrieval | `lib/ai/v3/ai_v3_retrieval.dart`, `ai_v3_domain_registry.dart` |
| Planner client | `lib/ai/v3/ai_v3_planner_service.dart`, `ai_v3_planner_request.dart` |
| Preparation and transactions | `lib/ai/v3/ai_v3_preparer.dart`, `ai_v3_transaction.dart`, `lib/ai/chat_pipeline.dart` |
| Deterministic mixing | `lib/ai/local_mixing_model.dart` |
| Learned mix refinement | `lib/ai/onnx_magnitude_predictor.dart`, `backend/llm_proxy/src/common/mix_resolve.py` |
| Mix materialization | `lib/ai/v3/ai_v3_mix_materializer.dart` |
| Audio/project facts | `lib/ai/project_state_builder.dart`, `lib/models/project_state.dart` |
| YAMNet roles | `lib/ai/instrument_classifier.dart`, `assets/models/yamnet.onnx` |
| Stem separation | `lib/ai/spleeter_stem_separator.dart` and the Spleeter ONNX assets |
| Audio-to-MIDI | `lib/ai/basic_pitch_transcriber.dart`, `assets/models/basic_pitch_nmp.onnx` |
| Training capture | `lib/ai/producer_data_collector.dart`, `lib/helpers/producer_training_upload_service.dart` |
| Dataset conversion | `backend/training/producer_capture_converter.py` |
| AI proxy | `backend/llm_proxy/template.yaml`, `src/handlers/api_responses.py`, `src/handlers/api_mix_resolve.py` |
| DAW architecture | `juce_audio_engine/`, `docs/engineering/audio_engine_architecture.md` |
| Native effects | `juce_audio_engine/android/src/main/cpp/NativeEffects.*`, `juce_audio_engine/ios/Classes/NativeEffects.*` |
| Flutter/native API | `juce_audio_engine/lib/juce_audio_engine.dart` |
| App backend | `backend/app_api/template.yaml`, `backend/app_api/src/` |
| Auth | `lib/helpers/auth_service.dart`, `backend/app_api/src/handlers/api_auth.py` |
| Project persistence | `lib/helpers/project_manager.dart`, `lib/helpers/audio_project_persistence.dart` |
| Security posture history | `security_best_practices_report.md`, current SAM templates, `ops/prod_waf/` |

## 51. Diagram production checklist

The following final diagrams would make this document suitable for a formal application package:

1. Whole-system deployment and trust boundaries.
2. AI planning, preparation, execution, rollback, and receipt sequence.
3. Hybrid deterministic and learned mixing pipeline with the 77-feature contract.
4. JUCE row, group, and master audio graph.
5. Backend services and data stores.
6. Data-classification diagram showing raw audio, derived features, prompts, identity data, billing data, telemetry, model artifacts, and training captures.
7. Model lifecycle from consented capture through conversion, training, evaluation, ONNX export, manifest publication, canary activation, monitoring, and rollback.
8. Asynchronous job state machine for separation, transcription, and rendering.

Each diagram should include a version, owner, review date, source commit, trust boundaries, and legend distinguishing implemented production behavior from shadow, designed, and future behavior.

## 52. Final assurance statement

Mixroom's core technical claim is supportable: it is an AI-assisted DAW built around a controlled hybrid architecture. A cloud language model interprets requests and creates typed plans. Local deterministic and learned systems analyze the project and refine mixing decisions. Flutter owns factual validation and transactional editing. JUCE owns real-time DSP and rendering. The backend owns authentication, provider credentials, limits, and operational policy.

The architecture does not eliminate uncertainty from AI. It contains that uncertainty within a bounded planning layer, verifies what can be verified deterministically, preserves a non-learned fallback, and identifies audible quality as an evaluation problem rather than a schema problem.

That distinction is the strongest evidence that Mixroom's AI stack is understood as an engineering system rather than treated as an opaque model integration.
