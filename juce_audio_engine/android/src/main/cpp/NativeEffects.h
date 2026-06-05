#pragma once
#include "JuceHeader.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <limits>
#include <vector>

#define numOutputs 2

namespace mixroom::fx
{
inline std::atomic<double> &globalTempoBpm()
{
    static std::atomic<double> bpm{120.0};
    return bpm;
}

inline void setGlobalTempoBpm(double bpm)
{
    globalTempoBpm().store(juce::jlimit(1.0, 400.0, bpm), std::memory_order_relaxed);
}

inline double getGlobalTempoBpm()
{
    return juce::jlimit(1.0, 400.0, globalTempoBpm().load(std::memory_order_relaxed));
}

inline std::atomic<double> &globalTransportSeconds()
{
    static std::atomic<double> seconds{0.0};
    return seconds;
}

inline void setGlobalTransportSeconds(double seconds)
{
    globalTransportSeconds().store(juce::jmax(0.0, seconds), std::memory_order_relaxed);
}

inline double getGlobalTransportSeconds()
{
    return juce::jmax(0.0, globalTransportSeconds().load(std::memory_order_relaxed));
}

inline std::atomic<bool> &globalTransportPlaying()
{
    static std::atomic<bool> playing{false};
    return playing;
}

inline void setGlobalTransportPlaying(bool playing)
{
    globalTransportPlaying().store(playing, std::memory_order_relaxed);
}

inline bool getGlobalTransportPlaying()
{
    return globalTransportPlaying().load(std::memory_order_relaxed);
}
} // namespace mixroom::fx

// using namespace juce;

inline void copyToFixedStereoBuffer(const juce::AudioBuffer<float> &source,
                                    juce::AudioBuffer<float> &destination)
{
    const int channelsToCopy =
        juce::jmin(source.getNumChannels(), destination.getNumChannels());
    const int numSamples =
        juce::jmin(source.getNumSamples(), destination.getNumSamples());

    destination.clear();
    if (channelsToCopy <= 0 || numSamples <= 0)
        return;

    for (int channel = 0; channel < channelsToCopy; ++channel)
        destination.copyFrom(channel, 0, source, channel, 0, numSamples);

    // Keep the internal FX buffers stereo even when host supplies mono.
    if (channelsToCopy == 1 && destination.getNumChannels() > 1)
        destination.copyFrom(1, 0, destination, 0, 0, numSamples);
}

inline double sanitiseEffectSampleRate(double sampleRate)
{
    return std::isfinite(sampleRate) ? juce::jmax(8000.0, sampleRate) : 44100.0;
}

inline float clampFilterFrequencyForSampleRate(float hz,
                                               double sampleRate,
                                               float minHz = 20.0f,
                                               float guardHz = 50.0f)
{
    const double effectiveRate = sanitiseEffectSampleRate(sampleRate);
    const double nyquist = effectiveRate * 0.5;
    const float maxHz = static_cast<float>(juce::jmax(
        static_cast<double>(minHz) + 10.0,
        nyquist - static_cast<double>(guardHz)));
    return juce::jlimit(minHz, maxHz, hz);
}

// ****REVERB****

struct ReverbParams
{
    float roomSize, damping, mix, predelay,
        modDepth, modRate, hpfFreq, lpfFreq;
};

class ReverbModule
{
public:
    ReverbModule()
    {
        // reset delayline to use constructor with maximum delay argument
        processChain.get<ChainIndex::Delay>() =
            juce::dsp::DelayLine<float, juce::dsp::DelayLineInterpolationTypes::Linear>(44100);
    }

    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        parameters.roomSize = apvts.getRawParameterValue("roomSize")->load() * 0.01f;
        parameters.damping = apvts.getRawParameterValue("damping")->load() * 0.01f;
        parameters.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
        parameters.predelay = apvts.getRawParameterValue("predelay")->load();
        parameters.modDepth = apvts.getRawParameterValue("modDepth")->load() * 0.005f;
        parameters.modRate = apvts.getRawParameterValue("modRate")->load();
        parameters.hpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("hpfFreq")->load(),
            sampleRate);
        parameters.lpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("lpfFreq")->load(),
            sampleRate,
            20.0f,
            10.0f);
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
        lastDelaySamples = -1.0f;
        lastModDepth = -1.0f;
        lastModRate = -1.0f;
        lastRoomSize = -1.0f;
        lastDamping = -1.0f;
        prepareProcessChain();
        reset();
    }

    void reset()
    {
        processChain.reset();
        dryBuffer.clear();
        wetBuffer.clear();
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int blockSamples = inputBuffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(inputBuffer, dryBuffer);
        copyToFixedStereoBuffer(inputBuffer, wetBuffer);
        setupDelay();
        setupFilters();
        setupModulation();
        setupReverb();
        wetBuffer.applyGain(0.5f); // reverb is loud
        auto wetBlock = juce::dsp::AudioBlock<float>(wetBuffer)
                            .getSubBlock(0, (size_t)blockSamples);
        juce::dsp::ProcessContextReplacing<float> wetContext(wetBlock);
        processChain.process(wetContext);
        mixToOutput(inputBuffer, blockSamples);
    }

private:
    static bool nearlyEqual(float a, float b, float epsilon = 1.0e-4f)
    {
        return std::abs(a - b) <= epsilon;
    }

    void prepareProcessChain()
    {
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        processChain.prepare(spec);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        prepareProcessChain();
        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
    }

    void setupDelay()
    {
        const float delaySamples =
            static_cast<float>(parameters.predelay * sampleRate * 0.001f);
        if (nearlyEqual(delaySamples, lastDelaySamples, 0.25f))
            return;

        processChain.get<ChainIndex::Delay>().setDelay(delaySamples);
        lastDelaySamples = delaySamples;
    }

    void setupFilters()
    {
        constexpr float kFreqEpsilon = 0.01f;
        if (std::abs(parameters.hpfFreq - lastHpfFreq) < kFreqEpsilon &&
            std::abs(parameters.lpfFreq - lastLpfFreq) < kFreqEpsilon)
            return;

        *processChain.get<ChainIndex::HPF>().state =
            *juce::dsp::IIR::Coefficients<float>::makeHighPass(sampleRate, parameters.hpfFreq);
        *processChain.get<ChainIndex::LPF>().state =
            *juce::dsp::IIR::Coefficients<float>::makeLowPass(sampleRate, parameters.lpfFreq);
        lastHpfFreq = parameters.hpfFreq;
        lastLpfFreq = parameters.lpfFreq;
    }

    void setupModulation()
    {
        if (nearlyEqual(parameters.modDepth, lastModDepth) &&
            nearlyEqual(parameters.modRate, lastModRate))
            return;

        processChain.get<ChainIndex::Chorus>().setCentreDelay(1.0f);
        processChain.get<ChainIndex::Chorus>().setFeedback(0.0f);
        processChain.get<ChainIndex::Chorus>().setMix(1.0f);
        processChain.get<ChainIndex::Chorus>().setDepth(parameters.modDepth);
        processChain.get<ChainIndex::Chorus>().setRate(parameters.modRate);
        lastModDepth = parameters.modDepth;
        lastModRate = parameters.modRate;
    }

    void setupReverb()
    {
        if (nearlyEqual(parameters.roomSize, lastRoomSize) &&
            nearlyEqual(parameters.damping, lastDamping))
            return;

        reverbParameters.roomSize = parameters.roomSize;
        reverbParameters.damping = parameters.damping;
        reverbParameters.width = 1.0f;
        reverbParameters.freezeMode = 0.0f;
        reverbParameters.wetLevel = 1.0f;
        reverbParameters.dryLevel = 0.0f;
        processChain.get<ChainIndex::Verb>().setParameters(reverbParameters);
        lastRoomSize = parameters.roomSize;
        lastDamping = parameters.damping;
    }

    void mixToOutput(juce::AudioBuffer<float> &buffer, int blockSamples)
    {
        const float dryMix = std::sin(0.5f * juce::float_Pi * (1.0f - parameters.mix));
        const float wetMix = std::sin(0.5f * juce::float_Pi * parameters.mix);
        const int channels = juce::jmin(
            numOutputs,
            juce::jmin(buffer.getNumChannels(), dryBuffer.getNumChannels()));
        const int samples = juce::jmin(
            blockSamples,
            juce::jmin(buffer.getNumSamples(), dryBuffer.getNumSamples()));
        for (int sample = 0; sample < samples; sample++)
        {
            for (int channel = 0; channel < channels; channel++)
            {
                const float drySample = dryBuffer.getSample(channel, sample) * dryMix;
                const float wetSample = wetBuffer.getSample(channel, sample) * wetMix;
                buffer.setSample(channel, sample, wetSample + drySample);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
    float lastHpfFreq{-1.0f};
    float lastLpfFreq{-1.0f};
    float lastDelaySamples{-1.0f};
    float lastModDepth{-1.0f};
    float lastModRate{-1.0f};
    float lastRoomSize{-1.0f};
    float lastDamping{-1.0f};
    juce::AudioBuffer<float> dryBuffer, wetBuffer;
    ReverbParams parameters;
    juce::Reverb::Parameters reverbParameters;
    using StereoFilter = juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>, juce::dsp::IIR::Coefficients<float>>;
    juce::dsp::ProcessorChain<juce::dsp::Chorus<float>, juce::dsp::DelayLine<float, juce::dsp::DelayLineInterpolationTypes::Linear>,
                              juce::dsp::Reverb, StereoFilter, StereoFilter>
        processChain;
    enum ChainIndex
    {
        Chorus,
        Delay,
        Verb,
        HPF,
        LPF
    };
};

class ReverbAudioProcessor : public juce::AudioProcessor
{
public:
    ReverbAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    ~ReverbAudioProcessor() override {}
    const juce::String getName() const override { return "Reverb"; }
    double getTailLengthSeconds() const override
    {
        const auto mix = (double)parameters.getRawParameterValue("mix")->load() * 0.01;
        if (mix <= 0.0001)
            return 0.0;

        const double roomSize =
            (double)parameters.getRawParameterValue("roomSize")->load() * 0.01;
        const double damping =
            (double)parameters.getRawParameterValue("damping")->load() * 0.01;
        const double predelaySec =
            (double)parameters.getRawParameterValue("predelay")->load() / 1000.0;
        const double decaySec = 0.35 + (roomSize * 7.5) + ((1.0 - damping) * 2.5);
        return juce::jlimit(0.0, 12.0, predelaySec + decaySec);
    }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;

private:
    ReverbModule reverb;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ReverbAudioProcessor)
};

// ****EQ****

struct EQParameters
{
    bool band1Bell, band4Bell, hpfBypass, lpfBypass;
    float hpfFreq, lpfFreq,
        band1Freq, band1Gain, band1Q,
        band2Freq, band2Gain, band2Q,
        band3Freq, band3Gain, band3Q,
        band4Freq, band4Gain, band4Q;
    int hpfSlope, lpfSlope;
};

class Equalizer
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        parameters.hpfFreq = apvts.getRawParameterValue("hpfFreq")->load();
        parameters.hpfSlope = static_cast<int>(apvts.getRawParameterValue("hpfSlope")->load());
        parameters.hpfBypass = apvts.getRawParameterValue("hpfBypass")->load();
        parameters.lpfFreq = apvts.getRawParameterValue("lpfFreq")->load();
        parameters.lpfSlope = static_cast<int>(apvts.getRawParameterValue("lpfSlope")->load());
        parameters.lpfBypass = apvts.getRawParameterValue("lpfBypass")->load();
        parameters.band1Freq = apvts.getRawParameterValue("band1Freq")->load();
        parameters.band1Gain = apvts.getRawParameterValue("band1Gain")->load();
        parameters.band1Q = apvts.getRawParameterValue("band1Q")->load();
        parameters.band2Freq = apvts.getRawParameterValue("band2Freq")->load();
        parameters.band2Gain = apvts.getRawParameterValue("band2Gain")->load();
        parameters.band2Q = apvts.getRawParameterValue("band2Q")->load();
        parameters.band3Freq = apvts.getRawParameterValue("band3Freq")->load();
        parameters.band3Gain = apvts.getRawParameterValue("band3Gain")->load();
        parameters.band3Q = apvts.getRawParameterValue("band3Q")->load();
        parameters.band4Freq = apvts.getRawParameterValue("band4Freq")->load();
        parameters.band4Gain = apvts.getRawParameterValue("band4Gain")->load();
        parameters.band4Q = apvts.getRawParameterValue("band4Q")->load();
        parameters.band1Bell = apvts.getRawParameterValue("band1Bell")->load();
        parameters.band4Bell = apvts.getRawParameterValue("band4Bell")->load();

        parameters.hpfFreq = clampFrequency(parameters.hpfFreq);
        parameters.lpfFreq = clampFrequency(parameters.lpfFreq);
        parameters.band1Freq = clampFrequency(parameters.band1Freq);
        parameters.band2Freq = clampFrequency(parameters.band2Freq);
        parameters.band3Freq = clampFrequency(parameters.band3Freq);
        parameters.band4Freq = clampFrequency(parameters.band4Freq);

        if (parameters.lpfFreq <= parameters.hpfFreq + 10.0f)
            parameters.lpfFreq = clampFrequency(parameters.hpfFreq + 10.0f);
    }

    void prepare(double newSampleRate, int maxBlockSize)
    {
        sampleRate = newSampleRate;
        bufferSize = maxBlockSize;
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = newSampleRate;
        spec.maximumBlockSize = maxBlockSize;
        spec.numChannels = numOutputs;
        processChain.prepare(spec);
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        setupHPF();
        setupLPF();
        setupBands();
        juce::dsp::AudioBlock<float> block(inputBuffer);
        juce::dsp::ProcessContextReplacing<float> context(block);
        processChain.process(context);
    }

private:
    float clampFrequency(float hz) const
    {
        constexpr float minHz = 20.0f;
        const double nyquist = sampleRate > 0.0 ? sampleRate * 0.5 : 22050.0;
        const float maxHz = (float)juce::jmax((double)minHz + 10.0, nyquist - 50.0);
        return juce::jlimit(minHz, maxHz, hz);
    }

    void setupHPF()
    {
        if (parameters.hpfBypass)
        {
            processChain.setBypassed<ChainIndex::HPF>(true);
        }
        else
        {
            processChain.setBypassed<ChainIndex::HPF>(false);
            *processChain.get<ChainIndex::HPF>().state =
                *juce::dsp::FilterDesign<float>::designIIRHighpassHighOrderButterworthMethod(
                    parameters.hpfFreq, sampleRate, 2 * (parameters.hpfSlope + 1))[0];
        }
    }

    void setupLPF()
    {
        if (parameters.lpfBypass)
        {
            processChain.setBypassed<ChainIndex::LPF>(true);
        }
        else
        {
            processChain.setBypassed<ChainIndex::LPF>(false);
            *processChain.get<ChainIndex::LPF>().state =
                *juce::dsp::FilterDesign<float>::designIIRLowpassHighOrderButterworthMethod(
                    parameters.lpfFreq, sampleRate, 2 * (parameters.lpfSlope + 1))[0];
        }
    }

    void setupBands()
    {
        *processChain.get<ChainIndex::Band1>().state = (parameters.band1Bell) ? *juce::dsp::IIR::Coefficients<float>::makePeakFilter(sampleRate, parameters.band1Freq,
                                                                                                                                     parameters.band1Q, juce::Decibels::decibelsToGain(parameters.band1Gain))
                                                                              : *juce::dsp::IIR::Coefficients<float>::makeLowShelf(sampleRate, parameters.band1Freq,
                                                                                                                                   parameters.band1Q, juce::Decibels::decibelsToGain(parameters.band1Gain));
        *processChain.get<ChainIndex::Band2>().state =
            *juce::dsp::IIR::Coefficients<float>::makePeakFilter(sampleRate, parameters.band2Freq,
                                                                 parameters.band2Q, juce::Decibels::decibelsToGain(parameters.band2Gain));
        *processChain.get<ChainIndex::Band3>().state =
            *juce::dsp::IIR::Coefficients<float>::makePeakFilter(sampleRate, parameters.band3Freq,
                                                                 parameters.band3Q, juce::Decibels::decibelsToGain(parameters.band3Gain));
        *processChain.get<ChainIndex::Band4>().state = (parameters.band4Bell) ? *juce::dsp::IIR::Coefficients<float>::makePeakFilter(sampleRate, parameters.band4Freq,
                                                                                                                                     parameters.band4Q, juce::Decibels::decibelsToGain(parameters.band4Gain))
                                                                              : *juce::dsp::IIR::Coefficients<float>::makeHighShelf(sampleRate, parameters.band4Freq,
                                                                                                                                    parameters.band4Q, juce::Decibels::decibelsToGain(parameters.band4Gain));
    }

    double sampleRate{0.0};
    int bufferSize{0};
    EQParameters parameters;
    using StereoFilter = juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>,
                                                        juce::dsp::IIR::Coefficients<float>>;
    juce::dsp::ProcessorChain<StereoFilter, StereoFilter, StereoFilter, StereoFilter,
                              StereoFilter, StereoFilter>
        processChain;
    enum ChainIndex
    {
        HPF,
        LPF,
        Band1,
        Band2,
        Band3,
        Band4
    };
};

#define numFilters 2
#define numBands 4

class EQAudioProcessor : public juce::AudioProcessor
{
public:
    EQAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;
    std::vector<float> getRecentWaveform(int sampleCount) const;

    ~EQAudioProcessor() override {}
    const juce::String getName() const override { return "EQ Parametric"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;
    const juce::StringArray filterSlopes{"12 dB/Oct", "24 dB/Oct", "36 dB/Oct"};

private:
    static constexpr int kWaveformRingSize = 4096;
    void pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept;

    Equalizer equalizer;
    const std::array<float, numBands> defaultFreq{60.0f, 400.0f, 2000.0f, 8000.0f};
    std::array<float, kWaveformRingSize> waveformRing{};
    std::atomic<int> waveformWritePos{0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(EQAudioProcessor)
};

// ****DELAY****

struct DelayParameters
{
    float delayTime, feedback, width, mix,
        modRate, modDepth, hpfFreq, lpfFreq, drive;
    bool bpmSync;
    int subdivisionIndex;
};

class Delay
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts, double inputBPM)
    {
        bpm = inputBPM;
        const float inputDelay = apvts.getRawParameterValue("delayTime")->load();
        const float inputWidth = apvts.getRawParameterValue("width")->load();
        parameters.width = static_cast<float>(inputWidth * sanitiseEffectSampleRate(sampleRate) * 0.001f);
        parameters.feedback = apvts.getRawParameterValue("feedback")->load();
        parameters.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
        parameters.modDepth = apvts.getRawParameterValue("modDepth")->load() * 0.005f;
        parameters.modRate = apvts.getRawParameterValue("modRate")->load();
        parameters.hpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("hpfFreq")->load(),
            sampleRate);
        parameters.lpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("lpfFreq")->load(),
            sampleRate,
            20.0f,
            10.0f);
        parameters.drive = apvts.getRawParameterValue("drive")->load();
        parameters.bpmSync = apvts.getRawParameterValue("bpmSync")->load();
        parameters.subdivisionIndex = static_cast<int>(
            apvts.getRawParameterValue("subdivisionIndex")->load());
        setDelayTime(apvts, inputDelay);
        // ensure delay time doesn't exceed delayBufferSize
        const int maxDelaySamples = juce::jmax(1, delayBufferSize - currentBlockSize);
        parameters.delayTime = juce::jlimit(0.0f,
                                            static_cast<float>(maxDelaySamples),
                                            parameters.delayTime);
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        currentBlockSize = bufferSize;
        writePosition = 0;
        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
        lastModDepth = -1.0f;
        lastModRate = -1.0f;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.clear();
        delayBufferSize = static_cast<int>(2.0 * (bufferSize + sampleRate));
        delayBuffer.setSize(numOutputs, delayBufferSize);
        delayBuffer.clear();
        prepareDspChains();
        reset();
    }

    void reset()
    {
        writePosition = 0;
        dryBuffer.clear();
        wetBuffer.clear();
        delayBuffer.clear();
        modChain.reset();
        filterChain.reset();
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int blockSamples = inputBuffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        currentBlockSize = juce::jmin(blockSamples, bufferSize);

        copyToFixedStereoBuffer(inputBuffer, dryBuffer);
        fillDelayBuffer();
        readDelayBuffer();
        applyFilters();
        applyDistortion();
        applyModulation();
        applyFeedback();
        incrementWritePosition();
        mixToOutput(inputBuffer, currentBlockSize);
    }

private:
    void prepareDspChains()
    {
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        modChain.prepare(spec);
        filterChain.prepare(spec);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        currentBlockSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.clear();

        delayBufferSize = static_cast<int>(2.0 * (bufferSize + sampleRate));
        delayBuffer.setSize(numOutputs, delayBufferSize);
        delayBuffer.clear();
        writePosition = 0;
        prepareDspChains();
        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
        lastModDepth = -1.0f;
        lastModRate = -1.0f;
    }

    void incrementWritePosition()
    {
        writePosition = (writePosition + currentBlockSize) % delayBufferSize;
    }

    void setDelayTime(const juce::AudioProcessorValueTreeState &apvts, float inputDelay)
    {
        juce::ignoreUnused(apvts);
        // convert delay time to samples based on sync status
        if (parameters.bpmSync)
        {
            parameters.delayTime = static_cast<float>(
                subdivisions[parameters.subdivisionIndex] * sampleRate * 60.0 / bpm);
        }
        else
        {
            parameters.delayTime = static_cast<float>(inputDelay * sanitiseEffectSampleRate(sampleRate) * 0.001f);
        }
    }

    // write dry buffer into delay buffer
    void fillDelayBuffer()
    {
        for (int channel = 0; channel < numOutputs; channel++)
        {
            if (currentBlockSize + writePosition <= delayBufferSize)
            {
                delayBuffer.copyFrom(channel, writePosition,
                                     dryBuffer.getReadPointer(channel), currentBlockSize);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - writePosition;
                delayBuffer.copyFrom(channel, writePosition,
                                     dryBuffer.getReadPointer(channel), bufferRemaining);
                delayBuffer.copyFrom(channel, 0, dryBuffer.getReadPointer(channel, bufferRemaining),
                                     currentBlockSize - bufferRemaining);
            }
        }
    }

    // write delay buffer with delay into wet buffer
    void readDelayBuffer()
    {
        std::array<int, numOutputs> readPosition = {
            static_cast<int>(delayBufferSize + writePosition -
                             parameters.delayTime - parameters.width) %
                delayBufferSize,
            static_cast<int>(delayBufferSize + writePosition -
                             parameters.delayTime + parameters.width) %
                delayBufferSize};
        for (int channel = 0; channel < numOutputs; channel++)
        {
            if (currentBlockSize + readPosition[channel] <= delayBufferSize)
            {
                wetBuffer.copyFrom(channel, 0,
                                   delayBuffer.getReadPointer(channel, readPosition[channel]), currentBlockSize);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - readPosition[channel];
                wetBuffer.copyFrom(channel, 0,
                                   delayBuffer.getReadPointer(channel, readPosition[channel]), bufferRemaining);
                wetBuffer.copyFrom(channel, bufferRemaining,
                                   delayBuffer.getReadPointer(channel), currentBlockSize - bufferRemaining);
            }
        }
    }

    // add feedback from wet buffer to delay buffer
    void applyFeedback()
    {
        const float feedbackGain = parameters.feedback * 0.01f;
        for (int channel = 0; channel < numOutputs; channel++)
        {
            if (delayBufferSize > currentBlockSize + writePosition)
            {
                delayBuffer.addFromWithRamp(channel, writePosition,
                                            wetBuffer.getWritePointer(channel), currentBlockSize, feedbackGain, feedbackGain);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - writePosition;
                delayBuffer.addFromWithRamp(channel, writePosition,
                                            wetBuffer.getWritePointer(channel), bufferRemaining, feedbackGain, feedbackGain);
                delayBuffer.addFromWithRamp(channel, 0, wetBuffer.getWritePointer(channel),
                                            currentBlockSize - bufferRemaining, feedbackGain, feedbackGain);
            }
        }
    }

    void applyFilters()
    {
        constexpr float kFreqEpsilon = 0.01f;
        const bool needsFilterUpdate =
            std::abs(parameters.hpfFreq - lastHpfFreq) >= kFreqEpsilon ||
            std::abs(parameters.lpfFreq - lastLpfFreq) >= kFreqEpsilon;
        if (needsFilterUpdate)
        {
        *filterChain.get<0>().state = *juce::dsp::FilterDesign<float>::
                                          designIIRHighpassHighOrderButterworthMethod(parameters.hpfFreq, sampleRate, 2)[0];
        *filterChain.get<1>().state = *juce::dsp::FilterDesign<float>::
                                          designIIRLowpassHighOrderButterworthMethod(parameters.lpfFreq, sampleRate, 2)[0];
            lastHpfFreq = parameters.hpfFreq;
            lastLpfFreq = parameters.lpfFreq;
        }
        auto filterBlock = juce::dsp::AudioBlock<float>(wetBuffer)
                               .getSubBlock(0, (size_t)currentBlockSize);
        juce::dsp::ProcessContextReplacing<float> filterContext(filterBlock);
        filterChain.process(filterContext);
    }

    void applyDistortion()
    {
        for (int sample = 0; sample < currentBlockSize; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                float wetSample = wetBuffer.getSample(channel, sample);
                wetSample *= (parameters.drive / 30.0f) + 1.0f;                                  // drive
                wetSample = (2.0f / juce::float_Pi) * atan((juce::float_Pi / 2.0f) * wetSample); // atan waveshaping
                wetSample *= juce::Decibels::decibelsToGain(parameters.drive / -12.0f);          // autogain
                wetBuffer.setSample(channel, sample, wetSample);
            }
        }
    }

    void applyModulation()
    {
        constexpr float kModEpsilon = 0.0001f;
        if (std::abs(parameters.modDepth - lastModDepth) >= kModEpsilon ||
            std::abs(parameters.modRate - lastModRate) >= kModEpsilon)
        {
            modChain.setCentreDelay(1.0f);
            modChain.setFeedback(0.0f);
            modChain.setMix(1.0f);
            modChain.setDepth(parameters.modDepth);
            modChain.setRate(parameters.modRate);
            lastModDepth = parameters.modDepth;
            lastModRate = parameters.modRate;
        }
        auto modBlock = juce::dsp::AudioBlock<float>(wetBuffer)
                            .getSubBlock(0, (size_t)currentBlockSize);
        juce::dsp::ProcessContextReplacing<float> modContext(modBlock);
        modChain.process(modContext);
    }

    void mixToOutput(juce::AudioBuffer<float> &buffer, int blockSamples)
    {
        const float dryMix = std::sin(0.5f * juce::float_Pi * (1.0f - parameters.mix));
        const float wetMix = std::sin(0.5f * juce::float_Pi * parameters.mix);
        const int channels = juce::jmin(
            numOutputs,
            juce::jmin(buffer.getNumChannels(), dryBuffer.getNumChannels()));
        const int samples = juce::jmin(
            blockSamples,
            juce::jmin(buffer.getNumSamples(), dryBuffer.getNumSamples()));
        for (int sample = 0; sample < samples; sample++)
        {
            for (int channel = 0; channel < channels; channel++)
            {
                const float drySample = dryBuffer.getSample(channel, sample) * dryMix;
                const float wetSample = wetBuffer.getSample(channel, sample) * wetMix;
                buffer.setSample(channel, sample, wetSample + drySample);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
    int delayBufferSize{0};
    int currentBlockSize{0};
    int writePosition{0};
    double bpm{0.0};
    float lastHpfFreq{-1.0f};
    float lastLpfFreq{-1.0f};
    float lastModDepth{-1.0f};
    float lastModRate{-1.0f};
    DelayParameters parameters;
    const std::array<float, 13> subdivisions{0.25f, (0.5f / 3.0f), 0.375f, 0.5f,
                                             (1.0f / 3.0f), 0.75f, 1.0f, (2.0f / 3.0f), 1.5f, 2.0f, (4.0f / 3.0f), 3.0f, 4.0f};
    juce::AudioBuffer<float> dryBuffer, wetBuffer, delayBuffer;
    juce::dsp::Chorus<float> modChain;
    using StereoFilter = juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>,
                                                        juce::dsp::IIR::Coefficients<float>>;
    juce::dsp::ProcessorChain<StereoFilter, StereoFilter> filterChain;
};

class DelayAudioProcessor : public juce::AudioProcessor
{
public:
    DelayAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    ~DelayAudioProcessor() override {}
    const juce::String getName() const override { return "Delay"; }
    double getTailLengthSeconds() const override
    {
        const double mix = (double)parameters.getRawParameterValue("mix")->load() * 0.01;
        if (mix <= 0.0001)
            return 0.0;

        const double bpm = resolvePlaybackBpm();
        const double baseDelayMs = resolveDelayTimeMs(bpm);
        const double stereoWidthMs =
            (double)parameters.getRawParameterValue("width")->load();
        const double feedback =
            juce::jlimit(0.0, 0.999, (double)parameters.getRawParameterValue("feedback")->load() * 0.01);
        const double repeatGapSec =
            juce::jmax(0.0, (baseDelayMs + stereoWidthMs) / 1000.0);

        if (repeatGapSec <= 0.0)
            return 0.0;
        if (feedback <= 0.0001)
            return juce::jlimit(0.0, 20.0, repeatGapSec);

        const double repeatsUntilSilent =
            std::ceil(std::log(0.0005) / std::log(feedback));
        return juce::jlimit(
            0.0,
            20.0,
            repeatGapSec * juce::jmax(1.0, repeatsUntilSilent));
    }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;

private:
    double resolvePlaybackBpm() const
    {
        if (auto *currentPlayHead = getPlayHead())
        {
            juce::AudioPlayHead::CurrentPositionInfo info;
            if (currentPlayHead->getCurrentPosition(info) &&
                std::isfinite(info.bpm) &&
                info.bpm >= 1.0 &&
                info.bpm <= 400.0)
            {
                return info.bpm;
            }
        }

        return mixroom::fx::getGlobalTempoBpm();
    }

    double resolveDelayTimeMs(double bpm) const
    {
        const bool bpmSync =
            parameters.getRawParameterValue("bpmSync")->load() >= 0.5f;
        if (!bpmSync)
            return (double)parameters.getRawParameterValue("delayTime")->load();

        const int subdivisionIndex = juce::jlimit(
            0,
            (int)delaySubdivisionRatios.size() - 1,
            (int)parameters.getRawParameterValue("subdivisionIndex")->load());
        return delaySubdivisionRatios[(size_t)subdivisionIndex] * 60000.0 /
               juce::jlimit(1.0, 400.0, bpm);
    }

    Delay delay;
    static constexpr std::array<double, 13> delaySubdivisionRatios{
        0.25,
        (0.5 / 3.0),
        0.375,
        0.5,
        (1.0 / 3.0),
        0.75,
        1.0,
        (2.0 / 3.0),
        1.5,
        2.0,
        (4.0 / 3.0),
        3.0,
        4.0,
    };
    const juce::StringArray delaySubdivisions{"16th", "16th Triplet", "16th Dotted",
                                              "8th", "8th Triplet", "8th Dotted", "Quarter", "Quarter Triplet", "Quarter Dotted",
                                              "Half", "Half Triplet", "Half Dotted", "Whole"};
    juce::AudioPlayHead *playHead;
    juce::AudioPlayHead::CurrentPositionInfo cpi;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(DelayAudioProcessor)
};

// ****DISTORTION****

struct DistortionParameters
{
    float drive, volume, offset, mix, anger,
        hpfFreq, lpfFreq, shape;
    int distortionType;
    bool shapeTilt;
};

class Distortion
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        parameters.drive = apvts.getRawParameterValue("drive")->load();
        parameters.volume = apvts.getRawParameterValue("volume")->load();
        parameters.offset = apvts.getRawParameterValue("offset")->load() * 0.005f;
        parameters.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
        parameters.anger = apvts.getRawParameterValue("anger")->load();
        parameters.distortionType = static_cast<int>(apvts.getRawParameterValue("type")->load());
        parameters.hpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("hpf")->load(),
            sampleRate);
        parameters.lpfFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("lpf")->load(),
            sampleRate,
            20.0f,
            10.0f);
        parameters.shape = apvts.getRawParameterValue("shape")->load();
        parameters.shapeTilt = apvts.getRawParameterValue("shapeTilt")->load();
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        const int up = oversampler.getOversamplingFactor();
        sampleRate = sanitiseEffectSampleRate(inputSampleRate) * up;
        bufferSize = 0;
        oversamplerInputBlockSize = 0;
        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
        lastShapeDb = -1000.0f;
        lastShapeTilt = false;
        ensureCapacity(maxBlockSize);
    }

    void process(const juce::dsp::ProcessContextReplacing<float> &context)
    {
        const int inputSamples = (int)context.getInputBlock().getNumSamples();
        if (inputSamples <= 0)
            return;

        if (juce::jlimit(0.0f, 1.0f, parameters.mix) <= 1.0e-4f)
            return;

        ensureCapacity(inputSamples);
        auto upsampleBlock = oversampler.processSamplesUp(context.getInputBlock());
        dryBuffer.clear();
        bandBuffer.clear();
        const int channels = juce::jmin(numOutputs, (int)upsampleBlock.getNumChannels());
        const int samples = juce::jmin(dryBuffer.getNumSamples(), (int)upsampleBlock.getNumSamples());
        for (int channel = 0; channel < channels; channel++)
        {
            dryBuffer.copyFrom(channel, 0, upsampleBlock.getChannelPointer(channel), samples);
            bandBuffer.copyFrom(channel, 0, upsampleBlock.getChannelPointer(channel), samples);
        }

        auto wetBlock = upsampleBlock.getSubBlock(0, (size_t)samples);
        auto cleanBandBlock = juce::dsp::AudioBlock<float>(bandBuffer).getSubBlock(0, (size_t)samples);

        applyDriveBandFilters(cleanBandBlock);
        for (int channel = 0; channel < channels; ++channel)
            juce::FloatVectorOperations::copy(
                wetBlock.getChannelPointer(channel),
                bandBuffer.getReadPointer(channel),
                samples);

        applyPreShape(wetBlock);
        distortBuffer(wetBlock);
        applyDcFilter(wetBlock);
        replaceDriveBand(wetBlock, dryBuffer, bandBuffer);
        applyWetOutputGain(wetBlock);
        applyMix(wetBlock, dryBuffer);
        oversampler.processSamplesDown(context.getOutputBlock());
    }

    int getOversamplerLatency()
    {
        return static_cast<int>(oversampler.getLatencyInSamples());
    }

    void reset()
    {
        bandFilterChain.reset();
        preShapeChain.reset();
        dcFilter.reset();
        oversampler.reset();
        dryBuffer.clear();
        bandBuffer.clear();
    }

private:
    void ensureCapacity(int inputBlockSamples)
    {
        const int requiredInputSamples = juce::jmax(1, inputBlockSamples);
        const int up = oversampler.getOversamplingFactor();
        const int requiredBufferSamples = requiredInputSamples * up;

        if (requiredBufferSamples <= bufferSize &&
            requiredInputSamples <= oversamplerInputBlockSize)
            return;

        bufferSize = juce::jmax(bufferSize, requiredBufferSamples);
        oversamplerInputBlockSize = juce::jmax(oversamplerInputBlockSize, requiredInputSamples);

        dryBuffer.setSize(numOutputs, bufferSize);
        bandBuffer.setSize(numOutputs, bufferSize);

        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        bandFilterChain.prepare(spec);
        preShapeChain.prepare(spec);
        dcFilter.prepare(spec);
        *dcFilter.state = *juce::dsp::IIR::Coefficients<float>::makeHighPass(sampleRate, 10.0f);
        bandFilterChain.reset();
        preShapeChain.reset();
        dcFilter.reset();

        oversampler.reset();
        oversampler.initProcessing((juce::uint32)oversamplerInputBlockSize);

        lastHpfFreq = -1.0f;
        lastLpfFreq = -1.0f;
        lastShapeDb = -1000.0f;
        lastShapeTilt = false;
    }

    void applyDriveBandFilters(juce::dsp::AudioBlock<float> &block)
    {
        constexpr float kFreqEpsilon = 0.01f;
        if (std::abs(parameters.hpfFreq - lastHpfFreq) >= kFreqEpsilon ||
            std::abs(parameters.lpfFreq - lastLpfFreq) >= kFreqEpsilon)
        {
            *bandFilterChain.get<BandFilterIndex::HPF>().state =
                *juce::dsp::IIR::Coefficients<float>::makeHighPass(sampleRate, parameters.hpfFreq);
            *bandFilterChain.get<BandFilterIndex::LPF>().state =
                *juce::dsp::IIR::Coefficients<float>::makeLowPass(sampleRate, parameters.lpfFreq);
            lastHpfFreq = parameters.hpfFreq;
            lastLpfFreq = parameters.lpfFreq;
        }
        juce::dsp::ProcessContextReplacing<float> filterContext(block);
        bandFilterChain.process(filterContext);
    }

    void applyPreShape(juce::dsp::AudioBlock<float> &block)
    {
        constexpr float kShapeEpsilon = 0.01f;
        if (std::abs(parameters.shape - lastShapeDb) >= kShapeEpsilon)
        {
            *preShapeChain.get<ShapeFilterIndex::LowShelf>().state =
                *juce::dsp::IIR::Coefficients<float>::makeLowShelf(
                    sampleRate,
                    900.0f,
                    0.4f,
                    juce::Decibels::decibelsToGain(parameters.shape * -1.0f));
            *preShapeChain.get<ShapeFilterIndex::HighShelf>().state =
                *juce::dsp::IIR::Coefficients<float>::makeHighShelf(
                    sampleRate,
                    900.0f,
                    0.4f,
                    juce::Decibels::decibelsToGain(parameters.shape));
            lastShapeDb = parameters.shape;
        }
        if (parameters.shapeTilt != lastShapeTilt)
        {
            preShapeChain.setBypassed<ShapeFilterIndex::HighShelf>(!parameters.shapeTilt);
            lastShapeTilt = parameters.shapeTilt;
        }
        juce::dsp::ProcessContextReplacing<float> filterContext(block);
        preShapeChain.process(filterContext);
    }

    void applyDcFilter(juce::dsp::AudioBlock<float> &block)
    {
        juce::dsp::ProcessContextReplacing<float> filterContext(block);
        dcFilter.process(filterContext);
    }

    void distortBuffer(juce::dsp::AudioBlock<float> &block)
    {
        const float autoGain = juce::Decibels::decibelsToGain(parameters.drive / -5.0f) *
                               (-0.7f * parameters.anger + 1.0f);
        const int channels = juce::jmin(numOutputs, (int)block.getNumChannels());
        const int samples = juce::jmin(bufferSize, (int)block.getNumSamples());
        for (int sample = 0; sample < samples; sample++)
        {
            for (int channel = 0; channel < channels; channel++)
            {
                float wetSample = block.getSample(channel, sample);
                wetSample *= (parameters.drive / 10.0f) + 1.0f;      // apply drive
                wetSample += parameters.offset;                      // apply dc offset
                distortSample(wetSample, parameters.distortionType); // apply distortion
                wetSample *= autoGain;                               // apply autogain
                block.setSample(channel, sample, wetSample);
            }
        }
    }

    void replaceDriveBand(juce::dsp::AudioBlock<float> &distortedBandBlock,
                          const juce::AudioBuffer<float> &dryBlock,
                          const juce::AudioBuffer<float> &cleanBandBlock)
    {
        const int channels = juce::jmin(
            numOutputs,
            juce::jmin((int)distortedBandBlock.getNumChannels(),
                       juce::jmin(dryBlock.getNumChannels(), cleanBandBlock.getNumChannels())));
        const int samples = juce::jmin(
            bufferSize,
            juce::jmin((int)distortedBandBlock.getNumSamples(),
                       juce::jmin(dryBlock.getNumSamples(), cleanBandBlock.getNumSamples())));

        // Replace only the selected band with its distorted version.
        for (int sample = 0; sample < samples; ++sample)
        {
            for (int channel = 0; channel < channels; ++channel)
            {
                const float drySample = dryBlock.getSample(channel, sample);
                const float cleanBandSample = cleanBandBlock.getSample(channel, sample);
                const float distortedBandSample = distortedBandBlock.getSample(channel, sample);
                distortedBandBlock.setSample(
                    channel,
                    sample,
                    drySample + distortedBandSample - cleanBandSample);
            }
        }
    }

    void applyWetOutputGain(juce::dsp::AudioBlock<float> &block)
    {
        const float outputGain = juce::Decibels::decibelsToGain(parameters.volume);
        const int channels = juce::jmin(numOutputs, (int)block.getNumChannels());
        const int samples = juce::jmin(bufferSize, (int)block.getNumSamples());
        for (int sample = 0; sample < samples; ++sample)
        {
            for (int channel = 0; channel < channels; ++channel)
                block.setSample(channel, sample, block.getSample(channel, sample) * outputGain);
        }
    }

    void distortSample(float &sample, int type)
    {
        float angerValue;
        switch (type)
        {
        case 0: // inverse absolute value
            angerValue = -0.9f * parameters.anger + 1.0f;
            sample = sample / (angerValue + std::abs(sample));
            break;
        case 1: // arctan
            angerValue = -2.5f * parameters.anger + 3.0f;
            sample = (2.0f / juce::float_Pi) * std::atan((juce::float_Pi / angerValue) * sample);
            break;
        case 2: // erf
            angerValue = -2.5f * parameters.anger + 3.0f;
            sample = std::erf(sample * std::sqrt(juce::float_Pi) / angerValue);
            break;
        case 3: // inverse square root
            angerValue = 4.5f * parameters.anger + 0.5f;
            sample = sample / std::sqrt((1.0f / angerValue) + (sample * sample));
            break;
        }
    }

    void applyMix(juce::dsp::AudioBlock<float> &wetBlock, const juce::AudioBuffer<float> &dryBlock)
    {
        const float dryMix = std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - parameters.mix)), 2.0f);
        const float wetMix = std::pow(std::sin(0.5f * juce::float_Pi * parameters.mix), 2.0f);
        const int channels =
            juce::jmin(numOutputs, juce::jmin((int)wetBlock.getNumChannels(), dryBlock.getNumChannels()));
        const int samples =
            juce::jmin(bufferSize, juce::jmin((int)wetBlock.getNumSamples(), dryBlock.getNumSamples()));
        for (int sample = 0; sample < samples; sample++)
        {
            for (int channel = 0; channel < channels; channel++)
            {
                const float wetSample = wetBlock.getSample(channel, sample) * wetMix;
                const float drySample = dryBlock.getSample(channel, sample) * dryMix;
                wetBlock.setSample(channel, sample, wetSample + drySample);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
    int oversamplerInputBlockSize{0};
    DistortionParameters parameters;
    juce::AudioBuffer<float> dryBuffer;
    juce::AudioBuffer<float> bandBuffer;
    using StereoFilter = juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>,
                                                        juce::dsp::IIR::Coefficients<float>>;
    juce::dsp::ProcessorChain<StereoFilter, StereoFilter> bandFilterChain;
    juce::dsp::ProcessorChain<StereoFilter, StereoFilter> preShapeChain;
    enum BandFilterIndex
    {
        HPF,
        LPF
    };
    enum ShapeFilterIndex
    {
        LowShelf,
        HighShelf
    };
    StereoFilter dcFilter;
    float lastHpfFreq{-1.0f};
    float lastLpfFreq{-1.0f};
    float lastShapeDb{-1000.0f};
    bool lastShapeTilt{false};
    juce::dsp::Oversampling<float> oversampler{2, 1,
                                               juce::dsp::Oversampling<float>::filterHalfBandPolyphaseIIR, false, true};
};

class DistortionAudioProcessor : public juce::AudioProcessor
{
public:
    DistortionAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    ~DistortionAudioProcessor() override {}
    const juce::String getName() const override { return "Distortion"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;

private:
    Distortion distortion;
    const juce::StringArray distortionTypes{"Mode 1", "Mode 2", "Mode 3", "Mode 4"};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(DistortionAudioProcessor)
};

// ****DEGRADE****

struct DegradeParameters
{
    float toneHz{6000.0f};
    float depthPercent{35.0f};
    float spreadPercent{40.0f};
    int modeIndex{0};
};

class DegradeModule
{
public:
    void prepare(double newSampleRate, int)
    {
        sampleRate = sanitiseEffectSampleRate(newSampleRate);
        maxDelaySamples = juce::jmax(
            8,
            (int)std::ceil(sampleRate * kMaxModDelayMs * 0.001) + 6);

        int desiredRingSize = 1;
        while (desiredRingSize < (maxDelaySamples + 8))
            desiredRingSize <<= 1;

        ringMask = desiredRingSize - 1;
        for (auto &ring : delayRings)
            ring.assign((size_t)desiredRingSize, 0.0f);

        reset();
    }

    void reset()
    {
        for (auto &ring : delayRings)
            std::fill(ring.begin(), ring.end(), 0.0f);

        for (auto &filter : noiseFilters)
            filter.reset();

        writePos = 0;
        sinePhase = 0.0;
        lastToneHz = -1.0f;
        lastSpreadPercent = -1.0f;
    }

    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.modeIndex = juce::jlimit(
            0, 2,
            (int)std::round(apvts.getRawParameterValue("mode")->load()));
        params.toneHz = juce::jlimit(
            20.0f,
            static_cast<float>(sampleRate * 0.45),
            apvts.getRawParameterValue("tone")->load());
        params.depthPercent = juce::jlimit(
            0.0f, 100.0f,
            apvts.getRawParameterValue("depth")->load());
        params.spreadPercent = juce::jlimit(
            0.0f, 100.0f,
            apvts.getRawParameterValue("spread")->load());

        updateNoiseFilters();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int channels = juce::jmin(buffer.getNumChannels(), numOutputs);
        const int numSamples = buffer.getNumSamples();
        if (channels <= 0 || numSamples <= 0 || ringMask <= 0)
            return;

        for (int sample = 0; sample < numSamples; ++sample)
        {
            const float sharedMod =
                params.modeIndex == 1 ? 0.0f : nextSharedModSample();

            for (int channel = 0; channel < channels; ++channel)
            {
                const float input = buffer.getSample(channel, sample);
                delayRings[(size_t)channel][(size_t)writePos] = input;

                const float mod = params.modeIndex == 1
                                      ? nextWideNoiseModSample(channel)
                                      : sharedMod;
                const float delaySamples = computeDelaySamples(mod);
                buffer.setSample(
                    channel,
                    sample,
                    readDelayedSample(
                        delayRings[(size_t)channel],
                        writePos,
                        ringMask,
                        delaySamples));
            }

            writePos = (writePos + 1) & ringMask;
        }
    }

private:
    static constexpr float kMaxModDelayMs = 5.0f;

    static float spreadPercentToOctaves(float spreadPercent)
    {
        const float norm =
            juce::jlimit(0.0f, 1.0f, spreadPercent * 0.01f);
        return 0.15f + (7.85f * norm * norm);
    }

    static float bandwidthOctavesToQ(double sampleRate,
                                     float centreHz,
                                     float bandwidthOctaves)
    {
        const double clampedCentre = juce::jlimit(
            20.0,
            sampleRate * 0.45,
            static_cast<double>(centreHz));
        const double omega = juce::MathConstants<double>::twoPi * clampedCentre /
                             sampleRate;
        const double sine = juce::jmax(1.0e-6, std::sin(omega));
        const double spread = std::sinh(
            (std::log(2.0) * 0.5) * bandwidthOctaves * (omega / sine));

        if (!std::isfinite(spread) || spread <= 1.0e-6)
            return 12.0f;

        return juce::jlimit(
            0.05f,
            24.0f,
            static_cast<float>(1.0 / (2.0 * spread)));
    }

    void updateNoiseFilters()
    {
        if (std::abs(params.toneHz - lastToneHz) < 0.01f &&
            std::abs(params.spreadPercent - lastSpreadPercent) < 0.01f)
            return;

        const float q = bandwidthOctavesToQ(
            sampleRate,
            params.toneHz,
            spreadPercentToOctaves(params.spreadPercent));

        for (auto &filter : noiseFilters)
            filter.setCoefficients(
                juce::IIRCoefficients::makeBandPass(sampleRate, params.toneHz, q));

        lastToneHz = params.toneHz;
        lastSpreadPercent = params.spreadPercent;
    }

    float nextSharedModSample()
    {
        if (params.modeIndex == 2)
            return nextSineSample();

        return nextNoiseSample(0);
    }

    float nextWideNoiseModSample(int channel)
    {
        return nextNoiseSample(channel);
    }

    float nextSineSample()
    {
        const auto sample = static_cast<float>(std::sin(sinePhase));
        sinePhase += juce::MathConstants<double>::twoPi *
                     static_cast<double>(params.toneHz) / sampleRate;
        while (sinePhase >= juce::MathConstants<double>::twoPi)
            sinePhase -= juce::MathConstants<double>::twoPi;
        return sample;
    }

    float nextNoiseSample(int channel)
    {
        const float white = (noiseRandoms[(size_t)channel].nextFloat() * 2.0f) - 1.0f;
        return juce::jlimit(
            -1.0f,
            1.0f,
            noiseFilters[(size_t)channel].processSingleSampleRaw(white));
    }

    float computeDelaySamples(float modSample) const
    {
        const float depthNorm = std::pow(
            juce::jlimit(0.0f, 1.0f, params.depthPercent * 0.01f),
            1.35f);
        const float maxDelay =
            static_cast<float>(juce::jmax(0, maxDelaySamples - 4)) * depthNorm;
        const float unipolar =
            0.5f * (juce::jlimit(-1.0f, 1.0f, modSample) + 1.0f);
        return maxDelay * unipolar;
    }

    static float readDelayedSample(const std::vector<float> &ring,
                                   int writeIndex,
                                   int mask,
                                   float delaySamples)
    {
        const float readPos =
            static_cast<float>(writeIndex) -
            juce::jlimit(0.0f, static_cast<float>(mask - 4), delaySamples);
        const int baseIndex = (int)std::floor(readPos);
        const float frac = readPos - static_cast<float>(baseIndex);

        const auto sampleAt = [&](int index)
        {
            return ring[(size_t)(index & mask)];
        };

        const float ym1 = sampleAt(baseIndex - 1);
        const float y0 = sampleAt(baseIndex);
        const float y1 = sampleAt(baseIndex + 1);
        const float y2 = sampleAt(baseIndex + 2);

        const float c0 = y0;
        const float c1 = 0.5f * (y1 - ym1);
        const float c2 = ym1 - (2.5f * y0) + (2.0f * y1) - (0.5f * y2);
        const float c3 =
            (0.5f * (y2 - ym1)) + (1.5f * (y0 - y1));
        return ((c3 * frac + c2) * frac + c1) * frac + c0;
    }

    double sampleRate{44100.0};
    int maxDelaySamples{0};
    int ringMask{0};
    int writePos{0};
    double sinePhase{0.0};
    float lastToneHz{-1.0f};
    float lastSpreadPercent{-1.0f};
    DegradeParameters params;
    std::array<std::vector<float>, numOutputs> delayRings;
    std::array<juce::IIRFilter, numOutputs> noiseFilters;
    std::array<juce::Random, numOutputs> noiseRandoms;
};

class DegradeAudioProcessor : public juce::AudioProcessor
{
public:
    DegradeAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;
    std::vector<float> getRecentWaveform(int sampleCount) const;

    ~DegradeAudioProcessor() override = default;
    const juce::String getName() const override { return "Degrade"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return false; }

    juce::AudioProcessorValueTreeState parameters;

private:
    static constexpr int kWaveformRingSize = 4096;
    void pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept;

    DegradeModule degrade;
    std::array<float, kWaveformRingSize> waveformRing{};
    std::atomic<int> waveformWritePos{0};
    const juce::StringArray degradeModes{"Noise", "Wide Noise", "Sine"};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(DegradeAudioProcessor)
};

// ****DE-ESSER****

struct DeEsserParameters
{
    float crossoverFreq, threshold, attackTime, releaseTime;
    bool stereo, wide, listen;
};

class Deesser
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts, bool isListen)
    {
        parameters.crossoverFreq = apvts.getRawParameterValue("crossoverFreq")->load();
        parameters.threshold = apvts.getRawParameterValue("threshold")->load();
        const float attackInput = apvts.getRawParameterValue("attack")->load();
        parameters.attackTime = std::exp(-1.0f / ((attackInput / 1000.0f) *
                                                  static_cast<float>(sampleRate)));
        const float releaseInput = apvts.getRawParameterValue("release")->load();
        parameters.releaseTime = std::exp(-1.0f / ((releaseInput / 1000.0f) *
                                                   static_cast<float>(sampleRate)));
        parameters.stereo = apvts.getRawParameterValue("stereo")->load();
        parameters.wide = apvts.getRawParameterValue("wide")->load();
        parameters.listen = isListen;
    }

    void prepare(double newSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(newSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        currentBlockSize = bufferSize;
        lowBuffer.setSize(numOutputs, bufferSize);
        highBuffer.setSize(numOutputs, bufferSize);
        compressionBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = static_cast<juce::uint32>(bufferSize);
        spec.numChannels = numOutputs;
        lowChain.prepare(spec);
        highChain.prepare(spec);
        reset();
    }

    void reset()
    {
        compressionLevel = {0.0f, 0.0f};
        outputGainReduction = {0.0f, 0.0f};
        lowBuffer.clear();
        highBuffer.clear();
        compressionBuffer.clear();
        envelopeBuffer.clear();
        lowChain.reset();
        highChain.reset();
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int blockSamples = inputBuffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        currentBlockSize = juce::jmin(blockSamples, bufferSize);
        if (currentBlockSize <= 0)
            return;
        copyToFixedStereoBuffer(inputBuffer, lowBuffer);
        copyToFixedStereoBuffer(inputBuffer, highBuffer);
        applyFilters();
        createEnvelope();
        calculateGainReduction();
        applyCompression();
        writeOutput(inputBuffer);
    }

    std::array<float, numOutputs> getGainReduction()
    {
        return std::array<float, numOutputs>{
            outputGainReduction[0] * -1.0f, outputGainReduction[1] * -1.0f};
    }

private:
    void applyFilters()
    {
        lowChain.setType(juce::dsp::LinkwitzRileyFilterType::lowpass);
        lowChain.setCutoffFrequency(parameters.crossoverFreq);
        highChain.setType(juce::dsp::LinkwitzRileyFilterType::highpass);
        highChain.setCutoffFrequency(parameters.crossoverFreq);
        auto lowBlock = juce::dsp::AudioBlock<float>(lowBuffer)
                            .getSubBlock(0, static_cast<size_t>(currentBlockSize));
        auto highBlock = juce::dsp::AudioBlock<float>(highBuffer)
                             .getSubBlock(0, static_cast<size_t>(currentBlockSize));
        juce::dsp::ProcessContextReplacing<float> lowContext(lowBlock);
        juce::dsp::ProcessContextReplacing<float> highContext(highBlock);
        lowChain.process(lowContext);
        highChain.process(highContext);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        lowBuffer.setSize(numOutputs, bufferSize);
        highBuffer.setSize(numOutputs, bufferSize);
        compressionBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);

        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = static_cast<juce::uint32>(bufferSize);
        spec.numChannels = numOutputs;
        lowChain.prepare(spec);
        highChain.prepare(spec);
    }

    void applyHisteresis(float &compLevel, float inputSample)
    {
        float histeresis = (compLevel < inputSample) ? parameters.attackTime : parameters.releaseTime;
        compLevel = inputSample + histeresis * (compLevel - inputSample);
    }

    void createEnvelope()
    {
        for (int sample = 0; sample < currentBlockSize; sample++)
        {
            if (parameters.stereo)
            {
                const float maxSample = juce::jmax(std::abs(highBuffer.getSample(0, sample)),
                                                   std::abs(highBuffer.getSample(1, sample)));
                applyHisteresis(compressionLevel[0], maxSample);
                for (int channel = 0; channel < numOutputs; channel++)
                {
                    envelopeBuffer.setSample(channel, sample, compressionLevel[0]);
                }
            }
            else
            {
                for (int channel = 0; channel < numOutputs; channel++)
                {
                    const float inputSample = std::abs(highBuffer.getSample(channel, sample));
                    applyHisteresis(compressionLevel[channel], inputSample);
                    envelopeBuffer.setSample(channel, sample, compressionLevel[channel]);
                }
            }
        }
    }

    void calculateGainReduction()
    {
        outputGainReduction = {0.0f, 0.0f};
        for (int sample = 0; sample < currentBlockSize; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                // apply threshold and ratio to envelope
                float currentGainReduction = slope * (parameters.threshold - juce::Decibels::gainToDecibels(
                                                                                 envelopeBuffer.getSample(channel, sample)));
                // remove positive gain reduction
                currentGainReduction = juce::jmin(0.0f, currentGainReduction);
                // set gr meter value
                outputGainReduction[channel] = juce::jmin(currentGainReduction, outputGainReduction[channel]);
                // convert decibels to gain
                currentGainReduction = std::pow(10.0f, 0.05f * currentGainReduction);
                // output compression multiplier to compression buffer
                compressionBuffer.setSample(channel, sample, currentGainReduction);
            }
        }
    }

    void applyCompression()
    {
        for (int channel = 0; channel < numOutputs; channel++)
        {
            // apply compression to high buffer
            juce::FloatVectorOperations::multiply(highBuffer.getWritePointer(channel),
                                                  compressionBuffer.getReadPointer(channel), currentBlockSize);
            // if wide set, also apply compression to low buffer
            if (parameters.wide)
            {
                juce::FloatVectorOperations::multiply(lowBuffer.getWritePointer(channel),
                                                      compressionBuffer.getReadPointer(channel), currentBlockSize);
            }
        }
    }

    void writeOutput(juce::AudioBuffer<float> &buffer)
    {
        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        const int samples = juce::jmin(currentBlockSize, buffer.getNumSamples());
        for (int channel = 0; channel < channels; channel++)
        {
            // if listen set, output high only, else sum low and high
            buffer.copyFrom(channel, 0, highBuffer.getReadPointer(channel), samples);
            if (!parameters.listen)
            {
                buffer.addFrom(channel, 0, lowBuffer.getReadPointer(channel), samples);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
    int currentBlockSize{0};
    float slope = 1.0f - (1.0f / 4.0f);
    DeEsserParameters parameters;
    std::array<float, numOutputs> compressionLevel{0.0f, 0.0f};
    std::array<float, numOutputs> outputGainReduction{0.0f, 0.0f};
    juce::AudioBuffer<float> lowBuffer, highBuffer, compressionBuffer, envelopeBuffer;
    juce::dsp::LinkwitzRileyFilter<float> lowChain, highChain;
};

class DeesserAudioProcessor : public juce::AudioProcessor
{
public:
    DeesserAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    ~DeesserAudioProcessor() override {}
    const juce::String getName() const override { return "De-Esser"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;
    std::array<float, numOutputs> gainReduction;
    bool listen{false};

private:
    Deesser deesser;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(DeesserAudioProcessor)
};

// =====================
// **** EQ 3-BAND ****
// =====================

// Fixed "wide" musical centers (no freq params exposed)
static constexpr float EQ3_LOW_FC = 140.0f;
static constexpr float EQ3_MID_FC = 1200.0f;
static constexpr float EQ3_HIGH_FC = 8000.0f;

// Wide curves: shelves gentle, mid broad
static constexpr float EQ3_SHELF_Q = 0.70f; // ~Butterworth-ish
static constexpr float EQ3_MID_Q = 0.60f;   // broad bell

struct EQ3Parameters
{
    float lowGainDb = 0.0f;
    float midGainDb = 0.0f;
    float highGainDb = 0.0f;
};

class EQ3Band
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.lowGainDb = apvts.getRawParameterValue("lowGain")->load();
        params.midGainDb = apvts.getRawParameterValue("midGain")->load();
        params.highGainDb = apvts.getRawParameterValue("highGain")->load();
    }

    void prepare(double newSampleRate, int maxBlockSize)
    {
        sampleRate = newSampleRate;

        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)maxBlockSize;
        spec.numChannels = numOutputs;

        chain.prepare(spec);
        chain.reset();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        updateCoefficients();

        juce::dsp::AudioBlock<float> block(buffer);
        juce::dsp::ProcessContextReplacing<float> ctx(block);
        chain.process(ctx);
    }

private:
    using StereoFilter = juce::dsp::ProcessorDuplicator<
        juce::dsp::IIR::Filter<float>,
        juce::dsp::IIR::Coefficients<float>>;

    enum ChainIndex
    {
        LowShelf,
        MidPeak,
        HighShelf
    };

    void updateCoefficients()
    {
        const auto lowG = juce::Decibels::decibelsToGain(params.lowGainDb);
        const auto midG = juce::Decibels::decibelsToGain(params.midGainDb);
        const auto highG = juce::Decibels::decibelsToGain(params.highGainDb);

        *chain.get<LowShelf>().state =
            *juce::dsp::IIR::Coefficients<float>::makeLowShelf(sampleRate, EQ3_LOW_FC, EQ3_SHELF_Q, lowG);

        *chain.get<MidPeak>().state =
            *juce::dsp::IIR::Coefficients<float>::makePeakFilter(sampleRate, EQ3_MID_FC, EQ3_MID_Q, midG);

        *chain.get<HighShelf>().state =
            *juce::dsp::IIR::Coefficients<float>::makeHighShelf(sampleRate, EQ3_HIGH_FC, EQ3_SHELF_Q, highG);
    }

    double sampleRate = 44100.0;
    EQ3Parameters params;

    juce::dsp::ProcessorChain<StereoFilter, StereoFilter, StereoFilter> chain;
};

class EQ3AudioProcessor : public juce::AudioProcessor
{
public:
    EQ3AudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

    // no editor UI inside JUCE
    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;
    std::vector<float> getRecentWaveform(int sampleCount) const;

    ~EQ3AudioProcessor() override = default;

    const juce::String getName() const override { return "EQ 3-Band"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    juce::AudioProcessorValueTreeState parameters;

private:
    EQ3Band eq3;
    static constexpr int kWaveformRingSize = 2048;
    void pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept;
    std::array<float, kWaveformRingSize> waveformRing{};
    std::atomic<int> waveformWritePos{0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(EQ3AudioProcessor)
};

// ****COMPRESSOR****

struct CompressorParameters
{
    float threshold;
    float attackCoeff;
    float releaseCoeff;
    float slope;
    float makeUpGain;
    float sidechainFreq;
    float mix;
    bool sidechainBypass;
    bool stereo;
};

class CompressorModule
{
public:
    void prepare(double newSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(newSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        currentBlockSize = bufferSize;

        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);

        for (auto &f : sidechainFilters)
        {
            f.reset();
            f.setCoefficients(
                juce::IIRCoefficients::makeHighPass(sampleRate, 20.0));
        }

        compressionLevel.fill(0.0f);
        gainReduction.fill(0.0f);
        lastSidechainFreq = 20.0f;
        reset();
    }

    void reset()
    {
        compressionLevel.fill(0.0f);
        gainReduction.fill(0.0f);
        dryBuffer.clear();
        wetBuffer.clear();
        envelopeBuffer.clear();
        for (auto &f : sidechainFilters)
            f.reset();
    }

    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.threshold = apvts.getRawParameterValue("threshold")->load();

        const float attackMs = apvts.getRawParameterValue("attack")->load();
        const float releaseMs = apvts.getRawParameterValue("release")->load();

        params.attackCoeff = std::exp(-1.0f / ((attackMs * 0.001f) * sampleRate));
        params.releaseCoeff = std::exp(-1.0f / ((releaseMs * 0.001f) * sampleRate));

        const float ratio = apvts.getRawParameterValue("ratio")->load();
        params.slope = 1.0f - (1.0f / ratio);

        params.makeUpGain = apvts.getRawParameterValue("makeUp")->load();
        params.sidechainFreq = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("scFreq")->load(),
            sampleRate,
            20.0f,
            10.0f);
        params.sidechainBypass = apvts.getRawParameterValue("scBypass")->load();
        params.stereo = apvts.getRawParameterValue("stereo")->load();
        params.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;

        if (!nearlyEqual(params.sidechainFreq, lastSidechainFreq, 0.01f))
        {
            for (auto &f : sidechainFilters)
                f.setCoefficients(
                    juce::IIRCoefficients::makeHighPass(sampleRate, params.sidechainFreq));
            lastSidechainFreq = params.sidechainFreq;
        }
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        juce::ScopedNoDenormals noDenormals;

        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        currentBlockSize = juce::jmin(blockSamples, bufferSize);
        if (currentBlockSize <= 0)
            return;

        copyToFixedStereoBuffer(buffer, dryBuffer);
        copyToFixedStereoBuffer(buffer, wetBuffer);

        if (!params.sidechainBypass)
            applySidechainFilter();

        createEnvelope();
        applyCompression();
        mixToOutput(buffer);
    }

    std::array<float, numOutputs> getGainReduction() const
    {
        return {
            -gainReduction[0],
            -gainReduction[1]};
    }

private:
    static bool nearlyEqual(float a, float b, float epsilon = 1.0e-4f)
    {
        return std::abs(a - b) <= epsilon;
    }

    void applySidechainFilter()
    {
        for (int ch = 0; ch < numOutputs; ++ch)
            sidechainFilters[ch].processSamples(
                wetBuffer.getWritePointer(ch), currentBlockSize);
    }

    void applyEnvelope(float &env, float input)
    {
        const float coeff = (input > env) ? params.attackCoeff : params.releaseCoeff;
        env = input + coeff * (env - input);
    }

    void createEnvelope()
    {
        for (int i = 0; i < currentBlockSize; ++i)
        {
            if (params.stereo)
            {
                const float s = std::max(
                    std::abs(wetBuffer.getSample(0, i)),
                    std::abs(wetBuffer.getSample(1, i)));

                applyEnvelope(compressionLevel[0], s);

                envelopeBuffer.setSample(0, i, compressionLevel[0]);
                envelopeBuffer.setSample(1, i, compressionLevel[0]);
            }
            else
            {
                for (int ch = 0; ch < numOutputs; ++ch)
                {
                    const float s = std::abs(wetBuffer.getSample(ch, i));
                    applyEnvelope(compressionLevel[ch], s);
                    envelopeBuffer.setSample(ch, i, compressionLevel[ch]);
                }
            }
        }
    }

    void applyCompression()
    {
        gainReduction = {0.0f, 0.0f};

        for (int i = 0; i < currentBlockSize; ++i)
        {
            for (int ch = 0; ch < numOutputs; ++ch)
            {
                float grDb =
                    params.slope *
                    (params.threshold -
                     juce::Decibels::gainToDecibels(
                         envelopeBuffer.getSample(ch, i)));

                grDb = juce::jmin(0.0f, grDb);
                gainReduction[ch] = juce::jmin(grDb, gainReduction[ch]);

                const float gain =
                    juce::Decibels::decibelsToGain(grDb + params.makeUpGain);

                wetBuffer.setSample(
                    ch, i,
                    dryBuffer.getSample(ch, i) * gain);
            }
        }
    }

    void mixToOutput(juce::AudioBuffer<float> &buffer)
    {
        const float dryMix =
            std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - params.mix)), 2.0f);
        const float wetMix =
            std::pow(std::sin(0.5f * juce::float_Pi * params.mix), 2.0f);
        const int channels =
            juce::jmin(numOutputs, juce::jmin(buffer.getNumChannels(), dryBuffer.getNumChannels()));
        const int samples =
            juce::jmin(currentBlockSize, juce::jmin(buffer.getNumSamples(), dryBuffer.getNumSamples()));

        for (int i = 0; i < samples; ++i)
            for (int ch = 0; ch < channels; ++ch)
                buffer.setSample(
                    ch, i,
                    dryBuffer.getSample(ch, i) * dryMix +
                        wetBuffer.getSample(ch, i) * wetMix);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);
    }

    double sampleRate = 0.0;
    int bufferSize = 0;
    int currentBlockSize = 0;

    CompressorParameters params;
    float lastSidechainFreq = -1.0f;

    std::array<float, numOutputs> compressionLevel{};
    std::array<float, numOutputs> gainReduction{};

    juce::AudioBuffer<float> dryBuffer, wetBuffer, envelopeBuffer;
    std::array<juce::IIRFilter, numOutputs> sidechainFilters;
};

class CompressorAudioProcessor : public juce::AudioProcessor
{
public:
    CompressorAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &) override {}
    void setStateInformation(const void *, int) override {}

    const juce::String getName() const override { return "Compressor"; }

    juce::AudioProcessorValueTreeState parameters;
    std::array<float, numOutputs> gainReduction;

    // Meter strip values
    std::array<float, 5> getMeterStrip() const noexcept
    {
        return {
            inRmsL.load(std::memory_order_relaxed),
            inRmsR.load(std::memory_order_relaxed),
            grDb.load(std::memory_order_relaxed),
            outRmsL.load(std::memory_order_relaxed),
            outRmsR.load(std::memory_order_relaxed),
        };
    }

private:
    CompressorModule compressor;

    std::atomic<float> inRmsL{0.0f};
    std::atomic<float> inRmsR{0.0f};
    std::atomic<float> outRmsL{0.0f};
    std::atomic<float> outRmsR{0.0f};
    std::atomic<float> grDb{0.0f};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(CompressorAudioProcessor)
};

// ****LIMITER****

struct LimiterParameters
{
    float threshold;
    float ceiling;
    float releaseTime;
    bool stereo;
};

class LimiterModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        const float threshold = apvts.getRawParameterValue("threshold")->load();
        const float ceiling = apvts.getRawParameterValue("ceiling")->load();
        const float releaseInput = apvts.getRawParameterValue("release")->load();
        const bool stereo = apvts.getRawParameterValue("stereo")->load();

        if (!std::isfinite(lastThreshold) || !nearlyEqual(threshold, lastThreshold))
        {
            parameters.threshold = threshold;
            lastThreshold = threshold;
        }

        if (!std::isfinite(lastCeiling) || !nearlyEqual(ceiling, lastCeiling))
        {
            parameters.ceiling = ceiling;
            lastCeiling = ceiling;
        }

        if (!std::isfinite(lastReleaseInput) || !nearlyEqual(releaseInput, lastReleaseInput, 0.01f))
        {
            parameters.releaseTime = static_cast<float>(
                std::exp(-1.0f / (releaseInput * sampleRate / 1000.0)));
            lastReleaseInput = releaseInput;
        }

        if (stereo != lastStereo)
        {
            parameters.stereo = stereo;
            lastStereo = stereo;
        }
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        currentBlockSize = bufferSize;
        compressionBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);
        lastThreshold = std::numeric_limits<float>::quiet_NaN();
        lastCeiling = std::numeric_limits<float>::quiet_NaN();
        lastReleaseInput = std::numeric_limits<float>::quiet_NaN();
        lastStereo = false;
        reset();
    }

    void reset()
    {
        compressionLevel = {0.0f, 0.0f};
        outputGainReduction = {0.0f, 0.0f};
        compressionBuffer.clear();
        envelopeBuffer.clear();
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int blockSamples = inputBuffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        currentBlockSize = juce::jmin(blockSamples, bufferSize);
        if (currentBlockSize <= 0)
            return;
        copyToFixedStereoBuffer(inputBuffer, compressionBuffer);
        createEnvelope();
        calculateGainReduction();
        applyLimiting(inputBuffer);
    }

    std::array<float, numOutputs> getGainReduction() const
    {
        return std::array<float, numOutputs>{
            outputGainReduction[0] * -1.0f,
            outputGainReduction[1] * -1.0f,
        };
    }

private:
    static bool nearlyEqual(float a, float b, float epsilon = 1.0e-4f)
    {
        return std::abs(a - b) <= epsilon;
    }

    void applyHysteresis(float &compLevel, float inputSample)
    {
        const float releaseLevel =
            inputSample + parameters.releaseTime * (compLevel - inputSample);
        compLevel = (compLevel < inputSample) ? inputSample : releaseLevel;
    }

    void createEnvelope()
    {
        for (int sample = 0; sample < currentBlockSize; ++sample)
        {
            if (parameters.stereo)
            {
                const float maxSample = juce::jmax(
                    std::abs(compressionBuffer.getSample(0, sample)),
                    std::abs(compressionBuffer.getSample(1, sample)));

                applyHysteresis(compressionLevel[0], maxSample);
                for (int channel = 0; channel < numOutputs; ++channel)
                    envelopeBuffer.setSample(channel, sample, compressionLevel[0]);
            }
            else
            {
                for (int channel = 0; channel < numOutputs; ++channel)
                {
                    const float inputSample = std::abs(compressionBuffer.getSample(channel, sample));
                    applyHysteresis(compressionLevel[channel], inputSample);
                    envelopeBuffer.setSample(channel, sample, compressionLevel[channel]);
                }
            }
        }
    }

    void calculateGainReduction()
    {
        outputGainReduction = {0.0f, 0.0f};

        for (int sample = 0; sample < currentBlockSize; ++sample)
        {
            for (int channel = 0; channel < numOutputs; ++channel)
            {
                float currentGainReduction =
                    parameters.threshold -
                    juce::Decibels::gainToDecibels(envelopeBuffer.getSample(channel, sample));

                currentGainReduction = juce::jmin(0.0f, currentGainReduction);
                outputGainReduction[channel] =
                    juce::jmin(currentGainReduction, outputGainReduction[channel]);

                currentGainReduction += parameters.ceiling - parameters.threshold;
                currentGainReduction =
                    std::pow(10.0f, 0.05f * currentGainReduction);

                compressionBuffer.setSample(channel, sample, currentGainReduction);
            }
        }
    }

    void applyLimiting(juce::AudioBuffer<float> &buffer)
    {
        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        for (int channel = 0; channel < channels; ++channel)
        {
            juce::FloatVectorOperations::multiply(
                buffer.getWritePointer(channel),
                compressionBuffer.getReadPointer(channel),
                currentBlockSize);
        }
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        compressionBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);
    }

    double sampleRate{0.0};
    int bufferSize{0};
    int currentBlockSize{0};

    LimiterParameters parameters;
    std::array<float, numOutputs> compressionLevel{0.0f, 0.0f};
    std::array<float, numOutputs> outputGainReduction{0.0f, 0.0f};
    float lastThreshold = std::numeric_limits<float>::quiet_NaN();
    float lastCeiling = std::numeric_limits<float>::quiet_NaN();
    float lastReleaseInput = std::numeric_limits<float>::quiet_NaN();
    bool lastStereo = false;

    juce::AudioBuffer<float> compressionBuffer, envelopeBuffer;
};

class LimiterAudioProcessor : public juce::AudioProcessor
{
public:
    LimiterAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Limiter"; }

    juce::AudioProcessorValueTreeState parameters;
    std::array<float, numOutputs> gainReduction;
    std::array<float, 5> getMeterStrip() const noexcept
    {
        return {
            0.0f,
            0.0f,
            grDb.load(std::memory_order_relaxed),
            0.0f,
            0.0f,
        };
    }

private:
    LimiterModule limiter;
    std::atomic<float> grDb{0.0f};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(LimiterAudioProcessor)
};

// ****CLIPPER****

struct ClipperParameters
{
    float threshold;
    float ceiling;
};

class ClipperModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        parameters.threshold = apvts.getRawParameterValue("threshold")->load();
        parameters.ceiling = apvts.getRawParameterValue("ceiling")->load();
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        bufferSize = maxBlockSize;
        oversampledBufferSize = maxBlockSize * 4;
        oversampler.reset();
        oversampler.initProcessing((size_t)maxBlockSize);
    }

    void process(const juce::dsp::ProcessContextReplacing<float> &context)
    {
        auto &outputBlock = context.getOutputBlock();
        auto upsampledBlock = oversampler.processSamplesUp(context.getInputBlock());
        const int nUp = (int)upsampledBlock.getNumSamples();

        clipBlock(upsampledBlock, nUp, oversampledGainReduction);
        oversampler.processSamplesDown(outputBlock);

        const int n = (int)outputBlock.getNumSamples();
        clipBlock(outputBlock, n, normalGainReduction);
        applyGain(outputBlock, n);
    }

    std::array<float, numOutputs> getGainReduction() const
    {
        return {
            oversampledGainReduction[0] + normalGainReduction[0],
            oversampledGainReduction[1] + normalGainReduction[1]};
    }

    int getOversamplerLatency() const
    {
        return (int)oversampler.getLatencyInSamples();
    }

    void reset()
    {
        oversampler.reset();
    }

private:
    void clipBlock(juce::dsp::AudioBlock<float> &block,
                   int blockSize,
                   std::array<float, numOutputs> &outGr)
    {
        outGr = {0.0f, 0.0f};
        std::array<float, numOutputs> tempGr{0.0f, 0.0f};

        const float thresholdHigh = juce::Decibels::decibelsToGain(parameters.threshold);
        const float thresholdLow = -thresholdHigh;

        const int channels = juce::jmin(numOutputs, (int)block.getNumChannels());
        const int samples = juce::jmin(blockSize, (int)block.getNumSamples());
        for (int sample = 0; sample < samples; ++sample)
        {
            for (int channel = 0; channel < channels; ++channel)
            {
                const float inputSample = block.getSample(channel, sample);
                const float outputSample = juce::jlimit(thresholdLow, thresholdHigh, inputSample);

                if (inputSample != outputSample)
                    tempGr[channel] = juce::Decibels::gainToDecibels(std::abs(inputSample) + 1.0e-9f) - parameters.threshold;

                outGr[channel] = juce::jmax(tempGr[channel], outGr[channel]);
                block.setSample(channel, sample, outputSample);
            }
        }
    }

    void applyGain(juce::dsp::AudioBlock<float> &block, int blockSize)
    {
        const float autoGain = juce::Decibels::decibelsToGain(-parameters.threshold);
        const float ceilingGain = juce::Decibels::decibelsToGain(parameters.ceiling);
        const int channels = juce::jmin(numOutputs, (int)block.getNumChannels());
        const int samples = juce::jmin(blockSize, (int)block.getNumSamples());

        for (int sample = 0; sample < samples; ++sample)
            for (int channel = 0; channel < channels; ++channel)
                block.setSample(channel, sample, block.getSample(channel, sample) * autoGain * ceilingGain);
    }

    int bufferSize{0};
    int oversampledBufferSize{0};
    ClipperParameters parameters{0.0f, 0.0f};
    std::array<float, numOutputs> oversampledGainReduction{0.0f, 0.0f};
    std::array<float, numOutputs> normalGainReduction{0.0f, 0.0f};
    juce::dsp::Oversampling<float> oversampler{
        2, 2,
        juce::dsp::Oversampling<float>::filterHalfBandPolyphaseIIR,
        false, true};
};

class ClipperAudioProcessor : public juce::AudioProcessor
{
public:
    ClipperAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Clipper"; }

    juce::AudioProcessorValueTreeState parameters;
    std::array<float, numOutputs> gainReduction;
    std::array<float, 5> getMeterStrip() const noexcept
    {
        return {
            0.0f,
            0.0f,
            grDb.load(std::memory_order_relaxed),
            0.0f,
            0.0f,
        };
    }

private:
    ClipperModule clipper;
    std::atomic<float> grDb{0.0f};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ClipperAudioProcessor)
};

// ****PITCH SHIFT****

struct PitchShiftParameters
{
    float semitones;
    float mix;
};

class PitchShiftModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.semitones = apvts.getRawParameterValue("semitones")->load();
        params.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
    }

    void setManualParameters(float semitones, float mix)
    {
        params.semitones = juce::jlimit(-12.0f, 12.0f, semitones);
        params.mix = juce::jlimit(0.0f, 1.0f, mix);
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = inputSampleRate > 0.0 ? inputSampleRate : 44100.0;
        ensureCapacity(maxBlockSize);
        reset();
    }

    void reset()
    {
        for (int ch = 0; ch < numOutputs; ++ch)
        {
            std::fill(ringBuffers[ch].begin(), ringBuffers[ch].end(), 0.0f);
            writePos[ch] = 0;
            phase[ch] = 0.0f;
        }
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int n = buffer.getNumSamples();
        ensureCapacity(n);
        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        if (n <= 0 || channels <= 0 || ringSize <= 2)
            return;

        const float ratio = std::pow(2.0f, params.semitones / 12.0f);
        const float phaseInc = (1.0f - ratio) / (float)(ringSize - 2);
        const float ringSpan = (float)(ringSize - 2);
        const float halfSpan = 0.5f * ringSpan;
        const float dryMix =
            std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - params.mix)), 2.0f);
        const float wetMix =
            std::pow(std::sin(0.5f * juce::float_Pi * params.mix), 2.0f);

        for (int ch = 0; ch < channels; ++ch)
        {
            auto &ring = ringBuffers[ch];
            float *io = buffer.getWritePointer(ch);
            int w = writePos[ch];
            float ph = phase[ch];

            for (int i = 0; i < n; ++i)
            {
                const float in = io[i];
                ring[(size_t)w] = in;

                const float d1 = ph * ringSpan;
                float d2 = d1 + halfSpan;
                if (d2 >= ringSpan)
                    d2 -= ringSpan;

                const float a = readDelayedSample(ring, w, d1);
                const float b = readDelayedSample(ring, w, d2);

                const float p1 = ph;
                float p2 = ph + 0.5f;
                if (p2 >= 1.0f)
                    p2 -= 1.0f;
                const float g1 = 0.5f - 0.5f *
                                             std::cos(juce::MathConstants<float>::twoPi * p1);
                const float g2 = 0.5f - 0.5f *
                                             std::cos(juce::MathConstants<float>::twoPi * p2);
                const float norm = juce::jmax(1.0e-6f, g1 + g2);

                const float wet = (a * g1 + b * g2) / norm;
                io[i] = in * dryMix + wet * wetMix;

                ph += phaseInc;
                if (ph >= 1.0f)
                    ph -= 1.0f;
                else if (ph < 0.0f)
                    ph += 1.0f;

                ++w;
                if (w >= ringSize)
                    w = 0;
            }

            writePos[ch] = w;
            phase[ch] = ph;
        }
    }

private:
    void ensureCapacity(int blockSize)
    {
        juce::ignoreUnused(blockSize);
        // Android hardware callbacks can arrive in very large chunks
        // (for example 1920 frames at 48 kHz). Basing the shifter window on
        // callback size turns the wet path into an audible echo. Keep the
        // pitch window sample-rate based instead so Android matches the much
        // shorter iOS live path.
        const int minDelay = juce::jlimit(
            512,
            1024,
            (int)std::lround(sampleRate * 0.02));
        const int requiredRingSize = minDelay + 2;
        if (requiredRingSize <= ringSize)
            return;

        ringSize = requiredRingSize;
        for (int ch = 0; ch < numOutputs; ++ch)
            ringBuffers[ch].assign((size_t)ringSize, 0.0f);
        reset();
    }

    static float readDelayedSample(const std::vector<float> &ring,
                                   int writeIdx,
                                   float delaySamples)
    {
        const int n = (int)ring.size();
        if (n <= 1)
            return 0.0f;

        float readPos = (float)writeIdx - delaySamples;
        if (readPos < 0.0f)
            readPos += (float)n;
        else if (readPos >= (float)n)
            readPos -= (float)n;

        const int i0 = (int)readPos;
        const int i1 = (i0 + 1) % n;
        const float frac = readPos - (float)i0;
        return ring[(size_t)i0] + (ring[(size_t)i1] - ring[(size_t)i0]) * frac;
    }

    PitchShiftParameters params{0.0f, 1.0f};
    double sampleRate{44100.0};
    int ringSize{0};
    std::array<std::vector<float>, numOutputs> ringBuffers;
    std::array<int, numOutputs> writePos{0, 0};
    std::array<float, numOutputs> phase{0.0f, 0.0f};
};

class PitchShiftAudioProcessor : public juce::AudioProcessor
{
public:
    PitchShiftAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void reset() override { pitchShift.reset(); }

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Pitch Shift"; }

    juce::AudioProcessorValueTreeState parameters;

private:
    PitchShiftModule pitchShift;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PitchShiftAudioProcessor)
};

class PitchCorrectorAudioProcessor : public juce::AudioProcessor
{
public:
    PitchCorrectorAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void reset() override
    {
        pitchShift.reset();
        smoothedCorrectionSemitones = 0.0f;
        lastDetectedPitchHz = 0.0f;
        pitchAnalysisSamplesUntilNext = 0;
        pitchAnalysisHistoryWritePos = 0;
        pitchAnalysisHistoryFilled = 0;
        std::fill(pitchAnalysisHistory.begin(), pitchAnalysisHistory.end(), 0.0f);
    }

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Pitch Corrector"; }

    juce::AudioProcessorValueTreeState parameters;

private:
    void appendPitchAnalysisSamples(const juce::AudioBuffer<float> &buffer);
    float estimatePitchHz();
    float targetCorrectionSemitones(float pitchHz, int key, int scale) const;

    PitchShiftModule pitchShift;
    std::vector<float> pitchAnalysisMono;
    std::vector<float> pitchAnalysisHistory;
    double currentSampleRate{44100.0};
    float smoothedCorrectionSemitones{0.0f};
    float lastDetectedPitchHz{0.0f};
    int pitchAnalysisIntervalSamples{1024};
    int pitchAnalysisSamplesUntilNext{0};
    int pitchAnalysisDecimation{4};
    int pitchAnalysisHistoryWritePos{0};
    int pitchAnalysisHistoryFilled{0};
    double pitchAnalysisSampleRate{12000.0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PitchCorrectorAudioProcessor)
};

// ****CHORUS****

struct ChorusParameters
{
    float rateHz;
    float depth;
    float centreDelayMs;
    float feedback;
    float mix;
};

class ChorusModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.rateHz = apvts.getRawParameterValue("rate")->load();
        params.depth = apvts.getRawParameterValue("depth")->load();
        params.centreDelayMs = apvts.getRawParameterValue("centreDelay")->load();
        params.feedback = apvts.getRawParameterValue("feedback")->load() * 0.01f;
        params.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
    }

    void prepare(double sampleRate, int maxBlockSize)
    {
        this->sampleRate = sanitiseEffectSampleRate(sampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        prepareChorus();
        lastRateHz = -1.0f;
        lastDepth = -1.0f;
        lastCentreDelayMs = -1.0f;
        lastFeedback = -2.0f;
        reset();
    }

    void reset()
    {
        dryBuffer.clear();
        wetBuffer.clear();
        chorus.reset();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int n = buffer.getNumSamples();
        if (n <= 0)
            return;

        ensureCapacity(n);
        copyToFixedStereoBuffer(buffer, dryBuffer);
        copyToFixedStereoBuffer(buffer, wetBuffer);

        constexpr float kParamEpsilon = 0.0001f;
        if (std::abs(params.rateHz - lastRateHz) >= kParamEpsilon ||
            std::abs(params.depth - lastDepth) >= kParamEpsilon ||
            std::abs(params.centreDelayMs - lastCentreDelayMs) >= kParamEpsilon ||
            std::abs(params.feedback - lastFeedback) >= kParamEpsilon)
        {
            chorus.setRate(params.rateHz);
            chorus.setDepth(params.depth);
            chorus.setCentreDelay(params.centreDelayMs);
            chorus.setFeedback(params.feedback);
            chorus.setMix(1.0f);
            lastRateHz = params.rateHz;
            lastDepth = params.depth;
            lastCentreDelayMs = params.centreDelayMs;
            lastFeedback = params.feedback;
        }

        auto wetBlock = juce::dsp::AudioBlock<float>(wetBuffer)
                            .getSubBlock(0, (size_t)n);
        juce::dsp::ProcessContextReplacing<float> ctx(wetBlock);
        chorus.process(ctx);

        const float dryMix = std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - params.mix)), 2.0f);
        const float wetMix = std::pow(std::sin(0.5f * juce::float_Pi * params.mix), 2.0f);

        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        for (int ch = 0; ch < channels; ++ch)
        {
            const float *dry = dryBuffer.getReadPointer(ch);
            const float *wet = wetBuffer.getReadPointer(ch);
            float *out = buffer.getWritePointer(ch);
            for (int i = 0; i < n; ++i)
                out[i] = dry[i] * dryMix + wet[i] * wetMix;
        }
    }

private:
    void prepareChorus()
    {
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        chorus.prepare(spec);
        chorus.reset();
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        prepareChorus();
        lastRateHz = -1.0f;
        lastDepth = -1.0f;
        lastCentreDelayMs = -1.0f;
        lastFeedback = -2.0f;
    }

    ChorusParameters params{0.8f, 0.35f, 7.0f, 0.1f, 0.35f};
    double sampleRate{44100.0};
    int bufferSize{0};
    float lastRateHz{-1.0f};
    float lastDepth{-1.0f};
    float lastCentreDelayMs{-1.0f};
    float lastFeedback{-2.0f};
    juce::AudioBuffer<float> dryBuffer, wetBuffer;
    juce::dsp::Chorus<float> chorus;
};

class ChorusAudioProcessor : public juce::AudioProcessor
{
public:
    ChorusAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Chorus"; }

    juce::AudioProcessorValueTreeState parameters;

private:
    ChorusModule chorusFx;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(ChorusAudioProcessor)
};

// ****VIBRATO****

struct VibratoParameters
{
    float rateHz;
    float depth;
    float centreDelayMs;
    float mix;
};

class VibratoModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.rateHz = apvts.getRawParameterValue("rate")->load();
        params.depth = apvts.getRawParameterValue("depth")->load();
        params.centreDelayMs = apvts.getRawParameterValue("centreDelay")->load();
        params.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
    }

    void prepare(double sampleRate, int maxBlockSize)
    {
        this->sampleRate = sanitiseEffectSampleRate(sampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        prepareVibrato();
        lastRateHz = -1.0f;
        lastDepth = -1.0f;
        lastCentreDelayMs = -1.0f;
        reset();
    }

    void reset()
    {
        dryBuffer.clear();
        wetBuffer.clear();
        vibrato.reset();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int n = buffer.getNumSamples();
        if (n <= 0)
            return;

        ensureCapacity(n);
        copyToFixedStereoBuffer(buffer, dryBuffer);
        copyToFixedStereoBuffer(buffer, wetBuffer);

        constexpr float kParamEpsilon = 0.0001f;
        if (std::abs(params.rateHz - lastRateHz) >= kParamEpsilon ||
            std::abs(params.depth - lastDepth) >= kParamEpsilon ||
            std::abs(params.centreDelayMs - lastCentreDelayMs) >= kParamEpsilon)
        {
            vibrato.setRate(params.rateHz);
            vibrato.setDepth(params.depth);
            vibrato.setCentreDelay(params.centreDelayMs);
            vibrato.setFeedback(0.0f);
            vibrato.setMix(1.0f);
            lastRateHz = params.rateHz;
            lastDepth = params.depth;
            lastCentreDelayMs = params.centreDelayMs;
        }

        auto wetBlock = juce::dsp::AudioBlock<float>(wetBuffer)
                            .getSubBlock(0, (size_t)n);
        juce::dsp::ProcessContextReplacing<float> ctx(wetBlock);
        vibrato.process(ctx);

        const float dryMix = std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - params.mix)), 2.0f);
        const float wetMix = std::pow(std::sin(0.5f * juce::float_Pi * params.mix), 2.0f);

        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        for (int ch = 0; ch < channels; ++ch)
        {
            const float *dry = dryBuffer.getReadPointer(ch);
            const float *wet = wetBuffer.getReadPointer(ch);
            float *out = buffer.getWritePointer(ch);
            for (int i = 0; i < n; ++i)
                out[i] = dry[i] * dryMix + wet[i] * wetMix;
        }
    }

private:
    void prepareVibrato()
    {
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        vibrato.prepare(spec);
        vibrato.reset();
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        prepareVibrato();
        lastRateHz = -1.0f;
        lastDepth = -1.0f;
        lastCentreDelayMs = -1.0f;
    }

    VibratoParameters params{4.5f, 0.6f, 7.0f, 1.0f};
    double sampleRate{44100.0};
    int bufferSize{0};
    float lastRateHz{-1.0f};
    float lastDepth{-1.0f};
    float lastCentreDelayMs{-1.0f};
    juce::AudioBuffer<float> dryBuffer, wetBuffer;
    juce::dsp::Chorus<float> vibrato;
};

class VibratoAudioProcessor : public juce::AudioProcessor
{
public:
    VibratoAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Vibrato"; }

    juce::AudioProcessorValueTreeState parameters;

private:
    VibratoModule vibratoFx;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(VibratoAudioProcessor)
};

// ****STEREO****

struct StereoParameters
{
    float widthPercent;
    float lowBypassHz;
    bool monoCheck;
};

class StereoModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.widthPercent = apvts.getRawParameterValue("width")->load();
        params.lowBypassHz = clampFilterFrequencyForSampleRate(
            apvts.getRawParameterValue("lowBypass")->load(),
            sampleRate,
            20.0f,
            20.0f);
        params.monoCheck = apvts.getRawParameterValue("mono")->load() >= 0.5f;
    }

    void syncParameters()
    {
        const float widthAmount =
            juce::jlimit(0.0f, 2.0f, params.widthPercent * 0.01f);
        const float lowBypassHz = clampFilterFrequencyForSampleRate(
            params.lowBypassHz,
            sampleRate,
            20.0f,
            20.0f);
        widthSmoothed.setCurrentAndTargetValue(widthAmount);
        monoSmoothed.setCurrentAndTargetValue(params.monoCheck ? 1.0f : 0.0f);
        lowBypassSmoothed.setCurrentAndTargetValue(lowBypassHz);
        updateFilters(lowBypassHz);
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        prepareFilters();
        prepareDecorrelators();
        widthSmoothed.reset(sampleRate, 0.02);
        monoSmoothed.reset(sampleRate, 0.02);
        lowBypassSmoothed.reset(sampleRate, 0.04);
        widthSmoothed.setCurrentAndTargetValue(1.0f);
        monoSmoothed.setCurrentAndTargetValue(0.0f);
        lowBypassSmoothed.setCurrentAndTargetValue(160.0f);
        lastLowBypassHz = -1.0f;
        reset();
    }

    void reset()
    {
        dryBuffer.clear();
        crossover.reset();
        resetDecorrelators();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(buffer, dryBuffer);

        const float targetWidthAmount =
            juce::jlimit(0.0f, 2.0f, params.widthPercent * 0.01f);
        const float targetLowBypassHz = clampFilterFrequencyForSampleRate(
            params.lowBypassHz,
            sampleRate,
            20.0f,
            20.0f);
        widthSmoothed.setTargetValue(targetWidthAmount);
        monoSmoothed.setTargetValue(params.monoCheck ? 1.0f : 0.0f);
        lowBypassSmoothed.setTargetValue(targetLowBypassHz);
        updateFilters(lowBypassSmoothed.skip(blockSamples));

        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());
        for (int sample = 0; sample < blockSamples; ++sample)
        {
            const float widthAmount = widthSmoothed.getNextValue();
            const float sideGain = 1.0f + (0.55f * widthAmount);
            const float synthGain = 0.85f * widthAmount;
            float lowL = 0.0f;
            float highL = 0.0f;
            float lowR = 0.0f;
            float highR = 0.0f;
            crossover.processSample(
                0,
                dryBuffer.getSample(0, sample),
                lowL,
                highL);
            crossover.processSample(
                1,
                dryBuffer.getSample(1, sample),
                lowR,
                highR);

            const float mid = 0.5f * (highL + highR);
            const float side = 0.5f * (highL - highR);
            const float decorL = processDecorBranch(0, mid);
            const float decorR = processDecorBranch(1, mid);
            const float syntheticSide = 0.5f * (decorL - decorR);
            const float widenedSide = side * sideGain + syntheticSide * synthGain;

            float outL = lowL + mid + widenedSide;
            float outR = lowR + mid - widenedSide;

            const float monoMix = monoSmoothed.getNextValue();
            const float mono = 0.5f * (outL + outR);
            outL = juce::jmap(monoMix, outL, mono);
            outR = juce::jmap(monoMix, outR, mono);

            if (channels > 0)
                buffer.setSample(0, sample, outL);
            if (channels > 1)
                buffer.setSample(1, sample, outR);
        }
    }

private:
    static bool nearlyEqual(float a, float b, float epsilon = 1.0e-3f)
    {
        return std::abs(a - b) <= epsilon;
    }

    void prepareFilters()
    {
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = (juce::uint32)bufferSize;
        spec.numChannels = (juce::uint32)numOutputs;
        crossover.prepare(spec);
        crossover.reset();
    }

    void prepareDecorrelators()
    {
        const int maxDelaySamples =
            juce::jmax(128, (int)std::ceil(sampleRate * 0.02));
        decorrelatorSize = maxDelaySamples + 4;
        for (auto &ring : decorrelatorRings)
            ring.assign((size_t)decorrelatorSize, 0.0f);
        resetDecorrelators();
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
        prepareFilters();
        lastLowBypassHz = -1.0f;
    }

    void updateFilters(float cutoffHz)
    {
        const float safeCutoff = clampFilterFrequencyForSampleRate(
            cutoffHz,
            sampleRate,
            20.0f,
            20.0f);
        if (nearlyEqual(safeCutoff, lastLowBypassHz))
            return;

        crossover.setCutoffFrequency(safeCutoff);
        lastLowBypassHz = safeCutoff;
    }

    void resetDecorrelators()
    {
        for (auto &ring : decorrelatorRings)
            std::fill(ring.begin(), ring.end(), 0.0f);
        decorrelatorWritePos.fill(0);
        decorPrevInput.fill(0.0f);
        decorPrevOutput.fill(0.0f);
    }

    float processDecorBranch(int branch, float input)
    {
        if (decorrelatorSize <= 1)
            return input;

        auto &ring = decorrelatorRings[(size_t)branch];
        int &writePos = decorrelatorWritePos[(size_t)branch];
        ring[(size_t)writePos] = input;

        const float delayMs = branch == 0 ? 7.3f : 11.1f;
        const float delayed = readDelayedSample(
            ring,
            writePos,
            (float)(sampleRate * delayMs * 0.001));
        writePos = (writePos + 1) % decorrelatorSize;

        const float coeff = branch == 0 ? 0.58f : -0.58f;
        const float output = -coeff * delayed + decorPrevInput[(size_t)branch] +
                             coeff * decorPrevOutput[(size_t)branch];
        decorPrevInput[(size_t)branch] = delayed;
        decorPrevOutput[(size_t)branch] = output;
        return output;
    }

    static float readDelayedSample(const std::vector<float> &ring,
                                   int writeIndex,
                                   float delaySamples)
    {
        const int size = (int)ring.size();
        if (size <= 1)
            return 0.0f;

        float readPos = (float)writeIndex - delaySamples;
        readPos = std::fmod(readPos, (float)size);
        if (readPos < 0.0f)
            readPos += (float)size;

        const int i0 = juce::jlimit(0, size - 1, (int)readPos);
        const int i1 = (i0 + 1 < size) ? (i0 + 1) : 0;
        const float frac = readPos - (float)i0;
        return ring[(size_t)i0] + (ring[(size_t)i1] - ring[(size_t)i0]) * frac;
    }

    StereoParameters params{100.0f, 160.0f, false};
    double sampleRate{44100.0};
    int bufferSize{0};
    int decorrelatorSize{0};
    float lastLowBypassHz{-1.0f};
    juce::AudioBuffer<float> dryBuffer;
    juce::dsp::LinkwitzRileyFilter<float> crossover;
    juce::LinearSmoothedValue<float> widthSmoothed;
    juce::LinearSmoothedValue<float> monoSmoothed;
    juce::LinearSmoothedValue<float> lowBypassSmoothed;
    std::array<std::vector<float>, 2> decorrelatorRings;
    std::array<int, 2> decorrelatorWritePos{0, 0};
    std::array<float, 2> decorPrevInput{0.0f, 0.0f};
    std::array<float, 2> decorPrevOutput{0.0f, 0.0f};
};

class StereoAudioProcessor : public juce::AudioProcessor
{
public:
    StereoAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Stereo"; }

    juce::AudioProcessorValueTreeState parameters;

private:
    enum class BypassRampDirection
    {
        none,
        toDry,
        toWet,
    };

    void ensureBypassBufferCapacity(int numSamples);
    void beginBypassRamp(BypassRampDirection direction);
    void applyBypassRamp(juce::AudioBuffer<float> &output,
                         const juce::AudioBuffer<float> &dry,
                         const juce::AudioBuffer<float> &wet);

    StereoModule stereoFx;
    double bypassSampleRate{44100.0};
    int bypassRampSamples{1};
    int bypassRampRemaining{0};
    BypassRampDirection bypassRampDirection{BypassRampDirection::none};
    bool lastBlockWasBypassed{false};
    juce::AudioBuffer<float> bypassDryBuffer;
    juce::AudioBuffer<float> bypassWetBuffer;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(StereoAudioProcessor)
};

// ****STEREO PRO****

struct StereoProParameters
{
    float gainDb;
    float widthPercent;
    float asymmetryPercent;
    float rotationDegrees;
};

class StereoProModule
{
public:
    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.gainDb = apvts.getRawParameterValue("gain")->load();
        params.widthPercent = apvts.getRawParameterValue("width")->load();
        params.asymmetryPercent = apvts.getRawParameterValue("asymmetry")->load();
        params.rotationDegrees = apvts.getRawParameterValue("rotation")->load();
    }

    void syncParameters()
    {
        gainSmoothed.setCurrentAndTargetValue(
            juce::Decibels::decibelsToGain(params.gainDb));
        widthSmoothed.setCurrentAndTargetValue(
            juce::jlimit(0.0f, 3.0f, params.widthPercent * 0.01f));
        asymmetrySmoothed.setCurrentAndTargetValue(
            juce::jlimit(-0.95f, 0.95f, params.asymmetryPercent * 0.01f));
        rotationSmoothed.setCurrentAndTargetValue(
            juce::jlimit(-1.0f, 1.0f, params.rotationDegrees / 90.0f));
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        workBuffer.setSize(numOutputs, bufferSize);
        gainSmoothed.reset(sampleRate, 0.02);
        widthSmoothed.reset(sampleRate, 0.02);
        asymmetrySmoothed.reset(sampleRate, 0.02);
        rotationSmoothed.reset(sampleRate, 0.02);
        gainSmoothed.setCurrentAndTargetValue(1.0f);
        widthSmoothed.setCurrentAndTargetValue(1.0f);
        asymmetrySmoothed.setCurrentAndTargetValue(0.0f);
        rotationSmoothed.setCurrentAndTargetValue(0.0f);
        reset();
    }

    void reset()
    {
        workBuffer.clear();
    }

    void process(juce::AudioBuffer<float> &buffer)
    {
        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(buffer, workBuffer);

        gainSmoothed.setTargetValue(
            juce::Decibels::decibelsToGain(params.gainDb));
        widthSmoothed.setTargetValue(
            juce::jlimit(0.0f, 3.0f, params.widthPercent * 0.01f));
        asymmetrySmoothed.setTargetValue(
            juce::jlimit(-0.95f, 0.95f, params.asymmetryPercent * 0.01f));
        rotationSmoothed.setTargetValue(
            juce::jlimit(-1.0f, 1.0f, params.rotationDegrees / 90.0f));
        const int channels = juce::jmin(numOutputs, buffer.getNumChannels());

        for (int sample = 0; sample < blockSamples; ++sample)
        {
            const float gain = gainSmoothed.getNextValue();
            const float width = widthSmoothed.getNextValue();
            const float asymmetry = asymmetrySmoothed.getNextValue();
            const float rotation = rotationSmoothed.getNextValue();
            float midGainL = 0.0f;
            float midGainR = 0.0f;
            float sideGainL = 0.0f;
            float sideGainR = 0.0f;
            float matrixNormalise = 1.0f;
            resolveStereoMatrix(width,
                                asymmetry,
                                rotation,
                                midGainL,
                                midGainR,
                                sideGainL,
                                sideGainR,
                                matrixNormalise);
            const float inL = workBuffer.getSample(0, sample);
            const float inR = workBuffer.getSample(1, sample);
            const float mid = 0.5f * (inL + inR);
            const float side = 0.5f * (inL - inR);

            const float rawL =
                ((mid * midGainL) + (side * sideGainL)) * matrixNormalise;
            const float rawR =
                ((mid * midGainR) - (side * sideGainR)) * matrixNormalise;
            const float outL = applyOutputSafety(gain * rawL);
            const float outR = applyOutputSafety(gain * rawR);

            if (channels > 0)
                buffer.setSample(0, sample, outL);
            if (channels > 1)
                buffer.setSample(1, sample, outR);
        }
    }

private:
    static void resolveStereoMatrix(float width,
                                    float asymmetry,
                                    float rotation,
                                    float &midGainL,
                                    float &midGainR,
                                    float &sideGainL,
                                    float &sideGainR,
                                    float &matrixNormalise)
    {
        const float angle = (rotation + 1.0f) * 0.25f * juce::float_Pi;
        midGainL = std::sqrt(2.0f) * std::cos(angle);
        midGainR = std::sqrt(2.0f) * std::sin(angle);
        sideGainL = width * (1.0f + asymmetry);
        sideGainR = width * (1.0f - asymmetry);

        const float peakL = std::abs(midGainL) + std::abs(sideGainL);
        const float peakR = std::abs(midGainR) + std::abs(sideGainR);
        const float matrixPeak = juce::jmax(1.0f, juce::jmax(peakL, peakR));
        matrixNormalise = 1.0f / matrixPeak;
    }

    static float applyOutputSafety(float sample)
    {
        if (!std::isfinite(sample))
            return 0.0f;

        constexpr float ceiling = 1.25f;
        return ceiling * std::tanh(sample / ceiling);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        workBuffer.setSize(numOutputs, bufferSize);
    }

    StereoProParameters params{0.0f, 100.0f, 0.0f, 0.0f};
    double sampleRate{44100.0};
    int bufferSize{0};
    juce::AudioBuffer<float> workBuffer;
    juce::LinearSmoothedValue<float> gainSmoothed;
    juce::LinearSmoothedValue<float> widthSmoothed;
    juce::LinearSmoothedValue<float> asymmetrySmoothed;
    juce::LinearSmoothedValue<float> rotationSmoothed;
};

class StereoProAudioProcessor : public juce::AudioProcessor
{
public:
    StereoProAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }

    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Stereo Pro"; }
    std::vector<float> getRecentScope(int pointCount) const;

    juce::AudioProcessorValueTreeState parameters;

private:
    enum class BypassRampDirection
    {
        none,
        toDry,
        toWet,
    };

    static constexpr int kScopeRingSize = 2048;
    void ensureBypassBufferCapacity(int numSamples);
    void beginBypassRamp(BypassRampDirection direction);
    void applyBypassRamp(juce::AudioBuffer<float> &output,
                         const juce::AudioBuffer<float> &dry,
                         const juce::AudioBuffer<float> &wet);
    void pushScopeSamples(const juce::AudioBuffer<float> &buffer) noexcept;
    StereoProModule stereoProFx;
    double bypassSampleRate{44100.0};
    int bypassRampSamples{1};
    int bypassRampRemaining{0};
    BypassRampDirection bypassRampDirection{BypassRampDirection::none};
    bool lastBlockWasBypassed{false};
    juce::AudioBuffer<float> bypassDryBuffer;
    juce::AudioBuffer<float> bypassWetBuffer;
    std::array<float, kScopeRingSize * 2> scopeRing{};
    std::atomic<int> scopeWritePos{0};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(StereoProAudioProcessor)
};

// ****VOLUME SHAPER****

struct VolumeShaperParameters
{
    float depthPercent;
    float mixPercent;
    float smoothPercent;
    float swingPercent;
    float phaseDegrees;
    int rateIndex;
    int shapeIndex;
};

class VolumeShaperModule
{
public:
    static constexpr std::array<double, 8> rateBeats{
        8.0,
        4.0,
        2.0,
        1.0,
        0.5,
        0.25,
        (2.0 / 3.0),
        1.5,
    };

    static const juce::StringArray rateChoices()
    {
        return {"2 Bars", "1 Bar", "1/2 Bar", "1 Beat", "1/2 Beat",
                "1/4 Beat", "Beat Triplet", "Beat Dotted"};
    }

    static const juce::StringArray shapeChoices()
    {
        return {"Duck", "Pump", "Gate", "Trance", "Chop", "Sine"};
    }

    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.depthPercent = apvts.getRawParameterValue("depth")->load();
        params.mixPercent = apvts.getRawParameterValue("mix")->load();
        params.smoothPercent = apvts.getRawParameterValue("smooth")->load();
        params.swingPercent = apvts.getRawParameterValue("swing")->load();
        params.phaseDegrees = apvts.getRawParameterValue("phase")->load();
        params.rateIndex = juce::jlimit(
            0,
            (int)rateBeats.size() - 1,
            (int)apvts.getRawParameterValue("rate")->load());
        params.shapeIndex = juce::jlimit(
            0,
            shapeChoices().size() - 1,
            (int)apvts.getRawParameterValue("shape")->load());
    }

    void syncParameters()
    {
        depthSmoothed.setCurrentAndTargetValue(
            juce::jlimit(0.0f, 1.0f, params.depthPercent * 0.01f));
        mixSmoothed.setCurrentAndTargetValue(
            juce::jlimit(0.0f, 1.0f, params.mixPercent * 0.01f));
        currentGain = computeGainForDisplay(
            params.shapeIndex,
            0.0f,
            params.depthPercent,
            params.smoothPercent,
            params.swingPercent);
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        depthSmoothed.reset(sampleRate, 0.02);
        mixSmoothed.reset(sampleRate, 0.02);
        depthSmoothed.setCurrentAndTargetValue(1.0f);
        mixSmoothed.setCurrentAndTargetValue(1.0f);
        reset();
    }

    void reset()
    {
        dryBuffer.clear();
        currentGain = 1.0f;
    }

    void process(juce::AudioBuffer<float> &buffer,
                 double blockTransportStartSec,
                 std::atomic<float> &phaseOut,
                 std::atomic<float> &gainOut)
    {
        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(buffer, dryBuffer);

        depthSmoothed.setTargetValue(
            juce::jlimit(0.0f, 1.0f, params.depthPercent * 0.01f));
        mixSmoothed.setTargetValue(
            juce::jlimit(0.0f, 1.0f, params.mixPercent * 0.01f));

        const double bpm = mixroom::fx::getGlobalTempoBpm();
        const double cycleBeats =
            rateBeats[(size_t)juce::jlimit(0, (int)rateBeats.size() - 1, params.rateIndex)];
        const float swingAmount = juce::jlimit(0.0f, 1.0f, params.swingPercent * 0.01f);
        const float phaseOffset = params.phaseDegrees / 360.0f;
        const float smoothingAlpha =
            computeSmoothingAlpha(params.smoothPercent, sampleRate);
        const int channels = juce::jmin(buffer.getNumChannels(), numOutputs);
        float lastDisplayPhase = 0.0f;

        for (int sample = 0; sample < blockSamples; ++sample)
        {
            const double transportSec =
                blockTransportStartSec + ((double)sample / sampleRate);
            const float rawPhase = wrapUnitPhase(
                resolveCyclePhase(transportSec, bpm, cycleBeats) + phaseOffset);
            const float displayPhase = applySwing(rawPhase, swingAmount);
            const float targetGain = computeGainForDisplay(
                params.shapeIndex,
                rawPhase,
                params.depthPercent,
                params.smoothPercent,
                params.swingPercent);

            if (smoothingAlpha >= 1.0f)
                currentGain = targetGain;
            else
                currentGain += (targetGain - currentGain) * smoothingAlpha;

            const float mix = mixSmoothed.getNextValue();
            lastDisplayPhase = displayPhase;

            for (int ch = 0; ch < channels; ++ch)
            {
                const float dry = dryBuffer.getSample(ch, sample);
                const float wet = dry * currentGain;
                buffer.setSample(ch, sample, dry + ((wet - dry) * mix));
            }
        }

        phaseOut.store(lastDisplayPhase, std::memory_order_relaxed);
        gainOut.store(currentGain, std::memory_order_relaxed);
    }

    static std::vector<float> buildPreviewCurve(int pointCount,
                                                int shapeIndex,
                                                float depthPercent,
                                                float smoothPercent,
                                                float swingPercent,
                                                float phaseDegrees,
                                                float displayPhase)
    {
        const int count = juce::jlimit(32, 512, pointCount);
        std::vector<float> out((size_t)(count + 1), 1.0f);
        out[0] = juce::jlimit(0.0f, 1.0f, displayPhase);

        const float swingAmount = juce::jlimit(0.0f, 1.0f, swingPercent * 0.01f);
        const float phaseOffset = phaseDegrees / 360.0f;
        const float alpha = computeSmoothingAlpha(smoothPercent, 2000.0);
        float current = computeGainForDisplay(shapeIndex, 0.0f, depthPercent,
                                              smoothPercent, swingPercent);
        for (int i = 0; i < count; ++i)
        {
            const float x = (count <= 1) ? 0.0f : (float)i / (float)(count - 1);
            const float rawPhase =
                wrapUnitPhase(invertSwing(x, swingAmount) + phaseOffset);
            const float target = computeGainForDisplay(
                shapeIndex,
                rawPhase,
                depthPercent,
                smoothPercent,
                swingPercent);
            if (alpha >= 1.0f)
                current = target;
            else
                current += (target - current) * alpha;
            out[(size_t)(i + 1)] = juce::jlimit(0.0f, 1.0f, current);
        }
        return out;
    }

private:
    static float computeSmoothingAlpha(float smoothPercent, double rate)
    {
        const float smooth = juce::jlimit(0.0f, 1.0f, smoothPercent * 0.01f);
        if (smooth <= 0.0001f || rate <= 0.0)
            return 1.0f;

        const double timeSeconds = 0.0005 + (double)smooth * 0.03;
        return (float)(1.0 - std::exp(-1.0 / (timeSeconds * rate)));
    }

    static float resolveCyclePhase(double transportSec, double bpm, double cycleBeats)
    {
        const double safeBpm = juce::jlimit(1.0, 400.0, bpm);
        const double safeCycleBeats = juce::jmax(0.125, cycleBeats);
        const double beatPos = juce::jmax(0.0, transportSec) * safeBpm / 60.0;
        const double cyclePos = std::fmod(beatPos / safeCycleBeats, 1.0);
        return (float)(cyclePos >= 0.0 ? cyclePos : cyclePos + 1.0);
    }

    static float wrapUnitPhase(float phase)
    {
        if (!std::isfinite(phase))
            return 0.0f;

        phase = std::fmod(phase, 1.0f);
        if (phase < 0.0f)
            phase += 1.0f;
        return juce::jlimit(0.0f, 1.0f, phase);
    }

    static float applySwing(float rawPhase, float swingAmount)
    {
        if (swingAmount <= 0.0001f)
            return juce::jlimit(0.0f, 1.0f, rawPhase);

        const float split =
            juce::jlimit(0.25f, 0.75f, 0.5f + (swingAmount * 0.22f));
        if (rawPhase < split)
            return 0.5f * (rawPhase / split);
        return 0.5f + 0.5f * ((rawPhase - split) / (1.0f - split));
    }

    static float invertSwing(float displayPhase, float swingAmount)
    {
        if (swingAmount <= 0.0001f)
            return juce::jlimit(0.0f, 1.0f, displayPhase);

        const float split =
            juce::jlimit(0.25f, 0.75f, 0.5f + (swingAmount * 0.22f));
        if (displayPhase < 0.5f)
            return split * (displayPhase / 0.5f);
        return split +
               (1.0f - split) * ((displayPhase - 0.5f) / 0.5f);
    }

    static float evaluateEnvelope(int shapeIndex, float phase)
    {
        const float x = juce::jlimit(0.0f, 1.0f, phase);
        const float twoPi = juce::MathConstants<float>::twoPi;
        switch (juce::jlimit(0, shapeChoices().size() - 1, shapeIndex))
        {
            case 0:
                return 1.0f - std::pow(1.0f - x, 2.6f);
            case 1:
                return 0.5f - 0.5f * std::cos(twoPi * x);
            case 2:
                return x < 0.5f ? 1.0f : 0.0f;
            case 3:
            {
                const float sub = std::fmod(x * 4.0f, 1.0f);
                return sub < 0.45f ? 1.0f : 0.0f;
            }
            case 4:
            {
                const float sub = std::fmod(x * 8.0f, 1.0f);
                return sub < 0.32f ? 1.0f : 0.0f;
            }
            case 5:
            default:
                return 0.5f + 0.5f * std::sin((twoPi * x) - (0.5f * juce::MathConstants<float>::pi));
        }
    }

    static float computeGainForDisplay(int shapeIndex,
                                       float rawPhase,
                                       float depthPercent,
                                       float smoothPercent,
                                       float swingPercent)
    {
        juce::ignoreUnused(smoothPercent);
        const float swingAmount = juce::jlimit(0.0f, 1.0f, swingPercent * 0.01f);
        const float displayPhase = applySwing(rawPhase, swingAmount);
        const float envelope = evaluateEnvelope(shapeIndex, displayPhase);
        const float depth = juce::jlimit(0.0f, 1.0f, depthPercent * 0.01f);
        const float minGain = 1.0f - depth;
        return juce::jlimit(0.0f, 1.0f, minGain + (envelope * depth));
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
    }

    VolumeShaperParameters params{100.0f, 100.0f, 18.0f, 0.0f, 0.0f, 3, 0};
    double sampleRate{44100.0};
    int bufferSize{0};
    float currentGain{1.0f};
    juce::AudioBuffer<float> dryBuffer;
    juce::LinearSmoothedValue<float> depthSmoothed;
    juce::LinearSmoothedValue<float> mixSmoothed;
};

class VolumeShaperAudioProcessor : public juce::AudioProcessor
{
public:
    VolumeShaperAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Volume Shaper"; }
    std::vector<float> getPreviewCurve(int pointCount) const;

    juce::AudioProcessorValueTreeState parameters;

private:
    VolumeShaperModule shaper;
    std::atomic<float> previewPhase{0.0f};
    std::atomic<float> previewGain{1.0f};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(VolumeShaperAudioProcessor)
};

// ****TIME SHAPER****

struct TimeShaperParameters
{
    float amountPercent;
    float mixPercent;
    float smoothPercent;
    float swingPercent;
    float phaseDegrees;
    int rateIndex;
    int patternIndex;
};

class TimeShaperModule
{
public:
    static constexpr std::array<double, 7> rateBeats{
        8.0,
        4.0,
        2.0,
        1.0,
        0.5,
        0.25,
        (2.0 / 3.0),
    };

    static const juce::StringArray rateChoices()
    {
        return {"2 Bars", "1 Bar", "1/2 Bar", "1 Beat",
                "1/2 Beat", "1/4 Beat", "Beat Triplet"};
    }

    static const juce::StringArray patternChoices()
    {
        return {"Repeat", "Half Speed", "Reverse", "Stutter",
                "Tape Stop", "Glide", "Scratch"};
    }

    void setParameters(const juce::AudioProcessorValueTreeState &apvts)
    {
        params.amountPercent = apvts.getRawParameterValue("amount")->load();
        params.mixPercent = apvts.getRawParameterValue("mix")->load();
        params.smoothPercent = apvts.getRawParameterValue("smooth")->load();
        params.swingPercent = apvts.getRawParameterValue("swing")->load();
        params.phaseDegrees = apvts.getRawParameterValue("phase")->load();
        params.rateIndex = juce::jlimit(
            0,
            (int)rateBeats.size() - 1,
            (int)apvts.getRawParameterValue("rate")->load());
        params.patternIndex = juce::jlimit(
            0,
            patternChoices().size() - 1,
            (int)apvts.getRawParameterValue("pattern")->load());
    }

    void syncParameters()
    {
        amountSmoothed.setCurrentAndTargetValue(
            juce::jlimit(0.0f, 1.0f, params.amountPercent * 0.01f));
        mixSmoothed.setCurrentAndTargetValue(
            juce::jlimit(0.0f, 1.0f, params.mixPercent * 0.01f));
        smoothedOffsetNorm = 0.0f;
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        dryBuffer.setSize(numOutputs, bufferSize);
        const double maxWindowSeconds = (8.0 * 60.0) / 30.0;
        ringSize = juce::jmax(
            bufferSize + 8,
            (int)std::ceil(sampleRate * maxWindowSeconds) + 8);
        ringBuffer.setSize(numOutputs, ringSize);
        amountSmoothed.reset(sampleRate, 0.02);
        mixSmoothed.reset(sampleRate, 0.02);
        amountSmoothed.setCurrentAndTargetValue(1.0f);
        mixSmoothed.setCurrentAndTargetValue(1.0f);
        reset();
    }

    void reset()
    {
        dryBuffer.clear();
        ringBuffer.clear();
        writePos = 0;
        filledSamples = 0;
        smoothedOffsetNorm = 0.0f;
    }

    void process(juce::AudioBuffer<float> &buffer,
                 double blockTransportStartSec,
                 std::atomic<float> &phaseOut,
                 std::atomic<float> &readNormOut)
    {
        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(buffer, dryBuffer);

        amountSmoothed.setTargetValue(
            juce::jlimit(0.0f, 1.0f, params.amountPercent * 0.01f));
        mixSmoothed.setTargetValue(
            juce::jlimit(0.0f, 1.0f, params.mixPercent * 0.01f));

        const double bpm = juce::jlimit(30.0, 400.0, mixroom::fx::getGlobalTempoBpm());
        const double cycleBeats =
            rateBeats[(size_t)juce::jlimit(0, (int)rateBeats.size() - 1, params.rateIndex)];
        const int windowSamples = juce::jlimit(
            8,
            juce::jmax(8, ringSize - 4),
            (int)std::round(sampleRate * cycleBeats * 60.0 / bpm));
        const float swingAmount = juce::jlimit(0.0f, 1.0f, params.swingPercent * 0.01f);
        const float phaseOffset = params.phaseDegrees / 360.0f;
        const float smoothingAlpha =
            computeSmoothingAlpha(params.smoothPercent, sampleRate);
        const int channels = juce::jmin(buffer.getNumChannels(), numOutputs);
        float lastPhase = 0.0f;

        for (int sample = 0; sample < blockSamples; ++sample)
        {
            const float inL = dryBuffer.getSample(0, sample);
            const float inR = dryBuffer.getSample(1, sample);
            ringBuffer.setSample(0, writePos, inL);
            ringBuffer.setSample(1, writePos, inR);
            filledSamples = juce::jmin(ringSize, filledSamples + 1);

            const double transportSec =
                blockTransportStartSec + ((double)sample / sampleRate);
            const float phase = applySwing(
                wrapUnitPhase(
                    resolveCyclePhase(transportSec, bpm, cycleBeats) +
                    phaseOffset),
                swingAmount);
            const float amount = amountSmoothed.getNextValue();
            const float mix = mixSmoothed.getNextValue();
            const float targetOffsetNorm =
                amount * evaluateOffsetNorm(params.patternIndex, phase);

            if (smoothingAlpha >= 1.0f)
                smoothedOffsetNorm = targetOffsetNorm;
            else
                smoothedOffsetNorm +=
                    (targetOffsetNorm - smoothedOffsetNorm) * smoothingAlpha;

            const float availableHistory =
                (float)juce::jmax(0, filledSamples - 2);
            const float offsetSamples = juce::jlimit(
                0.0f,
                availableHistory,
                smoothedOffsetNorm *
                    (float)juce::jmax(1, windowSamples - 2));

            const float wetL = readInterpolatedSample(0, offsetSamples);
            const float wetR = readInterpolatedSample(1, offsetSamples);

            if (channels > 0)
                buffer.setSample(0, sample, inL + ((wetL - inL) * mix));
            if (channels > 1)
                buffer.setSample(1, sample, inR + ((wetR - inR) * mix));

            writePos = (writePos + 1) % juce::jmax(1, ringSize);
            lastPhase = phase;
        }

        phaseOut.store(lastPhase, std::memory_order_relaxed);
        readNormOut.store(1.0f - smoothedOffsetNorm, std::memory_order_relaxed);
    }

    void updateHistory(const juce::AudioBuffer<float> &buffer,
                       double blockTransportStartSec,
                       std::atomic<float> &phaseOut,
                       std::atomic<float> &readNormOut)
    {
        const int blockSamples = buffer.getNumSamples();
        if (blockSamples <= 0)
            return;

        ensureCapacity(blockSamples);
        copyToFixedStereoBuffer(buffer, dryBuffer);

        const double bpm = juce::jlimit(30.0, 400.0, mixroom::fx::getGlobalTempoBpm());
        const double cycleBeats =
            rateBeats[(size_t)juce::jlimit(0, (int)rateBeats.size() - 1, params.rateIndex)];
        const float swingAmount = juce::jlimit(0.0f, 1.0f, params.swingPercent * 0.01f);
        const float phaseOffset = params.phaseDegrees / 360.0f;
        float lastPhase = 0.0f;

        for (int sample = 0; sample < blockSamples; ++sample)
        {
            ringBuffer.setSample(0, writePos, dryBuffer.getSample(0, sample));
            ringBuffer.setSample(1, writePos, dryBuffer.getSample(1, sample));
            filledSamples = juce::jmin(ringSize, filledSamples + 1);
            writePos = (writePos + 1) % juce::jmax(1, ringSize);
            const double transportSec =
                blockTransportStartSec + ((double)sample / sampleRate);
            lastPhase = applySwing(
                wrapUnitPhase(
                    resolveCyclePhase(transportSec, bpm, cycleBeats) +
                    phaseOffset),
                swingAmount);
        }

        phaseOut.store(lastPhase, std::memory_order_relaxed);
        readNormOut.store(1.0f, std::memory_order_relaxed);
        smoothedOffsetNorm = 0.0f;
    }

    static std::vector<float> buildPreviewCurve(int pointCount,
                                                int patternIndex,
                                                float amountPercent,
                                                float smoothPercent,
                                                float swingPercent,
                                                float phaseDegrees,
                                                float phase)
    {
        const int count = juce::jlimit(32, 512, pointCount);
        std::vector<float> out((size_t)(count + 1), 1.0f);
        out[0] = juce::jlimit(0.0f, 1.0f, phase);

        const float amount = juce::jlimit(0.0f, 1.0f, amountPercent * 0.01f);
        const float swingAmount = juce::jlimit(0.0f, 1.0f, swingPercent * 0.01f);
        const float phaseOffset = phaseDegrees / 360.0f;
        const float alpha = computeSmoothingAlpha(smoothPercent, 2000.0);
        float current = 1.0f;
        for (int i = 0; i < count; ++i)
        {
            const float x = (count <= 1) ? 0.0f : (float)i / (float)(count - 1);
            const float target = 1.0f -
                                 (amount * evaluateOffsetNorm(
                                               patternIndex,
                                               applySwing(
                                                   wrapUnitPhase(x + phaseOffset),
                                                   swingAmount)));
            if (alpha >= 1.0f)
                current = target;
            else
                current += (target - current) * alpha;
            out[(size_t)(i + 1)] = juce::jlimit(0.0f, 1.0f, current);
        }
        return out;
    }

private:
    static float computeSmoothingAlpha(float smoothPercent, double rate)
    {
        const float smooth = juce::jlimit(0.0f, 1.0f, smoothPercent * 0.01f);
        if (smooth <= 0.0001f || rate <= 0.0)
            return 1.0f;

        const double timeSeconds = 0.0005 + (double)smooth * 0.05;
        return (float)(1.0 - std::exp(-1.0 / (timeSeconds * rate)));
    }

    static float resolveCyclePhase(double transportSec, double bpm, double cycleBeats)
    {
        const double safeBpm = juce::jlimit(1.0, 400.0, bpm);
        const double safeCycleBeats = juce::jmax(0.125, cycleBeats);
        const double beatPos = juce::jmax(0.0, transportSec) * safeBpm / 60.0;
        const double cyclePos = std::fmod(beatPos / safeCycleBeats, 1.0);
        return (float)(cyclePos >= 0.0 ? cyclePos : cyclePos + 1.0);
    }

    static float wrapUnitPhase(float value)
    {
        if (!std::isfinite(value))
            return 0.0f;

        value = std::fmod(value, 1.0f);
        if (value < 0.0f)
            value += 1.0f;
        return juce::jlimit(0.0f, 1.0f, value);
    }

    static float applySwing(float rawPhase, float swingAmount)
    {
        if (swingAmount <= 0.0001f)
            return juce::jlimit(0.0f, 1.0f, rawPhase);

        const float split =
            juce::jlimit(0.25f, 0.75f, 0.5f + (swingAmount * 0.22f));
        if (rawPhase < split)
            return 0.5f * (rawPhase / split);
        return 0.5f + 0.5f * ((rawPhase - split) / (1.0f - split));
    }

    static float evaluatePlaybackPhase(int patternIndex, float phase)
    {
        const float x = juce::jlimit(0.0f, 1.0f, phase);
        switch (juce::jlimit(0, patternChoices().size() - 1, patternIndex))
        {
            case 0:
            {
                const float local = wrapUnitPhase(x * 4.0f);
                return local * 0.25f;
            }
            case 1:
                return x * 0.5f;
            case 2:
                return 1.0f - x;
            case 3:
            {
                const float segment = std::floor(x * 4.0f) * 0.25f;
                const float local = wrapUnitPhase(x * 16.0f);
                return juce::jlimit(0.0f, 1.0f, segment + (local * 0.0625f));
            }
            case 4:
                return x / (1.0f + (2.5f * x));
            case 5:
                return x * x;
            case 6:
            default:
            {
                const float segment = std::floor(x * 2.0f) * 0.5f;
                const float local = wrapUnitPhase(x * 2.0f);
                const float triangle =
                    local < 0.5f ? (local * 2.0f) : (2.0f - (local * 2.0f));
                return juce::jlimit(0.0f, 1.0f, segment + (triangle * 0.5f));
            }
        }
    }

    static float evaluateOffsetNorm(int patternIndex, float phase)
    {
        const float playbackPhase = evaluatePlaybackPhase(patternIndex, phase);
        return wrapUnitPhase(phase - playbackPhase);
    }

    float readInterpolatedSample(int channel, float offsetSamples) const
    {
        const int size = juce::jmax(1, ringSize);
        float readPos = (float)writePos - juce::jlimit(0.0f, (float)(size - 2), offsetSamples);
        while (readPos < 0.0f)
            readPos += (float)size;
        while (readPos >= (float)size)
            readPos -= (float)size;

        const int i0 = juce::jlimit(0, size - 1, (int)readPos);
        const int i1 = (i0 + 1 < size) ? (i0 + 1) : 0;
        const float frac = readPos - (float)i0;
        const float a = ringBuffer.getSample(channel, i0);
        const float b = ringBuffer.getSample(channel, i1);
        return a + ((b - a) * frac);
    }

    void ensureCapacity(int requiredSamples)
    {
        if (requiredSamples <= bufferSize)
            return;

        bufferSize = requiredSamples;
        dryBuffer.setSize(numOutputs, bufferSize);
    }

    TimeShaperParameters params{100.0f, 100.0f, 18.0f, 0.0f, 0.0f, 1, 0};
    double sampleRate{44100.0};
    int bufferSize{0};
    int ringSize{0};
    int writePos{0};
    int filledSamples{0};
    float smoothedOffsetNorm{0.0f};
    juce::AudioBuffer<float> dryBuffer;
    juce::AudioBuffer<float> ringBuffer;
    juce::LinearSmoothedValue<float> amountSmoothed;
    juce::LinearSmoothedValue<float> mixSmoothed;
};

class TimeShaperAudioProcessor : public juce::AudioProcessor
{
public:
    TimeShaperAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void reset() override;
    void processBlock(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;
    void processBlockBypassed(juce::AudioBuffer<float> &, juce::MidiBuffer &) override;

#ifndef JucePlugin_PreferredChannelConfigurations
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;
#endif

    juce::AudioProcessorEditor *createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}

    void getStateInformation(juce::MemoryBlock &destData) override;
    void setStateInformation(const void *data, int sizeInBytes) override;

    const juce::String getName() const override { return "Time Shaper"; }
    std::vector<float> getPreviewCurve(int pointCount) const;

    juce::AudioProcessorValueTreeState parameters;

private:
    bool handleStoppedTransport(bool transportPlaying,
                                float heldPhase,
                                float heldReadNorm);

    TimeShaperModule shaper;
    std::atomic<float> previewPhase{0.0f};
    std::atomic<float> previewReadNorm{1.0f};
    bool transportWasPlaying{false};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TimeShaperAudioProcessor)
};
