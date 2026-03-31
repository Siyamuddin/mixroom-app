#pragma once
#include "JuceHeader.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>
#include <atomic>
#include <cmath>

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
        prepareProcessChain();
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
        processChain.get<ChainIndex::Delay>().setDelay(
            static_cast<float>(parameters.predelay * sampleRate * 0.001f));
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
        processChain.get<ChainIndex::Chorus>().setCentreDelay(1.0f);
        processChain.get<ChainIndex::Chorus>().setFeedback(0.0f);
        processChain.get<ChainIndex::Chorus>().setMix(1.0f);
        processChain.get<ChainIndex::Chorus>().setDepth(parameters.modDepth);
        processChain.get<ChainIndex::Chorus>().setRate(parameters.modRate);
    }

    void setupReverb()
    {
        reverbParameters.roomSize = parameters.roomSize;
        reverbParameters.damping = parameters.damping;
        reverbParameters.width = 1.0f;
        reverbParameters.freezeMode = 0.0f;
        reverbParameters.wetLevel = 1.0f;
        reverbParameters.dryLevel = 0.0f;
        processChain.get<ChainIndex::Verb>().setParameters(reverbParameters);
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

        for (auto &f : sidechainFilters)
            f.setCoefficients(
                juce::IIRCoefficients::makeHighPass(sampleRate, params.sidechainFreq));
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
        parameters.threshold = apvts.getRawParameterValue("threshold")->load();
        parameters.ceiling = apvts.getRawParameterValue("ceiling")->load();

        const float releaseInput = apvts.getRawParameterValue("release")->load();
        parameters.releaseTime = static_cast<float>(
            std::exp(-1.0f / (releaseInput * sampleRate / 1000.0)));

        parameters.stereo = apvts.getRawParameterValue("stereo")->load();
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = sanitiseEffectSampleRate(inputSampleRate);
        bufferSize = juce::jmax(1, maxBlockSize);
        currentBlockSize = bufferSize;
        compressionBuffer.setSize(numOutputs, bufferSize);
        envelopeBuffer.setSize(numOutputs, bufferSize);
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

    juce::AudioBuffer<float> compressionBuffer, envelopeBuffer;
};

class LimiterAudioProcessor : public juce::AudioProcessor
{
public:
    LimiterAudioProcessor();

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
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

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        juce::ignoreUnused(inputSampleRate);
        ensureCapacity(maxBlockSize);
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

        const float dryMix = std::pow(std::sin(0.5f * juce::float_Pi * (1.0f - params.mix)), 2.0f);
        const float wetMix = std::pow(std::sin(0.5f * juce::float_Pi * params.mix), 2.0f);

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
                const float g1 = 1.0f - std::abs(2.0f * p1 - 1.0f);
                const float g2 = 1.0f - std::abs(2.0f * p2 - 1.0f);
                const float norm = g1 + g2 + 1.0e-6f;

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
        const int minDelay = juce::jmax(512, juce::jmax(1, blockSize) * 4);
        const int requiredRingSize = minDelay + 2;
        if (requiredRingSize <= ringSize)
            return;

        ringSize = requiredRingSize;
        for (int ch = 0; ch < numOutputs; ++ch)
        {
            ringBuffers[ch].assign((size_t)ringSize, 0.0f);
            writePos[ch] = 0;
            phase[ch] = 0.0f;
        }
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
