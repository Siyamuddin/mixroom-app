#pragma once

#include "JuceHeader.h"

#include <array>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstddef>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <regex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

struct TimelineMidiNote
{
    juce::String noteId;
    int pitch = 60;
    double startBeat = 0.0;
    double lengthBeats = 1.0;
    double velocity = 0.8;
};

class TimelineClipProcessorBase
{
public:
    virtual ~TimelineClipProcessorBase() = default;
    virtual void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) = 0;
    virtual void setMuted(bool m) = 0;
    virtual void setPitchSemitones(float semitones) = 0;
    virtual void setStretchOptions(double tempoRatio, bool preservePitch) = 0;
};

class TimelineMidiClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
    static void setFlutterAssetRootPath(const juce::String &rootPath)
    {
        const juce::ScopedLock lock(flutterAssetRootLock());
        flutterAssetRoot() = rootPath.trim();
    }

    TimelineMidiClipProcessor(std::atomic<double> *blockTransportStartSecPtr,
                              std::atomic<double> *hostSampleRatePtr,
                              std::atomic<bool> *isPlayingPtr)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          blockTransportStartSec(blockTransportStartSecPtr),
          hostSampleRate(hostSampleRatePtr),
          isPlaying(isPlayingPtr)
    {
    }

    void setTimeline(double startSec, double lengthSec, double inFileOffsetSec = 0.0) override
    {
        clipStartSec.store(startSec, std::memory_order_relaxed);
        clipLengthSec.store(lengthSec, std::memory_order_relaxed);
        fileOffsetSec.store(inFileOffsetSec, std::memory_order_relaxed);
    }

    void setMuted(bool m) override { muted.store(m, std::memory_order_relaxed); }

    void setPitchSemitones(float semitones) override
    {
        pitchSemitones.store(juce::jlimit(-24.0f, 24.0f, semitones),
                             std::memory_order_relaxed);
    }

    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        tempoPlaybackRatio.store(juce::jlimit(0.05, 20.0, tempoRatio),
                                 std::memory_order_relaxed);
        preserveTempoPitch.store(preservePitch, std::memory_order_relaxed);
    }

    void setPan(float pan)
    {
        panValue.store(juce::jlimit(-1.0f, 1.0f, pan), std::memory_order_relaxed);
    }

    void setPlayheadSeconds(double seconds)
    {
        playheadSec.store(juce::jmax(0.0, seconds), std::memory_order_relaxed);
    }

    double getTimelineLengthSeconds() const
    {
        return clipLengthSec.load(std::memory_order_relaxed);
    }

    void setMidiData(const juce::Array<TimelineMidiNote> &notes,
                     const juce::String &instrumentId,
                     const juce::String &instrumentName,
                     const juce::NamedValueSet &params,
                     double sourceTempoBpm)
    {
        PendingState next;
        next.notes = notes;
        next.instrumentId = instrumentId;
        next.instrumentName = instrumentName;
        next.sourceTempoBpm = juce::jlimit(1.0, 400.0, sourceTempoBpm);
        next.sampledDefinition =
            resolveSampledDefinition(instrumentId, instrumentName);
        if (next.sampledDefinition != nullptr)
            preloadSampledRegionsForNotes(
                *next.sampledDefinition,
                next.notes,
                instrumentId);
        next.sampledAttackOverride =
            params.contains(juce::Identifier("attackMs"));
        next.sampledReleaseOverride =
            params.contains(juce::Identifier("releaseMs"));

        next.preset = resolvePreset(instrumentId, instrumentName);
        if (next.sampledDefinition != nullptr &&
            !next.sampledDefinition->regions.empty())
        {
            next.preset.family = InstrumentFamily::sampled;
            next.preset.attackMs = next.sampledDefinition->defaultAttackSec * 1000.0;
            next.preset.releaseMs = next.sampledDefinition->defaultReleaseSec * 1000.0;
            next.preset.outputGain = 0.72;
            next.preset.drive = 0.0;
            next.preset.noise = 0.0;
        }
        applyParamOverrides(next.preset, params);

        {
            const juce::ScopedLock lock(stateLock);
            pendingState = next;
            pendingVersion++;
        }
    }

    void enqueueLiveMidiEvent(bool noteOn, int channel, int pitch, float velocity)
    {
        const juce::ScopedLock lock(liveStateLock);
        pendingLiveMidiEvents.push_back(
            {
                noteOn,
                juce::jlimit(1, 16, channel),
                juce::jlimit(0, 127, pitch),
                juce::jlimit(0.0f, 1.0f, velocity),
            });
        if (pendingLiveMidiEvents.size() > 512)
        {
            pendingLiveMidiEvents.erase(
                pendingLiveMidiEvents.begin(),
                pendingLiveMidiEvents.begin() +
                    (std::ptrdiff_t)(pendingLiveMidiEvents.size() - 512));
        }
    }

    bool preloadLiveMidiPitch(int pitch, float velocity)
    {
        PendingState state;
        {
            const juce::ScopedLock lock(stateLock);
            state = pendingState;
        }
        if (state.sampledDefinition == nullptr ||
            state.sampledDefinition->regions.empty())
            return true;

        const int sampledPitch =
            sampledMidiPitchForInstrument(state.instrumentId, pitch);
        const int midiVelocity = juce::jlimit(
            0,
            127,
            (int)std::lround(juce::jlimit(0.0f, 1.0f, velocity) * 127.0f));
        const SampledRegion *region = pickSampledRegion(
            *state.sampledDefinition,
            sampledPitch,
            midiVelocity,
            sampledPitch);
        return region != nullptr && ensureSampledRegionLoaded(*region);
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (hostSampleRate)
            hostSampleRate->store(deviceSampleRate, std::memory_order_relaxed);
        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (muted.load(std::memory_order_relaxed))
            return;
        if (!hostSampleRate)
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const bool hostPlaying =
            (isPlaying == nullptr) || isPlaying->load(std::memory_order_relaxed);

        const int numSamples = buffer.getNumSamples();
        if (numSamples <= 0)
            return;

        const int outChannels = buffer.getNumChannels();
        if (outChannels <= 0)
            return;

        const double blockStart =
            blockTransportStartSec != nullptr
                ? blockTransportStartSec->load(std::memory_order_relaxed)
                : playheadSec.load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;
        const double expectedBlockStart =
            steadyBlockStartSec.load(std::memory_order_relaxed);
        const bool previousHostPlaying =
            steadyWasPlaying.exchange(hostPlaying, std::memory_order_relaxed);
        const bool hadExpected = std::isfinite(expectedBlockStart);
        const double continuityToleranceSec = juce::jmax(4.0 / sr, 0.002);
        const bool discontinuity =
            !hostPlaying ||
            !hadExpected ||
            !previousHostPlaying ||
            std::abs(blockStart - expectedBlockStart) > continuityToleranceSec;
        steadyBlockStartSec.store(hostPlaying ? blockEnd : blockStart,
                                  std::memory_order_relaxed);
        if (discontinuity)
            activeTimelineNotes.clear();

        refreshCachedState();
        applyPendingLiveMidiEvents();

        const bool sampledMode =
            cachedPreset.family == InstrumentFamily::sampled &&
            cachedSampledDefinition != nullptr &&
            !cachedSampledDefinition->regions.empty();
        const double attackSec = juce::jmax(0.001, cachedPreset.attackMs / 1000.0);
        const double decaySec = juce::jmax(0.001, cachedPreset.decayMs / 1000.0);
        const double sustainLevel = juce::jlimit(0.05, 1.0, cachedPreset.sustainLevel);
        const double releaseSec = juce::jmax(0.02, cachedPreset.releaseMs / 1000.0);
        const float driveGain =
            sampledMode
                ? 1.0f
                : (float)(1.0 + cachedPreset.drive *
                                      (cachedPreset.family == InstrumentFamily::bass ? 3.0 : 5.0));
        const bool stereo = outChannels >= 2;
        auto *outL = buffer.getWritePointer(0);
        auto *outR = stereo ? buffer.getWritePointer(1) : nullptr;
        const float pan = juce::jlimit(-1.0f, 1.0f, panValue.load(std::memory_order_relaxed));
        const float panLeft = (pan <= 0.0f) ? 1.0f : (1.0f - pan);
        const float panRight = (pan >= 0.0f) ? 1.0f : (1.0f + pan);

        const bool hasTimelineNotes = hostPlaying && !cachedNotes.empty();
        const bool hasLiveNotes = !activeLiveNotes.empty();
        if (!hasTimelineNotes && !hasLiveNotes)
        {
            if (hostPlaying)
            {
                playheadSec.store(blockEnd, std::memory_order_relaxed);
            }
            return;
        }

        const double speedRatio = getTempoPlaybackRatio();
        const double safeRatio = speedRatio <= 0.0 ? 1.0 : speedRatio;
        const double sourceSecPerBeat = 60.0 / juce::jlimit(1.0, 400.0, cachedSourceTempoBpm);
        if (hasTimelineNotes)
        {
            const double cs = clipStartSec.load(std::memory_order_relaxed);
            const double cl = clipLengthSec.load(std::memory_order_relaxed);
            const double ce = cs + cl;

            if (blockEnd > cs && blockStart < ce)
            {
                const int writeStart = juce::jlimit(
                    0, numSamples, (int)std::ceil((cs - blockStart) * sr));
                const int writeEnd = juce::jlimit(
                    0, numSamples, (int)std::ceil((ce - blockStart) * sr));
                const int framesToRender = juce::jmax(0, writeEnd - writeStart);
                if (framesToRender > 0)
                {
                    const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
                    const double startTimelineSec = blockStart + ((double)writeStart / sr);
                    const double endTimelineSec =
                        startTimelineSec + ((double)framesToRender / sr);
                    const double blockSourceStartSec =
                        ((startTimelineSec - cs) * safeRatio) + inFile;
                    const double blockSourceEndSec =
                        ((endTimelineSec - cs) * safeRatio) + inFile;
                    std::vector<size_t> blockNoteIndices;
                    std::vector<double> blockNoteEndSourceSecs;
                    blockNoteIndices.reserve(cachedNotes.size());
                    blockNoteEndSourceSecs.reserve(cachedNotes.size());
                    std::vector<const SampledRegion *> timelineRegions;
                    std::vector<int> timelinePitches;
                    if (sampledMode)
                    {
                        timelineRegions.reserve(cachedNotes.size());
                        timelinePitches.reserve(cachedNotes.size());
                        for (const auto &note : cachedNotes)
                        {
                            const int sampledPitch =
                                sampledMidiPitchForInstrument(cachedInstrumentId, note.pitch);
                            const int midiVelocity = juce::jlimit(
                                0,
                                127,
                                (int)std::lround(
                                    juce::jlimit(0.0, 1.0, note.velocity) * 127.0));
                            timelinePitches.push_back(sampledPitch);
                            const SampledRegion *region = pickSampledRegion(
                                *cachedSampledDefinition,
                                sampledPitch,
                                midiVelocity,
                                (int)timelinePitches.size() - 1);
                            if (region != nullptr &&
                                !isSampledRegionReady(*region))
                            {
                                region = nullptr;
                            }
                            timelineRegions.push_back(region);
                        }
                    }

                    for (size_t noteIndex = 0; noteIndex < cachedNotes.size(); ++noteIndex)
                    {
                        const auto &note = cachedNotes[noteIndex];
                        const SampledRegion *sampledRegion =
                            sampledMode ? timelineRegions[noteIndex] : nullptr;
                        if (sampledMode && sampledRegion == nullptr)
                            continue;

                        double noteReleaseSec = releaseSec;
                        if (sampledRegion != nullptr &&
                            !cachedSampledReleaseOverride)
                        {
                            noteReleaseSec =
                                juce::jmax(0.02, sampledRegion->releaseSec);
                        }

                        const double noteStartSourceSec = note.startBeat * sourceSecPerBeat;
                        const double noteLengthSourceSec = juce::jmax(0.001, note.lengthBeats * sourceSecPerBeat);
                        const double noteEndSourceSec = noteStartSourceSec + noteLengthSourceSec + (noteReleaseSec * safeRatio);
                        if (noteEndSourceSec <= blockSourceStartSec)
                        {
                            activeTimelineNotes.erase(noteIndex);
                            continue;
                        }

                        if (noteStartSourceSec >= blockSourceEndSec)
                            continue;

                        const bool noteStartsInBlock =
                            noteStartSourceSec >= blockSourceStartSec &&
                            noteStartSourceSec < blockSourceEndSec;
                        const bool noteAlreadyActive =
                            activeTimelineNotes.find(noteIndex) != activeTimelineNotes.end();
                        if (!noteStartsInBlock && !noteAlreadyActive)
                            continue;
                        if (noteStartsInBlock)
                            activeTimelineNotes.insert(noteIndex);

                        blockNoteIndices.push_back(noteIndex);
                        blockNoteEndSourceSecs.push_back(noteEndSourceSec);
                    }

                    for (int i = 0; i < framesToRender; ++i)
                    {
                        const double timelineSec = startTimelineSec + ((double)i / sr);
                        const double sourceSec = ((timelineSec - cs) * safeRatio) + inFile;
                        float mixL = 0.0f;
                        float mixR = 0.0f;

                        for (size_t noteIndex : blockNoteIndices)
                        {
                            const auto &note = cachedNotes[noteIndex];
                            const SampledRegion *sampledRegion =
                                sampledMode ? timelineRegions[noteIndex] : nullptr;
                            if (sampledMode && sampledRegion == nullptr)
                                continue;

                            double noteAttackSec = attackSec;
                            double noteReleaseSec = releaseSec;
                            if (sampledRegion != nullptr)
                            {
                                if (!cachedSampledAttackOverride)
                                    noteAttackSec =
                                        juce::jmax(0.001, sampledRegion->attackSec);
                                if (!cachedSampledReleaseOverride)
                                    noteReleaseSec =
                                        juce::jmax(0.02, sampledRegion->releaseSec);
                            }
                            const double releaseSourceSec = noteReleaseSec * safeRatio;

                            const double noteStartSourceSec = note.startBeat * sourceSecPerBeat;
                            const double noteLengthSourceSec = juce::jmax(0.001, note.lengthBeats * sourceSecPerBeat);
                            const double noteEndSourceSec = noteStartSourceSec + noteLengthSourceSec + releaseSourceSec;
                            if (sourceSec < noteStartSourceSec || sourceSec >= noteEndSourceSec)
                                continue;

                            const double ageSourceSec = sourceSec - noteStartSourceSec;
                            const double ageRealSec = ageSourceSec / safeRatio;
                            const double noteLengthRealSec = noteLengthSourceSec / safeRatio;

                            const double env = envelopeLevel(
                                ageRealSec,
                                noteLengthRealSec,
                                noteAttackSec,
                                decaySec,
                                sustainLevel,
                                noteReleaseSec);

                            if (env <= 0.0)
                                continue;

                            const double totalRealSec = juce::jmax(
                                0.001, noteLengthRealSec + noteReleaseSec);
                            const double noteProgress = juce::jlimit(0.0, 1.0, ageRealSec / totalRealSec);

                            const int notePitchBase =
                                sampledMode ? timelinePitches[noteIndex] : note.pitch;
                            double notePitch = (double)notePitchBase + (double)pitchSemitones.load(std::memory_order_relaxed);
                            if (!preserveTempoPitch.load(std::memory_order_relaxed) && safeRatio > 0.0)
                                notePitch += 12.0 * (std::log(safeRatio) / std::log(2.0));

                            const float velocityGain =
                                (float)juce::jlimit(0.0, 1.0, note.velocity);

                            if (sampledRegion != nullptr)
                            {
                                float sampleL = 0.0f;
                                float sampleR = 0.0f;
                                if (!renderSampledStereo(
                                        *sampledRegion,
                                        notePitch,
                                        ageRealSec,
                                        sr,
                                        sampleL,
                                        sampleR))
                                {
                                    continue;
                                }

                                const float gain =
                                    (float)env *
                                    velocityGain *
                                    (float)cachedPreset.outputGain *
                                    (float)sampledRegion->gainLinear;
                                mixL += sampleL * gain;
                                mixR += sampleR * gain;
                                continue;
                            }

                            const double freq = 440.0 * std::pow(2.0, (notePitch - 69.0) / 12.0);
                            const int seedBase = (int)(note.pitch * 97 + (int)(note.startBeat * 2000.0) * 13);
                            const int sampleSeed = seedBase + (int)std::floor(ageRealSec * sr);

                            const float raw = renderInstrumentSample(cachedPreset,
                                                                     note.pitch,
                                                                     freq,
                                                                     ageRealSec,
                                                                     noteProgress,
                                                         env,
                                                         sr,
                                                         sampleSeed);
                            const float sampleValue = std::tanh(raw * driveGain) *
                                                      (float)env *
                                                      velocityGain *
                                                      (float)cachedPreset.outputGain;

                            const double pan = juce::jlimit(-0.95, 0.95,
                                                            std::sin((double)note.pitch * 0.23 + note.startBeat * 0.9) * cachedPreset.stereoWidth);
                            const float leftGain = (float)std::sqrt(0.5 * (1.0 - pan));
                            const float rightGain = (float)std::sqrt(0.5 * (1.0 + pan));

                            mixL += sampleValue * leftGain;
                            mixR += sampleValue * rightGain;
                        }

                        mixL = juce::jlimit(-1.0f, 1.0f, mixL);
                        mixR = juce::jlimit(-1.0f, 1.0f, mixR);
                        mixL *= panLeft;
                        mixR *= panRight;
                        const int outIndex = writeStart + i;

                        if (stereo)
                        {
                            outL[outIndex] += mixL;
                            outR[outIndex] += mixR;
                        }
                        else
                        {
                            outL[outIndex] += 0.5f * (mixL + mixR);
                        }
                    }

                    for (size_t activeIndex = 0;
                         activeIndex < blockNoteIndices.size() &&
                         activeIndex < blockNoteEndSourceSecs.size();
                         ++activeIndex)
                    {
                        if (blockNoteEndSourceSecs[activeIndex] <= blockSourceEndSec)
                            activeTimelineNotes.erase(blockNoteIndices[activeIndex]);
                    }
                }
            }
        }

        if (activeLiveNotes.empty())
            return;

        const double invSr = 1.0 / sr;
        for (int i = 0; i < numSamples; ++i)
        {
            float mixL = 0.0f;
            float mixR = 0.0f;

            for (auto &voice : activeLiveNotes)
            {
                const bool voiceSampled =
                    sampledMode && voice.sampledSource != nullptr;
                const double voiceAttackSec =
                    (voiceSampled && !cachedSampledAttackOverride)
                        ? juce::jmax(0.001, voice.sampledAttackSec)
                        : attackSec;
                const double voiceReleaseSec =
                    (voiceSampled && !cachedSampledReleaseOverride)
                        ? juce::jmax(0.02, voice.sampledReleaseSec)
                        : releaseSec;

                double env = 0.0;
                if (!voice.releasing)
                {
                    env = envelopeHoldLevel(
                        voice.ageSec,
                        voiceAttackSec,
                        decaySec,
                        sustainLevel);
                }
                else
                {
                    const double releaseNorm = voice.releaseAgeSec / voiceReleaseSec;
                    env = voice.releaseStartLevel * (1.0 - releaseNorm);
                }

                if (env <= 0.0)
                {
                    voice.ageSec += invSr;
                    if (voice.releasing)
                        voice.releaseAgeSec += invSr;
                    continue;
                }

                const double noteProgress = voice.releasing
                                                ? juce::jlimit(0.0, 1.0, voice.releaseAgeSec / voiceReleaseSec)
                                                : juce::jlimit(0.0, 0.85, voice.ageSec / juce::jmax(0.08, voiceAttackSec + 0.42));

                double notePitch = (double)voice.pitch + (double)pitchSemitones.load(std::memory_order_relaxed);

                if (voiceSampled)
                {
                    SampledRegion liveRegion;
                    liveRegion.sample = voice.sampledSource;
                    liveRegion.keyCenter = voice.sampledKeyCenter;
                    liveRegion.pitchKeytrack = voice.sampledPitchKeytrack;
                    liveRegion.pitchOffsetSemitones =
                        voice.sampledPitchOffsetSemitones;
                    liveRegion.sampleStartFrame = voice.sampledStartFrame;
                    liveRegion.sampleEndFrameExclusive =
                        voice.sampledEndFrameExclusive;
                    liveRegion.oneShot = voice.sampledOneShot;
                    float sampleL = 0.0f;
                    float sampleR = 0.0f;
                    const double sampledNotePitch =
                        (double)voice.sampledMidiPitch +
                        (double)pitchSemitones.load(std::memory_order_relaxed);
                    if (!renderSampledStereo(
                            liveRegion,
                            sampledNotePitch,
                            voice.ageSec,
                            sr,
                            sampleL,
                            sampleR))
                    {
                        voice.releasing = true;
                        voice.releaseAgeSec = voiceReleaseSec;
                        voice.ageSec += invSr;
                        continue;
                    }

                    const float gain =
                        (float)env *
                        (float)voice.velocity *
                        (float)cachedPreset.outputGain *
                        (float)voice.sampledGainLinear;
                    mixL += sampleL * gain;
                    mixR += sampleR * gain;

                    voice.ageSec += invSr;
                    if (voice.releasing)
                        voice.releaseAgeSec += invSr;
                    continue;
                }

                const double freq = 440.0 * std::pow(2.0, (notePitch - 69.0) / 12.0);
                const int sampleSeed = voice.seedBase + (int)std::floor(voice.ageSec * sr);

                const float raw = renderInstrumentSample(cachedPreset,
                                                         voice.pitch,
                                                         freq,
                                                         voice.ageSec,
                                                         noteProgress,
                                                         env,
                                                         sr,
                                                         sampleSeed);
                const float sampleValue = std::tanh(raw * driveGain) *
                                          (float)env *
                                          (float)voice.velocity *
                                          (float)cachedPreset.outputGain;

                const double pan = juce::jlimit(-0.95, 0.95,
                                                std::sin((double)voice.pitch * 0.23 + (double)voice.channel * 0.37) * cachedPreset.stereoWidth);
                const float leftGain = (float)std::sqrt(0.5 * (1.0 - pan));
                const float rightGain = (float)std::sqrt(0.5 * (1.0 + pan));

                mixL += sampleValue * leftGain;
                mixR += sampleValue * rightGain;

                voice.ageSec += invSr;
                if (voice.releasing)
                    voice.releaseAgeSec += invSr;
            }

            mixL = juce::jlimit(-1.0f, 1.0f, mixL);
            mixR = juce::jlimit(-1.0f, 1.0f, mixR);
            mixL *= panLeft;
            mixR *= panRight;
            if (stereo)
            {
                outL[i] += mixL;
                outR[i] += mixR;
            }
            else
            {
                outL[i] += 0.5f * (mixL + mixR);
            }
        }

        activeLiveNotes.erase(
            std::remove_if(
                activeLiveNotes.begin(),
                activeLiveNotes.end(),
                [sampledMode, releaseSec, this](const ActiveLiveNote &voice)
                {
                    const double voiceReleaseSec =
                        (sampledMode && voice.sampledSource != nullptr &&
                         !cachedSampledReleaseOverride)
                            ? juce::jmax(0.02, voice.sampledReleaseSec)
                            : releaseSec;
                    return voice.releasing && voice.releaseAgeSec >= voiceReleaseSec;
                }),
            activeLiveNotes.end());

        if (hostPlaying)
            playheadSec.store(blockEnd, std::memory_order_relaxed);
    }

    const juce::String getName() const override { return "TimelineMidiClipProcessor"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
    bool isBusesLayoutSupported(const BusesLayout &) const override { return true; }
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

private:
    enum class InstrumentFamily
    {
        basic,
        sampled,
        bass,
        pad,
        lead,
        pluck,
        keys,
        brass,
        wavetable,
        harmonic,
        drum,
    };

    struct InstrumentPreset
    {
        InstrumentFamily family = InstrumentFamily::basic;
        int oscillator = 1;
        double cutoffHz = 3200.0;
        double attackMs = 18.0;
        double releaseMs = 180.0;
        double drive = 0.08;
        double outputGain = 0.36;
        double detune = 0.0;
        double stereoWidth = 0.12;
        double tone = 0.55;
        double transient = 0.08;
        double pitchDropSemitones = 0.0;
        double noise = 0.02;
        double padDetuneOffset = 0.008;
        double decayMs = 120.0;
        double sustainLevel = 0.86;
    };

    struct DecodedSamplePcm
    {
        int sampleRate = 48000;
        std::vector<float> left;
        std::vector<float> right;

        int frameCount() const
        {
            return (int)juce::jmin(left.size(), right.size());
        }
    };

    struct SampledRegion
    {
        mutable std::shared_ptr<const DecodedSamplePcm> sample;
        juce::String sampleAssetPath;
        int loKey = 0;
        int hiKey = 127;
        int keyCenter = 60;
        int loVel = 0;
        int hiVel = 127;
        double gainLinear = 1.0;
        double attackSec = 0.005;
        double releaseSec = 0.35;
        double pitchKeytrack = 100.0;
        double pitchOffsetSemitones = 0.0;
        int sampleStartFrame = 0;
        int sampleEndFrameExclusive = 0;
        bool oneShot = false;
        int seqLength = 1;
        int seqPosition = 1;
        double loRand = 0.0;
        double hiRand = 1.0;
    };

    struct SampledDefinition
    {
        juce::String sfzAssetPath;
        std::vector<SampledRegion> regions;
        double defaultAttackSec = 0.005;
        double defaultReleaseSec = 0.35;
    };

    struct PendingState
    {
        juce::Array<TimelineMidiNote> notes;
        juce::String instrumentId;
        juce::String instrumentName;
        InstrumentPreset preset;
        std::shared_ptr<const SampledDefinition> sampledDefinition;
        bool sampledAttackOverride = false;
        bool sampledReleaseOverride = false;
        double sourceTempoBpm = 120.0;
    };

    struct LiveMidiEvent
    {
        bool noteOn = false;
        int channel = 1;
        int pitch = 60;
        float velocity = 1.0f;
    };

    struct ActiveLiveNote
    {
        int channel = 1;
        int pitch = 60;
        double velocity = 1.0;
        double ageSec = 0.0;
        bool releasing = false;
        double releaseAgeSec = 0.0;
        double releaseStartLevel = 1.0;
        int seedBase = 0;
        std::shared_ptr<const DecodedSamplePcm> sampledSource;
        int sampledMidiPitch = 60;
        int sampledKeyCenter = 60;
        double sampledGainLinear = 1.0;
        double sampledAttackSec = 0.005;
        double sampledReleaseSec = 0.35;
        double sampledPitchKeytrack = 100.0;
        double sampledPitchOffsetSemitones = 0.0;
        int sampledStartFrame = 0;
        int sampledEndFrameExclusive = 0;
        bool sampledOneShot = false;
    };

    static double readParam(const juce::NamedValueSet &params, const char *key, double fallback)
    {
        auto *v = params.getVarPointer(juce::Identifier(key));
        if (v == nullptr || v->isVoid())
            return fallback;
        if (v->isBool())
            return (bool)(*v) ? 1.0 : 0.0;
        if (v->isInt() || v->isInt64() || v->isDouble())
            return (double)(*v);
        return fallback;
    }

    static double hashNoise(int seed)
    {
        uint32_t x = (uint32_t)(seed * 747796405u + 2891336453u);
        x ^= x >> 16;
        x *= 2246822519u;
        x ^= x >> 13;
        x *= 3266489917u;
        x ^= x >> 16;
        const double n01 = (double)(x & 0x00ffffffu) / (double)0x01000000u;
        return (n01 * 2.0) - 1.0;
    }

    static double envelopeHoldLevel(
        double ageSec,
        double attackSec,
        double decaySec,
        double sustainLevel)
    {
        attackSec = juce::jmax(0.001, attackSec);
        decaySec = juce::jmax(0.001, decaySec);
        sustainLevel = juce::jlimit(0.05, 1.0, sustainLevel);
        if (ageSec < attackSec)
            return juce::jlimit(0.0, 1.0, ageSec / attackSec);

        const double decayAge = ageSec - attackSec;
        if (decayAge < decaySec)
        {
            const double t = decayAge / decaySec;
            return 1.0 + ((sustainLevel - 1.0) * t);
        }
        return sustainLevel;
    }

    static double envelopeLevel(
        double ageSec,
        double holdSec,
        double attackSec,
        double decaySec,
        double sustainLevel,
        double releaseSec)
    {
        if (ageSec < holdSec)
            return envelopeHoldLevel(ageSec, attackSec, decaySec, sustainLevel);

        releaseSec = juce::jmax(0.02, releaseSec);
        const double releaseAge = ageSec - holdSec;
        const double releaseStart =
            envelopeHoldLevel(holdSec, attackSec, decaySec, sustainLevel);
        return releaseStart * (1.0 - (releaseAge / releaseSec));
    }

    static double wrapPhase(double phase)
    {
        phase -= std::floor(phase);
        if (phase < 0.0)
            phase += 1.0;
        return phase;
    }

    static int sampledMidiPitchForInstrument(const juce::String &instrumentId,
                                             int pitch)
    {
        const juce::String id = instrumentId.trim().toLowerCase();
        const int safePitch = juce::jlimit(0, 127, pitch);
        const bool drumKit =
            id == "mixroom.drum_808_starter" ||
            id == "mixroom.drum_house" ||
            id == "mixroom.drum_breakbeat" ||
            id == "mixroom.drum_trap" ||
            id == "sfz.vsco.mixroom_drum_starter" ||
            id == "sfz.vsco.mixroom_dry_drum_kit" ||
            id == "sfz.vsco.mixroom_acoustic_drum_kit" ||
            id == "sfz.vsco.mixroom_electro_punch_kit" ||
            id == "sfz.vsco_2_ce_1_1_0_mixroomdrumstarter" ||
            id == "sfz.vsco_2_ce_1_1_0_mixroomdrydrumkit" ||
            id == "sfz.vsco_2_ce_1_1_0_mixroomacousticdrumkit" ||
            id == "sfz.vsco_2_ce_1_1_0_mixroomelectropunchkit" ||
            id.contains("mixroomdrumstarter.sfz") ||
            id.contains("mixroomdrydrumkit.sfz") ||
            id.contains("mixroomacousticdrumkit.sfz");
        if (!drumKit)
            return safePitch;

        switch (safePitch)
        {
        case 35:
            return 36;
        case 37:
        case 39:
            return 38;
        case 41:
        case 43:
            return 45;
        case 48:
            return 47;
        case 52:
        case 53:
            return 42;
        case 55:
        case 57:
        case 59:
            return 49;
        default:
            return safePitch;
        }
    }

    static float waveFromType(int type, double phase)
    {
        const double p = wrapPhase(phase);
        switch (type)
        {
        case 0:
            return (float)std::sin(juce::MathConstants<double>::twoPi * p);
        case 1:
            return (float)((2.0 * p) - 1.0);
        case 2:
            return p < 0.5 ? 1.0f : -1.0f;
        default:
            return (float)(p < 0.5 ? (-1.0 + 4.0 * p) : (3.0 - 4.0 * p));
        }
    }

    static double softSaturate(double input, double amount)
    {
        const double drive = juce::jmax(1.0, amount);
        const double norm = std::tanh(drive);
        if (norm <= 1.0e-6)
            return input;
        return std::tanh(input * drive) / norm;
    }

    using SfzOpcodeMap = std::unordered_map<std::string, juce::String>;

    struct SampledAssetCache
    {
        juce::CriticalSection lock;
        std::unordered_map<std::string, std::shared_ptr<const SampledDefinition>> definitions;
        std::unordered_map<std::string, std::shared_ptr<const DecodedSamplePcm>> samples;
        std::deque<std::string> sampleLru;
    };

    static SampledAssetCache &sampledAssetCache()
    {
        static SampledAssetCache cache;
        return cache;
    }

    static juce::String normalizeAssetPath(const juce::String &rawPath)
    {
        juce::String path = rawPath.trim().replaceCharacter('\\', '/');
        while (path.contains("//"))
            path = path.replace("//", "/");
        const bool preserveLeadingSlash =
            juce::File::isAbsolutePath(path) ||
            path.startsWith("./") ||
            path.startsWith("../") ||
            path.startsWithChar('~');
        if (preserveLeadingSlash)
            return path;
        while (path.startsWithChar('/'))
            path = path.substring(1);
        return path;
    }

    static juce::File resolveFlutterAssetFile(const juce::String &assetPathRaw)
    {
        const juce::String raw = assetPathRaw.trim();
        const bool allowDirectPath =
            juce::File::isAbsolutePath(raw) ||
            raw.startsWith("./") ||
            raw.startsWith("../") ||
            raw.startsWithChar('~');
        if (raw.isNotEmpty() && allowDirectPath)
        {
            const juce::File direct(raw);
            if (direct.existsAsFile())
                return direct;
        }

        const juce::String assetPath = normalizeAssetPath(assetPathRaw);
        if (assetPath.isEmpty())
            return {};

        juce::StringArray candidateAssetPaths;
        candidateAssetPaths.addIfNotAlreadyThere(assetPath);
        candidateAssetPaths.addIfNotAlreadyThere(
            assetPath.replace("#", "%23"));

        {
            const juce::ScopedLock lock(flutterAssetRootLock());
            const juce::String rootPath = flutterAssetRoot();
            if (rootPath.isNotEmpty())
            {
                const juce::File root(rootPath);
                for (const auto &candidatePath : candidateAssetPaths)
                {
                    const juce::File rootDirect = root.getChildFile(candidatePath);
                    if (rootDirect.existsAsFile())
                        return rootDirect;

                    const juce::File nested = root.getChildFile("flutter_assets")
                                                  .getChildFile(candidatePath);
                    if (nested.existsAsFile())
                        return nested;
                }
            }
        }

        const juce::File appBundle =
            juce::File::getSpecialLocation(juce::File::currentApplicationFile)
                .getParentDirectory();
        const std::array<juce::File, 4> roots = {
            appBundle.getChildFile("Frameworks")
                .getChildFile("App.framework")
                .getChildFile("flutter_assets"),
            appBundle.getChildFile("flutter_assets"),
            appBundle.getChildFile("Frameworks").getChildFile("App.framework"),
            appBundle};

        for (const auto &root : roots)
        {
            if (!root.exists())
                continue;
            for (const auto &candidatePath : candidateAssetPaths)
            {
                const auto direct = root.getChildFile(candidatePath);
                if (direct.existsAsFile())
                    return direct;

                const auto nested = root.getChildFile("flutter_assets")
                                        .getChildFile(candidatePath);
                if (nested.existsAsFile())
                    return nested;
            }
        }

        return appBundle.getChildFile("Frameworks")
            .getChildFile("App.framework")
            .getChildFile("flutter_assets")
            .getChildFile(assetPath);
    }

    static SfzOpcodeMap parseSfzOpcodes(const juce::String &lineRaw)
    {
        SfzOpcodeMap out;
        const juce::String line =
            lineRaw.upToFirstOccurrenceOf("//", false, false).trim();
        if (line.isEmpty())
            return out;

        static const std::regex pattern("([A-Za-z_][A-Za-z0-9_]*)=");
        const std::string utf8 = line.toStdString();

        std::vector<size_t> matchStarts;
        std::vector<size_t> matchLengths;
        std::vector<std::string> matchKeys;
        for (std::sregex_iterator it(utf8.begin(), utf8.end(), pattern), end;
             it != end; ++it)
        {
            matchStarts.push_back((size_t)it->position());
            matchLengths.push_back((size_t)it->length());
            matchKeys.push_back((*it)[1].str());
        }

        if (matchStarts.empty())
            return out;

        for (size_t i = 0; i < matchStarts.size(); ++i)
        {
            const size_t valueStart = matchStarts[i] + matchLengths[i];
            const size_t valueEnd =
                (i + 1 < matchStarts.size()) ? matchStarts[i + 1] : utf8.size();
            if (valueStart >= valueEnd)
                continue;

            const juce::String key =
                juce::String(matchKeys[i].c_str()).trim().toLowerCase();
            const juce::String value =
                juce::String::fromUTF8(utf8.data() + valueStart,
                                       (int)(valueEnd - valueStart))
                    .trim();
            if (key.isEmpty() || value.isEmpty())
                continue;
            out[key.toStdString()] = value;
        }

        return out;
    }

    static void mergeOpcodeMap(SfzOpcodeMap &dst, const SfzOpcodeMap &src)
    {
        for (const auto &entry : src)
            dst[entry.first] = entry.second;
    }

    static juce::String opcodeValue(const SfzOpcodeMap &values, const char *key)
    {
        if (auto found = values.find(std::string(key)); found != values.end())
            return found->second;
        return {};
    }

    static double parseSfzNumberOrNote(const juce::String &raw)
    {
        juce::String token = raw.trim();
        if (token.length() >= 2)
        {
            const juce::juce_wchar first = token[0];
            const juce::juce_wchar last = token[token.length() - 1];
            const bool doubleQuoted = first == '"' && last == '"';
            const bool singleQuoted = first == '\'' && last == '\'';
            if (doubleQuoted || singleQuoted)
                token = token.substring(1, token.length() - 1).trim();
        }
        if (token.isEmpty())
            return std::numeric_limits<double>::quiet_NaN();

        const std::string utf8 = token.toStdString();
        char *endPtr = nullptr;
        const double parsed = std::strtod(utf8.c_str(), &endPtr);
        if (endPtr != utf8.c_str() && endPtr != nullptr && *endPtr == '\0')
            return parsed;

        static const std::regex notePattern("^([A-Ga-g])([#b]?)(-?[0-9]+)$");
        std::smatch match;
        if (!std::regex_match(utf8, match, notePattern))
            return std::numeric_limits<double>::quiet_NaN();

        if (match.size() < 4)
            return std::numeric_limits<double>::quiet_NaN();
        const char step = (char)std::toupper(match[1].str()[0]);
        const std::string accidental = match[2].str();
        const int octave = std::atoi(match[3].str().c_str());

        int semitone = 0;
        switch (step)
        {
        case 'C':
            semitone = 0;
            break;
        case 'D':
            semitone = 2;
            break;
        case 'E':
            semitone = 4;
            break;
        case 'F':
            semitone = 5;
            break;
        case 'G':
            semitone = 7;
            break;
        case 'A':
            semitone = 9;
            break;
        case 'B':
            semitone = 11;
            break;
        default:
            return std::numeric_limits<double>::quiet_NaN();
        }

        if (accidental == "#")
            semitone += 1;
        else if (accidental == "b")
            semitone -= 1;
        const int midi = ((octave + 1) * 12) + semitone;
        return (double)midi;
    }

    static double readSfzNumeric(const SfzOpcodeMap &values,
                                 const char *key,
                                 double fallback)
    {
        const juce::String raw = opcodeValue(values, key).trim();
        if (raw.isEmpty())
            return fallback;
        const double parsed = parseSfzNumberOrNote(raw);
        if (!std::isfinite(parsed))
            return fallback;
        return parsed;
    }

    static juce::String resolveSfzSampleAssetPath(const juce::String &sfzAssetPath,
                                                  const juce::String &defaultPathRaw,
                                                  const juce::String &samplePathRaw)
    {
        const juce::String sfzPath = normalizeAssetPath(sfzAssetPath);
        const int slash = sfzPath.lastIndexOfChar('/');
        const juce::String sfzDir =
            slash >= 0 ? sfzPath.substring(0, slash) : juce::String();
        const juce::String defaultPath = normalizeAssetPath(defaultPathRaw);
        const juce::String samplePath = normalizeAssetPath(samplePathRaw);

        juce::String joined = sfzDir;
        if (defaultPath.isNotEmpty())
        {
            if (joined.isNotEmpty())
                joined << "/";
            joined << defaultPath;
        }
        if (samplePath.isNotEmpty())
        {
            if (joined.isNotEmpty())
                joined << "/";
            joined << samplePath;
        }

        return normalizeAssetPath(joined);
    }

    static void touchSampleLru(SampledAssetCache &cache, const std::string &key)
    {
        auto it = std::find(cache.sampleLru.begin(), cache.sampleLru.end(), key);
        if (it != cache.sampleLru.end())
            cache.sampleLru.erase(it);
        cache.sampleLru.push_back(key);
    }

    static std::shared_ptr<const DecodedSamplePcm>
    decodedSampleForAsset(const juce::String &sampleAssetPath)
    {
        const juce::String normalized = normalizeAssetPath(sampleAssetPath);
        if (normalized.isEmpty())
            return nullptr;
        const std::string cacheKey = normalized.toLowerCase().toStdString();

        auto &cache = sampledAssetCache();
        {
            const juce::ScopedLock lock(cache.lock);
            if (auto found = cache.samples.find(cacheKey); found != cache.samples.end())
            {
                touchSampleLru(cache, cacheKey);
                return found->second;
            }
        }

        const juce::File sampleFile = resolveFlutterAssetFile(normalized);
        if (!sampleFile.existsAsFile())
        {
            juce::Logger::writeToLog(
                "Live MIDI sampled instrument missing sample file: " + normalized);
            return nullptr;
        }

        juce::AudioFormatManager formats;
        formats.registerBasicFormats();
        std::unique_ptr<juce::AudioFormatReader> reader(
            formats.createReaderFor(sampleFile));
        if (reader == nullptr || reader->lengthInSamples <= 1)
            return nullptr;
        if (reader->lengthInSamples > (juce::int64)std::numeric_limits<int>::max())
            return nullptr;

        const int frameCount = (int)reader->lengthInSamples;
        juce::AudioBuffer<float> decodedBuffer(2, frameCount);
        const bool ok = reader->read(&decodedBuffer,
                                     0,
                                     frameCount,
                                     0,
                                     true,
                                     true);
        if (!ok)
            return nullptr;

        auto decoded = std::make_shared<DecodedSamplePcm>();
        decoded->sampleRate =
            (int)juce::jlimit(4000.0, 192000.0, reader->sampleRate);
        decoded->left.assign(decodedBuffer.getReadPointer(0),
                             decodedBuffer.getReadPointer(0) + frameCount);
        if (decodedBuffer.getNumChannels() > 1)
        {
            decoded->right.assign(decodedBuffer.getReadPointer(1),
                                  decodedBuffer.getReadPointer(1) + frameCount);
        }
        else
        {
            decoded->right = decoded->left;
        }

        {
            const juce::ScopedLock lock(cache.lock);
            cache.samples[cacheKey] = decoded;
            touchSampleLru(cache, cacheKey);
            constexpr size_t kMaxCachedSamples = 64;
            while (cache.sampleLru.size() > kMaxCachedSamples)
            {
                const std::string oldest = cache.sampleLru.front();
                cache.sampleLru.pop_front();
                cache.samples.erase(oldest);
            }
        }

        return decoded;
    }

    static std::shared_ptr<const SampledDefinition>
    sampledDefinitionForAsset(const juce::String &sfzAssetPathRaw)
    {
        const juce::String sfzAssetPath = normalizeAssetPath(sfzAssetPathRaw);
        if (sfzAssetPath.isEmpty())
            return nullptr;

        const std::string cacheKey = sfzAssetPath.toLowerCase().toStdString();
        auto &cache = sampledAssetCache();
        {
            const juce::ScopedLock lock(cache.lock);
            if (auto found = cache.definitions.find(cacheKey);
                found != cache.definitions.end())
            {
                return found->second;
            }
        }

        const juce::File sfzFile = resolveFlutterAssetFile(sfzAssetPath);
        if (!sfzFile.existsAsFile())
        {
            juce::Logger::writeToLog(
                "Live MIDI sampled instrument missing sfz file: " + sfzAssetPath);
            return nullptr;
        }

        const juce::String sfzText = sfzFile.loadFileAsString();
        if (sfzText.isEmpty())
            return nullptr;

        SfzOpcodeMap control;
        SfzOpcodeMap global;
        SfzOpcodeMap master;
        SfzOpcodeMap group;
        SfzOpcodeMap *region = nullptr;
        std::vector<SfzOpcodeMap> rawRegions;
        juce::String currentBlock;

        juce::StringArray lines;
        lines.addLines(sfzText);
        for (const auto &rawLine : lines)
        {
            const juce::String line =
                rawLine.upToFirstOccurrenceOf("//", false, false).trim();
            if (line.isEmpty())
                continue;

            juce::String blockTag;
            juce::String remainder = line;
            if (line.startsWithChar('<'))
            {
                const int closeIdx = line.indexOfChar('>');
                if (closeIdx > 1)
                {
                    blockTag = line.substring(1, closeIdx).trim().toLowerCase();
                    remainder = line.substring(closeIdx + 1).trim();
                }
            }

            if (blockTag.isNotEmpty())
            {
                const juce::String tag = blockTag;
                currentBlock = tag;
                region = nullptr;
                if (tag == "group")
                {
                    group.clear();
                }
                else if (tag == "master")
                {
                    master.clear();
                }
                else if (tag == "region")
                {
                    rawRegions.emplace_back();
                    region = &rawRegions.back();
                    mergeOpcodeMap(*region, control);
                    mergeOpcodeMap(*region, global);
                    mergeOpcodeMap(*region, master);
                    mergeOpcodeMap(*region, group);
                }
            }

            const auto opcodes = parseSfzOpcodes(remainder);
            if (opcodes.empty())
                continue;

            if (currentBlock == "control")
                mergeOpcodeMap(control, opcodes);
            else if (currentBlock == "global")
                mergeOpcodeMap(global, opcodes);
            else if (currentBlock == "master")
                mergeOpcodeMap(master, opcodes);
            else if (currentBlock == "group")
                mergeOpcodeMap(group, opcodes);
            else if (currentBlock == "region")
            {
                if (region == nullptr)
                {
                    rawRegions.emplace_back();
                    region = &rawRegions.back();
                    mergeOpcodeMap(*region, control);
                    mergeOpcodeMap(*region, global);
                    mergeOpcodeMap(*region, master);
                    mergeOpcodeMap(*region, group);
                }
                mergeOpcodeMap(*region, opcodes);
            }
        }

        const juce::String defaultPathRaw = opcodeValue(control, "default_path");
        const double globalAttackSec =
            readSfzNumeric(global, "ampeg_attack", 0.005);
        const double globalReleaseSec =
            readSfzNumeric(global, "ampeg_release", 0.35);
        const double globalVol = readSfzNumeric(global, "volume", 0.0);

        auto definition = std::make_shared<SampledDefinition>();
        definition->sfzAssetPath = sfzAssetPath;
        definition->defaultAttackSec = juce::jlimit(0.0, 4.0, globalAttackSec);
        definition->defaultReleaseSec =
            juce::jlimit(0.02, 12.0, globalReleaseSec);
        definition->regions.reserve(rawRegions.size());

        for (const auto &r : rawRegions)
        {
            const juce::String sampleRaw = opcodeValue(r, "sample").trim();
            if (sampleRaw.isEmpty())
                continue;

            const juce::String sampleAssetPath = resolveSfzSampleAssetPath(
                sfzAssetPath,
                opcodeValue(r, "default_path").isNotEmpty()
                    ? opcodeValue(r, "default_path")
                    : defaultPathRaw,
                sampleRaw);
            SampledRegion regionDef;
            regionDef.sampleAssetPath = sampleAssetPath;
            regionDef.loKey =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "lokey", 0.0)));
            regionDef.hiKey =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "hikey", 127.0)));

            double keyCenter = readSfzNumeric(r, "pitch_keycenter", std::numeric_limits<double>::quiet_NaN());
            if (!std::isfinite(keyCenter))
            {
                keyCenter = readSfzNumeric(
                    r,
                    "key",
                    (double)std::lround((regionDef.loKey + regionDef.hiKey) * 0.5));
            }
            regionDef.keyCenter =
                juce::jlimit(0, 127, (int)std::lround(keyCenter));
            regionDef.loVel =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "lovel", 0.0)));
            regionDef.hiVel =
                juce::jlimit(0, 127, (int)std::lround(readSfzNumeric(r, "hivel", 127.0)));

            const double regionVolDb = juce::jlimit(
                -24.0,
                20.0,
                readSfzNumeric(r, "volume", globalVol));
            regionDef.gainLinear = std::pow(10.0, regionVolDb / 20.0);
            regionDef.attackSec = juce::jlimit(
                0.0,
                4.0,
                readSfzNumeric(r, "ampeg_attack", globalAttackSec));
            regionDef.releaseSec = juce::jlimit(
                0.02,
                12.0,
                readSfzNumeric(r, "ampeg_release", globalReleaseSec));
            regionDef.pitchKeytrack = juce::jlimit(
                -1200.0,
                1200.0,
                readSfzNumeric(r, "pitch_keytrack", 100.0));
            regionDef.pitchOffsetSemitones = juce::jlimit(
                -48.0,
                48.0,
                readSfzNumeric(r, "transpose", 0.0) +
                    (readSfzNumeric(r, "tune", 0.0) / 100.0));
            regionDef.sampleStartFrame = juce::jmax(
                0,
                (int)std::lround(readSfzNumeric(r, "offset", 0.0)));
            regionDef.sampleEndFrameExclusive = juce::jmax(
                0,
                (int)std::lround(readSfzNumeric(r, "end", -1.0)) + 1);
            regionDef.oneShot =
                opcodeValue(r, "loop_mode").trim().toLowerCase() == "one_shot";
            regionDef.seqLength = juce::jmax(
                1,
                (int)std::lround(readSfzNumeric(r, "seq_length", 1.0)));
            regionDef.seqPosition = juce::jlimit(
                1,
                regionDef.seqLength,
                (int)std::lround(readSfzNumeric(r, "seq_position", 1.0)));
            regionDef.loRand = juce::jlimit(
                0.0,
                1.0,
                readSfzNumeric(r, "lorand", 0.0));
            regionDef.hiRand = juce::jlimit(
                regionDef.loRand,
                1.0,
                readSfzNumeric(r, "hirand", 1.0));
            definition->regions.push_back(regionDef);
        }

        if (definition->regions.empty())
        {
            juce::Logger::writeToLog(
                "Live MIDI sampled instrument produced no playable regions: " + sfzAssetPath);
            return nullptr;
        }

        {
            const juce::ScopedLock lock(cache.lock);
            cache.definitions[cacheKey] = definition;
        }
        return definition;
    }

    static juce::String sfzAssetPathForInstrument(const juce::String &instrumentId,
                                                  const juce::String &instrumentName)
    {
        const juce::String id = instrumentId.toLowerCase().trim();
        if (id.startsWith("sfz_asset:"))
            return normalizeAssetPath(instrumentId.substring(10));
        return {};
    }

    static std::shared_ptr<const SampledDefinition>
    resolveSampledDefinition(const juce::String &instrumentId,
                             const juce::String &instrumentName)
    {
        const juce::String assetPath =
            sfzAssetPathForInstrument(instrumentId, instrumentName);
        if (assetPath.isEmpty())
            return nullptr;
        return sampledDefinitionForAsset(assetPath);
    }

    static bool ensureSampledRegionLoaded(const SampledRegion &region)
    {
        if (region.sample != nullptr && region.sample->frameCount() >= 2)
            return true;
        if (region.sampleAssetPath.trim().isEmpty())
            return false;

        auto sample = decodedSampleForAsset(region.sampleAssetPath);
        if (sample == nullptr || sample->frameCount() < 2)
            return false;

        region.sample = sample;
        return true;
    }

    static bool isSampledRegionReady(const SampledRegion &region) noexcept
    {
        return region.sample != nullptr && region.sample->frameCount() >= 2;
    }

    static const SampledRegion *pickSampledRegion(const SampledDefinition &definition,
                                                  int pitch,
                                                  int velocity,
                                                  int sequenceStep = 0)
    {
        auto random01For = [&](const SampledRegion &region)
        {
            uint32_t seed = 0x45d9f3bu;
            seed ^= (uint32_t)(pitch * 1009);
            seed ^= (uint32_t)(velocity * 9176);
            seed ^= (uint32_t)(sequenceStep * 6151);
            seed ^= (uint32_t)(region.keyCenter * 313);
            seed ^= (uint32_t)(region.loKey * 137);
            seed ^= (uint32_t)(region.hiKey * 271);
            seed ^= seed >> 16;
            seed &= 0x7fffffffu;
            return (double)seed / (double)0x7fffffffu;
        };

        auto pickBest =
            [&](bool enforceVelocity, bool enforceSequence) -> const SampledRegion *
        {
            const SampledRegion *best = nullptr;
            int bestKeyDistance = std::numeric_limits<int>::max();
            int bestVelDistance = std::numeric_limits<int>::max();

            for (const auto &region : definition.regions)
            {
                if (pitch < region.loKey || pitch > region.hiKey)
                    continue;
                if (enforceVelocity && (velocity < region.loVel || velocity > region.hiVel))
                    continue;
                if (enforceSequence && region.seqLength > 1)
                {
                    const int expected = (sequenceStep % region.seqLength) + 1;
                    if (region.seqPosition != expected)
                        continue;
                }
                const double randomValue = random01For(region);
                if (randomValue < region.loRand || randomValue >= region.hiRand)
                    continue;

                const int keyDistance = std::abs(pitch - region.keyCenter);
                const int velDistance =
                    velocity < region.loVel ? (region.loVel - velocity)
                                            : velocity > region.hiVel ? (velocity - region.hiVel)
                                                                      : 0;
                if (best == nullptr || keyDistance < bestKeyDistance ||
                    (keyDistance == bestKeyDistance && velDistance < bestVelDistance))
                {
                    best = &region;
                    bestKeyDistance = keyDistance;
                    bestVelDistance = velDistance;
                }
            }
            return best;
        };

        if (auto *best = pickBest(true, true))
            return best;
        if (auto *best = pickBest(false, true))
            return best;
        if (auto *best = pickBest(true, false))
            return best;
        return pickBest(false, false);
    }

    static void preloadSampledRegionsForNotes(const SampledDefinition &definition,
                                              const juce::Array<TimelineMidiNote> &notes,
                                              const juce::String &instrumentId)
    {
        std::unordered_set<const SampledRegion *> regionsToLoad;
        regionsToLoad.reserve((size_t)juce::jmax(1, notes.size()));

        for (int i = 0; i < notes.size(); ++i)
        {
            const auto &note = notes.getReference(i);
            const int sampledPitch =
                sampledMidiPitchForInstrument(instrumentId, note.pitch);
            const int midiVelocity = juce::jlimit(
                0,
                127,
                (int)std::lround(
                    juce::jlimit(0.0, 1.0, note.velocity) * 127.0));
            if (const auto *region = pickSampledRegion(
                    definition,
                    sampledPitch,
                    midiVelocity,
                    i))
            {
                regionsToLoad.insert(region);
            }
        }

        for (const auto *region : regionsToLoad)
            if (region != nullptr)
                ensureSampledRegionLoaded(*region);
    }

    static int sampledRegionFrameLimit(const SampledRegion &region,
                                       const DecodedSamplePcm &pcm)
    {
        const int requestedEnd =
            region.sampleEndFrameExclusive > 0
                ? region.sampleEndFrameExclusive
                : pcm.frameCount();
        return juce::jlimit(
            juce::jmin(region.sampleStartFrame + 1, pcm.frameCount()),
            pcm.frameCount(),
            requestedEnd);
    }

    static double sampledPlaybackRate(const DecodedSamplePcm &pcm,
                                      const SampledRegion &region,
                                      double notePitch,
                                      double outputSampleRate)
    {
        const double semitoneOffset =
            ((notePitch - (double)region.keyCenter) *
             (region.pitchKeytrack / 100.0)) +
            region.pitchOffsetSemitones;
        return std::pow(2.0, semitoneOffset / 12.0) *
               ((double)pcm.sampleRate / outputSampleRate);
    }

    static bool renderSampledStereo(const SampledRegion &region,
                                    double notePitch,
                                    double ageSec,
                                    double outputSampleRate,
                                    float &outL,
                                    float &outR)
    {
        outL = 0.0f;
        outR = 0.0f;
        if (region.sample == nullptr || outputSampleRate <= 0.0 || ageSec < 0.0)
            return false;

        const auto &pcm = *region.sample;
        const int frameCount = pcm.frameCount();
        if (frameCount < 2)
            return false;

        const int startFrame =
            juce::jlimit(0, frameCount - 1, region.sampleStartFrame);
        const int endFrame = sampledRegionFrameLimit(region, pcm);
        const int usableFrames = endFrame - startFrame;
        if (usableFrames < 2)
            return false;

        const double playbackRate =
            sampledPlaybackRate(pcm, region, notePitch, outputSampleRate);
        if (!std::isfinite(playbackRate) || playbackRate <= 0.0)
            return false;

        const double samplePos =
            (double)startFrame + (ageSec * outputSampleRate * playbackRate);
        if (samplePos < (double)startFrame || samplePos >= (double)(endFrame - 1))
            return false;

        const int index =
            juce::jlimit(startFrame, endFrame - 1, (int)std::floor(samplePos));
        const int nextIndex = juce::jmin(index + 1, endFrame - 1);
        const double frac = samplePos - (double)index;

        const float l0 = pcm.left[(size_t)index];
        const float l1 = pcm.left[(size_t)nextIndex];
        const float r0 = pcm.right[(size_t)index];
        const float r1 = pcm.right[(size_t)nextIndex];
        outL = juce::jlimit(-1.0f, 1.0f, (float)(l0 + (l1 - l0) * frac));
        outR = juce::jlimit(-1.0f, 1.0f, (float)(r0 + (r1 - r0) * frac));
        return true;
    }

    static const std::unordered_map<std::string, InstrumentPreset> &presetMap()
    {
        static const std::unordered_map<std::string, InstrumentPreset> map = {
            {"mixroom.basic_synth", {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02}},
            {"mixroom.bass_mono", {InstrumentFamily::bass, 2, 760.0, 4.0, 260.0, 0.03, 0.31, 0.0, 0.0, 0.32, 0.02, 1.25, 0.0}},
            {"mixroom.soft_pad", {InstrumentFamily::pad, 3, 2100.0, 80.0, 620.0, 0.02, 0.31, 0.012, 0.28, 0.47, 0.04, 0.0, 0.03}},
            {"mixroom.figbug_wavetable", {InstrumentFamily::wavetable, 1, 5200.0, 6.0, 240.0, 0.18, 0.33, 0.006, 0.16, 0.72, 0.14, 0.0, 0.03}},
            {"mixroom.sarah_harmonic", {InstrumentFamily::pad, 3, 1980.0, 72.0, 760.0, 0.03, 0.30, 0.0, 0.10, 0.34, 0.02, 0.0, 0.02, 0.0}},
            {"mixroom.vanilla_poly", {InstrumentFamily::keys, 0, 3680.0, 5.0, 220.0, 0.03, 0.36, 0.001, 0.03, 0.58, 0.26, 0.0, 0.01}},
            {"mixroom.duck_synth", {InstrumentFamily::bass, 2, 1780.0, 2.0, 130.0, 0.28, 0.35, 0.003, 0.02, 0.78, 0.24, 9.0, 0.05}},
            {"mixroom.chow_kick", {InstrumentFamily::drum, 0, 900.0, 0.0, 90.0, 0.42, 0.42, 0.0, 0.0, 0.52, 0.40, 16.0, 0.14}},
            {"mixroom.warm_keys", {InstrumentFamily::keys, 1, 1880.0, 20.0, 480.0, 0.06, 0.34, 0.004, 0.07, 0.18, 0.08, 0.0, 0.02}},
            {"mixroom.super_saw", {InstrumentFamily::lead, 1, 6200.0, 4.0, 180.0, 0.22, 0.34, 0.01, 0.20, 0.75, 0.11, 0.0, 0.03}},
            {"mixroom.gentle_pluck", {InstrumentFamily::pluck, 3, 4800.0, 2.0, 130.0, 0.08, 0.33, 0.004, 0.11, 0.68, 0.24, 0.0, 0.03}},
            {"mixroom.sub_bass", {InstrumentFamily::bass, 2, 560.0, 3.0, 300.0, 0.015, 0.33, 0.0, 0.0, 0.18, 0.01, 0.85, 0.0}},
            {"mixroom.analog_brass", {InstrumentFamily::brass, 2, 2140.0, 32.0, 340.0, 0.18, 0.35, 0.007, 0.06, 0.34, 0.12, 0.0, 0.06}},
            {"mixroom.drum_acoustic_easy", {InstrumentFamily::drum, 1, 2300.0, 0.0, 120.0, 0.18, 0.41, 0.0, 0.0, 0.52, 0.26, 10.0, 0.15}},
            {"mixroom.drum_808_starter", {InstrumentFamily::drum, 0, 1100.0, 0.0, 190.0, 0.36, 0.44, 0.0, 0.0, 0.60, 0.35, 24.0, 0.18}},
            {"mixroom.drum_lofi", {InstrumentFamily::drum, 3, 1700.0, 1.0, 150.0, 0.28, 0.41, 0.0, 0.0, 0.45, 0.20, 12.0, 0.20}},
            {"mixroom.drum_house", {InstrumentFamily::drum, 1, 2600.0, 0.0, 95.0, 0.24, 0.42, 0.0, 0.0, 0.58, 0.28, 14.0, 0.17}},
            {"mixroom.night_bell", {InstrumentFamily::harmonic, 0, 5600.0, 1.0, 540.0, 0.06, 0.30, 0.002, 0.22, 0.76, 0.16, 0.0, 0.01}},
            {"mixroom.fm_keys", {InstrumentFamily::harmonic, 0, 4700.0, 3.0, 320.0, 0.05, 0.31, 0.002, 0.10, 0.78, 0.18, 0.0, 0.01}},
            {"mixroom.vintage_strings", {InstrumentFamily::pad, 1, 2400.0, 32.0, 640.0, 0.08, 0.31, 0.015, 0.24, 0.50, 0.07, 0.0, 0.02}},
            {"mixroom.neo_brass", {InstrumentFamily::brass, 0, 4320.0, 8.0, 210.0, 0.22, 0.36, 0.014, 0.18, 0.84, 0.18, 0.0, 0.03}},
            {"mixroom.reese_bass", {InstrumentFamily::bass, 1, 1300.0, 4.0, 200.0, 0.26, 0.35, 0.015, 0.08, 0.57, 0.16, 5.0, 0.05}},
            {"mixroom.air_pluck", {InstrumentFamily::pluck, 3, 5200.0, 1.0, 210.0, 0.08, 0.33, 0.008, 0.14, 0.72, 0.20, 0.0, 0.05}},
            {"mixroom.cinematic_pad", {InstrumentFamily::pad, 3, 1900.0, 95.0, 760.0, 0.05, 0.30, 0.018, 0.30, 0.44, 0.05, 0.0, 0.03}},
            {"mixroom.velvet_ep", {InstrumentFamily::keys, 3, 5400.0, 3.0, 520.0, 0.12, 0.36, 0.022, 0.22, 0.88, 0.32, 0.0, 0.03}},
            {"mixroom.house_organ", {InstrumentFamily::keys, 2, 3400.0, 0.0, 210.0, 0.11, 0.33, 0.003, 0.10, 0.62, 0.12, 0.0, 0.02}},
            {"mixroom.glass_pluck", {InstrumentFamily::pluck, 3, 5600.0, 1.0, 170.0, 0.09, 0.33, 0.007, 0.14, 0.74, 0.24, 0.0, 0.03}},
            {"mixroom.neon_lead", {InstrumentFamily::lead, 1, 6400.0, 3.0, 210.0, 0.24, 0.34, 0.012, 0.18, 0.78, 0.13, 0.0, 0.03}},
            {"mixroom.mellow_sub", {InstrumentFamily::bass, 2, 420.0, 6.0, 420.0, 0.008, 0.32, 0.0, 0.0, 0.10, 0.0, 0.35, 0.0}},
            {"mixroom.wide_air_pad", {InstrumentFamily::pad, 3, 2300.0, 74.0, 700.0, 0.04, 0.30, 0.020, 0.30, 0.50, 0.05, 0.0, 0.02}},
            {"mixroom.horn_stack", {InstrumentFamily::brass, 1, 2900.0, 20.0, 280.0, 0.16, 0.33, 0.004, 0.12, 0.58, 0.09, 0.0, 0.02}},
            {"mixroom.drum_trap", {InstrumentFamily::drum, 0, 2100.0, 0.0, 110.0, 0.32, 0.42, 0.0, 0.0, 0.62, 0.32, 18.0, 0.20}},
            {"mixroom.drum_breakbeat", {InstrumentFamily::drum, 2, 2400.0, 0.0, 130.0, 0.26, 0.42, 0.0, 0.0, 0.55, 0.25, 12.0, 0.18}},
            {"mixroom.drum_dnb", {InstrumentFamily::drum, 2, 2600.0, 0.0, 105.0, 0.33, 0.43, 0.0, 0.0, 0.67, 0.34, 20.0, 0.22}},
        };
        return map;
    }

    static InstrumentPreset resolvePreset(const juce::String &instrumentId, const juce::String &instrumentName)
    {
        const juce::String id = instrumentId.toLowerCase().trim();
        const std::string idKey = id.toStdString();
        if (auto found = presetMap().find(idKey); found != presetMap().end())
            return found->second;

        const juce::String text = (id + " " + instrumentName.toLowerCase());
        auto contains = [&](const char *needle) { return text.contains(needle); };

        if (contains("drum") || contains("kick") || contains("808"))
            return {InstrumentFamily::drum, 0, 2000.0, 0.0, 120.0, 0.3, 0.42, 0.0, 0.0, 0.58, 0.30, 16.0, 0.20};
        if (contains("bass"))
            return {InstrumentFamily::bass, 2, 1200.0, 6.0, 220.0, 0.24, 0.34, 0.004, 0.06, 0.52, 0.16, 6.0, 0.04};
        if (contains("pad") || contains("string"))
            return {InstrumentFamily::pad, 3, 2200.0, 80.0, 620.0, 0.05, 0.30, 0.012, 0.24, 0.48, 0.06, 0.0, 0.03};
        if (contains("pluck") || contains("bell"))
            return {InstrumentFamily::pluck, 3, 5100.0, 2.0, 190.0, 0.08, 0.33, 0.005, 0.13, 0.74, 0.20, 0.0, 0.03};
        if (contains("brass") || contains("horn"))
            return {InstrumentFamily::brass, 1, 2800.0, 18.0, 290.0, 0.14, 0.33, 0.004, 0.13, 0.56, 0.08, 0.0, 0.02};
        if (contains("key") || contains("piano") || contains("organ"))
            return {InstrumentFamily::keys, 0, 3300.0, 10.0, 280.0, 0.06, 0.32, 0.004, 0.12, 0.58, 0.12, 0.0, 0.02};
        if (contains("wave"))
            return {InstrumentFamily::wavetable, 1, 4800.0, 6.0, 240.0, 0.16, 0.33, 0.006, 0.14, 0.68, 0.12, 0.0, 0.03};
        if (contains("harmonic") || contains("fm"))
            return {InstrumentFamily::harmonic, 0, 3400.0, 12.0, 360.0, 0.09, 0.32, 0.005, 0.15, 0.62, 0.12, 0.0, 0.02};
        if (contains("lead") || contains("saw"))
            return {InstrumentFamily::lead, 1, 5600.0, 4.0, 200.0, 0.18, 0.34, 0.008, 0.16, 0.74, 0.10, 0.0, 0.03};

        return {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02};
    }

    static void applyParamOverrides(InstrumentPreset &preset, const juce::NamedValueSet &params)
    {
        if (params.contains(juce::Identifier("oscillator")))
            preset.oscillator = juce::jlimit(0, 3, (int)std::lround(readParam(params, "oscillator", preset.oscillator)));
        if (params.contains(juce::Identifier("cutoffHz")))
            preset.cutoffHz = juce::jlimit(200.0, 16000.0, readParam(params, "cutoffHz", preset.cutoffHz));
        if (params.contains(juce::Identifier("attackMs")))
            preset.attackMs = juce::jlimit(0.0, 1000.0, readParam(params, "attackMs", preset.attackMs));
        if (params.contains(juce::Identifier("decayMs")))
            preset.decayMs = juce::jlimit(0.0, 2000.0, readParam(params, "decayMs", preset.decayMs));
        if (params.contains(juce::Identifier("sustainLevel")))
            preset.sustainLevel = juce::jlimit(0.05, 1.0, readParam(params, "sustainLevel", preset.sustainLevel));
        if (params.contains(juce::Identifier("releaseMs")))
            preset.releaseMs = juce::jlimit(20.0, 2400.0, readParam(params, "releaseMs", preset.releaseMs));
        if (params.contains(juce::Identifier("drive")))
            preset.drive = juce::jlimit(0.0, 1.0, readParam(params, "drive", preset.drive));
        if (params.contains(juce::Identifier("outputGain")))
        {
            const double maxGain = (preset.family == InstrumentFamily::sampled) ? 2.0 : 0.75;
            preset.outputGain = juce::jlimit(0.15, maxGain, readParam(params, "outputGain", preset.outputGain));
        }
        if (params.contains(juce::Identifier("detune")))
            preset.detune = juce::jlimit(0.0, 0.03, readParam(params, "detune", preset.detune));
        if (params.contains(juce::Identifier("stereoWidth")))
            preset.stereoWidth = juce::jlimit(0.0, 0.45, readParam(params, "stereoWidth", preset.stereoWidth));
        if (params.contains(juce::Identifier("tone")))
            preset.tone = juce::jlimit(0.0, 1.0, readParam(params, "tone", preset.tone));
        if (params.contains(juce::Identifier("transient")))
            preset.transient = juce::jlimit(0.0, 1.0, readParam(params, "transient", preset.transient));
        if (params.contains(juce::Identifier("noise")))
            preset.noise = juce::jlimit(0.0, 0.45, readParam(params, "noise", preset.noise));
        if (params.contains(juce::Identifier("padDetuneOffset")))
            preset.padDetuneOffset = juce::jlimit(0.0, 0.03, readParam(params, "padDetuneOffset", preset.padDetuneOffset));
        if (params.contains(juce::Identifier("pitchDropSemitones")))
            preset.pitchDropSemitones = juce::jlimit(0.0, 36.0, readParam(params, "pitchDropSemitones", preset.pitchDropSemitones));
    }

    static float renderInstrumentSample(const InstrumentPreset &preset,
                                        int pitch,
                                        double frequencyHz,
                                        double ageSec,
                                        double noteProgress,
                                        double envelope,
                                        double sampleRate,
                                        int noiseSeed)
    {
        juce::ignoreUnused(envelope);

        const double phaseA = wrapPhase(ageSec * frequencyHz);
        const double phaseB = wrapPhase(ageSec * frequencyHz * (1.0 + juce::jlimit(0.0, 0.03, preset.detune + 0.001)));
        const double sampleIndex = ageSec * sampleRate;
        const double brightness = juce::jlimit(
            0.05, 1.0, preset.cutoffHz / (preset.cutoffHz + frequencyHz * (1.5 + (1.0 - preset.tone) * 2.5)));

        auto noise = [&](int salt)
        { return hashNoise(noiseSeed + salt + (int)sampleIndex); };

        auto phaseFor = [&](double freqHz)
        { return wrapPhase(ageSec * freqHz); };

        switch (preset.family)
        {
        case InstrumentFamily::bass:
        {
            const double toneShape = juce::jlimit(0.0, 1.0, preset.tone);
            const double driveShape = juce::jlimit(0.0, 1.0, preset.drive);
            const double det = juce::jlimit(0.0, 0.012, preset.detune);
            const double punch = std::exp(-18.0 * noteProgress);
            const double pitchRatio = std::pow(
                2.0,
                juce::jlimit(0.0, 6.0, preset.pitchDropSemitones) *
                    punch / 12.0);
            const double tunedFreq = frequencyHz * pitchRatio;
            const double bodyMix =
                juce::jlimit(0.05, 0.16, 0.06 + toneShape * 0.07);
            const double secondMix =
                juce::jlimit(0.03, 0.16, 0.04 + toneShape * 0.07 + driveShape * 0.05);
            const double thirdMix =
                juce::jlimit(0.01, 0.10, 0.01 + toneShape * 0.04 + driveShape * 0.05);
            const double airMix =
                juce::jlimit(0.0, 0.05, toneShape * 0.02 + driveShape * 0.02);
            const float sub = waveFromType(0, phaseFor(tunedFreq));
            const float body = waveFromType(3, phaseFor(tunedFreq * (1.0 + det * 0.35)) + 0.125) *
                               (float)bodyMix;
            const float second = waveFromType(0, phaseFor(tunedFreq * 2.0)) *
                                 (float)secondMix;
            const float third = waveFromType(0, phaseFor(tunedFreq * 3.0)) *
                                (float)thirdMix;
            const float air = waveFromType(3, phaseFor(tunedFreq * 4.0)) *
                              (float)airMix;
            const float grit = (float)((preset.noise * (0.002 + toneShape * 0.02)) *
                                       punch * noise(23));
            const float transient = (float)((0.001 + preset.transient * 0.012 + toneShape * 0.003) *
                                            std::exp(-60.0 * noteProgress) * noise(17));
            const double core =
                sub * juce::jlimit(0.76, 0.92, 0.90 - toneShape * 0.08) +
                body + second + third + air + grit + transient;
            const double saturated =
                softSaturate(core, 1.05 + driveShape * 1.5 + toneShape * 0.35);
            const double cleanBlend =
                juce::jlimit(0.62, 0.84, 0.80 - toneShape * 0.10);
            const double shapeBlend =
                juce::jlimit(0.18, 0.40, 0.22 + toneShape * 0.10 + driveShape * 0.08);
            const double bassLevel = juce::jlimit(
                0.46, 0.98, 0.56 + brightness * 0.28 + toneShape * 0.08 + punch * 0.08);
            return (float)((sub * cleanBlend + saturated * shapeBlend) * bassLevel);
        }
        case InstrumentFamily::pad:
        {
            const double det = juce::jlimit(0.0, 0.03, preset.detune + preset.padDetuneOffset);
            const double lfo = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.23);
            const float left = waveFromType(0, phaseFor(frequencyHz * (1.0 - det)));
            const float right = waveFromType(3, phaseFor(frequencyHz * (1.0 + det)));
            const float shimmer = waveFromType(1, phaseA + 0.25) * 0.18f;
            const float airy = (float)(preset.noise * 0.55 * noise(29));
            return (left * 0.48f + right * 0.40f + shimmer + airy) *
                   (float)(brightness * juce::jlimit(0.6, 1.35, 0.85 + lfo * 0.2 + (1.0 - noteProgress) * 0.3));
        }
        case InstrumentFamily::lead:
        {
            const double vibrato = 1.0 + std::sin(juce::MathConstants<double>::twoPi * ageSec * 5.1) * (0.001 + 0.002 * envelope);
            const float saw = waveFromType(1, phaseFor(frequencyHz * vibrato));
            const float pulse = waveFromType(2, phaseFor(frequencyHz * 1.01 * vibrato)) * 0.42f;
            const float edge = waveFromType(3, phaseFor(frequencyHz * 1.99 * vibrato)) * 0.18f;
            const float grit = (float)(preset.noise * 0.35 * std::exp(-10.0 * noteProgress) * noise(43));
            return (saw * 0.68f + pulse + edge + grit) * (float)(brightness * (1.2 - noteProgress * 0.25));
        }
        case InstrumentFamily::pluck:
        {
            const double decay = std::exp(-6.8 * noteProgress);
            const float tri = waveFromType(3, phaseA) * 0.62f;
            const float tone = waveFromType(0, phaseB) * 0.36f;
            const float pick = (float)((preset.transient + 0.12) * std::exp(-30.0 * noteProgress) * noise(61));
            return (float)((tri + tone) * decay + pick) * (float)(brightness * (1.1 + (1.0 - noteProgress) * 0.2));
        }
        case InstrumentFamily::keys:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            const double keyOpen = juce::jlimit(0.6, 1.7, 0.75 + preset.tone * 0.75 + (1.0 - noteProgress) * 0.2);
            const double warmth = juce::jlimit(0.0, 1.0, 1.0 - preset.tone);
            const double tineAmount = juce::jlimit(0.04, 0.34, 0.05 + preset.transient * 0.42 + preset.tone * 0.08);
            const double chorusDepth = juce::jlimit(0.0, 0.035, preset.detune + 0.006);

            if (style == 2)
            {
                const double swirl = std::sin(juce::MathConstants<double>::twoPi * ageSec * 5.2) * chorusDepth;
                const float drawbar1 = waveFromType(2, phaseA) * 0.42f;
                const float drawbar2 = waveFromType(2, phaseFor(frequencyHz * (2.0 + swirl))) * 0.24f;
                const float drawbar3 = waveFromType(2, phaseFor(frequencyHz * 3.0)) * 0.16f;
                const float drawbar4 = waveFromType(1, phaseFor(frequencyHz * (4.0 - swirl))) * 0.07f;
                const float leak = waveFromType(3, phaseFor(frequencyHz * 8.0)) * 0.03f;
                const float click = (float)((0.01 + preset.transient * 0.05) * std::exp(-72.0 * noteProgress) * noise(83));
                return (drawbar1 + drawbar2 + drawbar3 + drawbar4 + leak + click) *
                       (float)(brightness * juce::jlimit(0.72, 1.08, 0.86 + preset.tone * 0.22));
            }

            if (style == 3)
            {
                const float body = waveFromType(0, phaseA) * 0.34f;
                const float tine1 = waveFromType(0, phaseFor(frequencyHz * 2.0)) * 0.22f;
                const float tine2 = waveFromType(0, phaseFor(frequencyHz * (6.2 + preset.tone * 1.6))) * (float)tineAmount;
                const float bark = waveFromType(3, phaseFor(frequencyHz * (3.0 + chorusDepth * 9.0))) * 0.10f;
                const float chorus = waveFromType(0, phaseFor(frequencyHz * (1.0 + chorusDepth))) * 0.10f;
                const float thump = (float)((0.04 + preset.transient * 0.20) * std::exp(-34.0 * noteProgress) * noise(79));
                return (body + tine1 + tine2 + bark + chorus + thump) *
                       (float)(brightness * juce::jlimit(0.76, 1.18, 0.90 + preset.tone * 0.18));
            }

            if (style == 1)
            {
                const float body = waveFromType(0, phaseA) * 0.42f;
                const float felt = waveFromType(3, phaseFor(frequencyHz * 0.5) + 0.125) * (float)(0.14 + warmth * 0.10);
                const float reed = waveFromType(1, phaseFor(frequencyHz * 2.0)) * 0.12f;
                const float bloom = waveFromType(0, phaseFor(frequencyHz * (1.0 + chorusDepth))) * 0.14f;
                const float hammer = (float)((0.06 + preset.transient * 0.16) * std::exp(-30.0 * noteProgress) * noise(75));
                return (body + felt + reed + bloom + hammer) *
                       (float)(brightness * juce::jlimit(0.74, 1.12, 0.88 + warmth * 0.16));
            }

            const double inharmonic = 1.0 + juce::jlimit(0.0, 0.008, frequencyHz * 0.0000012 + preset.transient * 0.002);
            const float hammer = (float)((0.08 + preset.transient * 0.24) * std::exp(-34.0 * noteProgress) * noise(79));
            const float body = waveFromType(0, phaseA) * (float)(0.48 + warmth * 0.10);
            const float bloom = waveFromType(3, phaseFor(frequencyHz * 0.5) + 0.125) * (float)(0.06 + warmth * 0.10);
            const float second = waveFromType(0, phaseFor(frequencyHz * 2.0 * inharmonic)) * (float)(0.18 + preset.tone * 0.10);
            const float third = waveFromType(3, phaseFor(frequencyHz * 3.0 * inharmonic)) * (float)(0.06 + preset.drive * 0.14);
            const float tine = waveFromType(0, phaseFor(frequencyHz * (4.6 + preset.tone * 2.1))) * (float)tineAmount;
            return (body + bloom + second + third + tine + hammer) *
                   (float)(brightness * juce::jlimit(0.72, 1.14, 0.84 + preset.tone * 0.16));
        }
        case InstrumentFamily::brass:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            const double vibDepth = 0.0011 + envelope * (0.001 + style * 0.0003);
            const double vibRate = 4.8 + style * 0.5;
            const double vibrato = 1.0 + std::sin(juce::MathConstants<double>::twoPi * ageSec * vibRate) * vibDepth;
            const float saw = waveFromType(1, phaseFor(frequencyHz * vibrato)) * 0.48f;
            const float pulse = waveFromType(2, phaseFor(frequencyHz * 0.995 * vibrato)) * 0.35f;
            const float upper = waveFromType(style >= 2 ? 1 : 0, phaseFor(frequencyHz * 2.0 * vibrato)) * (0.15f + 0.03f * (float)style);
            const float breath = (float)((0.02 + preset.noise * 0.55) * std::exp(-7.0 * noteProgress) * noise(101));
            const float formantA = waveFromType(0, phaseFor(760.0 + style * 110.0)) * 0.07f;
            const float formantB = waveFromType(0, phaseFor(1320.0 + style * 140.0)) * 0.05f;
            return (saw + pulse + upper + breath + formantA + formantB) * (float)(brightness * (0.9 + envelope * 0.45));
        }
        case InstrumentFamily::wavetable:
        {
            const double modLfo = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.35);
            const double pd = wrapPhase(phaseA + 0.18 * std::sin(juce::MathConstants<double>::twoPi * phaseB + modLfo));
            const float main = (float)std::sin(juce::MathConstants<double>::twoPi * pd);
            const float upper = (float)std::sin(juce::MathConstants<double>::twoPi * pd * 2.0) * 0.33f;
            const float sparkle = waveFromType(1, pd * 1.5) * 0.22f;
            return (main + upper + sparkle) * (float)(brightness * (1.12 - noteProgress * 0.2));
        }
        case InstrumentFamily::harmonic:
        {
            const int style = juce::jlimit(0, 3, preset.oscillator);
            if (style == 3)
            {
                const double det = juce::jlimit(0.001, 0.018, preset.detune + 0.006);
                const double drift = std::sin(juce::MathConstants<double>::twoPi * ageSec * 0.18) * det;
                const double modA = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 1.5));
                const double modB = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 2.51));
                const double carrierA = wrapPhase(phaseA + modA * (0.035 + preset.tone * 0.05) + drift);
                const double carrierB = wrapPhase(phaseFor(frequencyHz * (1.0 + det)) + modB * (0.025 + preset.tone * 0.04) - drift);
                const float foundation = (float)std::sin(juce::MathConstants<double>::twoPi * carrierA) * 0.36f;
                const float bloom = (float)std::sin(juce::MathConstants<double>::twoPi * carrierB) * 0.24f;
                const float glass = (float)std::sin(2.0 * juce::MathConstants<double>::twoPi * carrierA) * 0.12f;
                const float sub = waveFromType(0, phaseFor(frequencyHz * 0.5)) * 0.10f;
                const float air = (float)((preset.noise * 0.16 + 0.01) * noise(111));
                return (foundation + bloom + glass + sub + air) *
                       (float)(brightness * juce::jlimit(0.72, 1.04, 0.80 + (1.0 - noteProgress) * 0.18));
            }

            const double modRatio = style == 0 ? 2.0 : style <= 1 ? 2.4
                                                                   : 3.0;
            const double modDepth = (style == 0 ? 0.09 : 0.05) + preset.tone * 0.13 + style * 0.02 + preset.transient * 0.04;
            const double mod = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * modRatio));
            const double carrier = wrapPhase(phaseA + mod * modDepth);
            const double p = juce::MathConstants<double>::twoPi * carrier;
            const float body = (float)std::sin(p) * 0.46f;
            const float even = (float)std::sin(2.0 * p) * 0.22f;
            const float odd = (float)std::sin(3.0 * p) * 0.16f;
            const float air = (float)std::sin(5.0 * p) * 0.08f;
            const float bell = (style == 0)
                                   ? (float)std::sin(6.0 * p) * (float)(0.06 + preset.transient * 0.16 + preset.tone * 0.04)
                                   : 0.0f;
            const float sheen = waveFromType(style == 0 ? 2 : 3, phaseB) * (style == 0 ? 0.09f : 0.12f);
            const float transient = (float)((0.02 + preset.transient * 0.12) * std::exp(-24.0 * noteProgress) * noise(111));
            return (body + even + odd + air + bell + sheen + transient) *
                   (float)(brightness * juce::jlimit(0.82, 1.16, 0.92 + (1.0 - noteProgress) * 0.22));
        }
        case InstrumentFamily::drum:
        {
            const int kitStyle = juce::jlimit(0, 3, preset.oscillator);
            const double kitBody = juce::jlimit(0.5, 1.2, 0.62 + preset.tone * 0.55);

            if (pitch <= 36)
            {
                const double extraDrop = (kitStyle == 0 ? 22.0 : kitStyle == 1 ? 12.0 : kitStyle == 2 ? 16.0
                                                                                                         : 14.0);
                const double curve = kitStyle == 0 ? 1.35 : 1.0;
                const double dropSemis = juce::jlimit(0.0, 36.0, preset.pitchDropSemitones + extraDrop);
                const double dropProgress = std::pow(1.0 - noteProgress, curve);
                const double ratio = std::pow(2.0, -(dropSemis * dropProgress) / 12.0);
                const double tunedFreq = juce::jlimit(24.0, 1400.0, frequencyHz * ratio);
                const float body = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(tunedFreq)) * (0.80f + 0.06f * (float)kitStyle);
                const float sub = waveFromType(0, phaseFor(tunedFreq * 0.5)) * (kitStyle == 0 ? 0.36f : 0.22f);
                const float click = (float)((0.07 + preset.transient * (0.34 + kitStyle * 0.07)) * std::exp(-40.0 * noteProgress) * noise(97));
                const float beater = (float)((kitStyle == 1 || kitStyle == 2 ? 0.08 : 0.03) *
                                             std::exp(-58.0 * noteProgress) *
                                             std::sin(juce::MathConstants<double>::twoPi * phaseFor(1700.0 + frequencyHz * 4.0)));
                return (body + sub + click + beater) * (float)(brightness * kitBody);
            }
            if (pitch <= 44)
            {
                const double toneMult = kitStyle == 0 ? 1.25 : kitStyle == 1 ? 1.6 : kitStyle == 2 ? 1.85
                                                                                                      : 1.45;
                const float toneA = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * toneMult)) *
                                    (float)std::exp(-8.0 * noteProgress) * 0.36f;
                const float toneB = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * toneMult * 1.72)) *
                                    (float)std::exp(-10.0 * noteProgress) * 0.20f;
                const float noiseBurst = (float)(noise(113) * std::exp(-(9.0 + kitStyle * 1.2) * noteProgress) *
                                                 (0.55 + 0.16 * kitStyle + preset.noise * 0.55));
                return (toneA + toneB + noiseBurst) * (float)(0.66 + brightness * 0.34);
            }
            if (pitch <= 52)
            {
                if (kitStyle == 1)
                {
                    const float rimTone = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * 3.2)) *
                                          (float)std::exp(-22.0 * noteProgress) * 0.34f;
                    const float rimSnap = (float)(noise(127) * std::exp(-26.0 * noteProgress) * 0.28);
                    return rimTone + rimSnap;
                }

                const double burst0 = std::exp(-95.0 * std::pow(noteProgress - 0.028, 2.0));
                const double burst1 = std::exp(-125.0 * std::pow(noteProgress - 0.068, 2.0));
                const double burst2 = std::exp(-165.0 * std::pow(noteProgress - 0.112, 2.0));
                const double clapEnv = juce::jlimit(0.0, 1.0, burst0 + burst1 + burst2);
                const double tail = std::exp(-(10.0 + kitStyle * 1.5) * noteProgress);
                return (float)(noise(127) * (clapEnv * 0.78 + tail * 0.22));
            }
            if (pitch <= 63)
            {
                const double tomMul = kitStyle == 0 ? 0.85 : kitStyle == 1 ? 1.0 : kitStyle == 2 ? 1.18
                                                                                                    : 0.95;
                const double tomFreq = juce::jlimit(70.0, 900.0, frequencyHz * tomMul);
                const float tone = (float)std::sin(juce::MathConstants<double>::twoPi * phaseFor(tomFreq)) *
                                   (float)std::exp(-6.5 * noteProgress) * 0.56f;
                const float ring = waveFromType(3, phaseFor(tomFreq * 1.6)) *
                                   (float)std::exp(-8.5 * noteProgress) * 0.24f;
                const float stick = (float)((0.03 + preset.transient * 0.14) *
                                            std::exp(-42.0 * noteProgress) * noise(141));
                return (tone + ring + stick) * (float)(0.72 + brightness * 0.28);
            }

            const double hatDecay = kitStyle == 0 ? 14.0 : kitStyle == 1 ? 18.0 : kitStyle == 2 ? 16.0
                                                                                                  : 11.0;
            const float noiseTone = (float)(noise(149) * std::exp(-hatDecay * noteProgress));
            const float metallic = waveFromType(2, phaseFor(6400.0 + kitStyle * 750.0)) * 0.23f +
                                   waveFromType(1, phaseFor(8900.0 + kitStyle * 980.0)) * 0.16f;
            const float air = waveFromType(0, phaseFor(12000.0 + kitStyle * 400.0)) * 0.06f;
            return (noiseTone + metallic + air) * (float)(0.64 + brightness * 0.36);
        }
        case InstrumentFamily::basic:
        default:
        {
            const float main = waveFromType(preset.oscillator, phaseA);
            const float sub = waveFromType(0, phaseFor(frequencyHz * 0.5)) * 0.30f;
            const float second = waveFromType(0, phaseFor(frequencyHz * 2.0)) * 0.12f;
            const float n = (float)(preset.noise * noise(11));
            return (main * 0.72f + sub + second + n) * (float)(brightness * (0.75 + preset.tone * 0.25));
        }
        }
    }

    double getTempoPlaybackRatio() const
    {
        return juce::jlimit(0.05, 20.0,
                            tempoPlaybackRatio.load(std::memory_order_relaxed));
    }

    void applyPendingLiveMidiEvents()
    {
        std::vector<LiveMidiEvent> pending;
        {
            const juce::ScopedLock lock(liveStateLock);
            if (pendingLiveMidiEvents.empty())
                return;
            pending.swap(pendingLiveMidiEvents);
        }

        const bool sampledMode =
            cachedPreset.family == InstrumentFamily::sampled &&
            cachedSampledDefinition != nullptr &&
            !cachedSampledDefinition->regions.empty();
        const double attackSec = juce::jmax(0.001, cachedPreset.attackMs / 1000.0);
        const double decaySec = juce::jmax(0.001, cachedPreset.decayMs / 1000.0);
        const double sustainLevel = juce::jlimit(0.05, 1.0, cachedPreset.sustainLevel);

        for (const auto &event : pending)
        {
            if (event.noteOn && event.velocity > 0.0f)
            {
                ActiveLiveNote voice;
                voice.channel = juce::jlimit(1, 16, event.channel);
                voice.pitch = juce::jlimit(0, 127, event.pitch);
                voice.velocity = juce::jlimit(0.0, 1.0, (double)event.velocity);
                voice.ageSec = 0.0;
                voice.releasing = false;
                voice.releaseAgeSec = 0.0;
                voice.releaseStartLevel = 1.0;
                voice.seedBase = voice.pitch * 97 + voice.channel * 29 + (int)std::lround(voice.velocity * 1000.0);

                if (sampledMode)
                {
                    const int sampledPitch =
                        sampledMidiPitchForInstrument(cachedInstrumentId, voice.pitch);
                    const int midiVelocity = juce::jlimit(
                        0,
                        127,
                        (int)std::lround(voice.velocity * 127.0));
                    const SampledRegion *region = pickSampledRegion(
                        *cachedSampledDefinition,
                        sampledPitch,
                        midiVelocity,
                        voice.seedBase);
                    if (region == nullptr || !isSampledRegionReady(*region))
                        continue;

                    voice.sampledMidiPitch = sampledPitch;
                    voice.sampledSource = region->sample;
                    voice.sampledKeyCenter = region->keyCenter;
                    voice.sampledGainLinear = region->gainLinear;
                    voice.sampledAttackSec = region->attackSec;
                    voice.sampledReleaseSec = region->releaseSec;
                    voice.sampledPitchKeytrack = region->pitchKeytrack;
                    voice.sampledPitchOffsetSemitones =
                        region->pitchOffsetSemitones;
                    voice.sampledStartFrame = region->sampleStartFrame;
                    voice.sampledEndFrameExclusive =
                        region->sampleEndFrameExclusive;
                    voice.sampledOneShot = region->oneShot;
                }

                activeLiveNotes.push_back(voice);
                if (activeLiveNotes.size() > 256)
                {
                    activeLiveNotes.erase(
                        activeLiveNotes.begin(),
                        activeLiveNotes.begin() +
                            (std::ptrdiff_t)(activeLiveNotes.size() - 256));
                }
                continue;
            }

            for (auto it = activeLiveNotes.rbegin(); it != activeLiveNotes.rend(); ++it)
            {
                if (it->channel != event.channel || it->pitch != event.pitch || it->releasing)
                    continue;

                it->releasing = true;
                it->releaseAgeSec = 0.0;
                const double voiceAttackSec =
                    (sampledMode && it->sampledSource != nullptr &&
                     !cachedSampledAttackOverride)
                        ? juce::jmax(0.001, it->sampledAttackSec)
                        : attackSec;
                it->releaseStartLevel = envelopeHoldLevel(
                    it->ageSec,
                    voiceAttackSec,
                    decaySec,
                    sustainLevel);
                break;
            }
        }
    }

    void refreshCachedState()
    {
        const int version = pendingVersion.load(std::memory_order_relaxed);
        if (version == cachedVersion)
            return;

        PendingState local;
        {
            const juce::ScopedLock lock(stateLock);
            local = pendingState;
            cachedVersion = pendingVersion.load(std::memory_order_relaxed);
        }

        cachedNotes.clear();
        cachedNotes.reserve((size_t)local.notes.size());
        for (const auto &note : local.notes)
        {
            TimelineMidiNote n;
            n.pitch = juce::jlimit(0, 127, note.pitch);
            n.startBeat = juce::jmax(0.0, note.startBeat);
            n.lengthBeats = juce::jmax(0.03125, note.lengthBeats);
            n.velocity = juce::jlimit(0.0, 1.0, note.velocity);
            cachedNotes.push_back(n);
        }

        cachedPreset = local.preset;
        cachedSampledDefinition = local.sampledDefinition;
        cachedSampledAttackOverride = local.sampledAttackOverride;
        cachedSampledReleaseOverride = local.sampledReleaseOverride;
        cachedSourceTempoBpm = local.sourceTempoBpm;
        activeTimelineNotes.clear();
    }

    static juce::CriticalSection &flutterAssetRootLock()
    {
        static juce::CriticalSection lock;
        return lock;
    }

    static juce::String &flutterAssetRoot()
    {
        static juce::String root;
        return root;
    }

    std::atomic<double> *blockTransportStartSec = nullptr;
    std::atomic<double> *hostSampleRate = nullptr;
    std::atomic<bool> *isPlaying = nullptr;

    std::atomic<double> clipStartSec{0.0};
    std::atomic<double> clipLengthSec{0.0};
    std::atomic<double> fileOffsetSec{0.0};
    std::atomic<float> pitchSemitones{0.0f};
    std::atomic<double> tempoPlaybackRatio{1.0};
    std::atomic<bool> preserveTempoPitch{false};
    std::atomic<bool> muted{false};
    std::atomic<double> playheadSec{0.0};
    std::atomic<float> panValue{0.0f};

    juce::CriticalSection stateLock;
    juce::CriticalSection liveStateLock;
    PendingState pendingState;
    std::atomic<int> pendingVersion{1};
    int cachedVersion = 0;
    std::vector<LiveMidiEvent> pendingLiveMidiEvents;
    std::vector<ActiveLiveNote> activeLiveNotes;
    std::unordered_set<size_t> activeTimelineNotes;
    std::atomic<double> steadyBlockStartSec{
        std::numeric_limits<double>::quiet_NaN()};
    std::atomic<bool> steadyWasPlaying{false};

    std::vector<TimelineMidiNote> cachedNotes;
    InstrumentPreset cachedPreset;
    std::shared_ptr<const SampledDefinition> cachedSampledDefinition;
    bool cachedSampledAttackOverride = false;
    bool cachedSampledReleaseOverride = false;
    double cachedSourceTempoBpm = 120.0;
};
