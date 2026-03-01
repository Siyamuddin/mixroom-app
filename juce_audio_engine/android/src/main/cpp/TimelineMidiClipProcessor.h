#pragma once

#include "JuceHeader.h"

#include <array>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <regex>
#include <unordered_map>
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

        const double blockStart = playheadSec.load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;

        refreshCachedState();
        applyPendingLiveMidiEvents();

        const bool sampledMode =
            cachedPreset.family == InstrumentFamily::sampled &&
            cachedSampledDefinition != nullptr &&
            !cachedSampledDefinition->regions.empty();
        const double attackSec = juce::jmax(0.001, cachedPreset.attackMs / 1000.0);
        const double releaseSec = juce::jmax(0.02, cachedPreset.releaseMs / 1000.0);
        const float driveGain =
            sampledMode ? 1.0f : (float)(1.0 + cachedPreset.drive * 5.0);
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
                    std::vector<const SampledRegion *> timelineRegions;
                    if (sampledMode)
                    {
                        timelineRegions.reserve(cachedNotes.size());
                        for (const auto &note : cachedNotes)
                        {
                            const int midiVelocity = juce::jlimit(
                                0,
                                127,
                                (int)std::lround(
                                    juce::jlimit(0.0, 1.0, note.velocity) * 127.0));
                            timelineRegions.push_back(
                                pickSampledRegion(
                                    *cachedSampledDefinition,
                                    juce::jlimit(0, 127, note.pitch),
                                    midiVelocity));
                        }
                    }

                    for (int i = 0; i < framesToRender; ++i)
                    {
                        const double timelineSec = startTimelineSec + ((double)i / sr);
                        const double sourceSec = ((timelineSec - cs) * safeRatio) + inFile;
                        float mixL = 0.0f;
                        float mixR = 0.0f;

                        for (size_t noteIndex = 0; noteIndex < cachedNotes.size(); ++noteIndex)
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

                            double env = 0.0;
                            if (ageRealSec < noteAttackSec)
                                env = ageRealSec / noteAttackSec;
                            else if (ageRealSec < noteLengthRealSec)
                                env = 1.0;
                            else
                                env = 1.0 - ((ageRealSec - noteLengthRealSec) / noteReleaseSec);

                            if (env <= 0.0)
                                continue;

                            const double totalRealSec = juce::jmax(
                                0.001, noteLengthRealSec + noteReleaseSec);
                            const double noteProgress = juce::jlimit(0.0, 1.0, ageRealSec / totalRealSec);

                            double notePitch = (double)note.pitch + (double)pitchSemitones.load(std::memory_order_relaxed);
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
                    env = (voice.ageSec < voiceAttackSec)
                              ? (voice.ageSec / voiceAttackSec)
                              : 1.0;
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
                    float sampleL = 0.0f;
                    float sampleR = 0.0f;
                    if (!renderSampledStereo(
                            voice.sampledSource,
                            voice.sampledKeyCenter,
                            notePitch,
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
        std::shared_ptr<const DecodedSamplePcm> sample;
        int loKey = 0;
        int hiKey = 127;
        int keyCenter = 60;
        int loVel = 0;
        int hiVel = 127;
        double gainLinear = 1.0;
        double attackSec = 0.005;
        double releaseSec = 0.35;
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
        int sampledKeyCenter = 60;
        double sampledGainLinear = 1.0;
        double sampledAttackSec = 0.005;
        double sampledReleaseSec = 0.35;
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

    static double wrapPhase(double phase)
    {
        phase -= std::floor(phase);
        if (phase < 0.0)
            phase += 1.0;
        return phase;
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
        while (path.startsWithChar('/'))
            path = path.substring(1);
        return path;
    }

    static juce::File resolveFlutterAssetFile(const juce::String &assetPathRaw)
    {
        const juce::String raw = assetPathRaw.trim();
        if (raw.isNotEmpty())
        {
            const juce::File direct(raw);
            if (direct.existsAsFile())
                return direct;
        }

        const juce::String assetPath = normalizeAssetPath(assetPathRaw);
        if (assetPath.isEmpty())
            return {};

        {
            const juce::ScopedLock lock(flutterAssetRootLock());
            const juce::String rootPath = flutterAssetRoot();
            if (rootPath.isNotEmpty())
            {
                const juce::File root(rootPath);
                const juce::File rootDirect = root.getChildFile(assetPath);
                if (rootDirect.existsAsFile())
                    return rootDirect;

                const juce::File nested = root.getChildFile("flutter_assets")
                                              .getChildFile(assetPath);
                if (nested.existsAsFile())
                    return nested;
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
            const auto direct = root.getChildFile(assetPath);
            if (direct.existsAsFile())
                return direct;

            const auto nested = root.getChildFile("flutter_assets")
                                    .getChildFile(assetPath);
            if (nested.existsAsFile())
                return nested;
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

    static double readSfzNumeric(const SfzOpcodeMap &values,
                                 const char *key,
                                 double fallback)
    {
        const juce::String raw = opcodeValue(values, key).trim();
        if (raw.isEmpty())
            return fallback;
        const double parsed = raw.getDoubleValue();
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
            return nullptr;

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
            return nullptr;

        const juce::String sfzText = sfzFile.loadFileAsString();
        if (sfzText.isEmpty())
            return nullptr;

        SfzOpcodeMap control;
        SfzOpcodeMap global;
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

            if (line.startsWithChar('<') && line.endsWithChar('>') &&
                line.length() >= 3)
            {
                const juce::String tag =
                    line.substring(1, line.length() - 1).trim().toLowerCase();
                currentBlock = tag;
                if (tag == "group")
                {
                    group.clear();
                }
                else if (tag == "region")
                {
                    rawRegions.emplace_back();
                    region = &rawRegions.back();
                    mergeOpcodeMap(*region, control);
                    mergeOpcodeMap(*region, global);
                    mergeOpcodeMap(*region, group);
                }
                continue;
            }

            const auto opcodes = parseSfzOpcodes(line);
            if (opcodes.empty())
                continue;

            if (currentBlock == "control")
                mergeOpcodeMap(control, opcodes);
            else if (currentBlock == "global")
                mergeOpcodeMap(global, opcodes);
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
            auto sample = decodedSampleForAsset(sampleAssetPath);
            if (sample == nullptr || sample->frameCount() < 2)
                continue;

            SampledRegion regionDef;
            regionDef.sample = sample;
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
            definition->regions.push_back(regionDef);
        }

        if (definition->regions.empty())
            return nullptr;

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

        static const std::unordered_map<std::string, std::string> knownMap = {
            {"sfz.vsco.violin_ens_sus_vib", "assets/instruments/VSCO-2-CE-1.1.0/ViolinEnsSusVib.sfz"},
            {"sfz.vsco.cello_ens_sus_vib", "assets/instruments/VSCO-2-CE-1.1.0/CelloEnsSusVib.sfz"},
            {"sfz.vsco.trumpet_sus", "assets/instruments/VSCO-2-CE-1.1.0/TrumpetSus.sfz"},
            {"sfz.vsco.fhorn_sus", "assets/instruments/VSCO-2-CE-1.1.0/FHornSus.sfz"},
            {"sfz.vsco.flute_sus_vib", "assets/instruments/VSCO-2-CE-1.1.0/FluteSusVib.sfz"},
            {"sfz.vsco.clarinet_sus", "assets/instruments/VSCO-2-CE-1.1.0/ClarinetSus.sfz"},
            {"sfz.vsco.organ_quiet", "assets/instruments/VSCO-2-CE-1.1.0/OrganQuiet.sfz"},
            {"sfz.vsco.organ_loud", "assets/instruments/VSCO-2-CE-1.1.0/OrganLoud.sfz"},
            {"sfz.vsco.marimba", "assets/instruments/VSCO-2-CE-1.1.0/Marimba.sfz"},
            {"sfz.vsco.glockenspiel", "assets/instruments/VSCO-2-CE-1.1.0/Glockenspiel.sfz"},
        };
        if (auto found = knownMap.find(id.toStdString()); found != knownMap.end())
            return found->second.c_str();

        const juce::String text = (id + " " + instrumentName.toLowerCase());
        auto contains = [&](const char *needle) { return text.contains(needle); };
        if (contains("violin"))
            return "assets/instruments/VSCO-2-CE-1.1.0/ViolinEnsSusVib.sfz";
        if (contains("cello"))
            return "assets/instruments/VSCO-2-CE-1.1.0/CelloEnsSusVib.sfz";
        if (contains("trumpet"))
            return "assets/instruments/VSCO-2-CE-1.1.0/TrumpetSus.sfz";
        if (contains("horn"))
            return "assets/instruments/VSCO-2-CE-1.1.0/FHornSus.sfz";
        if (contains("flute"))
            return "assets/instruments/VSCO-2-CE-1.1.0/FluteSusVib.sfz";
        if (contains("clarinet"))
            return "assets/instruments/VSCO-2-CE-1.1.0/ClarinetSus.sfz";
        if (contains("organ quiet"))
            return "assets/instruments/VSCO-2-CE-1.1.0/OrganQuiet.sfz";
        if (contains("organ"))
            return "assets/instruments/VSCO-2-CE-1.1.0/OrganLoud.sfz";
        if (contains("marimba"))
            return "assets/instruments/VSCO-2-CE-1.1.0/Marimba.sfz";
        if (contains("glock"))
            return "assets/instruments/VSCO-2-CE-1.1.0/Glockenspiel.sfz";
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

    static const SampledRegion *pickSampledRegion(const SampledDefinition &definition,
                                                  int pitch,
                                                  int velocity)
    {
        const SampledRegion *best = nullptr;
        int bestKeyDistance = std::numeric_limits<int>::max();
        int bestVelDistance = std::numeric_limits<int>::max();

        auto consider = [&](const SampledRegion &region, bool enforceVelocity)
        {
            if (pitch < region.loKey || pitch > region.hiKey)
                return;
            if (enforceVelocity && (velocity < region.loVel || velocity > region.hiVel))
                return;

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
        };

        for (const auto &region : definition.regions)
            consider(region, true);
        if (best != nullptr)
            return best;
        for (const auto &region : definition.regions)
            consider(region, false);
        return best;
    }

    static bool renderSampledStereo(
        const std::shared_ptr<const DecodedSamplePcm> &sample,
        int keyCenter,
        double notePitch,
        double ageSec,
        double outputSampleRate,
        float &outL,
        float &outR)
    {
        outL = 0.0f;
        outR = 0.0f;
        if (sample == nullptr || outputSampleRate <= 0.0 || ageSec < 0.0)
            return false;

        const auto &pcm = *sample;
        const int frameCount = pcm.frameCount();
        if (frameCount < 2)
            return false;

        const double semitoneOffset = notePitch - (double)keyCenter;
        const double playbackRate =
            std::pow(2.0, semitoneOffset / 12.0) *
            ((double)pcm.sampleRate / outputSampleRate);
        if (!std::isfinite(playbackRate) || playbackRate <= 0.0)
            return false;

        const double samplePos = ageSec * outputSampleRate * playbackRate;
        if (samplePos < 0.0 || samplePos >= (double)(frameCount - 1))
            return false;

        const int index = (int)std::floor(samplePos);
        const int nextIndex = juce::jmin(index + 1, frameCount - 1);
        const double frac = samplePos - (double)index;

        const float l0 = pcm.left[(size_t)index];
        const float l1 = pcm.left[(size_t)nextIndex];
        const float r0 = pcm.right[(size_t)index];
        const float r1 = pcm.right[(size_t)nextIndex];
        outL = juce::jlimit(-1.0f, 1.0f, (float)(l0 + (l1 - l0) * frac));
        outR = juce::jlimit(-1.0f, 1.0f, (float)(r0 + (r1 - r0) * frac));
        return true;
    }

    static bool renderSampledStereo(const SampledRegion &region,
                                    double notePitch,
                                    double ageSec,
                                    double outputSampleRate,
                                    float &outL,
                                    float &outR)
    {
        return renderSampledStereo(
            region.sample,
            region.keyCenter,
            notePitch,
            ageSec,
            outputSampleRate,
            outL,
            outR);
    }

    static const std::unordered_map<std::string, InstrumentPreset> &presetMap()
    {
        static const std::unordered_map<std::string, InstrumentPreset> map = {
            {"mixroom.basic_synth", {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02}},
            {"mixroom.bass_mono", {InstrumentFamily::bass, 2, 1200.0, 8.0, 220.0, 0.28, 0.34, 0.001, 0.04, 0.52, 0.18, 4.0, 0.04}},
            {"mixroom.soft_pad", {InstrumentFamily::pad, 3, 2100.0, 80.0, 620.0, 0.02, 0.31, 0.012, 0.28, 0.47, 0.04, 0.0, 0.03}},
            {"mixroom.figbug_wavetable", {InstrumentFamily::wavetable, 1, 5200.0, 6.0, 240.0, 0.18, 0.33, 0.006, 0.16, 0.72, 0.14, 0.0, 0.03}},
            {"mixroom.sarah_harmonic", {InstrumentFamily::harmonic, 3, 2800.0, 34.0, 540.0, 0.1, 0.32, 0.008, 0.20, 0.54, 0.08, 0.0, 0.03}},
            {"mixroom.vanilla_poly", {InstrumentFamily::keys, 0, 3600.0, 12.0, 260.0, 0.05, 0.33, 0.004, 0.13, 0.58, 0.10, 0.0, 0.02}},
            {"mixroom.duck_synth", {InstrumentFamily::bass, 2, 1600.0, 2.0, 140.0, 0.26, 0.35, 0.002, 0.06, 0.62, 0.20, 8.0, 0.03}},
            {"mixroom.chow_kick", {InstrumentFamily::drum, 0, 900.0, 0.0, 90.0, 0.42, 0.42, 0.0, 0.0, 0.52, 0.40, 16.0, 0.14}},
            {"mixroom.warm_keys", {InstrumentFamily::keys, 0, 3000.0, 14.0, 320.0, 0.06, 0.32, 0.005, 0.12, 0.52, 0.12, 0.0, 0.02}},
            {"mixroom.super_saw", {InstrumentFamily::lead, 1, 6200.0, 4.0, 180.0, 0.22, 0.34, 0.01, 0.20, 0.75, 0.11, 0.0, 0.03}},
            {"mixroom.gentle_pluck", {InstrumentFamily::pluck, 3, 4800.0, 2.0, 130.0, 0.08, 0.33, 0.004, 0.11, 0.68, 0.24, 0.0, 0.03}},
            {"mixroom.sub_bass", {InstrumentFamily::bass, 2, 900.0, 3.0, 200.0, 0.24, 0.35, 0.001, 0.03, 0.46, 0.12, 5.0, 0.03}},
            {"mixroom.analog_brass", {InstrumentFamily::brass, 1, 2600.0, 25.0, 300.0, 0.14, 0.33, 0.003, 0.12, 0.55, 0.08, 0.0, 0.02}},
            {"mixroom.drum_acoustic_easy", {InstrumentFamily::drum, 1, 2300.0, 0.0, 120.0, 0.18, 0.41, 0.0, 0.0, 0.52, 0.26, 10.0, 0.15}},
            {"mixroom.drum_808_starter", {InstrumentFamily::drum, 0, 1100.0, 0.0, 190.0, 0.36, 0.44, 0.0, 0.0, 0.60, 0.35, 24.0, 0.18}},
            {"mixroom.drum_lofi", {InstrumentFamily::drum, 3, 1700.0, 1.0, 150.0, 0.28, 0.41, 0.0, 0.0, 0.45, 0.20, 12.0, 0.20}},
            {"mixroom.drum_house", {InstrumentFamily::drum, 1, 2600.0, 0.0, 95.0, 0.24, 0.42, 0.0, 0.0, 0.58, 0.28, 14.0, 0.17}},
            {"mixroom.night_bell", {InstrumentFamily::harmonic, 0, 5600.0, 1.0, 540.0, 0.06, 0.30, 0.002, 0.22, 0.76, 0.16, 0.0, 0.01}},
            {"mixroom.fm_keys", {InstrumentFamily::harmonic, 0, 4100.0, 5.0, 340.0, 0.07, 0.32, 0.004, 0.14, 0.66, 0.14, 0.0, 0.02}},
            {"mixroom.vintage_strings", {InstrumentFamily::pad, 1, 2400.0, 32.0, 640.0, 0.08, 0.31, 0.015, 0.24, 0.50, 0.07, 0.0, 0.02}},
            {"mixroom.neo_brass", {InstrumentFamily::brass, 1, 3100.0, 16.0, 250.0, 0.15, 0.33, 0.004, 0.14, 0.61, 0.08, 0.0, 0.02}},
            {"mixroom.reese_bass", {InstrumentFamily::bass, 1, 1300.0, 4.0, 200.0, 0.26, 0.35, 0.015, 0.08, 0.57, 0.16, 5.0, 0.05}},
            {"mixroom.air_pluck", {InstrumentFamily::pluck, 3, 5200.0, 1.0, 210.0, 0.08, 0.33, 0.008, 0.14, 0.72, 0.20, 0.0, 0.05}},
            {"mixroom.cinematic_pad", {InstrumentFamily::pad, 3, 1900.0, 95.0, 760.0, 0.05, 0.30, 0.018, 0.30, 0.44, 0.05, 0.0, 0.03}},
            {"mixroom.velvet_ep", {InstrumentFamily::keys, 0, 3700.0, 7.0, 380.0, 0.07, 0.32, 0.005, 0.16, 0.66, 0.18, 0.0, 0.02}},
            {"mixroom.house_organ", {InstrumentFamily::keys, 2, 3400.0, 0.0, 210.0, 0.11, 0.33, 0.003, 0.10, 0.62, 0.12, 0.0, 0.02}},
            {"mixroom.glass_pluck", {InstrumentFamily::pluck, 3, 5600.0, 1.0, 170.0, 0.09, 0.33, 0.007, 0.14, 0.74, 0.24, 0.0, 0.03}},
            {"mixroom.neon_lead", {InstrumentFamily::lead, 1, 6400.0, 3.0, 210.0, 0.24, 0.34, 0.012, 0.18, 0.78, 0.13, 0.0, 0.03}},
            {"mixroom.mellow_sub", {InstrumentFamily::bass, 2, 980.0, 4.0, 260.0, 0.19, 0.35, 0.001, 0.04, 0.42, 0.10, 3.0, 0.02}},
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
            const float sub = waveFromType(0, phaseFor(frequencyHz * 0.5)) * 0.66f;
            const float body = waveFromType(2, phaseA) * 0.52f;
            const float growl = waveFromType(1, phaseA * 1.01) * 0.20f;
            const float transient = (float)((0.05 + preset.transient * 0.22) * std::exp(-24.0 * noteProgress) * noise(17));
            return (sub + body + growl + transient) * (float)(brightness * (1.25 - noteProgress * 0.45));
        }
        case InstrumentFamily::pad:
        {
            const double det = juce::jlimit(0.001, 0.03, preset.detune + 0.008);
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

            if (style == 2)
            {
                const float fundamental = waveFromType(2, phaseA) * 0.48f;
                const float octave = waveFromType(2, phaseFor(frequencyHz * 2.0)) * 0.28f;
                const float twelfth = waveFromType(2, phaseFor(frequencyHz * 3.0)) * 0.16f;
                const float chorus = waveFromType(1, phaseFor(frequencyHz * (2.0 + preset.detune * 14.0 + 0.011))) * 0.11f;
                const float click = (float)((0.04 + preset.transient * 0.18) * std::exp(-52.0 * noteProgress) * noise(83));
                return (fundamental + octave + twelfth + chorus + click) * (float)(brightness * keyOpen);
            }

            const double inharmonic = 1.0 + juce::jlimit(0.0, 0.005, (double)pitch * 0.00005);
            const float hammer = (float)((0.09 + preset.transient * 0.30) * std::exp(-36.0 * noteProgress) * noise(79));
            const float body = waveFromType(0, phaseA) * 0.58f;
            const float second = waveFromType(0, phaseFor(frequencyHz * 2.0 * inharmonic)) * 0.26f;
            const float third = waveFromType(style == 1 ? 1 : 0, phaseFor(frequencyHz * 3.0 * inharmonic)) * 0.15f;
            const float tine = waveFromType(style == 3 ? 3 : 0, phaseFor(frequencyHz * (4.8 + style * 0.5))) * 0.11f;
            return (body + second + third + tine + hammer) * (float)(brightness * keyOpen);
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
            const double modRatio = style <= 1 ? 2.0 : 3.0;
            const double modDepth = 0.05 + preset.tone * 0.13 + style * 0.02;
            const double mod = std::sin(juce::MathConstants<double>::twoPi * phaseFor(frequencyHz * modRatio));
            const double carrier = wrapPhase(phaseA + mod * modDepth);
            const double p = juce::MathConstants<double>::twoPi * carrier;
            const float body = (float)std::sin(p) * 0.50f;
            const float even = (float)std::sin(2.0 * p) * 0.26f;
            const float odd = (float)std::sin(3.0 * p) * 0.18f;
            const float air = (float)std::sin(5.0 * p) * 0.10f;
            const float sheen = waveFromType(style == 3 ? 1 : 3, phaseB) * 0.12f;
            const float transient = (float)((0.02 + preset.transient * 0.12) * std::exp(-24.0 * noteProgress) * noise(111));
            return (body + even + odd + air + sheen + transient) * (float)(brightness * (0.92 + (1.0 - noteProgress) * 0.22));
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
                    const int midiVelocity = juce::jlimit(
                        0,
                        127,
                        (int)std::lround(voice.velocity * 127.0));
                    const SampledRegion *region = pickSampledRegion(
                        *cachedSampledDefinition,
                        voice.pitch,
                        midiVelocity);
                    if (region == nullptr || region->sample == nullptr)
                        continue;

                    voice.sampledSource = region->sample;
                    voice.sampledKeyCenter = region->keyCenter;
                    voice.sampledGainLinear = region->gainLinear;
                    voice.sampledAttackSec = region->attackSec;
                    voice.sampledReleaseSec = region->releaseSec;
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
                it->releaseStartLevel = 1.0;
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

    std::vector<TimelineMidiNote> cachedNotes;
    InstrumentPreset cachedPreset;
    std::shared_ptr<const SampledDefinition> cachedSampledDefinition;
    bool cachedSampledAttackOverride = false;
    bool cachedSampledReleaseOverride = false;
    double cachedSourceTempoBpm = 120.0;
};
