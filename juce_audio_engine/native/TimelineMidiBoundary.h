#pragma once

namespace mixroom
{
constexpr bool timelineMidiBlockEntersClip(double blockStartSec,
                                           double blockEndSec,
                                           double clipStartSec) noexcept
{
    return blockStartSec <= clipStartSec && blockEndSec > clipStartSec;
}

constexpr double timelineMidiAdmissionSourceStartSec(
    double blockStartSec,
    double blockEndSec,
    double clipStartSec,
    double roundedSourceStartSec,
    double inFileOffsetSec) noexcept
{
    return timelineMidiBlockEntersClip(
               blockStartSec,
               blockEndSec,
               clipStartSec)
               ? inFileOffsetSec
               : roundedSourceStartSec;
}

static_assert(
    timelineMidiAdmissionSourceStartSec(
        1.99,
        2.01,
        2.0,
        1.0 / 44100.0,
        0.0) == 0.0,
    "A non-sample-aligned clip start must admit a beat-zero MIDI note.");
static_assert(
    timelineMidiAdmissionSourceStartSec(
        2.0,
        2.01,
        2.0,
        0.0,
        0.0) == 0.0,
    "A sample-aligned clip start must preserve existing behavior.");
static_assert(
    timelineMidiAdmissionSourceStartSec(
        2.001,
        2.011,
        2.0,
        0.001,
        0.0) == 0.001,
    "Starting inside a clip must not chase or retrigger an earlier note.");
static_assert(
    timelineMidiAdmissionSourceStartSec(
        1.99,
        2.01,
        2.0,
        0.75001,
        0.75) == 0.75,
    "The first block of a trimmed clip must begin at its exact trim point.");
static_assert(
    timelineMidiAdmissionSourceStartSec(
        1.98,
        1.99,
        2.0,
        0.0,
        0.75) == 0.0,
    "A block before the clip must not use the clip source boundary.");
} // namespace mixroom
