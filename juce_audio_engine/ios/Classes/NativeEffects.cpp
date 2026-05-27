#include "NativeEffects.h"

namespace
{
double resolveProcessorTransportSeconds(const juce::AudioProcessor &processor)
{
    const double globalSeconds =
        juce::jmax(0.0, mixroom::fx::getGlobalTransportSeconds());
    if (mixroom::fx::getGlobalTransportPlaying())
        return globalSeconds;

    if (auto *playHead = processor.getPlayHead())
    {
        if (const auto position = playHead->getPosition())
        {
            if (const auto timeSeconds = position->getTimeInSeconds())
                return juce::jmax(0.0, *timeSeconds);
            if (const auto timeSamples = position->getTimeInSamples())
            {
                const double sampleRate = processor.getSampleRate();
                if (sampleRate > 0.0)
                    return juce::jmax(0.0, (double)*timeSamples / sampleRate);
            }
        }
    }

    return globalSeconds;
}

double resolveProcessorTempoBpm(const juce::AudioProcessor &processor)
{
    const double globalBpm =
        juce::jlimit(30.0, 400.0, mixroom::fx::getGlobalTempoBpm());
    if (mixroom::fx::getGlobalTransportPlaying())
        return globalBpm;

    if (auto *playHead = processor.getPlayHead())
    {
        if (const auto position = playHead->getPosition())
            if (const auto bpm = position->getBpm())
                return juce::jlimit(30.0, 400.0, *bpm);
    }

    return globalBpm;
}

bool resolveProcessorTransportPlaying(const juce::AudioProcessor &processor)
{
    if (mixroom::fx::getGlobalTransportPlaying())
        return true;

    if (auto *playHead = processor.getPlayHead())
        if (const auto position = playHead->getPosition())
            return position->getIsPlaying();

    return false;
}
} // namespace

// ****REVERB****

ReverbAudioProcessor::ReverbAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("roomSize",
                                                                                 "Room Size", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 50.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("damping",
                                                                                 "Damping", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 50.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 20.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("predelay",
                                                                                 "Predelay", juce::NormalisableRange<float>(0.0f, 200.0f, 1.0f), 0.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modRate",
                                                                                 "Mod Rate", juce::NormalisableRange<float>(0.0f, 10.0f, 0.1f), 1.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modDepth",
                                                                                 "Mod Depth", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f, 0.35f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(500.0f, 20000.0f, 1.0f, 0.35f), 20000.0f, "Hz"));
    parameters.state = juce::ValueTree("savedParams");
}

void ReverbAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    reverb.prepare(sampleRate, samplesPerBlock);
    reverb.setParameters(parameters);
}

void ReverbAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    reverb.setParameters(parameters);
    reverb.process(buffer);
}

void ReverbAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void ReverbAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool ReverbAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool ReverbAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool ReverbAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ReverbAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****EQ****

EQAudioProcessor::EQAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    // create parameters for the highpass filter
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("hpfSlope",
                                                                                  "HPF Slope", filterSlopes, 0));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("hpfBypass",
                                                                                "HPF Bypass", false));
    // create parameters for the lowpass filter
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("lpfSlope",
                                                                                  "LPF Slope", filterSlopes, 0));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("lpfBypass",
                                                                                "LPF Bypass", false));
    // create parameters for peak bands
    for (int band = 1; band <= numBands; band++)
    {
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Freq", "Band " + juce::String(band) + " Frequency",
            juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f), defaultFreq[band - 1], "Hz"));
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Gain", "Band " + juce::String(band) + " Gain",
            juce::NormalisableRange<float>(-20.0f, 20.0f, 0.25f), 0.0f, "dB"));
        parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
            "band" + juce::String(band) + "Q", "Band " + juce::String(band) + " Q",
            juce::NormalisableRange<float>(0.1f, 10.0f, 0.1f, 0.4f), 1.0f, "Q"));
        // create shelf/bell switch for bands 1 and 4
        if (band == 1 || band == 4)
        {
            parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>(
                "band" + juce::String(band) + "Bell", "Band " + juce::String(band) + " Bell", false));
        }
    }
    parameters.state = juce::ValueTree("savedParams");
}

void EQAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    equalizer.prepare(sampleRate, samplesPerBlock);
    equalizer.setParameters(parameters);
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void EQAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    equalizer.setParameters(parameters);
    equalizer.process(buffer);
    pushWaveformSamples(buffer);
}

void EQAudioProcessor::pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = waveformWritePos.load(std::memory_order_relaxed);

    for (int i = 0; i < numSamples; ++i)
    {
        const float s = right != nullptr ? 0.5f * (left[i] + right[i]) : left[i];
        waveformRing[(size_t)writePos] = juce::jlimit(-1.0f, 1.0f, s);
        writePos = (writePos + 1) % kWaveformRingSize;
    }

    waveformWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> EQAudioProcessor::getRecentWaveform(int sampleCount) const
{
    const int count = juce::jlimit(16, kWaveformRingSize, sampleCount);
    std::vector<float> out((size_t)count, 0.0f);

    const int writePos = waveformWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kWaveformRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)i] = waveformRing[(size_t)readPos];
        readPos = (readPos + 1) % kWaveformRingSize;
    }

    return out;
}

void EQAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void EQAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that theParams returned correctly
    if (inputXml != nullptr)
    {
        // if theParams tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool EQAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool EQAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool EQAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool EQAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DELAY****

DelayAudioProcessor::DelayAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("delayTime",
                                                                                 "Delay Time", juce::NormalisableRange<float>(1.0f, 2000.0f, 1.0f), 100.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("feedback",
                                                                                 "Feedback", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 15.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("width",
                                                                                 "Width", juce::NormalisableRange<float>(0.0f, 10.0f, 1.0f), 0.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 13.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modRate",
                                                                                 "Mod Rate", juce::NormalisableRange<float>(0.0f, 10.0f, 0.1f), 1.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("modDepth",
                                                                                 "Mod Depth", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpfFreq",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f, 0.35f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpfFreq",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(500.0f, 20000.0f, 1.0f, 0.35f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("drive",
                                                                                 "Drive", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("bpmSync",
                                                                                "BPM Sync", false));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("subdivisionIndex",
                                                                                  "Subdivision", delaySubdivisions, 6));
    parameters.state = juce::ValueTree("savedParams");
}

void DelayAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    delay.prepare(sampleRate, samplesPerBlock);
    delay.setParameters(parameters, 120.0);
}

void DelayAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());
    // get host bpm
    double bpm = mixroom::fx::getGlobalTempoBpm();
    playHead = this->getPlayHead();
    if (playHead != nullptr)
    {
        if (playHead->getCurrentPosition(cpi) &&
            std::isfinite(cpi.bpm) &&
            cpi.bpm >= 1.0 &&
            cpi.bpm <= 400.0)
        {
            bpm = cpi.bpm;
        }
    }
    // apply delay
    delay.setParameters(parameters, bpm);
    delay.process(buffer);
}

void DelayAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DelayAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DelayAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DelayAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DelayAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DelayAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DISTORTION****

DistortionAudioProcessor::DistortionAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("drive",
                                                                                 "Drive", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("volume",
                                                                                 "Volume", juce::NormalisableRange<float>(-20.0f, 20.0f, 0.5f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("mix",
                                                                                 "Mix", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 100.0f, "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("anger",
                                                                                 "Anger", juce::NormalisableRange<float>(0.0f, 1.0f, 0.1f), 0.5f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("offset",
                                                                                 "DC Offset", juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 0.0f));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("hpf",
                                                                                 "HPF Frequency", juce::NormalisableRange<float>(20.0f, 10000.0f, 1.0f, 0.25f), 20.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("lpf",
                                                                                 "LPF Frequency", juce::NormalisableRange<float>(200.0f, 20000.0f, 1.0f, 0.25f), 20000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("shape",
                                                                                 "Pre Shape", juce::NormalisableRange<float>(-6.0f, 6.0f, 0.1f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("shapeTilt",
                                                                                "Shape Tilt", true));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>("type",
                                                                                  "Distortion Type", distortionTypes, 0));
    parameters.state = juce::ValueTree("savedParams");
}

void DistortionAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    distortion.prepare(sampleRate, samplesPerBlock);
    distortion.setParameters(parameters);
    setLatencySamples(distortion.getOversamplerLatency());
}

void DistortionAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> context(block);
    distortion.setParameters(parameters);
    distortion.process(context);
}

void DistortionAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer,
                                                    juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    // Make sure output bus extras are cleared (standard JUCE pattern)
    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    // IMPORTANT: drop any residual/latency state so no stale samples leak
    distortion.reset();

    // Leave buffer contents untouched = dry signal passes through
}

void DistortionAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DistortionAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DistortionAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DistortionAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DistortionAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DistortionAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DEGRADE****

DegradeAudioProcessor::DegradeAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterChoice>(
        "mode",
        "Mode",
        degradeModes,
        0));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "tone",
        "Tone",
        juce::NormalisableRange<float>(20.0f, 20000.0f, 1.0f, 0.25f),
        6000.0f,
        "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "depth",
        "Depth",
        juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
        35.0f,
        "%"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "spread",
        "Spread",
        juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
        40.0f,
        "%"));
    parameters.state = juce::ValueTree("savedParams");
}

void DegradeAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    degrade.prepare(sampleRate, samplesPerBlock);
    degrade.setParameters(parameters);
    setLatencySamples(0);
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void DegradeAudioProcessor::reset()
{
    degrade.reset();
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void DegradeAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    degrade.setParameters(parameters);
    degrade.process(buffer);
    pushWaveformSamples(buffer);
}

void DegradeAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer,
                                                 juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    degrade.reset();
}

void DegradeAudioProcessor::pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = waveformWritePos.load(std::memory_order_relaxed);
    for (int i = 0; i < numSamples; ++i)
    {
        const float mono = right != nullptr ? 0.5f * (left[i] + right[i]) : left[i];
        waveformRing[(size_t)writePos] = juce::jlimit(-1.0f, 1.0f, mono);
        writePos = (writePos + 1) % kWaveformRingSize;
    }
    waveformWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> DegradeAudioProcessor::getRecentWaveform(int sampleCount) const
{
    const int count = juce::jlimit(16, kWaveformRingSize, sampleCount);
    std::vector<float> out((size_t)count, 0.0f);

    const int writePos = waveformWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kWaveformRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)i] = waveformRing[(size_t)readPos];
        readPos = (readPos + 1) % kWaveformRingSize;
    }

    return out;
}

void DegradeAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> xml(parameters.state.createXml());
    copyXmlToBinary(*xml, destData);
}

void DegradeAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
    if (xml != nullptr && xml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*xml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DegradeAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ****DE-ESSER****

DeesserAudioProcessor::DeesserAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("threshold",
                                                                                 "Threshold", juce::NormalisableRange<float>(-40.0f, 0.0f, 0.5f), 0.0f, "dB"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("crossoverFreq",
                                                                                 "Frequency", juce::NormalisableRange<float>(200.0f, 15000.0f, 1.0f, 0.25f), 4000.0f, "Hz"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("attack",
                                                                                 "Attack", juce::NormalisableRange<float>(0.1f, 50.0f, 0.1f, 0.35f), 0.1f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>("release",
                                                                                 "Release", juce::NormalisableRange<float>(5.0f, 100.0f, 0.1f, 0.35f), 10.0f, "ms"));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("stereo", "Stereo", true));
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterBool>("wide", "Wide Band", false));
    parameters.state = juce::ValueTree("savedParams");
}

void DeesserAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    deesser.prepare(sampleRate, samplesPerBlock);
    deesser.setParameters(parameters, listen);
}

void DeesserAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear(i, 0, buffer.getNumSamples());

    deesser.setParameters(parameters, listen);
    deesser.process(buffer);
    gainReduction = deesser.getGainReduction();
}

void DeesserAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    // create xml with state information
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    // save xml to binary
    copyXmlToBinary(*outputXml, destData);
}

void DeesserAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    // create xml from binary
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    // check that inputXml returned correctly
    if (inputXml != nullptr)
    {
        // if inputXml tag name matches tree state tag name
        if (inputXml->hasTagName(parameters.state.getType()))
        {
            // copy xml into tree state
            parameters.state = juce::ValueTree::fromXml(*inputXml);
        }
    }
}

//==============================================================================
//==============================================================================
//==============================================================================

bool DeesserAudioProcessor::acceptsMidi() const
{
#if JucePlugin_WantsMidiInput
    return true;
#else
    return false;
#endif
}

bool DeesserAudioProcessor::producesMidi() const
{
#if JucePlugin_ProducesMidiOutput
    return true;
#else
    return false;
#endif
}

bool DeesserAudioProcessor::isMidiEffect() const
{
#if JucePlugin_IsMidiEffect
    return true;
#else
    return false;
#endif
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool DeesserAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** EQ 3-BAND ****
// =====================

EQ3AudioProcessor::EQ3AudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
#if !JucePlugin_IsMidiEffect
#if !JucePlugin_IsSynth
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
#endif
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)
#endif
                         ),
      parameters(*this, nullptr)
#endif
{
    // Expose ONLY 3 gain parameters
    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "lowGain", "Low Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "midGain", "Mid Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.createAndAddParameter(std::make_unique<juce::AudioParameterFloat>(
        "highGain", "High Gain",
        juce::NormalisableRange<float>(-24.0f, 24.0f, 0.25f),
        0.0f, "dB"));

    parameters.state = juce::ValueTree("savedParams");
}

void EQ3AudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    eq3.prepare(sampleRate, samplesPerBlock);
    eq3.setParameters(parameters);
    waveformRing.fill(0.0f);
    waveformWritePos.store(0, std::memory_order_relaxed);
}

void EQ3AudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (auto ch = getTotalNumInputChannels(); ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    eq3.setParameters(parameters);
    eq3.process(buffer);
    pushWaveformSamples(buffer);
}

void EQ3AudioProcessor::pushWaveformSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = waveformWritePos.load(std::memory_order_relaxed);
    for (int i = 0; i < numSamples; ++i)
    {
        const float s = right != nullptr ? 0.5f * (left[i] + right[i]) : left[i];
        waveformRing[(size_t)writePos] = juce::jlimit(-1.0f, 1.0f, s);
        writePos = (writePos + 1) % kWaveformRingSize;
    }
    waveformWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> EQ3AudioProcessor::getRecentWaveform(int sampleCount) const
{
    const int count = juce::jlimit(16, kWaveformRingSize, sampleCount);
    std::vector<float> out((size_t)count, 0.0f);

    const int writePos = waveformWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kWaveformRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)i] = waveformRing[(size_t)readPos];
        readPos = (readPos + 1) % kWaveformRingSize;
    }
    return out;
}

void EQ3AudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> xml(parameters.state.createXml());
    copyXmlToBinary(*xml, destData);
}

void EQ3AudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
    if (xml != nullptr && xml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*xml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool EQ3AudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** COMPRESSOR ****
// =====================

CompressorAudioProcessor::CompressorAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-50.0f, 0.0f, 0.1f), -12.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "attack", "Attack",
            juce::NormalisableRange<float>(0.5f, 100.0f, 0.1f), 10.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "release", "Release",
            juce::NormalisableRange<float>(5.0f, 1000.0f, 1.0f), 80.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ratio", "Ratio",
            juce::NormalisableRange<float>(1.0f, 20.0f, 0.1f), 4.0f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "makeUp", "Makeup",
            juce::NormalisableRange<float>(-10.0f, 20.0f, 0.1f), 0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "scFreq", "Sidechain HPF",
            juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f), 100.0f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "scBypass", "SC Bypass", true));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "stereo", "Stereo", true));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f), 100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void CompressorAudioProcessor::prepareToPlay(double sr, int bs)
{
    compressor.prepare(sr, bs);
    compressor.setParameters(parameters);
}

void CompressorAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const int numCh = buffer.getNumChannels();
    const int n = buffer.getNumSamples();

    // ===== IN RMS (stereo) =====
    if (numCh >= 2 && n > 0)
    {
        const float *L = buffer.getReadPointer(0);
        const float *R = buffer.getReadPointer(1);

        double ssL = 0.0, ssR = 0.0;
        for (int i = 0; i < n; ++i)
        {
            const double l = (double)L[i];
            const double r = (double)R[i];
            ssL += l * l;
            ssR += r * r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)n);
        const float rmR = (float)std::sqrt(ssR / (double)n);

        // smoothing (VU-ish)
        constexpr float alpha = 0.12f;
        auto smooth = [](float prev, float next)
        { return prev + alpha * (next - prev); };

        inRmsL.store(smooth(inRmsL.load(std::memory_order_relaxed), rmL), std::memory_order_relaxed);
        inRmsR.store(smooth(inRmsR.load(std::memory_order_relaxed), rmR), std::memory_order_relaxed);
    }

    // ===== PROCESS =====
    compressor.setParameters(parameters);
    compressor.process(buffer);

    // ===== GR =====
    gainReduction = compressor.getGainReduction(); // keep your existing variable if you want
    const float gr = juce::jmax(gainReduction[0], gainReduction[1]);
    grDb.store(gr, std::memory_order_relaxed); // max between L/R, rather than an average

    // ===== OUT RMS (stereo) =====
    if (numCh >= 2 && n > 0)
    {
        const float *L = buffer.getReadPointer(0);
        const float *R = buffer.getReadPointer(1);

        double ssL = 0.0, ssR = 0.0;
        for (int i = 0; i < n; ++i)
        {
            const double l = (double)L[i];
            const double r = (double)R[i];
            ssL += l * l;
            ssR += r * r;
        }

        const float rmL = (float)std::sqrt(ssL / (double)n);
        const float rmR = (float)std::sqrt(ssR / (double)n);

        constexpr float alpha = 0.12f;
        auto smooth = [](float prev, float next)
        { return prev + alpha * (next - prev); };

        outRmsL.store(smooth(outRmsL.load(std::memory_order_relaxed), rmL), std::memory_order_relaxed);
        outRmsR.store(smooth(outRmsR.load(std::memory_order_relaxed), rmR), std::memory_order_relaxed);
    }
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool CompressorAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** LIMITER ****
// =====================

LimiterAudioProcessor::LimiterAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "release", "Release",
            juce::NormalisableRange<float>(0.1f, 200.0f, 0.1f, 0.35f),
            1.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ceiling", "Ceiling",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "stereo", "Stereo", true));

    parameters.state = juce::ValueTree("savedParams");
}

void LimiterAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    limiter.prepare(sampleRate, samplesPerBlock);
    limiter.setParameters(parameters);
    grDb.store(0.0f, std::memory_order_relaxed);
}

void LimiterAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    limiter.setParameters(parameters);
    limiter.process(buffer);
    gainReduction = limiter.getGainReduction();
    const float gr = juce::jmax(gainReduction[0], gainReduction[1]);
    constexpr float alpha = 0.18f;
    const float prev = grDb.load(std::memory_order_relaxed);
    grDb.store(prev + alpha * (gr - prev), std::memory_order_relaxed);
}

void LimiterAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void LimiterAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool LimiterAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** CLIPPER ****
// =====================

ClipperAudioProcessor::ClipperAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "threshold", "Threshold",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "ceiling", "Ceiling",
            juce::NormalisableRange<float>(-40.0f, 0.0f, 0.1f),
            0.0f, "dB"));

    parameters.state = juce::ValueTree("savedParams");
}

void ClipperAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    clipper.prepare(sampleRate, samplesPerBlock);
    clipper.setParameters(parameters);
    setLatencySamples(clipper.getOversamplerLatency());
    grDb.store(0.0f, std::memory_order_relaxed);
}

void ClipperAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    clipper.setParameters(parameters);
    juce::dsp::AudioBlock<float> block(buffer);
    juce::dsp::ProcessContextReplacing<float> ctx(block);
    clipper.process(ctx);
    gainReduction = clipper.getGainReduction();
    const float gr = juce::jmax(gainReduction[0], gainReduction[1]);
    constexpr float alpha = 0.22f;
    const float prev = grDb.load(std::memory_order_relaxed);
    grDb.store(prev + alpha * (gr - prev), std::memory_order_relaxed);
}

void ClipperAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer,
                                                 juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    // Latency-reporting processors must override bypass processing.
    clipper.reset();
    grDb.store(0.0f, std::memory_order_relaxed);
}

void ClipperAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void ClipperAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ClipperAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** PITCH SHIFT ****
// =====================

PitchShiftAudioProcessor::PitchShiftAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "semitones", "Semitones",
            juce::NormalisableRange<float>(-12.0f, 12.0f, 0.1f),
            0.0f, "st"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void PitchShiftAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    pitchShift.prepare(sampleRate, samplesPerBlock);
    pitchShift.setParameters(parameters);
}

void PitchShiftAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    pitchShift.setParameters(parameters);
    pitchShift.process(buffer);
}

void PitchShiftAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void PitchShiftAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool PitchShiftAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =========================
// **** PITCH CORRECTOR ****
// =========================

PitchCorrectorAudioProcessor::PitchCorrectorAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "key", "Key",
            juce::NormalisableRange<float>(0.0f, 11.0f, 1.0f),
            0.0f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "scale", "Scale",
            juce::NormalisableRange<float>(0.0f, 2.0f, 1.0f),
            1.0f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "amount", "Amount",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            80.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "speed", "Speed",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            65.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void PitchCorrectorAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    currentSampleRate = sampleRate > 0.0 ? sampleRate : 44100.0;
    pitchShift.prepare(currentSampleRate, samplesPerBlock);
    smoothedCorrectionSemitones = 0.0f;
}

float PitchCorrectorAudioProcessor::estimatePitchHz(
    const juce::AudioBuffer<float> &buffer) const
{
    const int channels = juce::jmin(buffer.getNumChannels(), getTotalNumInputChannels());
    const int samples = buffer.getNumSamples();
    if (channels <= 0 || samples < 96 || currentSampleRate <= 0.0)
        return 0.0f;

    const auto monoAt = [&buffer, channels](int index) {
        float sum = 0.0f;
        for (int ch = 0; ch < channels; ++ch)
            sum += buffer.getReadPointer(ch)[index];
        return sum / (float)channels;
    };

    float mean = 0.0f;
    for (int i = 0; i < samples; ++i)
        mean += monoAt(i);
    mean /= (float)samples;

    float energy = 0.0f;
    for (int i = 0; i < samples; ++i)
    {
        const float x = monoAt(i) - mean;
        energy += x * x;
    }
    if (energy < 1.0e-7f)
        return 0.0f;

    const int minLag = juce::jmax(2, (int)std::floor(currentSampleRate / 1000.0));
    const int maxLag = juce::jmin(samples - 2, (int)std::ceil(currentSampleRate / 80.0));
    if (maxLag <= minLag)
        return 0.0f;

    int bestLag = 0;
    float bestScore = 0.0f;
    for (int lag = minLag; lag <= maxLag; ++lag)
    {
        float corr = 0.0f;
        float aEnergy = 0.0f;
        float bEnergy = 0.0f;
        for (int i = 0; i < samples - lag; ++i)
        {
            const float a = monoAt(i) - mean;
            const float b = monoAt(i + lag) - mean;
            corr += a * b;
            aEnergy += a * a;
            bEnergy += b * b;
        }

        const float denom = std::sqrt(aEnergy * bEnergy) + 1.0e-9f;
        const float score = corr / denom;
        if (score > bestScore)
        {
            bestScore = score;
            bestLag = lag;
        }
    }

    if (bestLag <= 0 || bestScore < 0.36f)
        return 0.0f;

    return (float)(currentSampleRate / (double)bestLag);
}

float PitchCorrectorAudioProcessor::targetCorrectionSemitones(
    float pitchHz, int key, int scale) const
{
    if (pitchHz <= 0.0f)
        return 0.0f;

    static constexpr int majorIntervals[] = {0, 2, 4, 5, 7, 9, 11};
    static constexpr int minorIntervals[] = {0, 2, 3, 5, 7, 8, 10};

    const float midi = 69.0f + 12.0f * std::log2(pitchHz / 440.0f);
    const int roundedMidi = (int)std::round(midi);
    if (scale <= 0)
        return juce::jlimit(-2.5f, 2.5f, (float)roundedMidi - midi);

    const int root = ((key % 12) + 12) % 12;
    const int *intervals = scale == 2 ? minorIntervals : majorIntervals;
    const int intervalCount = 7;
    int bestMidi = roundedMidi;
    float bestDistance = std::numeric_limits<float>::max();

    for (int octave = -1; octave <= 1; ++octave)
    {
        const int octaveBase = ((roundedMidi / 12) + octave) * 12;
        for (int i = 0; i < intervalCount; ++i)
        {
            const int candidate = octaveBase + root + intervals[i];
            const float distance = std::abs((float)candidate - midi);
            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestMidi = candidate;
            }
        }
    }

    return juce::jlimit(-2.5f, 2.5f, (float)bestMidi - midi);
}

void PitchCorrectorAudioProcessor::processBlock(
    juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const int key = (int)std::round(parameters.getRawParameterValue("key")->load());
    const int scale = (int)std::round(parameters.getRawParameterValue("scale")->load());
    const float amount = parameters.getRawParameterValue("amount")->load() * 0.01f;
    const float speed = parameters.getRawParameterValue("speed")->load() * 0.01f;
    const float mix = parameters.getRawParameterValue("mix")->load() * 0.01f;

    const float pitchHz = estimatePitchHz(buffer);
    const float target = pitchHz > 0.0f
                             ? targetCorrectionSemitones(pitchHz, key, scale) * amount
                             : 0.0f;
    const float alpha = pitchHz > 0.0f
                            ? juce::jmap(speed, 0.015f, 0.42f)
                            : 0.08f;
    smoothedCorrectionSemitones +=
        (target - smoothedCorrectionSemitones) * juce::jlimit(0.0f, 1.0f, alpha);

    if (std::abs(smoothedCorrectionSemitones) < 0.01f || mix <= 0.0f)
        return;

    pitchShift.setManualParameters(smoothedCorrectionSemitones, mix);
    pitchShift.process(buffer);
}

void PitchCorrectorAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void PitchCorrectorAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool PitchCorrectorAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =================
// **** CHORUS ****
// =================

ChorusAudioProcessor::ChorusAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "rate", "Rate",
            juce::NormalisableRange<float>(0.05f, 8.0f, 0.01f),
            0.8f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "depth", "Depth",
            juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f),
            0.35f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "centreDelay", "Centre Delay",
            juce::NormalisableRange<float>(1.0f, 30.0f, 0.1f),
            7.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "feedback", "Feedback",
            juce::NormalisableRange<float>(-95.0f, 95.0f, 0.1f),
            10.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            35.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void ChorusAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    chorusFx.prepare(sampleRate, samplesPerBlock);
    chorusFx.setParameters(parameters);
}

void ChorusAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    chorusFx.setParameters(parameters);
    chorusFx.process(buffer);
}

void ChorusAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void ChorusAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool ChorusAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ==================
// **** VIBRATO ****
// ==================

VibratoAudioProcessor::VibratoAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "rate", "Rate",
            juce::NormalisableRange<float>(0.1f, 12.0f, 0.01f),
            4.5f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "depth", "Depth",
            juce::NormalisableRange<float>(0.0f, 1.0f, 0.01f),
            0.6f));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "centreDelay", "Centre Delay",
            juce::NormalisableRange<float>(1.0f, 15.0f, 0.1f),
            7.0f, "ms"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.state = juce::ValueTree("savedParams");
}

void VibratoAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    vibratoFx.prepare(sampleRate, samplesPerBlock);
    vibratoFx.setParameters(parameters);
}

void VibratoAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    vibratoFx.setParameters(parameters);
    vibratoFx.process(buffer);
}

void VibratoAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void VibratoAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool VibratoAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =================
// **** STEREO ****
// =================

StereoAudioProcessor::StereoAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "width", "Width",
            juce::NormalisableRange<float>(0.0f, 200.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "lowBypass", "Low Bypass",
            juce::NormalisableRange<float>(20.0f, 2000.0f, 1.0f, 0.35f),
            160.0f, "Hz"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterBool>(
            "mono", "Mono",
            false));

    parameters.state = juce::ValueTree("savedParams");
}

void StereoAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    stereoFx.prepare(sampleRate, samplesPerBlock);
    stereoFx.setParameters(parameters);
    stereoFx.syncParameters();
    bypassSampleRate = sanitiseEffectSampleRate(sampleRate);
    bypassRampSamples = juce::jmax(1, (int)std::round(bypassSampleRate * 0.004));
    bypassRampRemaining = 0;
    bypassRampDirection = BypassRampDirection::none;
    lastBlockWasBypassed = false;
    ensureBypassBufferCapacity(samplesPerBlock);
}

void StereoAudioProcessor::reset()
{
    stereoFx.reset();
    bypassDryBuffer.clear();
    bypassWetBuffer.clear();
    bypassRampRemaining = 0;
    bypassRampDirection = BypassRampDirection::none;
    lastBlockWasBypassed = false;
}

void StereoAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    if (lastBlockWasBypassed)
        beginBypassRamp(BypassRampDirection::toWet);

    if (bypassRampDirection == BypassRampDirection::toWet)
    {
        ensureBypassBufferCapacity(buffer.getNumSamples());
        bypassDryBuffer.makeCopyOf(buffer, true);
    }

    stereoFx.setParameters(parameters);
    stereoFx.process(buffer);

    if (bypassRampDirection == BypassRampDirection::toWet)
        applyBypassRamp(buffer, bypassDryBuffer, buffer);

    lastBlockWasBypassed = false;
}

void StereoAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    if (!lastBlockWasBypassed)
        beginBypassRamp(BypassRampDirection::toDry);

    if (bypassRampDirection == BypassRampDirection::toDry)
    {
        ensureBypassBufferCapacity(buffer.getNumSamples());
        bypassDryBuffer.makeCopyOf(buffer, true);
        bypassWetBuffer.makeCopyOf(buffer, true);
        stereoFx.setParameters(parameters);
        stereoFx.process(bypassWetBuffer);
        applyBypassRamp(buffer, bypassDryBuffer, bypassWetBuffer);
    }

    lastBlockWasBypassed = true;
}

void StereoAudioProcessor::ensureBypassBufferCapacity(int numSamples)
{
    const int channels = juce::jmax(1, getTotalNumOutputChannels());
    const int samples = juce::jmax(1, numSamples);
    if (bypassDryBuffer.getNumChannels() != channels ||
        bypassDryBuffer.getNumSamples() < samples)
        bypassDryBuffer.setSize(channels, samples, false, false, true);
    if (bypassWetBuffer.getNumChannels() != channels ||
        bypassWetBuffer.getNumSamples() < samples)
        bypassWetBuffer.setSize(channels, samples, false, false, true);
}

void StereoAudioProcessor::beginBypassRamp(BypassRampDirection direction)
{
    bypassRampDirection = direction;
    bypassRampRemaining = bypassRampSamples;
}

void StereoAudioProcessor::applyBypassRamp(juce::AudioBuffer<float> &output,
                                           const juce::AudioBuffer<float> &dry,
                                           const juce::AudioBuffer<float> &wet)
{
    if (bypassRampDirection == BypassRampDirection::none)
        return;

    const int totalSamples = juce::jmax(1, bypassRampSamples);
    const int fadeSamples = juce::jmin(output.getNumSamples(), bypassRampRemaining);
    const int rampStart = juce::jmax(0, totalSamples - bypassRampRemaining);
    const int channels = juce::jmin(output.getNumChannels(),
                                    juce::jmin(dry.getNumChannels(), wet.getNumChannels()));

    for (int ch = 0; ch < channels; ++ch)
    {
        const float *dryPtr = dry.getReadPointer(ch);
        const float *wetPtr = wet.getReadPointer(ch);
        float *outPtr = output.getWritePointer(ch);

        for (int sample = 0; sample < output.getNumSamples(); ++sample)
        {
            float wetMix = (bypassRampDirection == BypassRampDirection::toWet) ? 1.0f : 0.0f;
            if (sample < fadeSamples)
            {
                const float progress =
                    (float)(rampStart + sample + 1) / (float)totalSamples;
                wetMix = (bypassRampDirection == BypassRampDirection::toWet)
                             ? progress
                             : (1.0f - progress);
            }

            outPtr[sample] =
                dryPtr[sample] + ((wetPtr[sample] - dryPtr[sample]) * wetMix);
        }
    }

    bypassRampRemaining -= fadeSamples;
    if (bypassRampRemaining <= 0)
    {
        bypassRampRemaining = 0;
        bypassRampDirection = BypassRampDirection::none;
    }
}

void StereoAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void StereoAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool StereoAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// =====================
// **** STEREO PRO ****
// =====================

StereoProAudioProcessor::StereoProAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "gain", "Gain",
            juce::NormalisableRange<float>(-18.0f, 18.0f, 0.1f),
            0.0f, "dB"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "width", "Width",
            juce::NormalisableRange<float>(0.0f, 300.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "asymmetry", "Asymmetry",
            juce::NormalisableRange<float>(-100.0f, 100.0f, 1.0f),
            0.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "rotation", "Rotation",
            juce::NormalisableRange<float>(-90.0f, 90.0f, 1.0f),
            0.0f, "deg"));

    parameters.state = juce::ValueTree("savedParams");
}

void StereoProAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    stereoProFx.prepare(sampleRate, samplesPerBlock);
    stereoProFx.setParameters(parameters);
    stereoProFx.syncParameters();
    bypassSampleRate = sanitiseEffectSampleRate(sampleRate);
    bypassRampSamples = juce::jmax(1, (int)std::round(bypassSampleRate * 0.004));
    bypassRampRemaining = 0;
    bypassRampDirection = BypassRampDirection::none;
    lastBlockWasBypassed = false;
    ensureBypassBufferCapacity(samplesPerBlock);
    scopeRing.fill(0.0f);
    scopeWritePos.store(0, std::memory_order_relaxed);
}

void StereoProAudioProcessor::reset()
{
    stereoProFx.reset();
    bypassDryBuffer.clear();
    bypassWetBuffer.clear();
    bypassRampRemaining = 0;
    bypassRampDirection = BypassRampDirection::none;
    lastBlockWasBypassed = false;
    scopeRing.fill(0.0f);
    scopeWritePos.store(0, std::memory_order_relaxed);
}

void StereoProAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    if (lastBlockWasBypassed)
        beginBypassRamp(BypassRampDirection::toWet);

    if (bypassRampDirection == BypassRampDirection::toWet)
    {
        ensureBypassBufferCapacity(buffer.getNumSamples());
        bypassDryBuffer.makeCopyOf(buffer, true);
    }

    stereoProFx.setParameters(parameters);
    stereoProFx.process(buffer);

    if (bypassRampDirection == BypassRampDirection::toWet)
        applyBypassRamp(buffer, bypassDryBuffer, buffer);

    pushScopeSamples(buffer);
    lastBlockWasBypassed = false;
}

void StereoProAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    if (!lastBlockWasBypassed)
        beginBypassRamp(BypassRampDirection::toDry);

    if (bypassRampDirection == BypassRampDirection::toDry)
    {
        ensureBypassBufferCapacity(buffer.getNumSamples());
        bypassDryBuffer.makeCopyOf(buffer, true);
        bypassWetBuffer.makeCopyOf(buffer, true);
        stereoProFx.setParameters(parameters);
        stereoProFx.process(bypassWetBuffer);
        applyBypassRamp(buffer, bypassDryBuffer, bypassWetBuffer);
    }

    lastBlockWasBypassed = true;
}

void StereoProAudioProcessor::ensureBypassBufferCapacity(int numSamples)
{
    const int channels = juce::jmax(1, getTotalNumOutputChannels());
    const int samples = juce::jmax(1, numSamples);
    if (bypassDryBuffer.getNumChannels() != channels ||
        bypassDryBuffer.getNumSamples() < samples)
        bypassDryBuffer.setSize(channels, samples, false, false, true);
    if (bypassWetBuffer.getNumChannels() != channels ||
        bypassWetBuffer.getNumSamples() < samples)
        bypassWetBuffer.setSize(channels, samples, false, false, true);
}

void StereoProAudioProcessor::beginBypassRamp(BypassRampDirection direction)
{
    bypassRampDirection = direction;
    bypassRampRemaining = bypassRampSamples;
}

void StereoProAudioProcessor::applyBypassRamp(juce::AudioBuffer<float> &output,
                                              const juce::AudioBuffer<float> &dry,
                                              const juce::AudioBuffer<float> &wet)
{
    if (bypassRampDirection == BypassRampDirection::none)
        return;

    const int totalSamples = juce::jmax(1, bypassRampSamples);
    const int fadeSamples = juce::jmin(output.getNumSamples(), bypassRampRemaining);
    const int rampStart = juce::jmax(0, totalSamples - bypassRampRemaining);
    const int channels = juce::jmin(output.getNumChannels(),
                                    juce::jmin(dry.getNumChannels(), wet.getNumChannels()));

    for (int ch = 0; ch < channels; ++ch)
    {
        const float *dryPtr = dry.getReadPointer(ch);
        const float *wetPtr = wet.getReadPointer(ch);
        float *outPtr = output.getWritePointer(ch);

        for (int sample = 0; sample < output.getNumSamples(); ++sample)
        {
            float wetMix = (bypassRampDirection == BypassRampDirection::toWet) ? 1.0f : 0.0f;
            if (sample < fadeSamples)
            {
                const float progress =
                    (float)(rampStart + sample + 1) / (float)totalSamples;
                wetMix = (bypassRampDirection == BypassRampDirection::toWet)
                             ? progress
                             : (1.0f - progress);
            }

            outPtr[sample] =
                dryPtr[sample] + ((wetPtr[sample] - dryPtr[sample]) * wetMix);
        }
    }

    bypassRampRemaining -= fadeSamples;
    if (bypassRampRemaining <= 0)
    {
        bypassRampRemaining = 0;
        bypassRampDirection = BypassRampDirection::none;
    }
}

void StereoProAudioProcessor::pushScopeSamples(const juce::AudioBuffer<float> &buffer) noexcept
{
    const int numSamples = buffer.getNumSamples();
    const int channels = juce::jmin(buffer.getNumChannels(), 2);
    if (numSamples <= 0 || channels <= 0)
        return;

    const float *left = buffer.getReadPointer(0);
    const float *right = channels > 1 ? buffer.getReadPointer(1) : nullptr;

    int writePos = scopeWritePos.load(std::memory_order_relaxed);
    for (int i = 0; i < numSamples; ++i)
    {
        const float l = juce::jlimit(-2.0f, 2.0f, left[i]);
        const float r = juce::jlimit(-2.0f, 2.0f, right != nullptr ? right[i] : left[i]);
        scopeRing[(size_t)(writePos * 2)] = l;
        scopeRing[(size_t)(writePos * 2 + 1)] = r;
        writePos = (writePos + 1) % kScopeRingSize;
    }

    scopeWritePos.store(writePos, std::memory_order_release);
}

std::vector<float> StereoProAudioProcessor::getRecentScope(int pointCount) const
{
    const int count = juce::jlimit(32, kScopeRingSize, pointCount);
    std::vector<float> out((size_t)(count * 2), 0.0f);

    const int writePos = scopeWritePos.load(std::memory_order_acquire);
    int readPos = writePos - count;
    while (readPos < 0)
        readPos += kScopeRingSize;

    for (int i = 0; i < count; ++i)
    {
        out[(size_t)(i * 2)] = scopeRing[(size_t)(readPos * 2)];
        out[(size_t)(i * 2 + 1)] = scopeRing[(size_t)(readPos * 2 + 1)];
        readPos = (readPos + 1) % kScopeRingSize;
    }

    return out;
}

void StereoProAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void StereoProAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool StereoProAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ==========================
// **** VOLUME SHAPER ****
// ==========================

VolumeShaperAudioProcessor::VolumeShaperAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "depth", "Depth",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "smooth", "Smooth",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            18.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "swing", "Swing",
            juce::NormalisableRange<float>(0.0f, 75.0f, 1.0f),
            0.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "phase", "Phase",
            juce::NormalisableRange<float>(-180.0f, 180.0f, 1.0f),
            0.0f, "deg"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterChoice>(
            "rate", "Rate",
            VolumeShaperModule::rateChoices(),
            3));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterChoice>(
            "shape", "Shape",
            VolumeShaperModule::shapeChoices(),
            0));

    parameters.state = juce::ValueTree("savedParams");
}

void VolumeShaperAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    shaper.prepare(sampleRate, samplesPerBlock);
    shaper.setParameters(parameters);
    shaper.syncParameters();
    previewPhase.store(0.0f, std::memory_order_relaxed);
    previewGain.store(1.0f, std::memory_order_relaxed);
}

void VolumeShaperAudioProcessor::reset()
{
    shaper.reset();
    previewPhase.store(0.0f, std::memory_order_relaxed);
    previewGain.store(1.0f, std::memory_order_relaxed);
}

void VolumeShaperAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const bool shouldAdvancePreview = resolveProcessorTransportPlaying(*this);
    const float heldPhase = previewPhase.load(std::memory_order_relaxed);
    const float heldGain = previewGain.load(std::memory_order_relaxed);
    shaper.setParameters(parameters);
    shaper.process(buffer,
                   resolveProcessorTransportSeconds(*this),
                   previewPhase,
                   previewGain);

    if (!shouldAdvancePreview)
    {
        previewPhase.store(heldPhase, std::memory_order_relaxed);
        previewGain.store(heldGain, std::memory_order_relaxed);
    }
}

void VolumeShaperAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const bool shouldAdvancePreview = resolveProcessorTransportPlaying(*this);
    const float heldPhase = previewPhase.load(std::memory_order_relaxed);
    const float heldGain = previewGain.load(std::memory_order_relaxed);
    shaper.setParameters(parameters);
    if (shouldAdvancePreview)
    {
        const double bpm = resolveProcessorTempoBpm(*this);
        const int rateIndex = juce::jlimit(
            0,
            (int)VolumeShaperModule::rateBeats.size() - 1,
            (int)parameters.getRawParameterValue("rate")->load());
        const double cycleBeats = VolumeShaperModule::rateBeats[(size_t)rateIndex];
        const double beatPos = resolveProcessorTransportSeconds(*this) * bpm / 60.0;
        const double cyclePos = std::fmod(beatPos / juce::jmax(0.125, cycleBeats), 1.0);
        float phase = (float)(cyclePos >= 0.0 ? cyclePos : cyclePos + 1.0);
        const float phaseDegrees =
            parameters.getRawParameterValue("phase") != nullptr
                ? parameters.getRawParameterValue("phase")->load()
                : 0.0f;
        const float swingPercent =
            parameters.getRawParameterValue("swing") != nullptr
                ? parameters.getRawParameterValue("swing")->load()
                : 0.0f;
        phase = std::fmod(phase + (phaseDegrees / 360.0f), 1.0f);
        if (phase < 0.0f)
            phase += 1.0f;

        const float swingAmount = juce::jlimit(0.0f, 1.0f, swingPercent * 0.01f);
        if (swingAmount > 0.0001f)
        {
            const float split =
                juce::jlimit(0.25f, 0.75f, 0.5f + (swingAmount * 0.22f));
            phase = phase < split
                        ? 0.5f * (phase / split)
                        : 0.5f + 0.5f * ((phase - split) / (1.0f - split));
        }

        previewPhase.store(phase, std::memory_order_relaxed);
        previewGain.store(1.0f, std::memory_order_relaxed);
        return;
    }

    previewPhase.store(heldPhase, std::memory_order_relaxed);
    previewGain.store(heldGain, std::memory_order_relaxed);
}

std::vector<float> VolumeShaperAudioProcessor::getPreviewCurve(int pointCount) const
{
    const auto *shapeParam = parameters.getRawParameterValue("shape");
    const auto *depthParam = parameters.getRawParameterValue("depth");
    const auto *smoothParam = parameters.getRawParameterValue("smooth");
    const auto *swingParam = parameters.getRawParameterValue("swing");
    const auto *phaseParam = parameters.getRawParameterValue("phase");
    if (shapeParam == nullptr || depthParam == nullptr ||
        smoothParam == nullptr || swingParam == nullptr || phaseParam == nullptr)
        return std::vector<float>((size_t)(juce::jlimit(32, 512, pointCount) + 1), 1.0f);

    return VolumeShaperModule::buildPreviewCurve(
        pointCount,
        (int)shapeParam->load(),
        depthParam->load(),
        smoothParam->load(),
        swingParam->load(),
        phaseParam->load(),
        previewPhase.load(std::memory_order_relaxed));
}

void VolumeShaperAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void VolumeShaperAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool VolumeShaperAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif

// ========================
// **** TIME SHAPER ****
// ========================

TimeShaperAudioProcessor::TimeShaperAudioProcessor()
#ifndef JucePlugin_PreferredChannelConfigurations
    : AudioProcessor(BusesProperties()
                         .withInput("Input", juce::AudioChannelSet::stereo(), true)
                         .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr)
#endif
{
    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "amount", "Amount",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "mix", "Mix",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            100.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "smooth", "Smooth",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            18.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "swing", "Swing",
            juce::NormalisableRange<float>(0.0f, 75.0f, 1.0f),
            0.0f, "%"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterFloat>(
            "phase", "Phase",
            juce::NormalisableRange<float>(-180.0f, 180.0f, 1.0f),
            0.0f, "deg"));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterChoice>(
            "rate", "Rate",
            TimeShaperModule::rateChoices(),
            1));

    parameters.createAndAddParameter(
        std::make_unique<juce::AudioParameterChoice>(
            "pattern", "Pattern",
            TimeShaperModule::patternChoices(),
            0));

    parameters.state = juce::ValueTree("savedParams");
}

void TimeShaperAudioProcessor::prepareToPlay(double sampleRate, int samplesPerBlock)
{
    shaper.prepare(sampleRate, samplesPerBlock);
    shaper.setParameters(parameters);
    shaper.syncParameters();
    previewPhase.store(0.0f, std::memory_order_relaxed);
    previewReadNorm.store(1.0f, std::memory_order_relaxed);
}

void TimeShaperAudioProcessor::reset()
{
    shaper.reset();
    previewPhase.store(0.0f, std::memory_order_relaxed);
    previewReadNorm.store(1.0f, std::memory_order_relaxed);
    transportWasPlaying = false;
}

bool TimeShaperAudioProcessor::handleStoppedTransport(bool transportPlaying,
                                                      float heldPhase,
                                                      float heldReadNorm)
{
    if (transportPlaying)
    {
        transportWasPlaying = true;
        return false;
    }

    if (transportWasPlaying)
    {
        shaper.reset();
        transportWasPlaying = false;
    }

    previewPhase.store(heldPhase, std::memory_order_relaxed);
    previewReadNorm.store(heldReadNorm, std::memory_order_relaxed);
    return true;
}

void TimeShaperAudioProcessor::processBlock(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const bool shouldAdvancePreview = resolveProcessorTransportPlaying(*this);
    const float heldPhase = previewPhase.load(std::memory_order_relaxed);
    const float heldReadNorm = previewReadNorm.load(std::memory_order_relaxed);
    if (handleStoppedTransport(shouldAdvancePreview, heldPhase, heldReadNorm))
        return;

    shaper.setParameters(parameters);
    shaper.process(buffer,
                   resolveProcessorTransportSeconds(*this),
                   previewPhase,
                   previewReadNorm);
}

void TimeShaperAudioProcessor::processBlockBypassed(juce::AudioBuffer<float> &buffer, juce::MidiBuffer &)
{
    juce::ScopedNoDenormals noDenormals;

    for (int ch = getTotalNumInputChannels();
         ch < getTotalNumOutputChannels(); ++ch)
        buffer.clear(ch, 0, buffer.getNumSamples());

    const bool shouldAdvancePreview = resolveProcessorTransportPlaying(*this);
    const float heldPhase = previewPhase.load(std::memory_order_relaxed);
    const float heldReadNorm = previewReadNorm.load(std::memory_order_relaxed);
    if (handleStoppedTransport(shouldAdvancePreview, heldPhase, heldReadNorm))
        return;

    shaper.setParameters(parameters);
    shaper.updateHistory(buffer,
                         resolveProcessorTransportSeconds(*this),
                         previewPhase,
                         previewReadNorm);
}

std::vector<float> TimeShaperAudioProcessor::getPreviewCurve(int pointCount) const
{
    const auto *patternParam = parameters.getRawParameterValue("pattern");
    const auto *amountParam = parameters.getRawParameterValue("amount");
    const auto *smoothParam = parameters.getRawParameterValue("smooth");
    const auto *swingParam = parameters.getRawParameterValue("swing");
    const auto *phaseParam = parameters.getRawParameterValue("phase");
    if (patternParam == nullptr || amountParam == nullptr ||
        smoothParam == nullptr || swingParam == nullptr || phaseParam == nullptr)
        return std::vector<float>((size_t)(juce::jlimit(32, 512, pointCount) + 1), 1.0f);

    return TimeShaperModule::buildPreviewCurve(
        pointCount,
        (int)patternParam->load(),
        amountParam->load(),
        smoothParam->load(),
        swingParam->load(),
        phaseParam->load(),
        previewPhase.load(std::memory_order_relaxed));
}

void TimeShaperAudioProcessor::getStateInformation(juce::MemoryBlock &destData)
{
    std::unique_ptr<juce::XmlElement> outputXml(parameters.state.createXml());
    copyXmlToBinary(*outputXml, destData);
}

void TimeShaperAudioProcessor::setStateInformation(const void *data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> inputXml(getXmlFromBinary(data, sizeInBytes));
    if (inputXml != nullptr && inputXml->hasTagName(parameters.state.getType()))
        parameters.state = juce::ValueTree::fromXml(*inputXml);
}

#ifndef JucePlugin_PreferredChannelConfigurations
bool TimeShaperAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const
{
#if JucePlugin_IsMidiEffect
    juce::ignoreUnused(layouts);
    return true;
#else
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono() &&
        layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;
#if !JucePlugin_IsSynth
    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;
#endif
    return true;
#endif
}
#endif
