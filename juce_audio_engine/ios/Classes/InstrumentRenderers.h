#pragma once

#include "JuceHeader.h"

namespace mixroom::instruments
{
struct MidiRenderNote
{
    int pitch = 60;
    double startBeat = 0.0;
    double lengthBeats = 1.0;
    double velocity = 0.8;
};

struct InstrumentRenderRequest
{
    juce::File outFile;
    juce::String instrumentId;
    juce::String instrumentName;
    double bpm = 120.0;
    juce::Array<MidiRenderNote> notes;
    juce::NamedValueSet params;
};

juce::String renderInstrumentClipToWav(const InstrumentRenderRequest &request);
} // namespace mixroom::instruments

