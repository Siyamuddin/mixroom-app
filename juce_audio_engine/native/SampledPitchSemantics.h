#pragma once

#include <cmath>

namespace mixroom
{
constexpr int effectiveSampleKeyCenterForRoundedRoot(
    int sourceKeyCenter,
    int roundedPresetRootNote) noexcept
{
    constexpr int neutralRootNote = 60;
    const int shiftedKeyCenter =
        sourceKeyCenter + roundedPresetRootNote - neutralRootNote;
    return shiftedKeyCenter < 0
               ? 0
               : shiftedKeyCenter > 127 ? 127 : shiftedKeyCenter;
}

inline int effectiveSampleKeyCenter(int sourceKeyCenter,
                                    double presetRootNote) noexcept
{
    return effectiveSampleKeyCenterForRoundedRoot(
        sourceKeyCenter, (int)std::lround(presetRootNote));
}

static_assert(effectiveSampleKeyCenterForRoundedRoot(21, 60) == 21,
              "The default sampler root must preserve SFZ key centers");
static_assert(effectiveSampleKeyCenterForRoundedRoot(60, 62) == 62,
              "Sampler root changes must remain relative to middle C");
static_assert(effectiveSampleKeyCenterForRoundedRoot(1, 0) == 0,
              "Shifted key centers must clamp at MIDI zero");
static_assert(effectiveSampleKeyCenterForRoundedRoot(126, 127) == 127,
              "Shifted key centers must clamp at MIDI 127");
} // namespace mixroom
