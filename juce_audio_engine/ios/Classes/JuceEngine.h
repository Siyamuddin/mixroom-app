#pragma once

#include "JuceHeader.h"
#include "SimpleGainProcessor.h"
#include "NativeEffects.h"
#include "JuceLogBridge.h"

#include <array>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <limits>
#include <mutex>
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

        const float p = pan->get(); // -1..1
        const float angle = (p + 1.0f) * juce::MathConstants<float>::pi * 0.25f;
        const float leftGain = std::cos(angle);
        const float rightGain = std::sin(angle);

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
        if (numCh < 2 || numSamples <= 0)
            return;

        const float *L = buffer.getReadPointer(0);
        const float *R = buffer.getReadPointer(1);

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
        return in == out && (in == juce::AudioChannelSet::stereo());
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

    juce::AudioFormatReaderSource *readerSource = nullptr; // non-owning
    std::unique_ptr<juce::ResamplingAudioSource> resampler;
    std::unique_ptr<PitchShiftAudioProcessor> pitchCompensator{
        std::make_unique<PitchShiftAudioProcessor>()};
    juce::MidiBuffer pitchMidiScratch;

    juce::AudioBuffer<float> temp;

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
        next.preset = resolvePreset(instrumentId, instrumentName);
        applyParamOverrides(next.preset, params);

        {
            const juce::ScopedLock lock(stateLock);
            pendingState = next;
            pendingVersion++;
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
        if (isPlaying != nullptr && !isPlaying->load(std::memory_order_relaxed))
            return;

        const double sr = hostSampleRate->load(std::memory_order_relaxed);
        if (sr <= 0.0)
            return;

        const int numSamples = buffer.getNumSamples();
        const double blockStart = blockTransportStartSec->load(std::memory_order_relaxed);
        const double blockEnd = blockStart + (double)numSamples / sr;

        const double cs = clipStartSec.load(std::memory_order_relaxed);
        const double cl = clipLengthSec.load(std::memory_order_relaxed);
        const double ce = cs + cl;

        if (blockEnd <= cs || blockStart >= ce)
            return;

        const int writeStart = juce::jlimit(
            0, numSamples, (int)std::ceil((cs - blockStart) * sr));
        const int writeEnd = juce::jlimit(
            0, numSamples, (int)std::ceil((ce - blockStart) * sr));
        const int framesToRender = juce::jmax(0, writeEnd - writeStart);
        if (framesToRender <= 0)
            return;

        refreshCachedState();
        if (cachedNotes.empty())
            return;

        const double speedRatio = getTempoPlaybackRatio();
        const double safeRatio = speedRatio <= 0.0 ? 1.0 : speedRatio;
        const double sourceSecPerBeat = 60.0 / juce::jlimit(1.0, 400.0, cachedSourceTempoBpm);
        const double inFile = fileOffsetSec.load(std::memory_order_relaxed);
        const double startTimelineSec = blockStart + ((double)writeStart / sr);
        const double attackSec = juce::jmax(0.001, cachedPreset.attackMs / 1000.0);
        const double releaseSec = juce::jmax(0.02, cachedPreset.releaseMs / 1000.0);
        const double releaseSourceSec = releaseSec * safeRatio;
        const float driveGain = (float)(1.0 + cachedPreset.drive * 5.0);

        const int outChannels = buffer.getNumChannels();
        const bool stereo = outChannels >= 2;

        for (int i = 0; i < framesToRender; ++i)
        {
            const double timelineSec = startTimelineSec + ((double)i / sr);
            const double sourceSec = ((timelineSec - cs) * safeRatio) + inFile;
            float mixL = 0.0f;
            float mixR = 0.0f;

            for (const auto &note : cachedNotes)
            {
                const double noteStartSourceSec = note.startBeat * sourceSecPerBeat;
                const double noteLengthSourceSec = juce::jmax(0.001, note.lengthBeats * sourceSecPerBeat);
                const double noteEndSourceSec = noteStartSourceSec + noteLengthSourceSec + releaseSourceSec;
                if (sourceSec < noteStartSourceSec || sourceSec >= noteEndSourceSec)
                    continue;

                const double ageSourceSec = sourceSec - noteStartSourceSec;
                const double ageRealSec = ageSourceSec / safeRatio;
                const double noteLengthRealSec = noteLengthSourceSec / safeRatio;

                double env = 0.0;
                if (ageRealSec < attackSec)
                    env = ageRealSec / attackSec;
                else if (ageRealSec < noteLengthRealSec)
                    env = 1.0;
                else
                    env = 1.0 - ((ageRealSec - noteLengthRealSec) / releaseSec);

                if (env <= 0.0)
                    continue;

                const double totalRealSec = juce::jmax(0.001, noteLengthRealSec + releaseSec);
                const double noteProgress = juce::jlimit(0.0, 1.0, ageRealSec / totalRealSec);

                double notePitch = (double)note.pitch + (double)pitchSemitones.load(std::memory_order_relaxed);
                if (!preserveTempoPitch.load(std::memory_order_relaxed) && safeRatio > 0.0)
                    notePitch += 12.0 * (std::log(safeRatio) / std::log(2.0));

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
                const float driven = std::tanh(raw * driveGain);
                const float sampleValue = driven *
                                          (float)env *
                                          (float)juce::jlimit(0.0, 1.0, note.velocity) *
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

            buffer.setSample(0, outIndex, buffer.getSample(0, outIndex) + mixL);
            if (stereo)
                buffer.setSample(1, outIndex, buffer.getSample(1, outIndex) + mixR);
            else
                buffer.setSample(0, outIndex, buffer.getSample(0, outIndex) + 0.5f * (mixL + mixR));
        }
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

    struct PendingState
    {
        juce::Array<TimelineMidiNote> notes;
        juce::String instrumentId;
        juce::String instrumentName;
        InstrumentPreset preset;
        double sourceTempoBpm = 120.0;
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
            preset.outputGain = juce::jlimit(0.15, 0.75, readParam(params, "outputGain", preset.outputGain));
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
    PendingState pendingState;
    std::atomic<int> pendingVersion{1};
    int cachedVersion = 0;

    std::vector<TimelineMidiNote> cachedNotes;
    InstrumentPreset cachedPreset;
    double cachedSourceTempoBpm = 120.0;
};

// ---------------------------
// JuceEngine
// ---------------------------
class JuceEngine
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
    juce::Array<juce::PluginDescription> getKnownPlugins() const;
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
    void setClipGain(int clipIndex, float gain); // gain ∈ 0..3
    void muteClip(int clipIndex, bool shouldMute);
    void setClipPan(int clipIndex, float pan); // -1..1 where 0 = center
    void setClipPitch(int clipIndex, float semitones); // pitch ∈ -24..24
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
    juce::Array<juce::NamedValueSet> getTrackPluginParameterInfo(int row, int effectIndex);
    void bypassRowEffect(int rowIndex, int effectIndex, bool shouldBypass);
    bool getRowEffectBypassState(int rowIndex, int effectIndex);
    void setTrackAutomationPoints(int trackRow,
                                  const std::vector<AutomationPoint> &points);
    void setRowGain(int row, float gain);
    void muteRow(int rowIndex, bool shouldMute);
    bool isRowMuted(int rowIndex);
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
    void setMasterGain(float gain);
    void muteMaster(bool shouldMute);
    void setMasterPan(float pan);

    // Transport for automation
    void setAutomationTransport(double timeSeconds); // Dart passes seconds

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
    void routeLiveInputToRow(int row, int channelCount);

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

private:
    JuceEngine();
    ~JuceEngine();

    void rewireTrackChain(int trackIdx,
                          juce::AudioProcessorGraph::UpdateKind updateKind = juce::AudioProcessorGraph::UpdateKind::sync); // clip-level FX+gain+pan → row
    void rewireMasterFxChain();                  // master FX chain
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

    // Basic limits
    static constexpr int kNumTracks = 5;  // legacy fixed-row compatibility paths
    static constexpr int kMaxRows = 100;  // hard safety cap
    static constexpr int kMaxClips = 500; // safety cap for simultaneous clips

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

        int clipId = -1; // stable
        int rowId = 0;   // stable row id

        // timeline
        double startSec = 0.0;
        double lengthSec = 0.0;
        double inFileOffsetSec = 0.0; // == trimStart. optional later for trimming
        float pitchSemitones = 0.0f;
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

    // Row meters (post row-pan)
    std::atomic<bool> rowMetersEnabled{true};
    MeterTapProcessor *rowMeterTaps[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr rowMeterTapNodes[kNumTracks];

    struct RowState
    {
        int rowId = 0; // stable id
        juce::String name = "Row";
        int iconId = 0;      // UI icon enum/int
        float gainUi = 1.0f; // 0..3 UI domain
        float panUi = 0.5f;  // 0..1 UI domain
        bool muted = false;
        std::vector<AutomationPoint> automationPoints;

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

    juce::LinearSmoothedValue<float> recPeak; // optional amplitude meter
    std::mutex graphRenderMutex;

    void rebuildBusesAndRewireClips();
    void attachRowBusNodes(RowState &r);
    void ensureRowBusNodesAttached(int rowIndex);
    void retargetRowMeterTapPointers();
    void rebuildRowIdIndexCache();
    juce::AudioProcessorGraph::Node::Ptr getRowInputNodeById(int rowId);
    int getRowIndexById(int rowId) const;
    void compactRowFxChain(int row);
    void compactMasterFxChain();
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

        // ===============================
        // MASTER METER TAP (POST-FX/GAIN/PAN)
        // ===============================
        // capture output (for metering purposes) before processing metronome
        engine.updateMasterMeterFromOutput(outputChannelData, numOutputChannels, numSamples);

        if (!enabled || !isPlaying)
            return;

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
