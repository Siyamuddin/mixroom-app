#pragma once
#include "JuceHeader.h"
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

#define numOutputs 2

// using namespace juce;

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
        parameters.hpfFreq = apvts.getRawParameterValue("hpfFreq")->load();
        parameters.lpfFreq = apvts.getRawParameterValue("lpfFreq")->load();
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = inputSampleRate;
        bufferSize = maxBlockSize;
        dryBuffer.setSize(numOutputs, bufferSize);
        wetBuffer.setSize(numOutputs, bufferSize);
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = bufferSize;
        spec.numChannels = numOutputs;
        processChain.prepare(spec);
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        dryBuffer.makeCopyOf(inputBuffer, true);
        wetBuffer.makeCopyOf(inputBuffer, true);
        setupDelay();
        setupFilters();
        setupModulation();
        setupReverb();
        wetBuffer.applyGain(0.5f); // reverb is loud
        juce::dsp::AudioBlock<float> wetBlock(wetBuffer);
        juce::dsp::ProcessContextReplacing<float> wetContext(wetBlock);
        processChain.process(wetContext);

        const int n = inputBuffer.getNumSamples();
        mixToOutput(inputBuffer, n);
    }

private:
    void setupDelay()
    {
        processChain.get<ChainIndex::Delay>().setDelay(
            static_cast<float>(parameters.predelay * sampleRate * 0.001f));
    }

    void setupFilters()
    {
        *processChain.get<ChainIndex::HPF>().state = *juce::dsp::FilterDesign<float>::
                                                         designIIRHighpassHighOrderButterworthMethod(parameters.hpfFreq, sampleRate, 2)[0];
        *processChain.get<ChainIndex::LPF>().state = *juce::dsp::FilterDesign<float>::
                                                         designIIRLowpassHighOrderButterworthMethod(parameters.lpfFreq, sampleRate, 2)[0];
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

    void mixToOutput(juce::AudioBuffer<float> &buffer, int n)
    {
        const float dryMix = std::sin(0.5f * juce::MathConstants<float>::pi * (1.0f - parameters.mix));
        const float wetMix = std::sin(0.5f * juce::MathConstants<float>::pi * parameters.mix);
        for (int sample = 0; sample < n; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                const float drySample = dryBuffer.getSample(channel, sample) * dryMix;
                const float wetSample = wetBuffer.getSample(channel, sample) * wetMix;
                buffer.setSample(channel, sample, wetSample + drySample);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
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
    const juce::String getName() const override { return "Mixroom Reverb"; }
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

    ~EQAudioProcessor() override {}
    const juce::String getName() const override { return "Mixroom EQ"; }
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
    Equalizer equalizer;
    const std::array<float, numBands> defaultFreq{60.0f, 400.0f, 2000.0f, 8000.0f};

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
        parameters.width = static_cast<float>(inputWidth * sampleRate * 0.001f);
        parameters.feedback = apvts.getRawParameterValue("feedback")->load();
        parameters.mix = apvts.getRawParameterValue("mix")->load() * 0.01f;
        parameters.modDepth = apvts.getRawParameterValue("modDepth")->load() * 0.005f;
        parameters.modRate = apvts.getRawParameterValue("modRate")->load();
        parameters.hpfFreq = apvts.getRawParameterValue("hpfFreq")->load();
        parameters.lpfFreq = apvts.getRawParameterValue("lpfFreq")->load();
        parameters.drive = apvts.getRawParameterValue("drive")->load();
        parameters.bpmSync = apvts.getRawParameterValue("bpmSync")->load();
        parameters.subdivisionIndex = static_cast<int>(
            apvts.getRawParameterValue("subdivisionIndex")->load());
        setDelayTime(apvts, inputDelay);
        // ensure delay time doesn't exceed delayBufferSize
        parameters.delayTime = juce::jmin(parameters.delayTime,
                                          static_cast<float>(delayBufferSize - bufferSize));
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        sampleRate = inputSampleRate;
        bufferSize = maxBlockSize;
        dryBuffer.setSize(numOutputs, maxBlockSize);
        wetBuffer.setSize(numOutputs, maxBlockSize);
        wetBuffer.clear();
        delayBufferSize = static_cast<int>(2.0 * (bufferSize + sampleRate));
        delayBuffer.setSize(numOutputs, delayBufferSize);
        delayBuffer.clear();
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = bufferSize;
        spec.numChannels = numOutputs;
        modChain.prepare(spec);
        filterChain.prepare(spec);
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int n = inputBuffer.getNumSamples();

        dryBuffer.makeCopyOf(inputBuffer, true);
        fillDelayBuffer(n);
        readDelayBuffer(n);
        applyFilters(n);
        applyDistortion(n);
        applyModulation(n);
        applyFeedback(n);
        incrementWritePosition(n);

        mixToOutput(inputBuffer, n);
    }

private:
    void incrementWritePosition(int n)
    {
        writePosition = (writePosition + n) % delayBufferSize;
    }

    void setDelayTime(const juce::AudioProcessorValueTreeState &apvts, float inputDelay)
    {
        // convert delay time to samples based on sync status
        if (parameters.bpmSync)
        {
            parameters.delayTime = static_cast<float>(
                subdivisions[parameters.subdivisionIndex] * sampleRate * 60.0 / bpm);
            // const float delayTimeInMilliseconds = static_cast<float>(
            //     parameters.delayTime / sampleRate * 1000.0);
            // set delayTime parameter to millisecond value of subdivision
            // apvts.getParameter("delayTime")->beginChangeGesture();
            // apvts.getParameter("delayTime")->setValueNotifyingHost(juce::NormalisableRange<float>(
            //     1.0f, 2000.0f, 1.0f).convertTo0to1(delayTimeInMilliseconds));
            // apvts.getParameter("delayTime")->endChangeGesture();
        }
        else
        {
            parameters.delayTime = static_cast<float>(inputDelay * sampleRate * 0.001f);
        }
    }

    // write dry buffer into delay buffer
    void fillDelayBuffer(int n)
    {
        for (int channel = 0; channel < numOutputs; channel++)
        {
            if (n + writePosition <= delayBufferSize)
            {
                delayBuffer.copyFrom(channel, writePosition,
                                     dryBuffer.getReadPointer(channel), n);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - writePosition;
                delayBuffer.copyFrom(channel, writePosition,
                                     dryBuffer.getReadPointer(channel), bufferRemaining);
                delayBuffer.copyFrom(channel, 0, dryBuffer.getReadPointer(channel, bufferRemaining),
                                     n - bufferRemaining);
            }
        }
    }

    // write delay buffer with delay into wet buffer
    void readDelayBuffer(int n)
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
            if (n + readPosition[channel] <= delayBufferSize)
            {
                wetBuffer.copyFrom(channel, 0,
                                   delayBuffer.getReadPointer(channel, readPosition[channel]), n);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - readPosition[channel];
                wetBuffer.copyFrom(channel, 0,
                                   delayBuffer.getReadPointer(channel, readPosition[channel]), bufferRemaining);
                wetBuffer.copyFrom(channel, bufferRemaining,
                                   delayBuffer.getReadPointer(channel), n - bufferRemaining);
            }
        }
    }

    // add feedback from wet buffer to delay buffer
    void applyFeedback(int n)
    {
        const float feedbackGain = parameters.feedback * 0.01f;
        for (int channel = 0; channel < numOutputs; channel++)
        {
            if (delayBufferSize > n + writePosition)
            {
                delayBuffer.addFromWithRamp(channel, writePosition,
                                            wetBuffer.getWritePointer(channel), n, feedbackGain, feedbackGain);
            }
            else
            {
                const int bufferRemaining = delayBufferSize - writePosition;
                delayBuffer.addFromWithRamp(channel, writePosition,
                                            wetBuffer.getWritePointer(channel), bufferRemaining, feedbackGain, feedbackGain);
                delayBuffer.addFromWithRamp(channel, 0, wetBuffer.getWritePointer(channel),
                                            n - bufferRemaining, feedbackGain, feedbackGain);
            }
        }
    }

    void applyFilters(int n)
    {
        *filterChain.get<0>().state = *juce::dsp::FilterDesign<float>::
                                          designIIRHighpassHighOrderButterworthMethod(parameters.hpfFreq, sampleRate, 2)[0];
        *filterChain.get<1>().state = *juce::dsp::FilterDesign<float>::
                                          designIIRLowpassHighOrderButterworthMethod(parameters.lpfFreq, sampleRate, 2)[0];
        juce::dsp::AudioBlock<float> filterBlock(wetBuffer);
        auto sub = filterBlock.getSubBlock(0, (size_t)n);
        juce::dsp::ProcessContextReplacing<float> filterContext(sub);
        filterChain.process(filterContext);
    }

    void applyDistortion(int n)
    {
        for (int sample = 0; sample < n; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                float wetSample = wetBuffer.getSample(channel, sample);
                wetSample *= (parameters.drive / 30.0f) + 1.0f;                                                                  // drive
                wetSample = (2.0f / juce::MathConstants<float>::pi) * atan((juce::MathConstants<float>::pi / 2.0f) * wetSample); // atan waveshaping
                wetSample *= juce::Decibels::decibelsToGain(parameters.drive / -12.0f);                                          // autogain
                wetBuffer.setSample(channel, sample, wetSample);
            }
        }
    }

    void applyModulation(int n)
    {
        modChain.setCentreDelay(1.0f);
        modChain.setFeedback(0.0f);
        modChain.setMix(1.0f);
        modChain.setDepth(parameters.modDepth);
        modChain.setRate(parameters.modRate);
        juce::dsp::AudioBlock<float> modBlock(wetBuffer);
        auto sub = modBlock.getSubBlock(0, (size_t)n);
        juce::dsp::ProcessContextReplacing<float> modContext(sub);
        modChain.process(modContext);
    }

    void mixToOutput(juce::AudioBuffer<float> &buffer, int n)
    {
        const float dryMix = std::sin(0.5f * juce::MathConstants<float>::pi * (1.0f - parameters.mix));
        const float wetMix = std::sin(0.5f * juce::MathConstants<float>::pi * parameters.mix);
        for (int sample = 0; sample < n; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
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
    int writePosition{0};
    double bpm{0.0};
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
    const juce::String getName() const override { return "Mixroom Delay"; }
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
    Delay delay;
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
        parameters.hpfFreq = apvts.getRawParameterValue("hpf")->load();
        parameters.lpfFreq = apvts.getRawParameterValue("lpf")->load();
        parameters.shape = apvts.getRawParameterValue("shape")->load();
        parameters.shapeTilt = apvts.getRawParameterValue("shapeTilt")->load();
    }

    void prepare(double inputSampleRate, int maxBlockSize)
    {
        const int up = oversampler.getOversamplingFactor();
        sampleRate = inputSampleRate * up;
        bufferSize = maxBlockSize * up;
        dryBuffer.setSize(numOutputs, bufferSize);
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = bufferSize;
        spec.numChannels = numOutputs;
        filterChain.prepare(spec);
        dcFilter.prepare(spec);
        *dcFilter.state = *juce::dsp::FilterDesign<float>::
                              designIIRHighpassHighOrderButterworthMethod(10.0f, sampleRate, 4)[0];
        oversampler.reset();
        oversampler.initProcessing(maxBlockSize);
    }

    void process(const juce::dsp::ProcessContextReplacing<float> &context)
    {
        auto upsampleBlock = oversampler.processSamplesUp(context.getInputBlock());
        const int nUp = (int)upsampleBlock.getNumSamples();

        if (dryBuffer.getNumSamples() < nUp)
            dryBuffer.setSize(numOutputs, nUp, false, false, true);

        for (int channel = 0; channel < numOutputs; channel++)
        {
            dryBuffer.copyFrom(channel, 0, upsampleBlock.getChannelPointer(channel), nUp);
        }

        applyInputFilters(upsampleBlock);
        distortBuffer(upsampleBlock, nUp);
        applyDcFilter(upsampleBlock);
        applyMix(upsampleBlock, dryBuffer, nUp);
        oversampler.processSamplesDown(context.getOutputBlock());
    }

    int getOversamplerLatency()
    {
        return static_cast<int>(oversampler.getLatencyInSamples());
    }

    void reset()
    {
        filterChain.reset();
        dcFilter.reset();
        oversampler.reset();
        dryBuffer.clear();
    }

private:
    void applyInputFilters(juce::dsp::AudioBlock<float> &block)
    {
        *filterChain.get<FilterChainIndex::HPF>().state = *juce::dsp::FilterDesign<float>::
                                                              designIIRHighpassHighOrderButterworthMethod(parameters.hpfFreq, sampleRate, 2)[0];
        *filterChain.get<FilterChainIndex::LPF>().state = *juce::dsp::FilterDesign<float>::
                                                              designIIRLowpassHighOrderButterworthMethod(parameters.lpfFreq, sampleRate, 2)[0];
        *filterChain.get<FilterChainIndex::LowShelf>().state = *juce::dsp::IIR::Coefficients<float>::
                                                                   makeLowShelf(sampleRate, 900.0f, 0.4f, juce::Decibels::decibelsToGain(parameters.shape * -1.0f));
        *filterChain.get<FilterChainIndex::HighShelf>().state = *juce::dsp::IIR::Coefficients<float>::
                                                                    makeHighShelf(sampleRate, 900.0f, 0.4f, juce::Decibels::decibelsToGain(parameters.shape));
        // bypass high shelf if tilt disabled
        filterChain.setBypassed<FilterChainIndex::HighShelf>(!parameters.shapeTilt);
        juce::dsp::ProcessContextReplacing<float> filterContext(block);
        filterChain.process(filterContext);
    }

    void applyDcFilter(juce::dsp::AudioBlock<float> &block)
    {
        juce::dsp::ProcessContextReplacing<float> filterContext(block);
        dcFilter.process(filterContext);
    }

    void distortBuffer(juce::dsp::AudioBlock<float> &block, int n)
    {
        const float outputGain = juce::Decibels::decibelsToGain(parameters.volume);
        const float autoGain = juce::Decibels::decibelsToGain(parameters.drive / -5.0f) *
                               (-0.7f * parameters.anger + 1.0f);
        for (int sample = 0; sample < n; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                float wetSample = block.getSample(channel, sample);
                wetSample *= (parameters.drive / 10.0f) + 1.0f;      // apply drive
                wetSample += parameters.offset;                      // apply dc offset
                distortSample(wetSample, parameters.distortionType); // apply distortion
                wetSample *= autoGain;                               // apply autogain
                wetSample *= outputGain;                             // apply volume
                block.setSample(channel, sample, wetSample);
            }
        }
    }

    void distortSample(float &sample, int type)
    {
        float angerValue;
        switch (type)
        {
        case 0: // inverse absolute value
            angerValue = -0.9f * parameters.anger + 1.0f;
            sample = sample / (angerValue + abs(sample));
            break;
        case 1: // arctan
            angerValue = -2.5f * parameters.anger + 3.0f;
            sample = (2.0f / juce::MathConstants<float>::pi) * atan((juce::MathConstants<float>::pi / angerValue) * sample);
            break;
        case 2: // erf
            angerValue = -2.5f * parameters.anger + 3.0f;
            sample = erf(sample * sqrt(juce::MathConstants<float>::pi) / angerValue);
            break;
        case 3: // inverse square root
            angerValue = 4.5f * parameters.anger + 0.5f;
            sample = sample / sqrt((1.0f / angerValue) + (sample * sample));
            break;
        }
    }

    void applyMix(juce::dsp::AudioBlock<float> &wetBlock, const juce::AudioBuffer<float> &dryBlock, int n)
    {
        const float dryMix = std::pow(std::sin(0.5f * juce::MathConstants<float>::pi * (1.0f - parameters.mix)), 2.0f);
        const float wetMix = std::pow(std::sin(0.5f * juce::MathConstants<float>::pi * parameters.mix), 2.0f);
        for (int sample = 0; sample < n; sample++)
        {
            for (int channel = 0; channel < numOutputs; channel++)
            {
                const float wetSample = wetBlock.getSample(channel, sample) * wetMix;
                const float drySample = dryBlock.getSample(channel, sample) * dryMix;
                wetBlock.setSample(channel, sample, wetSample + drySample);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
    DistortionParameters parameters;
    juce::AudioBuffer<float> dryBuffer;
    using StereoFilter = juce::dsp::ProcessorDuplicator<juce::dsp::IIR::Filter<float>,
                                                        juce::dsp::IIR::Coefficients<float>>;
    juce::dsp::ProcessorChain<StereoFilter, StereoFilter, StereoFilter, StereoFilter> filterChain;
    enum FilterChainIndex
    {
        HPF,
        LPF,
        LowShelf,
        HighShelf
    };
    StereoFilter dcFilter;
    juce::dsp::Oversampling<float> oversampler{2, 2,
                                               juce::dsp::Oversampling<float>::filterHalfBandPolyphaseIIR, false, true};
};

class DistortionAudioProcessor : public juce::AudioProcessor
{
public:
    DistortionAudioProcessor();
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &) override;
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

    ~DistortionAudioProcessor() override {}
    const juce::String getName() const override { return "Mixroom Distortion"; }
    double getTailLengthSeconds() const override { return 0.0; }
    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String &) override {}
    void releaseResources() override {}
    bool hasEditor() const override { return true; }

    juce::AudioProcessorValueTreeState parameters;
    juce::AudioBuffer<float> bypassFifo;
    int bypassWritePos = 0;

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
        sampleRate = newSampleRate;
        bufferSize = maxBlockSize;
        lowBuffer.setSize(numOutputs, maxBlockSize);
        highBuffer.setSize(numOutputs, maxBlockSize);
        compressionBuffer.setSize(numOutputs, maxBlockSize);
        envelopeBuffer.setSize(numOutputs, maxBlockSize);
        juce::dsp::ProcessSpec spec;
        spec.sampleRate = sampleRate;
        spec.maximumBlockSize = maxBlockSize;
        spec.numChannels = numOutputs;
        lowChain.prepare(spec);
        highChain.prepare(spec);
    }

    void process(juce::AudioBuffer<float> &inputBuffer)
    {
        const int n = inputBuffer.getNumSamples();

        lowBuffer.makeCopyOf(inputBuffer, true);
        highBuffer.makeCopyOf(inputBuffer, true);
        applyFilters();
        createEnvelope(n);
        calculateGainReduction(n);
        applyCompression(n);
        writeOutput(inputBuffer, n);
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
        juce::dsp::AudioBlock<float> lowBlock(lowBuffer);
        juce::dsp::AudioBlock<float> highBlock(highBuffer);
        juce::dsp::ProcessContextReplacing<float> lowContext(lowBlock);
        juce::dsp::ProcessContextReplacing<float> highContext(highBlock);
        lowChain.process(lowContext);
        highChain.process(highContext);
    }

    void applyHisteresis(float &compLevel, float inputSample)
    {
        float histeresis = (compLevel < inputSample) ? parameters.attackTime : parameters.releaseTime;
        compLevel = inputSample + histeresis * (compLevel - inputSample);
    }

    void createEnvelope(int n)
    {
        for (int sample = 0; sample < n; sample++)
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

    void calculateGainReduction(int n)
    {
        outputGainReduction = {0.0f, 0.0f};
        for (int sample = 0; sample < n; sample++)
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

    void applyCompression(int n)
    {
        for (int channel = 0; channel < numOutputs; channel++)
        {
            // apply compression to high buffer
            juce::FloatVectorOperations::multiply(highBuffer.getWritePointer(channel),
                                                  compressionBuffer.getReadPointer(channel), n);
            // if wide set, also apply compression to low buffer
            if (parameters.wide)
            {
                juce::FloatVectorOperations::multiply(lowBuffer.getWritePointer(channel),
                                                      compressionBuffer.getReadPointer(channel), n);
            }
        }
    }

    void writeOutput(juce::AudioBuffer<float> &buffer, int n)
    {
        for (int channel = 0; channel < numOutputs; channel++)
        {
            // if listen set, output high only, else sum low and high
            buffer.copyFrom(channel, 0, highBuffer.getReadPointer(channel), n);
            if (!parameters.listen)
            {
                buffer.addFrom(channel, 0, lowBuffer.getReadPointer(channel), n);
            }
        }
    }

    double sampleRate{0.0};
    int bufferSize{0};
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
    const juce::String getName() const override { return "Mixroom De-Esser"; }
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