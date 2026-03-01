#include "InstrumentRenderers.h"

#include <cmath>
#include <cstdint>
#include <memory>
#include <unordered_map>

namespace mixroom::instruments
{
namespace
{
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

struct NoteState
{
    double phaseA = 0.0;
    double phaseB = 0.0;
    double low = 0.0;
    double aux = 0.0;
    int seed = 0;
};

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

static bool readParam(const juce::NamedValueSet &params, const char *key, double &outValue)
{
    auto *value = params.getVarPointer(juce::Identifier(key));
    if (value == nullptr || value->isVoid())
        return false;
    if (value->isBool())
    {
        outValue = (bool)*value ? 1.0 : 0.0;
        return true;
    }
    if (value->isInt() || value->isInt64() || value->isDouble())
    {
        outValue = (double)*value;
        return true;
    }
    return false;
}

static double wrapPhase(double phase)
{
    phase -= std::floor(phase);
    if (phase < 0.0)
        phase += 1.0;
    return phase;
}

static double waveFromType(int type, double phase)
{
    const double p = wrapPhase(phase);
    switch (type)
    {
    case 0:
        return std::sin(juce::MathConstants<double>::twoPi * p);
    case 1:
        return (2.0 * p) - 1.0;
    case 2:
        return p < 0.5 ? 1.0 : -1.0;
    default:
        return p < 0.5 ? (-1.0 + 4.0 * p) : (3.0 - 4.0 * p);
    }
}

class InstrumentProcessor
{
public:
    virtual ~InstrumentProcessor() = default;

    virtual void prepare(const InstrumentPreset &newPreset, double newSampleRate)
    {
        preset = newPreset;
        sampleRate = juce::jmax(8000.0, newSampleRate);
    }

    virtual float renderSample(NoteState &state,
                               const MidiRenderNote &note,
                               int noteSampleIndex,
                               int totalNoteSamples,
                               double frequencyHz,
                               double noteProgress,
                               double envelope) = 0;

protected:
    static double noiseForSample(int seed, int index)
    {
        return hashNoise(seed + index * 17);
    }

    void advancePhase(double &phase, double frequencyHz) const
    {
        phase = wrapPhase(phase + (frequencyHz / sampleRate));
    }

    double lowPass(double input, double cutoffHz, double &state) const
    {
        const double clampedCutoff = juce::jlimit(50.0, sampleRate * 0.45, cutoffHz);
        const double alpha = 1.0 - std::exp((-2.0 * juce::MathConstants<double>::pi * clampedCutoff) / sampleRate);
        state += alpha * (input - state);
        return state;
    }

    double highPass(double input, double cutoffHz, double &state) const
    {
        const double lp = lowPass(input, cutoffHz, state);
        return input - lp;
    }

    InstrumentPreset preset;
    double sampleRate = 48000.0;
};

class BasicSynthProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double,
                       double) override
    {
        const double main = waveFromType(preset.oscillator, state.phaseA);
        const double sub = 0.32 * waveFromType(0, state.phaseB);
        const double noise = preset.noise * noiseForSample(state.seed, noteSampleIndex);
        const double raw = lowPass(main * 0.78 + sub + noise, preset.cutoffHz, state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, frequencyHz * 0.5);
        return (float)raw;
    }
};

class BassProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const double body = waveFromType(2, state.phaseA) * 0.52;
        const double sub = waveFromType(0, state.phaseB) * 0.66;
        const double growl = waveFromType(1, state.phaseA) * 0.20;
        const double transient = (0.04 + preset.transient * 0.22) *
                                 std::exp(-22.0 * noteProgress) *
                                 noiseForSample(state.seed, noteSampleIndex);
        const double dynamicCutoff =
            preset.cutoffHz * juce::jlimit(0.45, 1.05, 1.0 - noteProgress * 0.55);
        const double raw =
            lowPass(body + sub + growl + transient, dynamicCutoff, state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, frequencyHz * 0.5);
        return (float)raw;
    }
};

class PadProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const double det = juce::jlimit(0.001, 0.03, preset.detune + 0.008);
        const double lfo =
            std::sin(juce::MathConstants<double>::twoPi * (double)noteSampleIndex / sampleRate * 0.23);
        const double left = waveFromType(0, state.phaseA);
        const double right = waveFromType(3, state.phaseB);
        const double shimmer = waveFromType(1, state.phaseA + 0.25) * 0.18;
        const double noise = preset.noise * 0.5 * noiseForSample(state.seed, noteSampleIndex);
        const double openAmount = juce::jlimit(0.5, 1.35, 0.7 + (1.0 - noteProgress) * 0.5 + lfo * 0.15);
        const double raw =
            lowPass(left * 0.48 + right * 0.4 + shimmer + noise, preset.cutoffHz * openAmount, state.low);

        advancePhase(state.phaseA, frequencyHz * (1.0 - det));
        advancePhase(state.phaseB, frequencyHz * (1.0 + det));
        return (float)raw;
    }
};

class LeadProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double envelope) override
    {
        const double vibrato =
            1.0 + std::sin(juce::MathConstants<double>::twoPi * (double)noteSampleIndex / sampleRate * 5.1) *
                      (0.001 + 0.002 * envelope);
        const double saw = waveFromType(1, state.phaseA);
        const double pulse = waveFromType(2, state.phaseB) * 0.42;
        const double edge = waveFromType(3, state.phaseA * 1.99) * 0.18;
        const double noise = preset.noise * 0.35 * std::exp(-12.0 * noteProgress) *
                             noiseForSample(state.seed, noteSampleIndex);
        const double cutoffOpen = juce::jlimit(0.8, 1.55, 1.2 - noteProgress * 0.35);
        const double raw =
            lowPass(saw * 0.68 + pulse + edge + noise, preset.cutoffHz * cutoffOpen, state.low);

        advancePhase(state.phaseA, frequencyHz * vibrato);
        advancePhase(state.phaseB, frequencyHz * 1.01 * vibrato);
        return (float)raw;
    }
};

class PluckProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const double decay = std::exp(-6.5 * noteProgress);
        const double tri = waveFromType(3, state.phaseA) * 0.62;
        const double tone = waveFromType(0, state.phaseB) * 0.36;
        const double pick = (preset.transient + 0.12) * std::exp(-28.0 * noteProgress) *
                            noiseForSample(state.seed, noteSampleIndex);
        const double raw =
            lowPass((tri + tone) * decay + pick, preset.cutoffHz * (1.1 + (1.0 - noteProgress) * 0.25), state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, frequencyHz * 2.0);
        return (float)raw;
    }
};

class KeysProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const int style = juce::jlimit(0, 3, preset.oscillator);
        const double keyOpen =
            juce::jlimit(0.6, 1.7, 0.75 + preset.tone * 0.75 + (1.0 - noteProgress) * 0.2);

        if (style == 2)
        {
            const double fundamental = waveFromType(2, state.phaseA) * 0.48;
            const double octave = waveFromType(2, state.phaseB) * 0.28;
            const double twelfth = waveFromType(2, state.phaseB * 1.5) * 0.16;
            const double chorus = waveFromType(1, state.phaseB + 0.13) * 0.11;
            const double click = (0.04 + preset.transient * 0.18) *
                                 std::exp(-52.0 * noteProgress) *
                                 noiseForSample(state.seed + 31, noteSampleIndex);
            const double raw = lowPass(fundamental + octave + twelfth + chorus + click,
                                       preset.cutoffHz * keyOpen,
                                       state.low);

            advancePhase(state.phaseA, frequencyHz);
            advancePhase(state.phaseB, frequencyHz * 2.0);
            return (float)raw;
        }

        const double inharmonic = 1.0 + juce::jlimit(0.0, 0.005, frequencyHz * 0.0000005);
        const double hammer = (0.09 + preset.transient * 0.30) *
                              std::exp(-36.0 * noteProgress) *
                              noiseForSample(state.seed + 21, noteSampleIndex);
        const double body = waveFromType(0, state.phaseA) * 0.58;
        const double second = waveFromType(0, state.phaseB * inharmonic) * 0.26;
        const double third = waveFromType(style == 1 ? 1 : 0, state.phaseB * 1.5 * inharmonic) * 0.15;
        const double tine = waveFromType(style == 3 ? 3 : 0, state.phaseB * (2.4 + style * 0.25)) * 0.11;
        const double raw =
            lowPass(body + second + third + tine + hammer, preset.cutoffHz * keyOpen, state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, frequencyHz * 2.0);
        return (float)raw;
    }
};

class BrassProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double envelope) override
    {
        const int style = juce::jlimit(0, 3, preset.oscillator);
        const double vibratoDepth = 0.0011 + envelope * (0.001 + style * 0.0003);
        const double vibratoRate = 4.8 + style * 0.5;
        const double vibrato =
            1.0 + std::sin(juce::MathConstants<double>::twoPi * (double)noteSampleIndex / sampleRate * vibratoRate) *
                      vibratoDepth;
        const double saw = waveFromType(1, state.phaseA) * 0.48;
        const double pulse = waveFromType(2, state.phaseB) * 0.35;
        const double upper = waveFromType(style >= 2 ? 1 : 0, state.phaseA * 2.0) * (0.15 + 0.03 * style);
        const double breath = (0.02 + preset.noise * 0.55) *
                              std::exp(-7.0 * noteProgress) *
                              noiseForSample(state.seed + 41, noteSampleIndex);
        const double t = (double)noteSampleIndex / sampleRate;
        const double formantA = std::sin(juce::MathConstants<double>::twoPi * (760.0 + style * 110.0) * t) * 0.07;
        const double formantB = std::sin(juce::MathConstants<double>::twoPi * (1320.0 + style * 140.0) * t) * 0.05;
        const double dynamicCutoff = preset.cutoffHz * juce::jlimit(0.65, 1.6, 0.85 + envelope * 0.65 - noteProgress * 0.12);
        const double raw = lowPass(saw + pulse + upper + breath + formantA + formantB, dynamicCutoff, state.low);

        advancePhase(state.phaseA, frequencyHz * vibrato);
        advancePhase(state.phaseB, frequencyHz * (1.0 - 0.006) * vibrato);
        return (float)raw;
    }
};

class WavetableProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const double modLfo =
            std::sin(juce::MathConstants<double>::twoPi * (double)noteSampleIndex / sampleRate * 0.35);
        const double pd =
            wrapPhase(state.phaseA + 0.18 * std::sin(juce::MathConstants<double>::twoPi * state.phaseB + modLfo));
        const double main = std::sin(juce::MathConstants<double>::twoPi * pd);
        const double upper = std::sin(juce::MathConstants<double>::twoPi * pd * 2.0) * 0.33;
        const double sparkle = waveFromType(1, pd * 1.5) * 0.22;
        const double raw = lowPass(main + upper + sparkle,
                                   preset.cutoffHz * (1.1 - noteProgress * 0.25),
                                   state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, 0.27);
        return (float)raw;
    }
};

class HarmonicProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const int style = juce::jlimit(0, 3, preset.oscillator);
        const double modRatio = style <= 1 ? 2.0 : 3.0;
        const double modDepth = 0.05 + preset.tone * 0.13 + style * 0.02;
        const double mod = std::sin(juce::MathConstants<double>::twoPi * state.phaseB * modRatio);
        const double carrier = wrapPhase(state.phaseA + mod * modDepth);
        const double p = juce::MathConstants<double>::twoPi * carrier;
        const double body = std::sin(p) * 0.50;
        const double even = std::sin(2.0 * p) * 0.26;
        const double odd = std::sin(3.0 * p) * 0.18;
        const double air = std::sin(5.0 * p) * 0.10;
        const double sheen = waveFromType(style == 3 ? 1 : 3, state.phaseB) * 0.12;
        const double transient = (0.02 + preset.transient * 0.12) *
                                 std::exp(-24.0 * noteProgress) *
                                 noiseForSample(state.seed + 57, noteSampleIndex);
        const double dynamicCutoff = preset.cutoffHz * (0.9 + (1.0 - noteProgress) * 0.35);
        const double raw = lowPass(body + even + odd + air + sheen + transient, dynamicCutoff, state.low);

        advancePhase(state.phaseA, frequencyHz);
        advancePhase(state.phaseB, frequencyHz * 0.5);
        return (float)raw;
    }
};

class DrumProcessor final : public InstrumentProcessor
{
public:
    float renderSample(NoteState &state,
                       const MidiRenderNote &note,
                       int noteSampleIndex,
                       int,
                       double frequencyHz,
                       double noteProgress,
                       double) override
    {
        const int style = juce::jlimit(0, 3, preset.oscillator);
        if (note.pitch <= 36)
            return renderKick(state, noteSampleIndex, frequencyHz, noteProgress, style);
        if (note.pitch <= 44)
            return renderSnare(state, noteSampleIndex, frequencyHz, noteProgress, style);
        if (note.pitch <= 52)
            return renderClap(state, noteSampleIndex, frequencyHz, noteProgress, style);
        if (note.pitch <= 63)
            return renderTom(state, noteSampleIndex, frequencyHz, noteProgress, style);
        return renderHat(state, noteSampleIndex, noteProgress, style);
    }

private:
    float renderKick(NoteState &state, int noteSampleIndex, double frequencyHz, double noteProgress, int style)
    {
        const double extraDrop = style == 0 ? 22.0 : style == 1 ? 12.0
                                              : style == 2   ? 16.0
                                                             : 14.0;
        const double curve = style == 0 ? 1.35 : 1.0;
        const double dropSemis = juce::jlimit(0.0, 36.0, preset.pitchDropSemitones + extraDrop);
        const double dropProgress = std::pow(1.0 - noteProgress, curve);
        const double ratio = std::pow(2.0, -(dropSemis * dropProgress) / 12.0);
        const double tunedFreq = juce::jlimit(24.0, 1400.0, frequencyHz * ratio);

        const double body = std::sin(juce::MathConstants<double>::twoPi * state.phaseA) * (0.80 + 0.06 * style);
        const double sub = std::sin(juce::MathConstants<double>::twoPi * state.phaseB) * (style == 0 ? 0.36 : 0.22);
        const double click =
            (0.07 + preset.transient * (0.34 + style * 0.07)) * std::exp(-40.0 * noteProgress) *
            noiseForSample(state.seed + 7, noteSampleIndex);
        const double beater =
            ((style == 1 || style == 2) ? 0.08 : 0.03) *
            std::exp(-58.0 * noteProgress) *
            std::sin(juce::MathConstants<double>::twoPi * state.phaseB * 10.0);
        const double raw = lowPass(body + sub + click + beater, preset.cutoffHz * (0.75 + (1.0 - noteProgress) * 0.9), state.low);

        advancePhase(state.phaseA, tunedFreq);
        advancePhase(state.phaseB, tunedFreq * 0.5);
        return (float)raw;
    }

    float renderSnare(NoteState &state, int noteSampleIndex, double frequencyHz, double noteProgress, int style)
    {
        const double toneMult = style == 0 ? 1.25 : style == 1 ? 1.6
                                              : style == 2   ? 1.85
                                                             : 1.45;
        const double toneA = std::sin(juce::MathConstants<double>::twoPi * state.phaseA) * std::exp(-8.0 * noteProgress) * 0.36;
        const double toneB = std::sin(juce::MathConstants<double>::twoPi * state.phaseB) * std::exp(-10.0 * noteProgress) * 0.20;
        const double noise =
            noiseForSample(state.seed + 17, noteSampleIndex) *
            std::exp(-(9.0 + style * 1.2) * noteProgress) *
            (0.55 + 0.16 * style + preset.noise * 0.55);
        const double raw = highPass(toneA + toneB + noise, 780.0 + style * 140.0, state.aux);
        advancePhase(state.phaseA, frequencyHz * toneMult);
        advancePhase(state.phaseB, frequencyHz * toneMult * 1.72);
        return (float)raw;
    }

    float renderClap(NoteState &state, int noteSampleIndex, double frequencyHz, double noteProgress, int style)
    {
        if (style == 1)
        {
            const double rimTone =
                std::sin(juce::MathConstants<double>::twoPi * state.phaseA) *
                std::exp(-22.0 * noteProgress) * 0.34;
            const double rimSnap =
                noiseForSample(state.seed + 29, noteSampleIndex) * std::exp(-26.0 * noteProgress) * 0.28;
            advancePhase(state.phaseA, frequencyHz * 3.2);
            return (float)(rimTone + rimSnap);
        }

        const double burst0 = std::exp(-95.0 * std::pow(noteProgress - 0.028, 2.0));
        const double burst1 = std::exp(-125.0 * std::pow(noteProgress - 0.068, 2.0));
        const double burst2 = std::exp(-165.0 * std::pow(noteProgress - 0.112, 2.0));
        const double envelope = juce::jlimit(0.0, 1.0, burst0 + burst1 + burst2);
        const double tail = std::exp(-(10.0 + style * 1.5) * noteProgress);
        const double noise = noiseForSample(state.seed + 29, noteSampleIndex);
        return (float)(noise * (envelope * 0.78 + tail * 0.22));
    }

    float renderTom(NoteState &state, int noteSampleIndex, double frequencyHz, double noteProgress, int style)
    {
        const double tomMul = style == 0 ? 0.85 : style == 1 ? 1.0
                                            : style == 2   ? 1.18
                                                           : 0.95;
        const double tomFreq = juce::jlimit(70.0, 900.0, frequencyHz * tomMul);
        const double tone = std::sin(juce::MathConstants<double>::twoPi * state.phaseA) *
                            std::exp(-6.5 * noteProgress) * 0.56;
        const double ring = waveFromType(3, state.phaseB) * std::exp(-8.5 * noteProgress) * 0.24;
        const double stick =
            (0.03 + preset.transient * 0.14) * std::exp(-42.0 * noteProgress) *
            noiseForSample(state.seed + 37, noteSampleIndex);
        const double raw = lowPass(tone + ring + stick, preset.cutoffHz * 1.1, state.low);
        advancePhase(state.phaseA, tomFreq);
        advancePhase(state.phaseB, tomFreq * 1.6);
        return (float)raw;
    }

    float renderHat(NoteState &state, int noteSampleIndex, double noteProgress, int style)
    {
        const double hatDecay = style == 0 ? 14.0 : style == 1 ? 18.0
                                              : style == 2   ? 16.0
                                                             : 11.0;
        const double noise =
            noiseForSample(state.seed + 47, noteSampleIndex) * std::exp(-hatDecay * noteProgress);
        const double metallic = waveFromType(2, state.phaseA) * 0.23 + waveFromType(1, state.phaseB) * 0.16;
        const double air = waveFromType(0, state.phaseA * 1.7) * 0.06;
        const double raw = highPass(noise + metallic + air, 4800.0 + style * 380.0, state.aux);
        advancePhase(state.phaseA, 6400.0 + style * 750.0);
        advancePhase(state.phaseB, 8900.0 + style * 980.0);
        return (float)raw;
    }
};

static std::unique_ptr<InstrumentProcessor> makeProcessor(InstrumentFamily family)
{
    switch (family)
    {
    case InstrumentFamily::bass:
        return std::make_unique<BassProcessor>();
    case InstrumentFamily::pad:
        return std::make_unique<PadProcessor>();
    case InstrumentFamily::lead:
        return std::make_unique<LeadProcessor>();
    case InstrumentFamily::pluck:
        return std::make_unique<PluckProcessor>();
    case InstrumentFamily::keys:
        return std::make_unique<KeysProcessor>();
    case InstrumentFamily::brass:
        return std::make_unique<BrassProcessor>();
    case InstrumentFamily::wavetable:
        return std::make_unique<WavetableProcessor>();
    case InstrumentFamily::harmonic:
        return std::make_unique<HarmonicProcessor>();
    case InstrumentFamily::drum:
        return std::make_unique<DrumProcessor>();
    case InstrumentFamily::basic:
    default:
        return std::make_unique<BasicSynthProcessor>();
    }
}

static const std::unordered_map<std::string, InstrumentPreset> &presetMap()
{
    static const std::unordered_map<std::string, InstrumentPreset> map = {
        {"mixroom.basic_synth", {InstrumentFamily::basic, 1, 3200.0, 18.0, 180.0, 0.08, 0.36, 0.002, 0.12, 0.56, 0.08, 0.0, 0.02}},
        {"mixroom.bass_mono", {InstrumentFamily::bass, 2, 1200.0, 8.0, 220.0, 0.28, 0.34, 0.001, 0.04, 0.52, 0.18, 4.0, 0.04}},
        {"mixroom.soft_pad", {InstrumentFamily::pad, 3, 2100.0, 80.0, 620.0, 0.02, 0.31, 0.012, 0.28, 0.47, 0.04, 0.0, 0.03}},
        {"mixroom.figbug_wavetable", {InstrumentFamily::wavetable, 1, 5200.0, 6.0, 240.0, 0.18, 0.33, 0.006, 0.16, 0.72, 0.14, 0.0, 0.03}},
        {"mixroom.sarah_harmonic", {InstrumentFamily::harmonic, 3, 2800.0, 34.0, 540.0, 0.1, 0.32, 0.008, 0.2, 0.54, 0.08, 0.0, 0.03}},
        {"mixroom.vanilla_poly", {InstrumentFamily::keys, 0, 3600.0, 12.0, 260.0, 0.05, 0.33, 0.004, 0.13, 0.58, 0.1, 0.0, 0.02}},
        {"mixroom.duck_synth", {InstrumentFamily::bass, 2, 1600.0, 2.0, 140.0, 0.26, 0.35, 0.002, 0.06, 0.62, 0.2, 8.0, 0.03}},
        {"mixroom.chow_kick", {InstrumentFamily::drum, 0, 900.0, 0.0, 90.0, 0.42, 0.42, 0.0, 0.0, 0.52, 0.4, 16.0, 0.14}},
        {"mixroom.warm_keys", {InstrumentFamily::keys, 0, 3000.0, 14.0, 320.0, 0.06, 0.32, 0.005, 0.12, 0.52, 0.12, 0.0, 0.02}},
        {"mixroom.super_saw", {InstrumentFamily::lead, 1, 6200.0, 4.0, 180.0, 0.22, 0.34, 0.01, 0.2, 0.75, 0.11, 0.0, 0.03}},
        {"mixroom.gentle_pluck", {InstrumentFamily::pluck, 3, 4800.0, 2.0, 130.0, 0.08, 0.33, 0.004, 0.11, 0.68, 0.24, 0.0, 0.03}},
        {"mixroom.sub_bass", {InstrumentFamily::bass, 2, 900.0, 3.0, 200.0, 0.24, 0.35, 0.001, 0.03, 0.46, 0.12, 5.0, 0.03}},
        {"mixroom.analog_brass", {InstrumentFamily::brass, 1, 2600.0, 25.0, 300.0, 0.14, 0.33, 0.003, 0.12, 0.55, 0.08, 0.0, 0.02}},
        {"mixroom.drum_acoustic_easy", {InstrumentFamily::drum, 1, 2300.0, 0.0, 120.0, 0.18, 0.41, 0.0, 0.0, 0.52, 0.26, 10.0, 0.15}},
        {"mixroom.drum_808_starter", {InstrumentFamily::drum, 0, 1100.0, 0.0, 190.0, 0.36, 0.44, 0.0, 0.0, 0.6, 0.35, 24.0, 0.18}},
        {"mixroom.drum_lofi", {InstrumentFamily::drum, 3, 1700.0, 1.0, 150.0, 0.28, 0.41, 0.0, 0.0, 0.45, 0.2, 12.0, 0.2}},
        {"mixroom.drum_house", {InstrumentFamily::drum, 1, 2600.0, 0.0, 95.0, 0.24, 0.42, 0.0, 0.0, 0.58, 0.28, 14.0, 0.17}},
        {"mixroom.night_bell", {InstrumentFamily::harmonic, 0, 5600.0, 1.0, 540.0, 0.06, 0.3, 0.002, 0.22, 0.76, 0.16, 0.0, 0.01}},
        {"mixroom.fm_keys", {InstrumentFamily::harmonic, 0, 4100.0, 5.0, 340.0, 0.07, 0.32, 0.004, 0.14, 0.66, 0.14, 0.0, 0.02}},
        {"mixroom.vintage_strings", {InstrumentFamily::pad, 1, 2400.0, 32.0, 640.0, 0.08, 0.31, 0.015, 0.24, 0.5, 0.07, 0.0, 0.02}},
        {"mixroom.neo_brass", {InstrumentFamily::brass, 1, 3100.0, 16.0, 250.0, 0.15, 0.33, 0.004, 0.14, 0.61, 0.08, 0.0, 0.02}},
        {"mixroom.reese_bass", {InstrumentFamily::bass, 1, 1300.0, 4.0, 200.0, 0.26, 0.35, 0.015, 0.08, 0.57, 0.16, 5.0, 0.05}},
        {"mixroom.air_pluck", {InstrumentFamily::pluck, 3, 5200.0, 1.0, 210.0, 0.08, 0.33, 0.008, 0.14, 0.72, 0.2, 0.0, 0.05}},
        {"mixroom.cinematic_pad", {InstrumentFamily::pad, 3, 1900.0, 95.0, 760.0, 0.05, 0.3, 0.018, 0.3, 0.44, 0.05, 0.0, 0.03}},
        {"mixroom.velvet_ep", {InstrumentFamily::keys, 0, 3700.0, 7.0, 380.0, 0.07, 0.32, 0.005, 0.16, 0.66, 0.18, 0.0, 0.02}},
        {"mixroom.house_organ", {InstrumentFamily::keys, 2, 3400.0, 0.0, 210.0, 0.11, 0.33, 0.003, 0.10, 0.62, 0.12, 0.0, 0.02}},
        {"mixroom.glass_pluck", {InstrumentFamily::pluck, 3, 5600.0, 1.0, 170.0, 0.09, 0.33, 0.007, 0.14, 0.74, 0.24, 0.0, 0.03}},
        {"mixroom.neon_lead", {InstrumentFamily::lead, 1, 6400.0, 3.0, 210.0, 0.24, 0.34, 0.012, 0.18, 0.78, 0.13, 0.0, 0.03}},
        {"mixroom.mellow_sub", {InstrumentFamily::bass, 2, 980.0, 4.0, 260.0, 0.19, 0.35, 0.001, 0.04, 0.42, 0.10, 3.0, 0.02}},
        {"mixroom.wide_air_pad", {InstrumentFamily::pad, 3, 2300.0, 74.0, 700.0, 0.04, 0.30, 0.020, 0.30, 0.50, 0.05, 0.0, 0.02}},
        {"mixroom.horn_stack", {InstrumentFamily::brass, 1, 2900.0, 20.0, 280.0, 0.16, 0.33, 0.004, 0.12, 0.58, 0.09, 0.0, 0.02}},
        {"mixroom.drum_trap", {InstrumentFamily::drum, 0, 2100.0, 0.0, 110.0, 0.32, 0.42, 0.0, 0.0, 0.62, 0.32, 18.0, 0.2}},
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
        return {InstrumentFamily::drum, 0, 2000.0, 0.0, 120.0, 0.3, 0.42, 0.0, 0.0, 0.58, 0.3, 16.0, 0.2};
    if (contains("bass"))
        return {InstrumentFamily::bass, 2, 1200.0, 6.0, 220.0, 0.24, 0.34, 0.004, 0.06, 0.52, 0.16, 6.0, 0.04};
    if (contains("pad") || contains("string"))
        return {InstrumentFamily::pad, 3, 2200.0, 80.0, 620.0, 0.05, 0.3, 0.012, 0.24, 0.48, 0.06, 0.0, 0.03};
    if (contains("pluck") || contains("bell"))
        return {InstrumentFamily::pluck, 3, 5100.0, 2.0, 190.0, 0.08, 0.33, 0.005, 0.13, 0.74, 0.2, 0.0, 0.03};
    if (contains("brass") || contains("horn"))
        return {InstrumentFamily::brass, 1, 2800.0, 18.0, 290.0, 0.14, 0.33, 0.004, 0.13, 0.56, 0.08, 0.0, 0.02};
    if (contains("key") || contains("piano") || contains("organ"))
        return {InstrumentFamily::keys, 0, 3300.0, 10.0, 280.0, 0.06, 0.32, 0.004, 0.12, 0.58, 0.12, 0.0, 0.02};
    if (contains("wave"))
        return {InstrumentFamily::wavetable, 1, 4800.0, 6.0, 240.0, 0.16, 0.33, 0.006, 0.14, 0.68, 0.12, 0.0, 0.03};
    if (contains("harmonic") || contains("fm"))
        return {InstrumentFamily::harmonic, 0, 3400.0, 12.0, 360.0, 0.09, 0.32, 0.005, 0.15, 0.62, 0.12, 0.0, 0.02};
    if (contains("lead") || contains("saw"))
        return {InstrumentFamily::lead, 1, 5600.0, 4.0, 200.0, 0.18, 0.34, 0.008, 0.16, 0.74, 0.1, 0.0, 0.03};

    return presetMap().at("mixroom.basic_synth");
}

static void applyParamOverrides(InstrumentPreset &preset, const juce::NamedValueSet &params)
{
    double rawValue = 0.0;
    if (readParam(params, "oscillator", rawValue))
        preset.oscillator = juce::jlimit(0, 3, (int)std::lround(rawValue));
    if (readParam(params, "cutoffHz", rawValue))
        preset.cutoffHz = juce::jlimit(200.0, 16000.0, rawValue);
    if (readParam(params, "attackMs", rawValue))
        preset.attackMs = juce::jlimit(0.0, 1000.0, rawValue);
    if (readParam(params, "releaseMs", rawValue))
        preset.releaseMs = juce::jlimit(20.0, 2400.0, rawValue);
    if (readParam(params, "drive", rawValue))
        preset.drive = juce::jlimit(0.0, 1.0, rawValue);
    if (readParam(params, "outputGain", rawValue))
        preset.outputGain = juce::jlimit(0.15, 0.75, rawValue);
    if (readParam(params, "detune", rawValue))
        preset.detune = juce::jlimit(0.0, 0.03, rawValue);
    if (readParam(params, "stereoWidth", rawValue))
        preset.stereoWidth = juce::jlimit(0.0, 0.45, rawValue);
    if (readParam(params, "tone", rawValue))
        preset.tone = juce::jlimit(0.0, 1.0, rawValue);
    if (readParam(params, "transient", rawValue))
        preset.transient = juce::jlimit(0.0, 1.0, rawValue);
    if (readParam(params, "noise", rawValue))
        preset.noise = juce::jlimit(0.0, 0.45, rawValue);
    if (readParam(params, "pitchDropSemitones", rawValue))
        preset.pitchDropSemitones = juce::jlimit(0.0, 36.0, rawValue);
}
} // namespace

juce::String renderInstrumentClipToWav(const InstrumentRenderRequest &request)
{
    if (request.outFile.getFullPathName().trim().isEmpty())
        return {};

    juce::File outFile = request.outFile;
    outFile.getParentDirectory().createDirectory();
    if (outFile.existsAsFile() && !outFile.deleteFile())
        return {};

    InstrumentPreset preset = resolvePreset(request.instrumentId, request.instrumentName);
    applyParamOverrides(preset, request.params);

    auto processor = makeProcessor(preset.family);
    if (processor == nullptr)
        return {};

    const double sampleRate = 48000.0;
    const int channels = 2;
    const int bitsPerSample = 16;
    const double bpm = juce::jlimit(1.0, 400.0, request.bpm);
    const double msPerBeat = 60000.0 / bpm;

    processor->prepare(preset, sampleRate);

    juce::Array<MidiRenderNote> notes;
    notes.ensureStorageAllocated(request.notes.size());
    for (const auto &n : request.notes)
    {
        MidiRenderNote clean;
        clean.pitch = juce::jlimit(0, 127, n.pitch);
        clean.startBeat = juce::jmax(0.0, n.startBeat);
        clean.lengthBeats = juce::jmax(0.0625, n.lengthBeats);
        clean.velocity = juce::jlimit(0.0, 1.0, n.velocity);
        notes.add(clean);
    }

    double endBeat = 4.0;
    for (const auto &n : notes)
        endBeat = juce::jmax(endBeat, n.startBeat + n.lengthBeats);

    const double totalMs = juce::jmax(1200.0, endBeat * msPerBeat + preset.releaseMs + 120.0);
    const int totalSamples = juce::jmax(2048, (int)std::ceil(totalMs * sampleRate / 1000.0));

    juce::AudioBuffer<float> buffer(channels, totalSamples);
    buffer.clear();

    for (const auto &note : notes)
    {
        const int noteStart = (int)std::round(note.startBeat * msPerBeat * sampleRate / 1000.0);
        const int sustainSamples = juce::jmax(1, (int)std::round(note.lengthBeats * msPerBeat * sampleRate / 1000.0));
        const int attackSamples = juce::jmax(1, (int)std::round(preset.attackMs * sampleRate / 1000.0));
        const int releaseSamples = juce::jmax(1, (int)std::round(preset.releaseMs * sampleRate / 1000.0));
        const int totalNoteSamples = sustainSamples + releaseSamples;
        const double frequencyHz = 440.0 * std::pow(2.0, ((double)note.pitch - 69.0) / 12.0);

        NoteState noteState;
        noteState.seed = note.pitch * 97 + noteStart * 7 + totalNoteSamples * 13;
        noteState.phaseA = wrapPhase((double)((note.pitch * 19) % 100) / 100.0);
        noteState.phaseB = wrapPhase((double)((note.pitch * 37) % 100) / 100.0);

        for (int i = 0; i < totalNoteSamples; ++i)
        {
            const int idx = noteStart + i;
            if (idx < 0 || idx >= totalSamples)
                break;

            double envelope = 1.0;
            if (i < attackSamples)
            {
                envelope = (double)i / (double)attackSamples;
            }
            else if (i >= sustainSamples)
            {
                const int releasePos = i - sustainSamples;
                envelope = 1.0 - ((double)releasePos / (double)releaseSamples);
            }
            envelope = juce::jlimit(0.0, 1.0, envelope);

            const double noteProgress =
                totalNoteSamples <= 1 ? 1.0 : juce::jlimit(0.0, 1.0, (double)i / (double)(totalNoteSamples - 1));

            const float raw = processor->renderSample(noteState,
                                                      note,
                                                      i,
                                                      totalNoteSamples,
                                                      frequencyHz,
                                                      noteProgress,
                                                      envelope);
            const double driven = std::tanh((1.0 + preset.drive * 5.0) * (double)raw);
            const double sampleValue = driven * envelope * note.velocity * preset.outputGain;

            const double pan = std::sin((double)note.pitch * 0.23 + (double)noteState.seed * 0.013) * preset.stereoWidth;
            const double clampedPan = juce::jlimit(-0.95, 0.95, pan);
            const double leftGain = std::sqrt(0.5 * (1.0 - clampedPan));
            const double rightGain = std::sqrt(0.5 * (1.0 + clampedPan));
            buffer.addSample(0, idx, (float)(sampleValue * leftGain));
            buffer.addSample(1, idx, (float)(sampleValue * rightGain));
        }
    }

    float peak = 0.0f;
    for (int ch = 0; ch < channels; ++ch)
    {
        const float *channelData = buffer.getReadPointer(ch);
        for (int i = 0; i < totalSamples; ++i)
            peak = juce::jmax(peak, std::abs(channelData[i]));
    }

    if (peak > 0.98f)
        buffer.applyGain(0.98f / peak);

    auto stream = outFile.createOutputStream();
    if (stream == nullptr)
        return {};

    juce::WavAudioFormat wav;
    std::unique_ptr<juce::AudioFormatWriter> writer(
        wav.createWriterFor(stream.get(), sampleRate, (unsigned int)channels, bitsPerSample, {}, 0));
    if (writer == nullptr)
        return {};

    stream.release();
    writer->writeFromAudioSampleBuffer(buffer, 0, totalSamples);
    writer.reset();

    return outFile.getFullPathName();
}
} // namespace mixroom::instruments
