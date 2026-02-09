#pragma once

#include "JuceHeader.h"
#include "SimpleGainProcessor.h"
#include "NativeEffects.h"
#include "JuceLogBridge.h"

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
        double startMs = transportPositionSeconds.load(std::memory_order_relaxed) * 1000.0;
        const double stepMs = 1000.0 / currentSampleRate;

        for (int sample = 0; sample < numSamples; ++sample)
        {
            const double tMs = startMs + stepMs * sample;
            const float g = getGainAt(localPoints, tMs);

            for (int ch = 0; ch < numChannels; ++ch)
                buffer.getWritePointer(ch)[sample] *= g;
        }

        // advance transport
        double old = transportPositionSeconds.load(std::memory_order_relaxed);
        const double deltaSec = (double)numSamples / currentSampleRate;
        transportPositionSeconds.store(old + deltaSec, std::memory_order_relaxed);
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

    void setTransportPosition(double seconds)
    {
        transportPositionSeconds.store(seconds, std::memory_order_relaxed);
    }

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

    std::atomic<double> transportPositionSeconds{0.0};
    double currentSampleRate = 44100.0;
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
// JuceEngine
// ---------------------------
class JuceEngine
{
public:
    static JuceEngine &get();

    void initialiseEngine();
    void loadTrack(int idx, const juce::File &file);                    // deprecated name (clip)
    void loadClip(int clipIndex, int rowIndex, const juce::File &file); // main API
    void removeTrack(int clipIndex);                                    // removes clip
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
    juce::String exportTrack(int trackIndex, const juce::File &outFile);
    void play();
    void pause();
    void seek(int trackIndex, double positionSeconds);
    void bypassPlugin(int trackIndex, int effectIndex, bool shouldBypass);
    bool getPluginBypassState(int trackIndex, int effectIndex);
    void bypassTrack(int trackIndex, bool shouldBypass);
    juce::Array<juce::PluginDescription> getKnownPlugins() const;
    void insertPluginEffect(int trackIdx, const juce::String &pluginPath, std::function<void(bool)> callback);
    void shutdownEngine();

    // special functions for "video audio" lane
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
    void moveClipToRow(int clipIndex, int newRow);

    // ROW (track bus) FX
    void insertTrackEffect(int trackRow, const juce::String &pluginPath, std::function<void(bool)> callback);
    void removeTrackEffect(int trackRow, int effectIndex);
    void reorderTrackEffects(int trackRow, int fromIndex, int toIndex);
    void setTrackEffectParameter(int trackRow,
                                 int effectIndex,
                                 const juce::String &paramName,
                                 const juce::var &newValue);
    juce::StringArray getTrackEffectsForRow(int trackRow);
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
    void insertMasterEffect(const juce::String &pluginPath, std::function<void(bool)> callback);
    void removeMasterEffect(int effectIndex);
    void reorderMasterEffects(int fromIndex, int toIndex);
    void setMasterEffectParameter(int effectIndex,
                                  const juce::String &paramName,
                                  const juce::var &newValue);
    juce::StringArray getMasterEffects();
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

private:
    JuceEngine();
    ~JuceEngine();

    void rewireTrackChain(int trackIdx);         // clip-level FX+gain+pan → row
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
    juce::Array<juce::AudioProcessorGraph::Node::Ptr> trackNodes;                       // clips
    juce::Array<SimpleGainProcessor *> gainProcessors;                                  // per-clip gain
    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackEffectChains; // per-clip FX (legacy but safe)

    juce::KnownPluginList pluginList;
    std::vector<juce::String> getExposedParametersForPlugin(const juce::String &pluginId);

    juce::AudioDeviceManager deviceManager;
    juce::AudioProcessorPlayer audioPlayer;

    // Playback-only "video audio" lane (excluded from exports)
    juce::AudioProcessorGraph::Node::Ptr videoAudioNode{nullptr};
    SimpleGainProcessor *videoGainProc{nullptr};
    bool hasVideoAudio{false};

    // Basic limits
    static constexpr int kNumTracks = 5;  // row buses
    static constexpr int kMaxClips = 500; // safety cap for simultaneous clips

    // CLIP-level panning & routing
    juce::Array<StereoPanProcessor *> clipPanProcessors; // per-clip pan
    juce::Array<int> clipTrackAssignments;               // which row track this clip feeds (0..kNumTracks-1)

    // TRACK (row) buses: input → [FX] → automation → gain → pan → master
    TrackInputProcessor *trackInputProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackInputNodes[kNumTracks];

    juce::OwnedArray<juce::Array<juce::AudioProcessorGraph::NodeID>> trackBusEffectChains;

    VolumeAutomationProcessor *trackAutomationProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackAutomationNodes[kNumTracks];

    SimpleGainProcessor *trackGainProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackGainNodes[kNumTracks];

    StereoPanProcessor *trackPanProcessors[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr trackPanNodes[kNumTracks];

    // MASTER bus: [FX...] → gain → pan → output
    juce::Array<juce::AudioProcessorGraph::NodeID> *masterEffectChain = nullptr;

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

    // METERING
    struct StereoMeterState
    {
        std::atomic<float> peakL{0.0f};
        std::atomic<float> peakR{0.0f};
        std::atomic<float> rmsL{0.0f};
        std::atomic<float> rmsR{0.0f};
    };
    StereoMeterState masterMeter;
    std::atomic<bool> masterMeterEnabled{true};
    std::atomic<bool> masterClipLatched{false};

    // Row meters (post row-pan)
    StereoMeterState rowMeters[kNumTracks];
    std::atomic<bool> rowMetersEnabled{true};

    MeterTapProcessor *rowMeterTaps[kNumTracks] = {nullptr};
    juce::AudioProcessorGraph::Node::Ptr rowMeterTapNodes[kNumTracks];
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
