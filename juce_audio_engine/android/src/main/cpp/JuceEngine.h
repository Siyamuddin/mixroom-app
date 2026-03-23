#pragma once

#include "JuceHeader.h"
#include "SimpleGainProcessor.h"
#include "NativeEffects.h"
#include "JuceLogBridge.h"

#include <array>
#include <atomic>
#include <algorithm>
#include <cstddef>
#include <cmath>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <regex>
#include <unordered_map>
#include <vector>

extern "C" void juceLogToFlutter(const char *msg);

class MetronomeAudioCallback;

// ---------------------------
// Helper: simple stereo pan
// ---------------------------
class StereoPanProcessor : public juce::AudioProcessor
{
public:
    StereoPanProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
        addParameter(pan = new juce::AudioParameterFloat(
                         "pan", "Pan",
                         -1.0f, 1.0f, 0.0f)); // -1 = L, 0 = C, 1 = R
    }

    const juce::String getName() const override { return "StereoPanProcessor"; }

    void prepareToPlay(double sampleRate, int samplesPerBlockExpected) override {}

    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &) override
    {
        const int numChannels = buffer.getNumChannels();
        const int numSamples = buffer.getNumSamples();
        if (numChannels < 2)
            return;

        // Stereo balance law with unity center:
        // p = -1 -> full left, p = 0 -> center (L=1,R=1), p = +1 -> full right.
        // This avoids cumulative -3 dB center drops when multiple pan stages are chained.
        const float p = juce::jlimit(-1.0f, 1.0f, pan->get()); // -1..1
        const float leftGain = (p <= 0.0f) ? 1.0f : (1.0f - p);
        const float rightGain = (p >= 0.0f) ? 1.0f : (1.0f + p);

        auto *left = buffer.getWritePointer(0);
        auto *right = buffer.getWritePointer(1);

        for (int i = 0; i < numSamples; ++i)
        {
            const float l = left[i];
            const float r = right[i];
            left[i] = l * leftGain;
            right[i] = r * rightGain;
        }
    }

    // Boilerplate
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Allow mono or stereo, but they must match
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

    juce::AudioParameterFloat *pan = nullptr;
};

class MeterTapProcessor : public juce::AudioProcessor
{
public:
    explicit MeterTapProcessor(std::atomic<float> *pL,
                               std::atomic<float> *pR,
                               std::atomic<float> *rL,
                               std::atomic<float> *rR,
                               std::atomic<bool> *enabledFlag)
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          peakL(pL), peakR(pR), rmsL(rL), rmsR(rR), enabled(enabledFlag)
    {
    }

    const juce::String getName() const override { return "MeterTapProcessor"; }
    void prepareToPlay(double, int) override {}
    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        if (enabled && !enabled->load(std::memory_order_relaxed))
            return;

        const int numCh = buffer.getNumChannels();
        const int numSamples = buffer.getNumSamples();
        if (numCh <= 0 || numSamples <= 0)
            return;

        const float *L = buffer.getReadPointer(0);
        const float *R = numCh > 1 ? buffer.getReadPointer(1) : L;

        float pkL = 0.0f, pkR = 0.0f;
        double ssL = 0.0, ssR = 0.0;

        for (int i = 0; i < numSamples; ++i)
        {
            const float l = L[i];
            const float r = R[i];
            const float al = std::abs(l);
            const float ar = std::abs(r);

            if (al > pkL)
                pkL = al;
            if (ar > pkR)
                pkR = ar;

            ssL += (double)l * (double)l;
            ssR += (double)r * (double)r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)numSamples);
        const float rmR = (float)std::sqrt(ssR / (double)numSamples);

        // smoothing (slightly slower than your master, looks nicer in mini meters)
        constexpr float alpha = 0.18f;
        auto smooth = [](float prev, float next)
        { return prev + alpha * (next - prev); };

        if (peakL && peakR && rmsL && rmsR)
        {
            const float prevPkL = peakL->load(std::memory_order_relaxed);
            const float prevPkR = peakR->load(std::memory_order_relaxed);
            const float prevRmL = rmsL->load(std::memory_order_relaxed);
            const float prevRmR = rmsR->load(std::memory_order_relaxed);

            peakL->store(smooth(prevPkL, pkL), std::memory_order_relaxed);
            peakR->store(smooth(prevPkR, pkR), std::memory_order_relaxed);
            rmsL->store(smooth(prevRmL, rmL), std::memory_order_relaxed);
            rmsR->store(smooth(prevRmR, rmR), std::memory_order_relaxed);
        }
    }

    void setMeterTargets(std::atomic<float> *pL,
                         std::atomic<float> *pR,
                         std::atomic<float> *rL,
                         std::atomic<float> *rR)
    {
        peakL = pL;
        peakR = pR;
        rmsL = rL;
        rmsR = rR;
    }

    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        const auto in = layouts.getMainInputChannelSet();
        const auto out = layouts.getMainOutputChannelSet();
        return in == out &&
               (in == juce::AudioChannelSet::mono() ||
                in == juce::AudioChannelSet::stereo());
    }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

private:
    std::atomic<float> *peakL = nullptr;
    std::atomic<float> *peakR = nullptr;
    std::atomic<float> *rmsL = nullptr;
    std::atomic<float> *rmsR = nullptr;
    std::atomic<bool> *enabled = nullptr;
};

// ---------------------------
// Helper: volume automation
// ---------------------------
struct AutomationPoint
{
    double timeMs = 0.0; // X value in milliseconds
    float value = 0.75f; // Y value (0.0 – 1.0 gain) (0.75 = unity-ish)
};

class VolumeAutomationProcessor : public juce::AudioProcessor
{
public:
    VolumeAutomationProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
    }
    ~VolumeAutomationProcessor() override = default;

    //==============================================================================
    const juce::String getName() const override { return "VolumeAutomationProcessor"; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    //==============================================================================
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    //==============================================================================
    void prepareToPlay(double sampleRate, int /*samplesPerBlockExpected*/) override
    {
        currentSampleRate = sampleRate;
    }

    void releaseResources() override {}

    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Allow mono or stereo tracks
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }

    //==============================================================================
    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &) override
    {
        const int numSamples = buffer.getNumSamples();
        const int numChannels = buffer.getNumChannels();

        if (currentSampleRate <= 0.0)
            return;

        // --- Acquire automation data safely ---
        std::vector<AutomationPoint> localPoints;
        {
            juce::SpinLock::ScopedTryLockType lock(pointsLock);
            if (!lock.isLocked() || points.empty())
                return;

            localPoints = points; // copy is safe
        }

        // --- Transport (atomic) ---
        double startMs = 0.0;
        if (blockTransportStartSecPtr)
            startMs = blockTransportStartSecPtr->load(std::memory_order_relaxed) * 1000.0;

        const double stepMs = 1000.0 / currentSampleRate;

        for (int sample = 0; sample < numSamples; ++sample)
        {
            const double tMs = startMs + stepMs * sample;
            const float g = getGainAt(localPoints, tMs);

            for (int ch = 0; ch < numChannels; ++ch)
                buffer.getWritePointer(ch)[sample] *= g;
        }

        // advance transport
        const double deltaSec = (double)numSamples / currentSampleRate;
    }

    //==============================================================================
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    //==============================================================================
    void getStateInformation(juce::MemoryBlock &destData) override {}
    void setStateInformation(const void *data, int sizeInBytes) override {}

    //==============================================================================
    // Public API for UI
    void setAutomationPoints(const std::vector<AutomationPoint> &newPoints)
    {
        juce::SpinLock::ScopedLockType lock(pointsLock);
        points = newPoints;
        std::sort(points.begin(), points.end(),
                  [](const AutomationPoint &a, const AutomationPoint &b)
                  { return a.timeMs < b.timeMs; });
    }

    void clearAutomation()
    {
        juce::SpinLock::ScopedLockType lock(pointsLock);
        points.clear();
    }

    void setBlockTransportPtr(std::atomic<double> *ptr) { blockTransportStartSecPtr = ptr; }

private:
    //==============================================================================
    float getGainAt(const std::vector<AutomationPoint> &pts, double timeMs) const
    {
        if (pts.empty())
            return 1.0f;

        if (timeMs <= pts.front().timeMs)
            return mapValueToGain(pts.front().value);

        if (timeMs >= pts.back().timeMs)
            return mapValueToGain(pts.back().value);

        // binary search
        int lo = 0, hi = (int)pts.size() - 1;
        while (hi - lo > 1)
        {
            int mid = (lo + hi) / 2;
            if (timeMs < pts[mid].timeMs)
                hi = mid;
            else
                lo = mid;
        }

        const auto &p0 = pts[lo];
        const auto &p1 = pts[hi];

        const double t = juce::jlimit(0.0, 1.0,
                                      (timeMs - p0.timeMs) / (p1.timeMs - p0.timeMs));

        float v = (float)juce::jmap(t, (double)p0.value, (double)p1.value);
        return mapValueToGain(v);
    }

    // Your nonlinear gain mapper
    float mapValueToGain(float v) const
    {
        if (v >= 0.75f)
        {
            float t = (v - 0.75f) / 0.25f;
            return juce::jmap(t, 1.0f, 2.0f);
        }
        else
        {
            float t = v / 0.75f;
            return juce::jmap(t, 0.0f, 1.0f);
        }
    }

    //==============================================================================
    std::vector<AutomationPoint> points;
    juce::SpinLock pointsLock;

    double currentSampleRate = 44100.0;

    std::atomic<double> *blockTransportStartSecPtr = nullptr;
};

// dummy node before a track/row (so it can easily switch next nodes)
class TrackInputProcessor : public juce::AudioProcessor
{
public:
    TrackInputProcessor()
        : juce::AudioProcessor(
              BusesProperties()
                  .withInput("Input", juce::AudioChannelSet::stereo(), true)
                  .withOutput("Output", juce::AudioChannelSet::stereo(), true))
    {
    }

    const juce::String getName() const override { return "TrackInputProcessor"; }

    void prepareToPlay(double /*sampleRate*/, int /*samplesPerBlockExpected*/) override {}

    void releaseResources() override {}

    void processBlock(juce::AudioBuffer<float> &buffer,
                      juce::MidiBuffer &) override
    {
        // juce::ignoreUnused(buffer); // pure pass-through for now
    }

    // Boilerplate
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override
    {
        auto in = layouts.getMainInputChannelSet();
        auto out = layouts.getMainOutputChannelSet();

        if (in.isDisabled() || out.isDisabled())
            return false;

        if (in != out)
            return false;

        // Track buses: mono or stereo, but must match
        return in == juce::AudioChannelSet::mono() || in == juce::AudioChannelSet::stereo();
    }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}

    bool hasEditor() const override { return false; }
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}
};

// ---------------------------
// FilePlayerProcessor
// ---------------------------
class FilePlayerProcessor : public juce::AudioProcessor
{
public:
    FilePlayerProcessor(
        std::unique_ptr<juce::AudioFormatReaderSource> src,
        juce::int64 totalLengthInSamples,
        const juce::File &file)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          sourceFile(file),
          totalLength(totalLengthInSamples)
    {
        if (src && src->getAudioFormatReader())
        {
            readerSource = src.get();
            fileSampleRate = readerSource->getAudioFormatReader()->sampleRate;

            resampler = std::make_unique<juce::ResamplingAudioSource>(
                src.release(), true /* delete input */);
        }
        else
        {
            fileSampleRate = 44100.0;
        }
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (resampler)
        {
            const double ratio = fileSampleRate / deviceSampleRate;
            resampler->setResamplingRatio(ratio);
            resampler->prepareToPlay(samplesPerBlock, deviceSampleRate);
        }

        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override
    {
        if (resampler)
            resampler->releaseResources();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (resampler)
        {
            juce::AudioSourceChannelInfo info(&buffer, 0, buffer.getNumSamples());
            resampler->getNextAudioBlock(info);
        }
    }

    void setPosition(double seconds)
    {
        if (readerSource)
            readerSource->setNextReadPosition(
                (juce::int64)(seconds * fileSampleRate));

        if (resampler)
            resampler->flushBuffers();
    }

    double getCurrentPosition() const
    {
        if (!readerSource)
            return 0.0;

        return (double)readerSource->getNextReadPosition() / fileSampleRate;
    }

    double getTotalLengthSeconds() const
    {
        return (double)totalLength / fileSampleRate;
    }

    double getSampleRate() const { return fileSampleRate; }
    const juce::File &getSourceFile() const { return sourceFile; }
    juce::int64 getTotalLength() const { return totalLength; }

    // Boilerplate
    const juce::String getName() const override { return "FilePlayerProcessor"; }
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
    juce::AudioFormatReaderSource *readerSource = nullptr; // non-owning
    std::unique_ptr<juce::ResamplingAudioSource> resampler;

    juce::File sourceFile;
    juce::int64 totalLength = 0;
    double currentSampleRate = 44100.0;
    double fileSampleRate = 44100.0;
};

// ---------------------------
// TimelineClipProcessor (NEW)
// - outputs silence outside [clipStartSec, clipEndSec)
// - reads contiguous audio only for the overlap of this block
// - uses engine-provided block transport start time (atomic)
// ---------------------------
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
    virtual void setReversed(bool shouldReverse) = 0;
    virtual void setStretchOptions(double tempoRatio, bool preservePitch) = 0;
};

class TimelineClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
    TimelineClipProcessor(std::unique_ptr<juce::AudioFormatReaderSource> src,
                          juce::int64 totalLengthInSamples,
                          const juce::File &file,
                          std::atomic<double> *blockTransportStartSecPtr,
                          std::atomic<double> *hostSampleRatePtr,
                          std::atomic<bool> *isPlayingPtr)
        : juce::AudioProcessor(BusesProperties()
                                   .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
          sourceFile(file),
          totalLength(totalLengthInSamples),
          blockTransportStartSec(blockTransportStartSecPtr),
          hostSampleRate(hostSampleRatePtr),
          isPlaying(isPlayingPtr)
    {
        if (src && src->getAudioFormatReader())
        {
            readerSource = src.get();
            fileSampleRate = readerSource->getAudioFormatReader()->sampleRate;

            resampler = std::make_unique<juce::ResamplingAudioSource>(
                src.release(), true /* delete input */);
        }
        else
        {
            fileSampleRate = 44100.0;
        }
    }

    // --- timeline API (JUCE owns clip times) ---
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
    void setReversed(bool shouldReverse) override
    {
        reversed.store(shouldReverse, std::memory_order_relaxed);
    }
    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        tempoPlaybackRatio.store(juce::jlimit(0.05, 20.0, tempoRatio),
                                 std::memory_order_relaxed);
        preserveTempoPitch.store(preservePitch, std::memory_order_relaxed);
    }

    void prepareToPlay(double deviceSampleRate, int samplesPerBlock) override
    {
        if (hostSampleRate)
            hostSampleRate->store(deviceSampleRate, std::memory_order_relaxed);

        if (resampler)
        {
            const auto ratio = getPlaybackResamplingRatio(deviceSampleRate);
            resampler->setResamplingRatio(ratio);
            lastAppliedRatio = ratio;
            resampler->prepareToPlay(samplesPerBlock, deviceSampleRate);
        }
        if (pitchCompensator)
        {
            pitchCompensator->prepareToPlay(deviceSampleRate, samplesPerBlock);
            if (auto *mix = pitchCompensator->parameters.getRawParameterValue("mix"))
                mix->store(100.0f, std::memory_order_relaxed);
        }

        sourcePrimed = false;
        lastReadTimelineEndSec = std::numeric_limits<double>::quiet_NaN();
        lastFileOffsetSec = fileOffsetSec.load(std::memory_order_relaxed);

        setPlayConfigDetails(0, 2, deviceSampleRate, samplesPerBlock);
    }

    void releaseResources() override
    {
        if (resampler)
            resampler->releaseResources();
        if (pitchCompensator)
            pitchCompensator->releaseResources();
    }

    void processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override
    {
        buffer.clear();

        if (muted.load(std::memory_order_relaxed))
            return;

        if (!resampler || !readerSource || !blockTransportStartSec || !hostSampleRate)
            return;

        if (isPlaying != nullptr && !isPlaying->load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        // Keep tempo-ratio changes sample-accurate while playing.
        const auto ratio = getPlaybackResamplingRatio(sr);
        if (std::abs(ratio - lastAppliedRatio) > 1.0e-9)
        {
            resampler->setResamplingRatio(ratio);
            lastAppliedRatio = ratio;
        }

        const int numSamples = buffer.getNumSamples();

        const double blockStart = blockTransportStartSec->load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;

        const double cs = clipStartSec.load(std::memory_order_relaxed);
        const double cl = clipLengthSec.load(std::memory_order_relaxed);
        const double ce = cs + cl;

        // no overlap => silence
        if (blockEnd <= cs || blockStart >= ce)
            return;

        // Convert clip overlap to integer sample bounds in this block.
        // Use ceil for both bounds to avoid sample holes/overlaps from float truncation.
        const int writeStart = juce::jlimit(
            0, numSamples,
            (int)std::ceil((cs - blockStart) * sr));
        const int writeEnd = juce::jlimit(
            0, numSamples,
            (int)std::ceil((ce - blockStart) * sr));

        const int framesToRead = juce::jmax(0, writeEnd - writeStart);
        if (framesToRead <= 0)
            return;

        // Convert exact write start sample back to timeline, then to file position.
        // This keeps block-to-block reads sample-consistent when clip positions shift.
        const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
        const double speedRatio = getTempoPlaybackRatio();
        const double readTimelineStart = blockStart + ((double)writeStart / sr);
        const double filePosSec = ((readTimelineStart - cs) * speedRatio) + inFile;

        const auto desiredReadPos = (juce::int64)std::llround(filePosSec * fileSampleRate);
        const bool timelineDiscontinuity =
            !sourcePrimed ||
            !std::isfinite(lastReadTimelineEndSec) ||
            (std::abs(readTimelineStart - lastReadTimelineEndSec) > (2.0 / sr));
        const bool fileOffsetChanged =
            !sourcePrimed ||
            (std::abs(inFile - lastFileOffsetSec) > (0.5 / fileSampleRate));
        const bool needsReposition = timelineDiscontinuity || fileOffsetChanged;
        const bool shouldReverse = reversed.load(std::memory_order_relaxed);

        if (shouldReverse)
        {
            if (needsReposition && pitchCompensator)
                pitchCompensator->reset();

            if (!renderReversedBlock(framesToRead, sr, readTimelineStart, ce, inFile))
                return;

            applyRequestedPitchShift(temp);

            for (int ch = 0; ch < juce::jmin(2, buffer.getNumChannels()); ++ch)
                buffer.copyFrom(ch, writeStart, temp, ch, 0, framesToRead);

            sourcePrimed = true;
            lastReadTimelineEndSec = readTimelineStart + ((double)framesToRead / sr);
            lastFileOffsetSec = inFile;
            return;
        }

        // Only force seek + flush on real discontinuities (scrub/jump/start),
        // otherwise keep resampler history to avoid block-boundary artifacts.
        if (needsReposition)
        {
            readerSource->setNextReadPosition(desiredReadPos);
            resampler->flushBuffers();
            if (pitchCompensator)
                pitchCompensator->reset();
            sourcePrimed = true;
        }

        // read into a temp buffer then copy into output at [writeStart, writeStart+framesToRead)
        temp.setSize(2, framesToRead, false, false, true);
        temp.clear();

        juce::AudioSourceChannelInfo info(&temp, 0, framesToRead);
        resampler->getNextAudioBlock(info);

        applyRequestedPitchShift(temp);

        for (int ch = 0; ch < juce::jmin(2, buffer.getNumChannels()); ++ch)
            buffer.copyFrom(ch, writeStart, temp, ch, 0, framesToRead);

        lastReadTimelineEndSec = readTimelineStart + ((double)framesToRead / sr);
        lastFileOffsetSec = inFile;
    }

    // boilerplate
    const juce::String getName() const override { return "TimelineClipProcessor"; }
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
    double getTempoPlaybackRatio() const
    {
        return juce::jlimit(0.05, 20.0,
                            tempoPlaybackRatio.load(std::memory_order_relaxed));
    }

    double getPlaybackResamplingRatio(double deviceSampleRate) const
    {
        if (deviceSampleRate <= 0.0)
            return 1.0;
        const double baseRatio = fileSampleRate / deviceSampleRate;
        return baseRatio * getTempoPlaybackRatio();
    }

    void applyPitchShiftSemitones(juce::AudioBuffer<float> &buffer, double semitones)
    {
        if (!pitchCompensator)
            return;

        if (std::abs(semitones) < 0.01)
            return;

        // The built-in shifter is ±12 st per pass; split larger shifts.
        const int passes = juce::jlimit(
            1, 8, (int)std::ceil(std::abs(semitones) / 12.0));
        const float semitonesPerPass = (float)(semitones / (double)passes);

        if (auto *mix = pitchCompensator->parameters.getRawParameterValue("mix"))
            mix->store(100.0f, std::memory_order_relaxed);
        if (auto *semitonesParam =
                pitchCompensator->parameters.getRawParameterValue("semitones"))
            semitonesParam->store(
                juce::jlimit(-12.0f, 12.0f, semitonesPerPass),
                std::memory_order_relaxed);

        pitchMidiScratch.clear();
        for (int i = 0; i < passes; ++i)
            pitchCompensator->processBlock(buffer, pitchMidiScratch);
    }

    void applyRequestedPitchShift(juce::AudioBuffer<float> &buffer)
    {
        double requestedSemitones =
            (double)pitchSemitones.load(std::memory_order_relaxed);

        if (preserveTempoPitch.load(std::memory_order_relaxed))
        {
            const double tempoRatio = getTempoPlaybackRatio();
            if (tempoRatio > 0.0)
            {
                // Cancel pitch drift caused by tempo resampling when preserve mode is enabled.
                requestedSemitones +=
                    -12.0 * (std::log(tempoRatio) / std::log(2.0));
            }
        }

        applyPitchShiftSemitones(
            buffer, juce::jlimit(-96.0, 96.0, requestedSemitones));
    }

    bool renderReversedBlock(int framesToRead,
                             double deviceSampleRate,
                             double readTimelineStart,
                             double clipEndSec,
                             double inFileOffsetSec)
    {
        auto *reader = readerSource != nullptr ? readerSource->getAudioFormatReader() : nullptr;
        if (reader == nullptr || deviceSampleRate <= 0.0 || framesToRead <= 0)
            return false;

        const double timelineBlockSec = (double)framesToRead / deviceSampleRate;
        const double speedRatio = getTempoPlaybackRatio();
        const double blockTimelineEnd = readTimelineStart + timelineBlockSec;
        const double rawStartSec =
            inFileOffsetSec + juce::jmax(0.0, (clipEndSec - blockTimelineEnd) * speedRatio);
        const double rawEndSec =
            inFileOffsetSec + juce::jmax(0.0, (clipEndSec - readTimelineStart) * speedRatio);

        auto sourceStartSample =
            (juce::int64)std::floor(rawStartSec * fileSampleRate);
        auto sourceEndSample =
            (juce::int64)std::ceil(rawEndSec * fileSampleRate);

        sourceStartSample = juce::jlimit<juce::int64>(0, totalLength, sourceStartSample);
        sourceEndSample = juce::jlimit<juce::int64>(0, totalLength, sourceEndSample);

        const auto sourceSampleSpan =
            std::max<juce::int64>(juce::int64{0}, sourceEndSample - sourceStartSample);
        const auto maxBufferedSourceSamples =
            static_cast<juce::int64>(std::numeric_limits<int>::max()) - juce::int64{8};
        const auto bufferedSourceSampleSpan =
            std::min<juce::int64>(sourceSampleSpan, maxBufferedSourceSamples);
        const int sourceSamplesNeeded = std::max(
            8,
            static_cast<int>(bufferedSourceSampleSpan + juce::int64{8}));

        reverseSourceTemp.setSize(2, sourceSamplesNeeded, false, false, true);
        reverseSourceTemp.clear();

        const int readSamples = static_cast<int>(bufferedSourceSampleSpan);
        if (readSamples <= 0)
            return false;

        reader->read(&reverseSourceTemp,
                     0,
                     readSamples,
                     sourceStartSample,
                     true,
                     true);
        reverseSourceTemp.reverse(0, readSamples);

        temp.setSize(2, framesToRead, false, false, true);
        temp.clear();

        const double samplesPerOutputSample =
            (fileSampleRate / deviceSampleRate) * speedRatio;

        for (int ch = 0; ch < juce::jmin(2, temp.getNumChannels()); ++ch)
        {
            juce::LagrangeInterpolator interpolator;
            interpolator.reset();
            interpolator.process(
                samplesPerOutputSample,
                reverseSourceTemp.getReadPointer(ch),
                temp.getWritePointer(ch),
                framesToRead);
        }

        return true;
    }

    juce::AudioFormatReaderSource *readerSource = nullptr; // non-owning
    std::unique_ptr<juce::ResamplingAudioSource> resampler;
    std::unique_ptr<PitchShiftAudioProcessor> pitchCompensator{
        std::make_unique<PitchShiftAudioProcessor>()};
    juce::MidiBuffer pitchMidiScratch;

    juce::AudioBuffer<float> temp;
    juce::AudioBuffer<float> reverseSourceTemp;

    juce::File sourceFile;
    juce::int64 totalLength = 0;
    double fileSampleRate = 44100.0;

    std::atomic<double> *blockTransportStartSec = nullptr;
    std::atomic<double> *hostSampleRate = nullptr;
    std::atomic<bool> *isPlaying = nullptr;

    std::atomic<double> clipStartSec{0.0};
    std::atomic<double> clipLengthSec{0.0};
    std::atomic<double> fileOffsetSec{0.0};
    std::atomic<float> pitchSemitones{0.0f};
    std::atomic<bool> reversed{false};
    std::atomic<double> tempoPlaybackRatio{1.0};
    std::atomic<bool> preserveTempoPitch{false};
    std::atomic<bool> muted{false};
    bool sourcePrimed = false;
    double lastAppliedRatio = 1.0;
    double lastReadTimelineEndSec = std::numeric_limits<double>::quiet_NaN();
    double lastFileOffsetSec = 0.0;
};

class TimelineMidiClipProcessor : public juce::AudioProcessor, public TimelineClipProcessorBase
{
public:
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

    void setReversed(bool shouldReverse) override
    {
        juce::ignoreUnused(shouldReverse);
    }

    void setStretchOptions(double tempoRatio, bool preservePitch) override
    {
        tempoPlaybackRatio.store(juce::jlimit(0.05, 20.0, tempoRatio),
                                 std::memory_order_relaxed);
        preserveTempoPitch.store(preservePitch, std::memory_order_relaxed);
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
        if (!blockTransportStartSec || !hostSampleRate)
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const bool hostPlaying =
            (isPlaying == nullptr) || isPlaying->load(std::memory_order_relaxed);

        const int numSamples = buffer.getNumSamples();
        const int outChannels = buffer.getNumChannels();
        if (numSamples <= 0 || outChannels <= 0)
            return;

        const double blockStart = blockTransportStartSec->load(std::memory_order_relaxed);
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

        const bool hasTimelineNotes = hostPlaying && !cachedNotes.empty();
        const bool hasLiveNotes = !activeLiveNotes.empty();
        if (!hasTimelineNotes && !hasLiveNotes)
            return;

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
                        const int outIndex = writeStart + i;

                        if (stereo)
                        {
                            outL[outIndex] += mixL;
                            outR[outIndex] += mixR;
                        }
                        else
                            outL[outIndex] += 0.5f * (mixL + mixR);
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
            if (stereo)
            {
                outL[i] += mixL;
                outR[i] += mixR;
            }
            else
                outL[i] += 0.5f * (mixL + mixR);
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

    struct SfzParsedLine
    {
        juce::String blockTag;
        SfzOpcodeMap opcodes;
    };

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
        const juce::String assetPath = normalizeAssetPath(assetPathRaw);
        if (assetPath.isEmpty())
            return {};

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

    static SfzParsedLine parseSfzLine(const juce::String &lineRaw)
    {
        SfzParsedLine out;
        const juce::String line =
            lineRaw.upToFirstOccurrenceOf("//", false, false).trim();
        if (line.isEmpty())
            return out;

        juce::String remainder = line;
        if (line.startsWithChar('<'))
        {
            const int close = line.indexOfChar('>');
            if (close > 1)
            {
                out.blockTag =
                    line.substring(1, close).trim().toLowerCase();
                remainder = line.substring(close + 1).trim();
            }
        }

        if (remainder.isNotEmpty())
            out.opcodes = parseSfzOpcodes(remainder);
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
            const auto parsed = parseSfzLine(rawLine);
            if (parsed.blockTag.isEmpty() && parsed.opcodes.empty())
                continue;

            if (parsed.blockTag.isNotEmpty())
            {
                const juce::String tag = parsed.blockTag;
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
            }

            const auto &opcodes = parsed.opcodes;
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

// ---------------------------
// JuceEngine
// ---------------------------
class JuceEngine : public juce::MidiInputCallback,
                   public juce::ChangeListener
{
public:
    struct ExportOptions
    {
        juce::String format{"wav"}; // "wav" | "mp3"
        double sampleRate{44100.0};
        int wavBitDepth{16};
        bool wavDithering{true};
        int mp3BitrateKbps{192};
    };

    static JuceEngine &get();

    void initialiseEngine();
    void loadTrack(int idx, const juce::File &file); // deprecated name (clip)
    void removeTrack(int clipIndex);                 // removes clip
    juce::StringArray getTrackEffects(int trackIndex);
    void removePluginEffect(int trackIdx, int effectIndex);
    void reorderPluginEffects(int trackIdx, int fromIndex, int toIndex);
    void setEffectParameter(int trackIndex,
                            int effectIndex,
                            const juce::String &paramID,
                            const juce::var &newValue);
    void setTrackVolume(int trackIdx, float volume);
    double getCurrentPosition(int trackIndex);
    double getTrackDuration(int trackIndex);
    juce::Array<juce::NamedValueSet> getPluginParameterInfo(int trackIndex, int effectIndex);
    juce::String exportMix(const juce::File &outFile);
    juce::String exportMix(const juce::File &outFile, const ExportOptions &options);
    juce::String exportTrack(int trackIndex, const juce::File &outFile);
    juce::String exportTrack(int trackIndex, const juce::File &outFile, const ExportOptions &options);
    void seek(int trackIndex, double positionSeconds);
    void bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass);
    bool getPluginBypassState(int trackIndex, int effectIndex);
    void bypassTrack(int trackIndex, bool shouldBypass);
    juce::Array<juce::PluginDescription> getKnownPlugins();
    void insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback);
    void shutdownEngine();

    // Rows
    int addRow(const juce::String &name, int iconId);
    bool removeRow(int rowId);
    bool moveRowOrder(int fromIndex, int toIndex);
    int insertRowAbove(int referenceRowId, const juce::String &name, int iconId);
    int insertRowBelow(int referenceRowId, const juce::String &name, int iconId);
    bool renameRow(int rowId, const juce::String &newName);
    bool setRowIcon(int rowId, int iconId);
    juce::Array<juce::NamedValueSet> getRows() const;

    // Clips (stable ids)
    bool loadClip(int clipId, int rowId, const juce::File &file,
                  double startSec, double lengthSec, double inFileOffsetSec = 0.0);
    bool loadMidiClip(int clipId,
                      int rowId,
                      const juce::String &instrumentId,
                      const juce::String &instrumentName,
                      const juce::Array<TimelineMidiNote> &notes,
                      const juce::NamedValueSet &params,
                      double sourceTempoBpm,
                      double startSec,
                      double lengthSec,
                      double inFileOffsetSec = 0.0);
    bool updateMidiClipEvents(int clipId,
                              const juce::String &instrumentId,
                              const juce::String &instrumentName,
                              const juce::Array<TimelineMidiNote> &notes,
                              const juce::NamedValueSet &params,
                              double sourceTempoBpm);
    bool supportsLiveMidiClipPlayback() const { return true; }
    struct LiveMidiInputEvent
    {
        int clipId = -1;
        bool noteOn = false;
        int channel = 1;
        int pitch = 60;
        float velocity = 0.0f;
        double transportSec = 0.0;
    };
    bool setLiveMidiInputTargetClip(int clipId);
    std::vector<LiveMidiInputEvent> consumeLiveMidiInputEvents();
    bool unloadClip(int clipId);
    bool moveClipToRow(int clipId, int newRowId);
    bool setClipTime(int clipId, double startSec, double lengthSec, double inFileOffsetSec = 0.0);

    // Transport
    void play();
    void pause();
    void setTransportSeconds(double t);
    double getTransportSeconds() const;
    void setBlockTransportStartFromCurrent()
    {
        blockTransportStartSec.store(
            transportSec.load(std::memory_order_relaxed),
            std::memory_order_relaxed);
    }
    // Audio thread only; routes queued MIDI input events into clip processors.
    void dispatchQueuedLiveMidiInputEventsForAudioThread();
    void advanceTransportBySamples(int numSamples)
    {
        if (!isPlayingAtomic.load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRateAtomic.load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const double delta = (double)numSamples / sr;
        transportSec.store(
            transportSec.load(std::memory_order_relaxed) + delta,
            std::memory_order_relaxed);
    }
    bool tryLockGraphRender() { return graphRenderMutex.try_lock(); }
    void unlockGraphRender() { graphRenderMutex.unlock(); }

    // (deprecated/unused) special functions for "video audio" lane
    void loadVideoAudio(const juce::File &file);
    void unloadVideoAudio();
    void setVideoAudioGain(float gain);
    void seekVideoAudio(double seconds);

    // Debug
    void debugPrintGraph(const juce::String &title);
    void debugPrintGraphStructure();

    // CLIP-LEVEL
    void setClipGain(int clipIndex, float gain); // gain UI ∈ 0..3 (mapped to -60..+6 dB)
    void muteClip(int clipIndex, bool shouldMute);
    void setClipPan(int clipIndex, float pan); // -1..1 where 0 = center
    void setClipPitch(int clipIndex, float semitones); // pitch ∈ -24..24
    void setClipReversed(int clipIndex, bool shouldReverse);
    void setClipStretchOptions(int clipIndex, double tempoRatio, bool preservePitch);

    // ROW (track bus) FX
    bool insertTrackEffect(int trackRow, const juce::String &pluginPath);
    void removeTrackEffect(int trackRow, int effectIndex);
    void reorderTrackEffects(int trackRow, int fromIndex, int toIndex);
    void setTrackEffectParameter(int trackRow,
                                 int effectIndex,
                                 const juce::String &paramName,
                                 const juce::var &newValue);
    juce::StringArray getTrackEffectsForRow(int trackRow);
    juce::StringArray getTrackEffectIdsForRow(int trackRow);
    juce::StringArray getTrackEffectInstanceIdsForRow(int trackRow);
    juce::Array<juce::NamedValueSet> getTrackPluginParameterInfo(int row, int effectIndex);
    void bypassRowEffect(int rowIndex, int effectIndex, bool shouldBypass);
    bool getRowEffectBypassState(int rowIndex, int effectIndex);
    void setTrackAutomationPoints(int trackRow,
                                  const std::vector<AutomationPoint> &points);
    void setTrackEffectAutomationPoints(int trackRow,
                                        int effectIndex,
                                        const juce::String &paramId,
                                        float minValue,
                                        float maxValue,
                                        const std::vector<AutomationPoint> &points);
    void clearTrackEffectAutomationForRow(int trackRow);
    void setRowGainAutomationPoints(int row,
                                    const std::vector<AutomationPoint> &points);
    void setRowGain(int row, float gain);
    void muteRow(int rowIndex, bool shouldMute);
    bool isRowMuted(int rowIndex);
    void setRowPanAutomationPoints(int row,
                                   const std::vector<AutomationPoint> &points);
    void setRowPan(int row, float pan);

    // MASTER bus FX
    bool insertMasterEffect(const juce::String &pluginPath);
    void removeMasterEffect(int effectIndex);
    void reorderMasterEffects(int fromIndex, int toIndex);
    void setMasterEffectParameter(int effectIndex,
                                  const juce::String &paramName,
                                  const juce::var &newValue);
    juce::StringArray getMasterEffects();
    juce::StringArray getMasterEffectIds();
    juce::Array<juce::NamedValueSet> getMasterPluginParameterInfo(int effectIndex);
    void bypassMasterEffect(int effectIndex, bool shouldBypass);
    bool getMasterEffectBypassState(int effectIndex);
    void setMasterEffectAutomationPoints(int effectIndex,
                                         const juce::String &paramId,
                                         float minValue,
                                         float maxValue,
                                         const std::vector<AutomationPoint> &points);
    void clearMasterEffectAutomation();
    void setMasterGainAutomationPoints(const std::vector<AutomationPoint> &points);
    void setMasterGain(float gain);
    void muteMaster(bool shouldMute);
    void setMasterPanAutomationPoints(const std::vector<AutomationPoint> &points);
    void setMasterPan(float pan);

    // Transport for automation
    void setAutomationTransport(double timeSeconds); // Dart passes seconds
    void applyTrackEffectAutomationAtCurrentBlockStart();

    void setMetronomeEnabled(bool);
    void setMetronomeVolume(float);
    void setMetronomeBpm(double);
    void setMetronomeTransportMs(double);

    std::vector<float> decodeAudioMono16k(const juce::File &file);
    juce::NamedValueSet analyzeAudioStereo16k(const juce::File &file);

    // Device info
    juce::StringArray getAvailableInputDevices();
    bool selectInputDevice(const juce::String &name);
    juce::String getCurrentInputDeviceName() const;
    int getNumInputChannels() const;
    void routeLiveInputToRow(int row, int channelCount, int channelStart = 0);
    bool prepareRecordingInputs(int desiredInputChannels,
                                const juce::String &reason);
    void prepareRecordingInputsAsync(int desiredInputChannels,
                                     const juce::String &reason);
    void refreshAudioRouteAsync(const juce::String &reason);
    void requestAudioDeviceRefreshAsync(const juce::String &reason);

    // Recording
    bool startRecordingToWav(const juce::File &file,
                             int channelStart,
                             int channelCount);
    void stopRecording();
    bool isRecording() const;
    void captureInput(const float *const *input,
                      int numInputChannels,
                      int numSamples);
    void captureOutput(float *const *output,
                       int numOutputChannels,
                       int numSamples);
    double getRecordingPeak() const;

    // Metering/Visualization
    void applyOutputSafetyGuard(float *const *output,
                                int numOutputChannels,
                                int numSamples) noexcept;
    void armOutputSafetyFadeIn(double sampleRate) noexcept;
    void setMasterMeterEnabled(bool enabled);
    const std::array<float, 4> getMasterMeterValues();
    void updateMasterMeterFromOutput(const float *const *out,
                                     int numOutCh,
                                     int numSamples) noexcept;
    // Master clip indicator (latched)
    bool getMasterClipLatched() const noexcept;
    void clearMasterClipLatched() noexcept;
    void setRowMetersEnabled(bool enabled);
    const std::array<float, 4> getRowMeterValues(int row);

    // Gets master + all row meters
    std::vector<float> getAllMeterValues() const;

    // Compressor meter strip (white-box only)
    const std::array<float, 5> getClipCompressorMeter(int clipIndex, int effectIndex);
    const std::array<float, 5> getRowCompressorMeter(int row, int effectIndex);
    const std::array<float, 5> getMasterCompressorMeter(int effectIndex);
    double getHostSampleRate() const;
    std::vector<float> getRowEqWaveform(int row, int effectIndex, int sampleCount);
    std::vector<float> getMasterEqWaveform(int effectIndex, int sampleCount);
    void handleIncomingMidiMessage(juce::MidiInput *source,
                                   const juce::MidiMessage &message) override;
    void changeListenerCallback(juce::ChangeBroadcaster *source) override;

private:
    JuceEngine();
    ~JuceEngine();

    void rewireTrackChain(int trackIdx,
                          juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync); // clip-level FX+gain+pan → row
    void rewireMasterFxChain();                  // master FX chain
    void armOutputSafetyForCurrentRoute() noexcept;
    void ensureBusGraphInitialised();            // rows + master
    void rewireTrackBusFxChain(int trackRow);    // row-level FX between input and automation
    int getTrackIndexForClip(int clipIdx) const; // clip → row mapping
    float panUIToNormalized(float uiPan)         // OLD: uiPan ∈ [-1, 1] NEW: uiPan ∈ [0, 1]
    {
        // return juce::jmap(uiPan, -1.0f, 1.0f, 0.0f, 1.0f); // map to [0, 1]
        return juce::jmap(uiPan, 0.0f, 1.0f, 0.0f, 1.0f); // map to [0, 1] (basically does nothing, just clamp)
    }

    static const juce::StringArray mixroomPlugins;

    bool engineInitialized = false;
    bool formatsRegistered = false; // will only be flipped once to true
    juce::AudioFormatManager formatManager;
    juce::AudioPluginFormatManager pluginFormatManager;
    juce::AudioProcessorGraph graph;
    juce::AudioProcessorGraph exportGraph;

    juce::SpinLock recordLock;

    juce::AudioProcessorGraph::Node::Ptr inputNode;
    juce::AudioProcessorGraph::Node::Ptr outputNode;

    // Legacy clip containers still used by compatibility code paths.
    juce::Array<juce::AudioProcessorGraph::Node::Ptr> trackNodes;
    juce::Array<SimpleGainProcessor *> gainProcessors;
    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackEffectChains;

    juce::KnownPluginList pluginList;
    void scanPluginsIfNeeded();
    bool pluginsScanned = false;
    std::vector<juce::String> getExposedParametersForPlugin(const juce::String &pluginId);

    juce::AudioDeviceManager deviceManager;
    juce::AudioProcessorPlayer audioPlayer;

    // (deprecated/unused) Playback-only "video audio" lane (excluded from exports)
    juce::AudioProcessorGraph::Node::Ptr videoAudioNode{nullptr};
    SimpleGainProcessor *videoGainProc{nullptr};
    bool hasVideoAudio{false};

    std::atomic<double> transportSec{0.0};           // source of truth
    std::atomic<double> blockTransportStartSec{0.0}; // set each audio callback block
    std::atomic<double> hostSampleRateAtomic{44100.0};
    std::atomic<bool> isPlayingAtomic{false};
    std::atomic<int> liveMidiInputTargetClip{-1};
    std::mutex liveMidiInputQueueMutex;
    std::vector<LiveMidiInputEvent> liveMidiInputPendingForAudio;
    std::vector<LiveMidiInputEvent> liveMidiInputPendingForFlutter;
    std::vector<juce::String> midiInputCallbackDeviceIds;
    std::atomic<bool> midiInputCallbacksInitialized{false};

    // Basic limits
    static constexpr int kNumTracks = 5;  // legacy fixed-row compatibility paths
    static constexpr int kMaxRows = 100;  // hard safety cap
    static constexpr int kMaxClips = 500; // safety cap for simultaneous clips
    static constexpr float kGainUiMin = 0.0f;
    static constexpr float kGainUiMax = 3.0f;
    static constexpr float kGainDbMin = -60.0f;
    static constexpr float kGainDbMax = 6.0f;
    static constexpr float kGainUiUnity = 2.0f;

    // Legacy row/clip routing containers retained for compatibility.
    juce::Array<StereoPanProcessor *> clipPanProcessors;
    juce::Array<int> clipTrackAssignments;

    TrackInputProcessor *trackInputProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackInputNodes[kNumTracks];

    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackBusEffectChains;

    VolumeAutomationProcessor *trackAutomationProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackAutomationNodes[kNumTracks];

    SimpleGainProcessor *trackGainProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackGainNodes[kNumTracks];

    StereoPanProcessor *trackPanProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackPanNodes[kNumTracks];

    struct ClipState
    {
        bool alive = false;
        bool wired = false;
        bool isMidi = false;
        bool muted = false;

        int clipId = -1; // stable
        int rowId = 0;   // stable row id

        // timeline
        double startSec = 0.0;
        double lengthSec = 0.0;
        double inFileOffsetSec = 0.0; // == trimStart. optional later for trimming
        float pitchSemitones = 0.0f;
        bool reversed = false;
        double tempoRatio = 1.0;
        bool preservePitch = false;

        // nodes/processors
        juce::AudioProcessorGraph::Node::Ptr playerNode; // TimelineClipProcessor / TimelineMidiClipProcessor
        SimpleGainProcessor *gainProc = nullptr;
        juce::AudioProcessorGraph::Node::Ptr gainNode;

        StereoPanProcessor *panProc = nullptr;
        juce::AudioProcessorGraph::Node::Ptr panNode;

        juce::Array<juce::AudioProcessorGraph::NodeID> fxChain; // clip-level legacy FX
        int lastRowInputNodeUid = 0;                            // cached destination for fast rewires
    };

    // fixed slots so ids never shift
    std::vector<ClipState> clips;

    // METERING
    struct StereoMeterState
    {
        std::atomic<float> peakL{0.0f};
        std::atomic<float> peakR{0.0f};
        std::atomic<float> rmsL{0.0f};
        std::atomic<float> rmsR{0.0f};

        StereoMeterState() = default;

        StereoMeterState(const StereoMeterState &other)
        {
            peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
        }

        StereoMeterState &operator=(const StereoMeterState &other)
        {
            if (this != &other)
            {
                peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            }
            return *this;
        }

        StereoMeterState(StereoMeterState &&other) noexcept
        {
            peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
            rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
        }

        StereoMeterState &operator=(StereoMeterState &&other) noexcept
        {
            if (this != &other)
            {
                peakL.store(other.peakL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                peakR.store(other.peakR.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsL.store(other.rmsL.load(std::memory_order_relaxed), std::memory_order_relaxed);
                rmsR.store(other.rmsR.load(std::memory_order_relaxed), std::memory_order_relaxed);
            }
            return *this;
        }
    };
    StereoMeterState masterMeter;
    std::atomic<bool> masterMeterEnabled{true};
    std::atomic<bool> masterClipLatched{false};
    std::array<float, 2> outputSafetyLastSample{0.0f, 0.0f};
    int outputSafetyMuteSamplesRemaining = 0;
    int outputSafetyFadeSamplesRemaining = 0;
    int outputSafetyFadeSamplesTotal = 0;

    // Row meters (post row-pan)
    std::atomic<bool> rowMetersEnabled{true};
    MeterTapProcessor *rowMeterTaps[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr rowMeterTapNodes[kNumTracks];

    struct RowState
    {
        struct TrackEffectAutomationLane
        {
            int effectIndex = -1;
            juce::String paramId;
            float minValue = 0.0f;
            float maxValue = 1.0f;
            std::vector<AutomationPoint> points;
            float lastAppliedNormalized = std::numeric_limits<float>::quiet_NaN();
        };

        int rowId = 0; // stable id
        juce::String name = "Row";
        int iconId = 0;      // UI icon enum/int
        float gainUi = kGainUiUnity; // 0..3 UI domain, piecewise taper with unity at 2.0
        float panUi = 0.5f;  // 0..1 UI domain
        bool muted = false;
        std::vector<AutomationPoint> automationPoints;
        std::vector<AutomationPoint> gainAutomationPoints;
        std::vector<AutomationPoint> panAutomationPoints;
        std::vector<TrackEffectAutomationLane> effectAutomationLanes;

        // processors
        TrackInputProcessor *inputProc = nullptr;
        VolumeAutomationProcessor *automationProc = nullptr;
        SimpleGainProcessor *gainProc = nullptr;
        StereoPanProcessor *panProc = nullptr;
        MeterTapProcessor *meterTapProc = nullptr;

        // nodes
        juce::AudioProcessorGraph::Node::Ptr inputNode;
        juce::AudioProcessorGraph::Node::Ptr automationNode;
        juce::AudioProcessorGraph::Node::Ptr gainNode;
        juce::AudioProcessorGraph::Node::Ptr panNode;
        juce::AudioProcessorGraph::Node::Ptr meterTapNode;

        // FX chain node ids (row-level FX between input and automation)
        juce::Array<juce::AudioProcessorGraph::NodeID> fxChain;
        juce::StringArray fxIds;

        StereoMeterState meter;
    };

    // row storage
    std::vector<RowState> rows;
    std::unordered_map<int, int> rowIdToIndex;
    std::atomic<int> nextRowId{1};

    // MASTER bus: [FX...] → gain → pan → output
    juce::Array<juce::AudioProcessorGraph::NodeID> *masterEffectChain = nullptr;
    juce::StringArray masterEffectIds;
    std::vector<RowState::TrackEffectAutomationLane> masterEffectAutomationLanes;
    std::vector<AutomationPoint> masterGainAutomationPoints;
    std::vector<AutomationPoint> masterPanAutomationPoints;

    SimpleGainProcessor *masterGainProcessor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr masterGainNode;

    StereoPanProcessor *masterPanProcessor = nullptr;
    juce::AudioProcessorGraph::Node::Ptr masterPanNode;

    bool busGraphInitialised = false;

    std::unique_ptr<MetronomeAudioCallback> metronomeCallback;

    // Recording state
    std::unique_ptr<juce::AudioFormatWriter> recorderWriter;
    std::unique_ptr<juce::FileOutputStream> recorderStream;

    bool recordingActive = false;
    int recordChannelStart = 0;
    int recordChannelCount = 1;
    int recordChannelOffset = 0;
    std::atomic<int> recordingRestoreDesiredInputs{0};
    std::atomic<int> desiredInputOpenChannels{0};
    std::atomic<bool> audioRouteRefreshPending{false};
    std::atomic<int> ignoredDeviceChangeCallbacks{0};

    juce::LinearSmoothedValue<float> recPeak; // optional amplitude meter
    // Recursive because public graph mutation entrypoints can call one another.
    std::recursive_mutex graphRenderMutex;

    void rebuildBusesAndRewireClips();
    void attachRowBusNodes(RowState &r);
    void ensureRowBusNodesAttached(int rowIndex);
    void retargetRowMeterTapPointers();
    void rebuildRowIdIndexCache();
    juce::AudioProcessorGraph::Node::Ptr getRowInputNodeById(int rowId);
    int getRowIndexById(int rowId) const;
    void applyTrackEffectAutomationAtTimeSeconds(double timeSeconds);
    void resetTrackEffectAutomationLatches();
    void resetTrackEffectAutomationLatchesForRow(int row);
    void compactRowFxChain(int row);
    void compactMasterFxChain();
    bool applyPreferredAudioDeviceSetup(int desiredInputChannels,
                                        bool forceReopen,
                                        const juce::String &reason);
    void refreshMidiInputCallbacks();
    void clearMidiInputCallbacks();
    void logCurrentAudioDeviceState(const juce::String &reason) const;
};

class MetronomeAudioCallback : public juce::AudioIODeviceCallback
{
public:
    MetronomeAudioCallback(juce::AudioProcessorPlayer &p, JuceEngine &e)
        : player(p), engine(e)
    {
    }

    // ===== Public API =====
    void setEnabled(bool e) { enabled = e; }
    void setVolume(float v) { volume = v; } // 0..1
    void setBpm(double newBpm)
    {
        bpm = newBpm;
        msPerBeat = 60000.0 / bpm;
    }

    void setTransportMs(double ms)
    {
        transportMs = ms;
        alignToTransport();
    }

    void setIsPlaying(bool p) { isPlaying = p; }

    // ===== AudioIODeviceCallback =====
    void audioDeviceAboutToStart(juce::AudioIODevice *device) override
    {
        sampleRate = device->getCurrentSampleRate();
        msPerBeat = 60000.0 / bpm;
        clickPhaseInc = juce::MathConstants<double>::twoPi * clickFrequency / sampleRate;
        engine.armOutputSafetyFadeIn(sampleRate);
        player.audioDeviceAboutToStart(device);
        alignToTransport();
    }

    void audioDeviceStopped() override
    {
        player.audioDeviceStopped();
    }

    void audioDeviceIOCallbackWithContext(
        const float *const *inputChannelData,
        int numInputChannels,
        float *const *outputChannelData,
        int numOutputChannels,
        int numSamples,
        const juce::AudioIODeviceCallbackContext &context) override
    {
        engine.captureInput(inputChannelData, numInputChannels, numSamples);

        // ===============================
        // 2️⃣ CLEAR OUTPUT
        // ===============================
        for (int ch = 0; ch < numOutputChannels; ++ch)
            juce::FloatVectorOperations::clear(outputChannelData[ch], numSamples);

        if (!engine.tryLockGraphRender())
            return;
        struct _RenderUnlock
        {
            JuceEngine &engineRef;
            ~_RenderUnlock() { engineRef.unlockGraphRender(); }
        } renderUnlock{engine};

        // set block transport start time for all processors (clips, automation)
        engine.setBlockTransportStartFromCurrent();
        engine.applyTrackEffectAutomationAtCurrentBlockStart();
        engine.dispatchQueuedLiveMidiInputEventsForAudioThread();

        // ===============================
        // 3️⃣ RENDER GRAPH (OUTPUT ONLY)
        // ===============================
        player.audioDeviceIOCallbackWithContext(
            nullptr,
            0,
            outputChannelData,
            numOutputChannels,
            numSamples,
            context);

        engine.advanceTransportBySamples(numSamples);

        if (!enabled || !isPlaying)
        {
            engine.applyOutputSafetyGuard(outputChannelData, numOutputChannels, numSamples);
            engine.updateMasterMeterFromOutput(outputChannelData, numOutputChannels, numSamples);
            return;
        }

        const double msPerSample = 1000.0 / sampleRate;

        for (int i = 0; i < numSamples; ++i)
        {
            transportMs += msPerSample;

            if (transportMs >= nextBeatMs)
            {
                currentBeat = (currentBeat + 1) % beatsPerBar;
                clickPhase = 0;
                clickPhaseRad = 0.0;
                nextBeatMs += msPerBeat;

                const bool accent = (currentBeat == 0);
                setupClickFilter(accent);
                setupTone(accent);
            }

            float clickSample = 0.0f;
            float toneSample = 0.0f;

            // ===== Click transient =====
            if (clickPhase < clickLength)
            {
                const double impulse = (clickPhase == 0) ? 1.0 : 0.0;

                const double y =
                    a0 * impulse +
                    a1 * z1 +
                    a2 * z2 -
                    b1 * z1 -
                    b2 * z2;

                z2 = z1;
                z1 = y;

                clickSample = (float)(y * clickEnv * volume);
                clickEnv *= (1.0 - clickEnvDecay);

                ++clickPhase;
            }

            // ===== Tonal body =====
            if (toneEnv > 0.0001)
            {
                toneSample =
                    (float)(std::sin(tonePhase) *
                            toneEnv *
                            volume *
                            0.35f);

                tonePhase += tonePhaseInc;
                toneEnv *= (1.0 - toneEnvDecay);
            }

            // ===== Mix =====
            const float out = clickSample + toneSample;

            for (int ch = 0; ch < numOutputChannels; ++ch)
                outputChannelData[ch][i] += out;
        }

        engine.applyOutputSafetyGuard(outputChannelData, numOutputChannels, numSamples);
        engine.updateMasterMeterFromOutput(outputChannelData, numOutputChannels, numSamples);
    }

    void setupClickFilter(bool accent)
    {
        const double freq = accent ? 6800.0 : 5200.0;
        const double q = accent ? 1.3 : 1.0;

        const double w0 = juce::MathConstants<double>::twoPi * freq / sampleRate;
        const double alpha = std::sin(w0) / (2.0 * q);
        const double cosw = std::cos(w0);

        const double b0 = alpha;
        const double b1n = 0.0;
        const double b2n = -alpha;
        const double a0n = 1.0 + alpha;
        const double a1n = -2.0 * cosw;
        const double a2n = 1.0 - alpha;

        a0 = b0 / a0n;
        a1 = b1n / a0n;
        a2 = b2n / a0n;
        b1 = a1n / a0n;
        b2 = a2n / a0n;

        z1 = z2 = 0.0;

        clickEnv = 1.0;
        clickEnvDecay = accent ? 0.004 : 0.006;
    }

    void setupTone(bool accent)
    {
        const double freq = accent ? 2400.0 : 1800.0; // musical, not harsh
        tonePhaseInc =
            juce::MathConstants<double>::twoPi * freq / sampleRate;

        tonePhase = 0.0;
        toneEnv = 1.0;
        toneEnvDecay = accent ? 0.0025 : 0.0035;
    }

private:
    juce::AudioProcessorPlayer &player;
    JuceEngine &engine;

    bool enabled = false;
    bool isPlaying = false;

    float volume = 0.5f;
    double bpm = 120.0;
    int beatsPerBar = 4;

    double sampleRate = 44100.0;
    double msPerBeat = 500.0;
    double transportMs = 0.0;
    double nextBeatMs = 0.0;

    int currentBeat = 0;
    int clickPhase = 0;

    double clickFrequency = 8000.0; // FL-style brightness
    double clickPhaseRad = 0.0;
    double clickPhaseInc = 0.0;

    const int clickLength = 130;    // ~0.9 ms @ 44.1k
    const float clickDecay = 0.15f; // very fast decay

    double clickEnv = 0.0;
    double clickEnvDecay = 0.0;

    double tonePhase = 0.0;
    double tonePhaseInc = 0.0;
    double toneEnv = 0.0;
    double toneEnvDecay = 0.0;

    juce::Random rng;

    // One-pole bandpass approximation
    double bp_z1 = 0.0;
    double bp_z2 = 0.0;
    double bp_a0 = 0.0;
    double bp_a1 = 0.0;
    double bp_b1 = 0.0;
    double bp_b2 = 0.0;

    double env = 0.0;
    double envDecay = 0.0;

    double z1 = 0.0;
    double z2 = 0.0;

    // biquad coefficients
    double a0 = 0.0;
    double a1 = 0.0;
    double a2 = 0.0;
    double b1 = 0.0;
    double b2 = 0.0;

    void alignToTransport()
    {
        const double beatIndex = transportMs / msPerBeat;
        currentBeat = (int)std::floor(beatIndex) % beatsPerBar;
        nextBeatMs = (std::floor(beatIndex) + 1.0) * msPerBeat;
    }
};
