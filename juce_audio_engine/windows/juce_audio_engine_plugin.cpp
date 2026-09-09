#include "juce_audio_engine_plugin.h"

#include <windows.h>

#include <VersionHelpers.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cmath>
#include <exception>
#include <limits>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include "../ios/Classes/InstrumentRenderers.h"
#include "../ios/Classes/JuceEngine.h"

namespace {

juce::ScopedJuceInitialiser_GUI g_juce_initialiser;

const flutter::EncodableValue* FindValue(const flutter::EncodableMap* args,
                                         const char* key) {
  if (args == nullptr) return nullptr;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return nullptr;
  return &it->second;
}

int FindInt(const flutter::EncodableMap* args, const char* key,
            int default_value = 0) {
  const flutter::EncodableValue* raw = FindValue(args, key);
  if (raw == nullptr) return default_value;
  if (auto value = std::get_if<int32_t>(raw)) return *value;
  if (auto value = std::get_if<int64_t>(raw)) return static_cast<int>(*value);
  if (auto value = std::get_if<double>(raw)) return static_cast<int>(*value);
  if (auto value = std::get_if<std::string>(raw)) {
    try {
      return std::stoi(*value);
    } catch (...) {
      return default_value;
    }
  }
  return default_value;
}

double FindDouble(const flutter::EncodableMap* args, const char* key,
                  double default_value = 0.0) {
  const flutter::EncodableValue* raw = FindValue(args, key);
  if (raw == nullptr) return default_value;
  if (auto value = std::get_if<double>(raw)) return *value;
  if (auto value = std::get_if<int32_t>(raw)) return static_cast<double>(*value);
  if (auto value = std::get_if<int64_t>(raw)) return static_cast<double>(*value);
  if (auto value = std::get_if<std::string>(raw)) {
    try {
      return std::stod(*value);
    } catch (...) {
      return default_value;
    }
  }
  return default_value;
}

bool FindBool(const flutter::EncodableMap* args, const char* key,
              bool default_value = false) {
  const flutter::EncodableValue* raw = FindValue(args, key);
  if (raw == nullptr) return default_value;
  if (auto value = std::get_if<bool>(raw)) return *value;
  if (auto value = std::get_if<int32_t>(raw)) return *value != 0;
  if (auto value = std::get_if<int64_t>(raw)) return *value != 0;
  if (auto value = std::get_if<double>(raw)) return *value != 0.0;
  if (auto value = std::get_if<std::string>(raw)) {
    const std::string& s = *value;
    if (s == "1" || s == "true" || s == "TRUE") return true;
    if (s == "0" || s == "false" || s == "FALSE") return false;
  }
  return default_value;
}

std::string FindString(const flutter::EncodableMap* args, const char* key,
                       const std::string& default_value = std::string()) {
  const flutter::EncodableValue* raw = FindValue(args, key);
  if (raw == nullptr) return default_value;
  if (auto value = std::get_if<std::string>(raw)) return *value;
  return default_value;
}

bool EncodableToDouble(const flutter::EncodableValue& value, double* out_value) {
  if (auto v = std::get_if<double>(&value)) {
    *out_value = *v;
    return true;
  }
  if (auto v = std::get_if<int32_t>(&value)) {
    *out_value = static_cast<double>(*v);
    return true;
  }
  if (auto v = std::get_if<int64_t>(&value)) {
    *out_value = static_cast<double>(*v);
    return true;
  }
  if (auto v = std::get_if<std::string>(&value)) {
    try {
      *out_value = std::stod(*v);
      return true;
    } catch (...) {
      return false;
    }
  }
  return false;
}

int ResolveRowId(const flutter::EncodableMap* args, int default_value = 0) {
  int row_id = FindInt(args, "rowId", default_value);
  if (FindValue(args, "row") != nullptr) {
    row_id = FindInt(args, "row", row_id);
  }
  return row_id;
}

juce::String ToJuceString(const std::string& value) {
  return juce::String::fromUTF8(value.c_str());
}

std::string FromJuceString(const juce::String& value) {
  return value.toStdString();
}

template <typename Fn>
auto CallOnMessageThreadSync(Fn&& fn) -> decltype(fn()) {
  using ReturnType = decltype(fn());

  auto* message_manager = juce::MessageManager::getInstance();
  if (message_manager == nullptr || message_manager->isThisTheMessageThread()) {
    if constexpr (std::is_void_v<ReturnType>) {
      fn();
      return;
    } else {
      return fn();
    }
  }

  if constexpr (std::is_void_v<ReturnType>) {
    message_manager->callSync([&fn]() { fn(); });
    return;
  } else {
    ReturnType out{};
    message_manager->callSync([&fn, &out]() { out = fn(); });
    return out;
  }
}

juce::var EncodableToJuceVar(const flutter::EncodableValue& value) {
  if (auto v = std::get_if<bool>(&value)) {
    return juce::var(*v);
  }
  if (auto v = std::get_if<int32_t>(&value)) {
    return juce::var(*v);
  }
  if (auto v = std::get_if<int64_t>(&value)) {
    return juce::var(static_cast<juce::int64>(*v));
  }
  if (auto v = std::get_if<double>(&value)) {
    return juce::var(*v);
  }
  if (auto v = std::get_if<std::string>(&value)) {
    return juce::var(ToJuceString(*v));
  }
  return {};
}

flutter::EncodableValue JuceVarToEncodable(const juce::var& value) {
  if (value.isVoid()) return flutter::EncodableValue();
  if (value.isBool()) return flutter::EncodableValue(static_cast<bool>(value));
  if (value.isInt()) return flutter::EncodableValue(static_cast<int32_t>(static_cast<int>(value)));
  if (value.isInt64()) {
    return flutter::EncodableValue(static_cast<int64_t>(static_cast<juce::int64>(value)));
  }
  if (value.isDouble()) return flutter::EncodableValue(static_cast<double>(value));
  if (value.isString()) return flutter::EncodableValue(FromJuceString(value.toString()));

  if (auto* array = value.getArray()) {
    flutter::EncodableList list;
    list.reserve(array->size());
    for (const auto& item : *array) {
      list.push_back(JuceVarToEncodable(item));
    }
    return flutter::EncodableValue(list);
  }

  if (auto* object = value.getDynamicObject()) {
    flutter::EncodableMap map;
    const auto& named_values = object->getProperties();
    for (int i = 0; i < named_values.size(); ++i) {
      map[flutter::EncodableValue(named_values.getName(i).toString().toStdString())] =
          JuceVarToEncodable(named_values.getValueAt(i));
    }
    return flutter::EncodableValue(map);
  }

  return flutter::EncodableValue(FromJuceString(value.toString()));
}

juce::Array<TimelineMidiNote> ParseTimelineMidiNotes(
    const flutter::EncodableValue* raw_notes) {
  juce::Array<TimelineMidiNote> out;
  if (raw_notes == nullptr) return out;

  const auto* list = std::get_if<flutter::EncodableList>(raw_notes);
  if (list == nullptr) return out;

  out.ensureStorageAllocated(static_cast<int>(list->size()));
  for (const auto& entry : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;

    TimelineMidiNote note;

    auto id_it = map->find(flutter::EncodableValue("id"));
    if (id_it != map->end()) {
      if (auto id_value = std::get_if<std::string>(&id_it->second)) {
        note.noteId = ToJuceString(*id_value);
      }
    }

    double pitch = 60.0;
    auto pitch_it = map->find(flutter::EncodableValue("pitch"));
    if (pitch_it != map->end()) {
      EncodableToDouble(pitch_it->second, &pitch);
    }

    double start_beat = 0.0;
    auto start_it = map->find(flutter::EncodableValue("startBeat"));
    if (start_it != map->end()) {
      EncodableToDouble(start_it->second, &start_beat);
    }

    double length_beats = 1.0;
    auto length_it = map->find(flutter::EncodableValue("lengthBeats"));
    if (length_it != map->end()) {
      EncodableToDouble(length_it->second, &length_beats);
    }

    double velocity = 0.8;
    auto velocity_it = map->find(flutter::EncodableValue("velocity"));
    if (velocity_it != map->end()) {
      EncodableToDouble(velocity_it->second, &velocity);
    }

    note.pitch = juce::jlimit(0, 127, static_cast<int>(std::lround(pitch)));
    note.startBeat = juce::jmax(0.0, start_beat);
    note.lengthBeats = juce::jmax(0.03125, length_beats);
    note.velocity = juce::jlimit(0.0, 1.0, velocity);
    out.add(note);
  }

  return out;
}

juce::NamedValueSet ParseMidiParams(const flutter::EncodableValue* raw_params) {
  juce::NamedValueSet out;
  if (raw_params == nullptr) return out;

  const auto* map = std::get_if<flutter::EncodableMap>(raw_params);
  if (map == nullptr) return out;

  for (const auto& entry : *map) {
    const auto* key = std::get_if<std::string>(&entry.first);
    if (key == nullptr || key->empty()) continue;

    double value = 0.0;
    if (!EncodableToDouble(entry.second, &value)) continue;
    out.set(juce::Identifier(ToJuceString(*key)), juce::var(value));
  }

  return out;
}

juce::Array<mixroom::instruments::MidiRenderNote> ParseMidiRenderNotes(
    const flutter::EncodableValue* raw_notes) {
  juce::Array<mixroom::instruments::MidiRenderNote> out;
  if (raw_notes == nullptr) return out;

  const auto* list = std::get_if<flutter::EncodableList>(raw_notes);
  if (list == nullptr) return out;

  out.ensureStorageAllocated(static_cast<int>(list->size()));
  for (const auto& entry : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;

    double pitch = 60.0;
    double start_beat = 0.0;
    double length_beats = 1.0;
    double velocity = 0.8;

    auto pitch_it = map->find(flutter::EncodableValue("pitch"));
    if (pitch_it != map->end()) EncodableToDouble(pitch_it->second, &pitch);

    auto start_it = map->find(flutter::EncodableValue("startBeat"));
    if (start_it != map->end()) EncodableToDouble(start_it->second, &start_beat);

    auto length_it = map->find(flutter::EncodableValue("lengthBeats"));
    if (length_it != map->end()) EncodableToDouble(length_it->second, &length_beats);

    auto velocity_it = map->find(flutter::EncodableValue("velocity"));
    if (velocity_it != map->end()) EncodableToDouble(velocity_it->second, &velocity);

    mixroom::instruments::MidiRenderNote note;
    note.pitch = juce::jlimit(0, 127, static_cast<int>(std::lround(pitch)));
    note.startBeat = juce::jmax(0.0, start_beat);
    note.lengthBeats = juce::jmax(0.03125, length_beats);
    note.velocity = juce::jlimit(0.0, 1.0, velocity);
    out.add(note);
  }

  return out;
}

struct PitchLabRange {
  double start_ms = 0.0;
  double end_ms = 0.0;
};

struct PitchLabSegment {
  double original_start_ms = 0.0;
  double original_end_ms = 0.0;
  double target_start_ms = 0.0;
  double target_end_ms = 0.0;
  double semitones = 0.0;
};

double EncodableMapDouble(const flutter::EncodableMap& map, const char* key,
                          double fallback = 0.0) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  double value = fallback;
  if (!EncodableToDouble(it->second, &value)) return fallback;
  return std::isfinite(value) ? value : fallback;
}

std::vector<PitchLabRange> ParsePitchLabRanges(
    const flutter::EncodableValue* raw_ranges) {
  std::vector<PitchLabRange> out;
  if (raw_ranges == nullptr) return out;
  const auto* list = std::get_if<flutter::EncodableList>(raw_ranges);
  if (list == nullptr) return out;
  out.reserve(list->size());

  for (const auto& entry : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;
    PitchLabRange range;
    range.start_ms = EncodableMapDouble(*map, "startMs", 0.0);
    range.end_ms = EncodableMapDouble(*map, "endMs", 0.0);
    if (!std::isfinite(range.start_ms) || !std::isfinite(range.end_ms)) {
      continue;
    }
    if (range.end_ms < range.start_ms) std::swap(range.start_ms, range.end_ms);
    if (range.end_ms > range.start_ms + 1.0) out.push_back(range);
  }

  return out;
}

std::vector<PitchLabSegment> ParsePitchLabSegments(
    const flutter::EncodableValue* raw_segments) {
  std::vector<PitchLabSegment> out;
  if (raw_segments == nullptr) return out;
  const auto* list = std::get_if<flutter::EncodableList>(raw_segments);
  if (list == nullptr) return out;
  out.reserve(std::min<size_t>(list->size(), 256));

  size_t count = 0;
  for (const auto& entry : *list) {
    if (count++ >= 256) break;
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;
    PitchLabSegment segment;
    segment.original_start_ms =
        EncodableMapDouble(*map, "originalStartMs", 0.0);
    segment.original_end_ms = EncodableMapDouble(*map, "originalEndMs", 0.0);
    segment.target_start_ms = EncodableMapDouble(*map, "targetStartMs", 0.0);
    segment.target_end_ms = EncodableMapDouble(*map, "targetEndMs", 0.0);
    segment.semitones = juce::jlimit(
        -48.0, 48.0, EncodableMapDouble(*map, "semitones", 0.0));
    if (std::isfinite(segment.original_start_ms) &&
        std::isfinite(segment.original_end_ms) &&
        std::isfinite(segment.target_start_ms) &&
        std::isfinite(segment.target_end_ms) &&
        segment.original_end_ms > segment.original_start_ms + 1.0 &&
        segment.target_end_ms > segment.target_start_ms + 1.0) {
      out.push_back(segment);
    }
  }

  return out;
}

double PitchLabLocalMsToFileSec(double local_ms, double trim_start_ms,
                                double trim_end_ms,
                                double source_timeline_duration_ms) {
  const double active_source_ms = juce::jmax(1.0, trim_end_ms - trim_start_ms);
  const double timeline_ms = juce::jmax(1.0, source_timeline_duration_ms);
  return (trim_start_ms + juce::jlimit(0.0, timeline_ms, local_ms) *
                              (active_source_ms / timeline_ms)) /
         1000.0;
}

float PitchLabReadInterpolated(const juce::AudioBuffer<float>& buffer,
                               int channel, double source_pos) {
  const int n = buffer.getNumSamples();
  if (n <= 0) return 0.0f;
  const int ch = juce::jlimit(0, buffer.getNumChannels() - 1, channel);
  const double clamped = juce::jlimit(0.0, static_cast<double>(n - 1), source_pos);
  const int i0 = static_cast<int>(std::floor(clamped));
  const int i1 = juce::jmin(n - 1, i0 + 1);
  const float frac = static_cast<float>(clamped - static_cast<double>(i0));
  const float a = buffer.getSample(ch, i0);
  return a + (buffer.getSample(ch, i1) - a) * frac;
}

void PitchLabApplyPitchCompensation(juce::AudioBuffer<float>& buffer,
                                    double sample_rate, double semitones) {
  if (buffer.getNumSamples() <= 0 || std::abs(semitones) < 0.01) return;
  const int passes =
      juce::jlimit(1, 8, static_cast<int>(std::ceil(std::abs(semitones) / 12.0)));
  const float semitones_per_pass =
      static_cast<float>(semitones / static_cast<double>(passes));
  juce::MidiBuffer midi;
  for (int i = 0; i < passes; ++i) {
    PitchShiftAudioProcessor shifter;
    shifter.prepareToPlay(sample_rate, juce::jmax(512, buffer.getNumSamples()));
    if (auto* mix = shifter.parameters.getRawParameterValue("mix")) {
      mix->store(100.0f, std::memory_order_relaxed);
    }
    if (auto* semitones_param =
            shifter.parameters.getRawParameterValue("semitones")) {
      semitones_param->store(juce::jlimit(-12.0f, 12.0f, semitones_per_pass),
                             std::memory_order_relaxed);
    }
    midi.clear();
    shifter.processBlock(buffer, midi);
  }
}

void PitchLabStreamSourceRange(juce::AudioFormatReader& reader,
                               juce::AudioBuffer<float>& output,
                               juce::int64 source_start, int source_count,
                               int target_start, int target_count) {
  if (source_count <= 1 || target_count <= 0) return;
  constexpr int block_size = 4096;
  const int source_channels = juce::jmax(1, static_cast<int>(reader.numChannels));
  const double source_span = static_cast<double>(juce::jmax(1, source_count - 1));
  const double denom = static_cast<double>(juce::jmax(1, target_count - 1));

  for (int target_offset = 0; target_offset < target_count;
       target_offset += block_size) {
    const int block_count = juce::jmin(block_size, target_count - target_offset);
    const double block_source_start =
        (static_cast<double>(target_offset) / denom) * source_span;
    const double block_source_end =
        (static_cast<double>(target_offset + block_count - 1) / denom) *
        source_span;
    const int read_offset = juce::jlimit(
        0, source_count - 1, static_cast<int>(std::floor(block_source_start)));
    const int read_end = juce::jlimit(
        read_offset + 1, source_count + 1,
        static_cast<int>(std::ceil(block_source_end)) + 2);
    const int read_count = juce::jmax(1, read_end - read_offset);
    juce::AudioBuffer<float> scratch(source_channels, read_count);
    scratch.clear();
    reader.read(&scratch, 0, read_count, source_start + read_offset, true,
                true);

    for (int i = 0; i < block_count; ++i) {
      const double source_pos =
          ((static_cast<double>(target_offset + i) / denom) * source_span) -
          static_cast<double>(read_offset);
      for (int ch = 0; ch < 2; ++ch) {
        output.addSample(
            ch, target_start + target_offset + i,
            PitchLabReadInterpolated(scratch, source_channels == 1 ? 0 : ch,
                                     source_pos));
      }
    }
  }
}

void PitchLabMixSourceRange(juce::AudioFormatReader& reader,
                            juce::AudioBuffer<float>& output,
                            double output_sample_rate, double source_start_sec,
                            double source_end_sec, double target_start_ms,
                            double target_end_ms, double pitch_semitones) {
  if (source_end_sec <= source_start_sec + 0.0005 ||
      target_end_ms <= target_start_ms + 0.5) {
    return;
  }
  const juce::int64 source_start = juce::jlimit<juce::int64>(
      0, reader.lengthInSamples,
      static_cast<juce::int64>(std::floor(source_start_sec * reader.sampleRate)));
  const juce::int64 source_end = juce::jlimit<juce::int64>(
      0, reader.lengthInSamples,
      static_cast<juce::int64>(std::ceil(source_end_sec * reader.sampleRate)));
  const juce::int64 source_count64 =
      std::max<juce::int64>(0, source_end - source_start);
  if (source_count64 <= 1 ||
      source_count64 > static_cast<juce::int64>(std::numeric_limits<int>::max()) - 8) {
    return;
  }
  const int source_count = static_cast<int>(source_count64);
  const int target_start = juce::jlimit(
      0, output.getNumSamples(),
      static_cast<int>(std::floor(target_start_ms * output_sample_rate / 1000.0)));
  const int target_end = juce::jlimit(
      0, output.getNumSamples(),
      static_cast<int>(std::ceil(target_end_ms * output_sample_rate / 1000.0)));
  const int target_count = juce::jmax(0, target_end - target_start);
  if (target_count <= 0) return;

  const double source_duration_sec = juce::jmax(0.001, source_end_sec - source_start_sec);
  const double target_duration_sec =
      juce::jmax(0.001, (target_end_ms - target_start_ms) / 1000.0);
  const double resample_speed = source_duration_sec / target_duration_sec;
  const double stretch_pitch_drift = 12.0 * (std::log(resample_speed) / std::log(2.0));
  if (std::abs(pitch_semitones) < 0.01 &&
      std::abs(stretch_pitch_drift) < 0.03) {
    PitchLabStreamSourceRange(reader, output, source_start, source_count,
                              target_start, target_count);
    return;
  }

  juce::AudioBuffer<float> source(juce::jmax(1, static_cast<int>(reader.numChannels)),
                                  source_count + 2);
  source.clear();
  reader.read(&source, 0, source_count, source_start, true, true);

  juce::AudioBuffer<float> rendered(2, target_count);
  rendered.clear();
  const double source_span = static_cast<double>(juce::jmax(1, source_count - 1));
  const double denom = static_cast<double>(juce::jmax(1, target_count - 1));
  for (int i = 0; i < target_count; ++i) {
    const double source_pos = (static_cast<double>(i) / denom) * source_span;
    for (int ch = 0; ch < 2; ++ch) {
      rendered.setSample(
          ch, i,
          PitchLabReadInterpolated(source, source.getNumChannels() == 1 ? 0 : ch,
                                   source_pos));
    }
  }

  PitchLabApplyPitchCompensation(
      rendered, output_sample_rate,
      juce::jlimit(-96.0, 96.0, pitch_semitones - stretch_pitch_drift));
  for (int ch = 0; ch < 2; ++ch) {
    output.addFrom(ch, target_start, rendered, ch, 0, target_count);
  }
}

juce::String RenderPitchLabAudioNative(
    const juce::File& source_file, const juce::File& out_file,
    double trim_start_ms, double trim_end_ms,
    double source_timeline_duration_ms, double output_duration_ms,
    std::vector<PitchLabRange> suppressed_ranges,
    const std::vector<PitchLabSegment>& segments) {
  juce::AudioFormatManager format_manager;
  format_manager.registerBasicFormats();
  std::unique_ptr<juce::AudioFormatReader> reader(
      format_manager.createReaderFor(source_file));
  if (!reader) return {};
  if (trim_end_ms <= trim_start_ms) {
    trim_end_ms = static_cast<double>(reader->lengthInSamples) * 1000.0 /
                  juce::jmax(1.0, reader->sampleRate);
  }

  const double output_sample_rate = 48000.0;
  const int output_samples = juce::jlimit(
      1, static_cast<int>(output_sample_rate * 60.0 * 12.0),
      static_cast<int>(std::ceil(output_duration_ms * output_sample_rate / 1000.0)));
  juce::AudioBuffer<float> output(2, output_samples);
  output.clear();
  std::sort(suppressed_ranges.begin(), suppressed_ranges.end(),
            [](const PitchLabRange& a, const PitchLabRange& b) {
              return a.start_ms < b.start_ms;
            });

  double cursor_ms = 0.0;
  for (const auto& range : suppressed_ranges) {
    const double start_ms =
        juce::jlimit(0.0, source_timeline_duration_ms, range.start_ms);
    const double end_ms =
        juce::jlimit(0.0, source_timeline_duration_ms, range.end_ms);
    if (start_ms > cursor_ms + 4.0) {
      PitchLabMixSourceRange(
          *reader, output, output_sample_rate,
          PitchLabLocalMsToFileSec(cursor_ms, trim_start_ms, trim_end_ms,
                                   source_timeline_duration_ms),
          PitchLabLocalMsToFileSec(start_ms, trim_start_ms, trim_end_ms,
                                   source_timeline_duration_ms),
          cursor_ms, start_ms, 0.0);
    }
    cursor_ms = juce::jmax(cursor_ms, end_ms);
  }
  if (cursor_ms < source_timeline_duration_ms - 4.0) {
    PitchLabMixSourceRange(
        *reader, output, output_sample_rate,
        PitchLabLocalMsToFileSec(cursor_ms, trim_start_ms, trim_end_ms,
                                 source_timeline_duration_ms),
        PitchLabLocalMsToFileSec(source_timeline_duration_ms, trim_start_ms,
                                 trim_end_ms, source_timeline_duration_ms),
        cursor_ms, source_timeline_duration_ms, 0.0);
  }

  for (const auto& segment : segments) {
    PitchLabMixSourceRange(
        *reader, output, output_sample_rate,
        PitchLabLocalMsToFileSec(segment.original_start_ms, trim_start_ms,
                                 trim_end_ms, source_timeline_duration_ms),
        PitchLabLocalMsToFileSec(segment.original_end_ms, trim_start_ms,
                                 trim_end_ms, source_timeline_duration_ms),
        segment.target_start_ms, segment.target_end_ms, segment.semitones);
  }

  for (int ch = 0; ch < output.getNumChannels(); ++ch) {
    auto* samples = output.getWritePointer(ch);
    for (int i = 0; i < output.getNumSamples(); ++i) {
      samples[i] = std::tanh(samples[i] * 0.98f);
    }
  }

  out_file.deleteFile();
  std::unique_ptr<juce::FileOutputStream> stream(out_file.createOutputStream());
  if (!stream) return {};
  juce::WavAudioFormat wav;
  std::unique_ptr<juce::AudioFormatWriter> writer(
      wav.createWriterFor(stream.get(), output_sample_rate, 2, 24, {}, 0));
  if (!writer) return {};
  stream.release();
  if (!writer->writeFromAudioSampleBuffer(output, 0, output.getNumSamples())) {
    return {};
  }
  return out_file.getFullPathName();
}

std::vector<AutomationPoint> ParseAutomationPoints(
    const flutter::EncodableValue* raw_points, float max_value = 3.0f) {
  std::vector<AutomationPoint> out;
  if (raw_points == nullptr) return out;

  const auto* list = std::get_if<flutter::EncodableList>(raw_points);
  if (list == nullptr) return out;

  out.reserve(list->size());

  for (const auto& entry : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;

    auto find_numeric = [&](const char* key, double fallback) {
      auto it = map->find(flutter::EncodableValue(key));
      if (it == map->end()) return fallback;
      double parsed = fallback;
      if (EncodableToDouble(it->second, &parsed)) return parsed;
      return fallback;
    };

    double time_ms = 0.0;
    if (map->find(flutter::EncodableValue("x")) != map->end()) {
      time_ms = find_numeric("x", 0.0);
    } else if (map->find(flutter::EncodableValue("timeSeconds")) != map->end()) {
      time_ms = find_numeric("timeSeconds", 0.0) * 1000.0;
    } else if (map->find(flutter::EncodableValue("timeMs")) != map->end()) {
      time_ms = find_numeric("timeMs", 0.0);
    }

    float value = 1.0f;
    if (map->find(flutter::EncodableValue("value")) != map->end()) {
      value = static_cast<float>(find_numeric("value", 1.0));
    } else if (map->find(flutter::EncodableValue("volume")) != map->end()) {
      value = static_cast<float>(find_numeric("volume", 1.0));
    }

    AutomationPoint point;
    point.timeMs = juce::jmax(0.0, time_ms);
    point.value = juce::jlimit(0.0f, max_value, value);
    out.push_back(point);
  }

  return out;
}

flutter::EncodableList StringArrayToEncodableList(const juce::StringArray& strings) {
  flutter::EncodableList out;
  out.reserve(strings.size());
  for (const auto& item : strings) {
    out.push_back(flutter::EncodableValue(item.toStdString()));
  }
  return out;
}

flutter::EncodableList NamedValueSetArrayToParameterList(
    const juce::Array<juce::NamedValueSet>& list) {
  flutter::EncodableList out;
  out.reserve(list.size());

  for (const auto& entry : list) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("id")] =
        flutter::EncodableValue(entry.getWithDefault("id", juce::var()).toString().toStdString());
    map[flutter::EncodableValue("name")] =
        flutter::EncodableValue(entry.getWithDefault("name", juce::var()).toString().toStdString());
    map[flutter::EncodableValue("type")] =
        flutter::EncodableValue(entry.getWithDefault("type", juce::var()).toString().toStdString());

    if (entry.contains("min")) {
      map[flutter::EncodableValue("min")] =
          flutter::EncodableValue(static_cast<double>(entry["min"]));
    }
    if (entry.contains("max")) {
      map[flutter::EncodableValue("max")] =
          flutter::EncodableValue(static_cast<double>(entry["max"]));
    }
    if (entry.contains("default")) {
      map[flutter::EncodableValue("defaultValue")] = JuceVarToEncodable(entry["default"]);
    }
    if (entry.contains("value")) {
      map[flutter::EncodableValue("value")] = JuceVarToEncodable(entry["value"]);
    }

    for (int i = 0;; ++i) {
      const juce::String key = "choice_" + juce::String(i);
      if (!entry.contains(key)) break;
      map[flutter::EncodableValue(key.toStdString())] =
          flutter::EncodableValue(entry[key].toString().toStdString());
    }

    out.push_back(flutter::EncodableValue(map));
  }

  return out;
}

flutter::EncodableList RowsToEncodableList(
    const juce::Array<juce::NamedValueSet>& rows) {
  flutter::EncodableList out;
  out.reserve(rows.size());

  for (const auto& row : rows) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("rowId")] =
        flutter::EncodableValue(static_cast<int32_t>(static_cast<int>(row["rowId"])));
    map[flutter::EncodableValue("name")] =
        flutter::EncodableValue(row["name"].toString().toStdString());
    map[flutter::EncodableValue("iconId")] =
        flutter::EncodableValue(static_cast<int32_t>(static_cast<int>(row["iconId"])));
    out.push_back(flutter::EncodableValue(map));
  }

  return out;
}

flutter::EncodableMap NamedValueStatsToEncodableMap(
    const juce::NamedValueSet& stats) {
  flutter::EncodableMap map;
  const char* kKeys[] = {
      "phase_corr", "side_ratio", "stereo_imbalance", "rms",
      "peak",       "crest",      "zcr",             "dc_offset",
  };
  for (const char* key : kKeys) {
    if (stats.contains(juce::Identifier(key))) {
      map[flutter::EncodableValue(key)] =
          flutter::EncodableValue(static_cast<double>(stats[juce::Identifier(key)]));
    }
  }
  return map;
}

template <size_t N>
flutter::EncodableList FloatArrayToEncodableList(const std::array<float, N>& values) {
  flutter::EncodableList out;
  out.reserve(N);
  for (float value : values) {
    out.push_back(flutter::EncodableValue(static_cast<double>(value)));
  }
  return out;
}

flutter::EncodableList FloatVectorToEncodableList(const std::vector<float>& values) {
  flutter::EncodableList out;
  out.reserve(values.size());
  for (float value : values) {
    out.push_back(flutter::EncodableValue(static_cast<double>(value)));
  }
  return out;
}

flutter::EncodableList PluginDescriptionsToEncodableList(
    const juce::Array<juce::PluginDescription>& descriptions) {
  std::set<std::string> seen_ids;
  std::vector<flutter::EncodableMap> maps;
  maps.reserve(descriptions.size());

  for (const auto& desc : descriptions) {
    std::string id = desc.fileOrIdentifier.toStdString();
    if (id.empty()) id = desc.name.toStdString();
    if (id.empty() || !seen_ids.insert(id).second) continue;

    flutter::EncodableMap map;
    map[flutter::EncodableValue("id")] = flutter::EncodableValue(id);

    const std::string name = desc.name.toStdString();
    map[flutter::EncodableValue("name")] =
        flutter::EncodableValue(name.empty() ? id : name);

    const std::string format = desc.pluginFormatName.toStdString();
    if (!format.empty()) {
      map[flutter::EncodableValue("format")] = flutter::EncodableValue(format);
    }

    const std::string manufacturer = desc.manufacturerName.toStdString();
    if (!manufacturer.empty()) {
      map[flutter::EncodableValue("manufacturer")] =
          flutter::EncodableValue(manufacturer);
    }

    const std::string category = desc.category.toStdString();
    if (!category.empty()) {
      map[flutter::EncodableValue("category")] = flutter::EncodableValue(category);
    }

    maps.push_back(std::move(map));
  }

  std::sort(maps.begin(), maps.end(), [](const auto& lhs, const auto& rhs) {
    auto get_name = [](const flutter::EncodableMap& map) {
      auto it = map.find(flutter::EncodableValue("name"));
      if (it == map.end()) return std::string();
      if (auto value = std::get_if<std::string>(&it->second)) return *value;
      return std::string();
    };
    return get_name(lhs) < get_name(rhs);
  });

  flutter::EncodableList out;
  out.reserve(maps.size());
  for (const auto& map : maps) {
    out.push_back(flutter::EncodableValue(map));
  }
  return out;
}

}  // namespace

namespace juce_audio_engine {

// static
void JuceAudioEnginePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "juce_audio_engine",
          &flutter::StandardMethodCodec::GetInstance());

  auto events_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "juce_audio_engine/events",
          &flutter::StandardMethodCodec::GetInstance());
  events_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
             /*events*/) { return nullptr; },
          [](const flutter::EncodableValue* /*arguments*/) { return nullptr; }));

  auto logs_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "juce_audio_engine/logs",
          &flutter::StandardMethodCodec::GetInstance());
  logs_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [](const flutter::EncodableValue* /*arguments*/,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
             /*events*/) { return nullptr; },
          [](const flutter::EncodableValue* /*arguments*/) { return nullptr; }));

  auto plugin = std::make_unique<JuceAudioEnginePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

JuceAudioEnginePlugin::JuceAudioEnginePlugin() = default;

JuceAudioEnginePlugin::~JuceAudioEnginePlugin() = default;

void JuceAudioEnginePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = method_call.arguments() == nullptr
                         ? nullptr
                         : std::get_if<flutter::EncodableMap>(
                               method_call.arguments());

  try {
    if (method_call.method_name() == "getPlatformVersion") {
      std::ostringstream version;
      version << "Windows ";
      if (IsWindows10OrGreater()) {
        version << "10+";
      } else if (IsWindows8OrGreater()) {
        version << "8";
      } else if (IsWindows7OrGreater()) {
        version << "7";
      } else {
        version << "unknown";
      }
      result->Success(flutter::EncodableValue(version.str()));
      return;
    }

    if (method_call.method_name() == "getEngineCapabilities") {
      flutter::EncodableMap caps;
      caps[flutter::EncodableValue("externalPluginHosting")] =
          flutter::EncodableValue(true);
      caps[flutter::EncodableValue("supportedPluginFormats")] =
          flutter::EncodableValue(
              flutter::EncodableList{flutter::EncodableValue("VST3")});
      caps[flutter::EncodableValue("nativePluginEditor")] =
          flutter::EncodableValue(false);
      result->Success(flutter::EncodableValue(caps));
      return;
    }

    if (method_call.method_name() == "initialise") {
      CallOnMessageThreadSync([] { JuceEngine::get().initialiseEngine(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "shutdown") {
      CallOnMessageThreadSync([] { JuceEngine::get().shutdownEngine(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "loadTrack") {
      const int index = FindInt(args, "index", 0);
      const std::string path = FindString(args, "path");
      CallOnMessageThreadSync([index, path] {
        JuceEngine::get().loadTrack(index, juce::File(ToJuceString(path)));
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "removeTrack") {
      const int track = FindInt(args, "track", 0);
      CallOnMessageThreadSync([track] { JuceEngine::get().removeTrack(track); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getTrackEffects") {
      const int track = FindInt(args, "track", 0);
      const auto effects =
          CallOnMessageThreadSync([track] { return JuceEngine::get().getTrackEffects(track); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(effects)));
      return;
    }

    if (method_call.method_name() == "removeEffect") {
      const int track = FindInt(args, "track", 0);
      const int effect = FindInt(args, "effect", 0);
      CallOnMessageThreadSync(
          [track, effect] { JuceEngine::get().removePluginEffect(track, effect); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "reorderEffects") {
      const int track = FindInt(args, "track", 0);
      const int from = FindInt(args, "from", 0);
      const int to = FindInt(args, "to", 0);
      CallOnMessageThreadSync([track, from, to] {
        JuceEngine::get().reorderPluginEffects(track, from, to);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "seek") {
      const int track = FindInt(args, "track", 0);
      const double position = FindDouble(args, "position", 0.0);
      CallOnMessageThreadSync(
          [track, position] { JuceEngine::get().seek(track, position); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getCurrentPosition") {
      const int track = FindInt(args, "track", 0);
      const double value = CallOnMessageThreadSync(
          [track] { return JuceEngine::get().getCurrentPosition(track); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "getTrackDuration") {
      const int track = FindInt(args, "track", 0);
      const double value = CallOnMessageThreadSync(
          [track] { return JuceEngine::get().getTrackDuration(track); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "play") {
      CallOnMessageThreadSync([] { JuceEngine::get().play(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "pause") {
      CallOnMessageThreadSync([] { JuceEngine::get().pause(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "insertEffect") {
      const int track = FindInt(args, "track", 0);
      const std::string path = FindString(args, "path");
      CallOnMessageThreadSync([track, path] {
        JuceEngine::get().insertPluginEffect(track, ToJuceString(path),
                                             [](bool /*success*/) {});
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setEffect") {
      const int track = FindInt(args, "track", 0);
      const int plugin_index = FindInt(args, "pluginIndex", 0);
      const std::string param_id = FindString(args, "paramId");
      const flutter::EncodableValue* raw_value = FindValue(args, "value");
      if (raw_value != nullptr) {
        const juce::var value = EncodableToJuceVar(*raw_value);
        CallOnMessageThreadSync([track, plugin_index, param_id, value] {
          JuceEngine::get().setEffectParameter(track, plugin_index,
                                               ToJuceString(param_id), value);
        });
      }
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setTrackVolume") {
      const int track = FindInt(args, "track", 0);
      const float volume = static_cast<float>(FindDouble(args, "volume", 0.0));
      CallOnMessageThreadSync(
          [track, volume] { JuceEngine::get().setTrackVolume(track, volume); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getPluginParameters") {
      const int track = FindInt(args, "track", 0);
      const int effect = FindInt(args, "effect", 0);
      const auto parameters = CallOnMessageThreadSync([track, effect] {
        return JuceEngine::get().getPluginParameterInfo(track, effect);
      });
      result->Success(
          flutter::EncodableValue(NamedValueSetArrayToParameterList(parameters)));
      return;
    }

    if (method_call.method_name() == "getTrackPluginParameters") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const auto parameters = CallOnMessageThreadSync([row, effect, force_individual_row] {
        return JuceEngine::get().getTrackPluginParameterInfo(row, effect, force_individual_row);
      });
      result->Success(
          flutter::EncodableValue(NamedValueSetArrayToParameterList(parameters)));
      return;
    }

    if (method_call.method_name() == "getMasterPluginParameters") {
      const int effect = FindInt(args, "effect", 0);
      const auto parameters = CallOnMessageThreadSync([effect] {
        return JuceEngine::get().getMasterPluginParameterInfo(effect);
      });
      result->Success(
          flutter::EncodableValue(NamedValueSetArrayToParameterList(parameters)));
      return;
    }

    if (method_call.method_name() == "scanPlugins") {
      const auto plugins = CallOnMessageThreadSync(
          [] { return JuceEngine::get().getKnownPlugins(); });
      result->Success(flutter::EncodableValue(PluginDescriptionsToEncodableList(plugins)));
      return;
    }

    if (method_call.method_name() == "exportMix") {
      const std::string out_path = FindString(args, "outPath");
      if (out_path.empty()) {
        result->Success(flutter::EncodableValue(std::string()));
        return;
      }

      JuceEngine::ExportOptions options;
      const std::string format = FindString(args, "format", "wav");
      if (!format.empty()) options.format = ToJuceString(format);
      options.sampleRate = FindDouble(args, "sampleRate", 44100.0);
      options.wavBitDepth = FindInt(args, "wavBitDepth", 16);
      options.wavDithering = FindBool(args, "wavDithering", true);
      options.mp3BitrateKbps = FindInt(args, "mp3BitrateKbps", 192);
      options.clipSnapshotJson =
          ToJuceString(FindString(args, "clipSnapshotJson"));
      options.dryClipRender = FindBool(args, "dryClipRender", false);
      options.bypassMasterProcessing =
          FindBool(args, "bypassMasterProcessing", false);
      options.bypassGroupProcessing =
          FindBool(args, "bypassGroupProcessing", false);
      options.preserveRealtimePlayback =
          FindBool(args, "preserveRealtimePlayback", false);
      options.timelineStartSeconds =
          FindDouble(args, "timelineStartSeconds", 0.0);
      if (const auto* raw_ids = FindValue(args, "audibleClipIds")) {
        if (const auto* ids = std::get_if<flutter::EncodableList>(raw_ids)) {
          options.restrictToAudibleClipIds = true;
          for (const auto& raw_id : *ids) {
            if (const auto* value = std::get_if<int32_t>(&raw_id)) {
              options.audibleClipIds.add(*value);
            } else if (const auto* value = std::get_if<int64_t>(&raw_id)) {
              options.audibleClipIds.add(static_cast<int>(*value));
            }
          }
        }
      }

      const std::string exported = CallOnMessageThreadSync([out_path, options] {
        return JuceEngine::get()
            .exportMix(juce::File(ToJuceString(out_path)), options)
            .toStdString();
      });
      result->Success(flutter::EncodableValue(exported));
      return;
    }

    if (method_call.method_name() == "exportTrack") {
      const int track = FindInt(args, "track", 0);
      const std::string out_path = FindString(args, "outPath");
      if (out_path.empty()) {
        result->Success(flutter::EncodableValue(std::string()));
        return;
      }

      JuceEngine::ExportOptions options;
      const std::string format = FindString(args, "format", "wav");
      if (!format.empty()) options.format = ToJuceString(format);
      options.sampleRate = FindDouble(args, "sampleRate", 44100.0);
      options.wavBitDepth = FindInt(args, "wavBitDepth", 16);
      options.wavDithering = FindBool(args, "wavDithering", true);
      options.mp3BitrateKbps = FindInt(args, "mp3BitrateKbps", 192);

      const std::string exported =
          CallOnMessageThreadSync([track, out_path, options] {
            return JuceEngine::get()
                .exportTrack(track, juce::File(ToJuceString(out_path)), options)
                .toStdString();
          });
      result->Success(flutter::EncodableValue(exported));
      return;
    }

    if (method_call.method_name() == "renderInstrumentClip") {
      mixroom::instruments::InstrumentRenderRequest request;
      request.outFile = juce::File(ToJuceString(FindString(args, "outPath")));
      request.instrumentId =
          ToJuceString(FindString(args, "instrumentId", "mixroom.basic_synth"));
      request.instrumentName =
          ToJuceString(FindString(args, "instrumentName", "Basic Synth"));
      request.bpm = FindDouble(args, "bpm", 120.0);
      request.notes = ParseMidiRenderNotes(FindValue(args, "notes"));
      request.params = ParseMidiParams(FindValue(args, "params"));

      const std::string rendered =
          mixroom::instruments::renderInstrumentClipToWav(request).toStdString();
      result->Success(flutter::EncodableValue(rendered));
      return;
    }

    if (method_call.method_name() == "renderPitchLabAudio") {
      const juce::String rendered = RenderPitchLabAudioNative(
          juce::File(ToJuceString(FindString(args, "sourcePath"))),
          juce::File(ToJuceString(FindString(args, "outPath"))),
          FindDouble(args, "trimStartMs", 0.0),
          FindDouble(args, "trimEndMs", 0.0),
          FindDouble(args, "sourceTimelineDurationMs", 0.0),
          FindDouble(args, "outputDurationMs", 0.0),
          ParsePitchLabRanges(FindValue(args, "suppressedRanges")),
          ParsePitchLabSegments(FindValue(args, "segments")));
      result->Success(flutter::EncodableValue(rendered.toStdString()));
      return;
    }

    if (method_call.method_name() == "bypassPlugin") {
      const int track = FindInt(args, "track", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool bypass = FindBool(args, "bypass", false);
      CallOnMessageThreadSync([track, effect, bypass] {
        JuceEngine::get().bypassPlugin(track, effect, bypass);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "bypassTrack") {
      const int track = FindInt(args, "track", 0);
      const bool bypass = FindBool(args, "bypass", false);
      CallOnMessageThreadSync(
          [track, bypass] { JuceEngine::get().bypassTrack(track, bypass); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getPluginBypassState") {
      const int track = FindInt(args, "track", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool bypass = CallOnMessageThreadSync(
          [track, effect] { return JuceEngine::get().getPluginBypassState(track, effect); });
      result->Success(flutter::EncodableValue(bypass));
      return;
    }

    if (method_call.method_name() == "_internalLog") {
      result->Success(flutter::EncodableValue("testing blabla success"));
      return;
    }

    if (method_call.method_name() == "loadVideoAudio") {
      const std::string path = FindString(args, "path");
      CallOnMessageThreadSync(
          [path] { JuceEngine::get().loadVideoAudio(juce::File(ToJuceString(path))); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "unloadVideoAudio") {
      CallOnMessageThreadSync([] { JuceEngine::get().unloadVideoAudio(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setVideoAudioGain") {
      const float gain = static_cast<float>(FindDouble(args, "gain", 0.0));
      CallOnMessageThreadSync(
          [gain] { JuceEngine::get().setVideoAudioGain(gain); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "seekVideoAudio") {
      const double seconds = FindDouble(args, "seconds", 0.0);
      CallOnMessageThreadSync(
          [seconds] { JuceEngine::get().seekVideoAudio(seconds); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "supportsLiveMidiClipPlayback") {
      const bool supported = CallOnMessageThreadSync(
          [] { return JuceEngine::get().supportsLiveMidiClipPlayback(); });
      result->Success(flutter::EncodableValue(supported));
      return;
    }

    if (method_call.method_name() == "loadMidiClip") {
      const int clip = FindInt(args, "clip", 0);
      const int row = ResolveRowId(args, 0);
      const std::string instrument_id =
          FindString(args, "instrumentId", "mixroom.basic_synth");
      const std::string instrument_name =
          FindString(args, "instrumentName", "Basic Synth");
      const auto notes = ParseTimelineMidiNotes(FindValue(args, "notes"));
      const auto params = ParseMidiParams(FindValue(args, "params"));
      const double source_tempo = FindDouble(args, "sourceTempoBpm", 120.0);
      const double start_sec = FindDouble(args, "startSec", 0.0);
      const double length_sec = FindDouble(args, "lengthSec", 0.0);
      const double offset_sec = FindDouble(args, "inFileOffsetSec", 0.0);

      const bool ok = CallOnMessageThreadSync([=] {
        return JuceEngine::get().loadMidiClip(
            clip, row, ToJuceString(instrument_id), ToJuceString(instrument_name),
            notes, params, source_tempo, start_sec, length_sec, offset_sec);
      });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "updateMidiClipEvents") {
      const int clip = FindInt(args, "clip", 0);
      const std::string instrument_id =
          FindString(args, "instrumentId", "mixroom.basic_synth");
      const std::string instrument_name =
          FindString(args, "instrumentName", "Basic Synth");
      const auto notes = ParseTimelineMidiNotes(FindValue(args, "notes"));
      const auto params = ParseMidiParams(FindValue(args, "params"));
      const double source_tempo = FindDouble(args, "sourceTempoBpm", 120.0);

      const bool ok = CallOnMessageThreadSync([=] {
        return JuceEngine::get().updateMidiClipEvents(
            clip, ToJuceString(instrument_id), ToJuceString(instrument_name),
            notes, params, source_tempo);
      });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "setMidiClipPluginParameter") {
      const int clip = FindInt(args, "clip", -1);
      const auto param_id = ToJuceString(FindString(args, "paramId"));
      const float value = static_cast<float>(FindDouble(args, "value", 0.0));
      CallOnMessageThreadSync([clip, param_id, value] {
        JuceEngine::get().setMidiClipPluginParameter(clip, param_id, value);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMidiClipPluginAutomationPoints") {
      const int clip = FindInt(args, "clip", -1);
      const auto param_id = ToJuceString(FindString(args, "paramId"));
      const auto points =
          ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([clip, param_id, points] {
        JuceEngine::get().setMidiClipPluginAutomationPoints(
            clip, param_id, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "clearMidiClipPluginAutomation") {
      const int clip = FindInt(args, "clip", -1);
      CallOnMessageThreadSync([clip] {
        JuceEngine::get().clearMidiClipPluginAutomation(clip);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setLiveMidiInputTargetClip") {
      const int clip = FindInt(args, "clip", -1);
      const bool ok = CallOnMessageThreadSync(
          [clip] { return JuceEngine::get().setLiveMidiInputTargetClip(clip); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "consumeLiveMidiInputEvents") {
      const auto events = CallOnMessageThreadSync(
          [] { return JuceEngine::get().consumeLiveMidiInputEvents(); });
      flutter::EncodableList list;
      list.reserve(events.size());
      for (const auto& event : events) {
        flutter::EncodableMap item;
        item[flutter::EncodableValue("clip")] =
            flutter::EncodableValue(static_cast<int32_t>(event.clipId));
        item[flutter::EncodableValue("type")] =
            flutter::EncodableValue(event.noteOn ? "noteOn" : "noteOff");
        item[flutter::EncodableValue("channel")] =
            flutter::EncodableValue(static_cast<int32_t>(event.channel));
        item[flutter::EncodableValue("pitch")] =
            flutter::EncodableValue(static_cast<int32_t>(event.pitch));
        item[flutter::EncodableValue("velocity")] =
            flutter::EncodableValue(static_cast<double>(event.velocity));
        item[flutter::EncodableValue("transportSec")] =
            flutter::EncodableValue(event.transportSec);
        list.push_back(flutter::EncodableValue(item));
      }
      result->Success(flutter::EncodableValue(list));
      return;
    }

    if (method_call.method_name() == "getConnectedMidiInputDevices") {
      const auto devices =
          CallOnMessageThreadSync([] { return juce::MidiInput::getAvailableDevices(); });
      flutter::EncodableList list;
      list.reserve(devices.size());
      for (const auto& device : devices) {
        const std::string id = device.identifier.toStdString();
        if (id.empty()) continue;
        std::string name = device.name.toStdString();
        if (name.empty()) name = id;
        flutter::EncodableMap map;
        map[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
        map[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
        list.push_back(flutter::EncodableValue(map));
      }
      result->Success(flutter::EncodableValue(list));
      return;
    }

    if (method_call.method_name() == "beginProjectClipLoad") {
      CallOnMessageThreadSync(
          [] { JuceEngine::get().beginProjectClipLoad(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "endProjectClipLoad") {
      CallOnMessageThreadSync([] { JuceEngine::get().endProjectClipLoad(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "endProjectClipLoadDetailed") {
      const auto status = CallOnMessageThreadSync(
          [] { return JuceEngine::get().endProjectClipLoadDetailed(); });
      result->Success(flutter::EncodableValue(
          static_cast<int32_t>(status)));
      return;
    }

    if (method_call.method_name() == "loadClip" ||
        method_call.method_name() == "loadClipDetailed") {
      const int clip = FindInt(args, "clip", 0);
      const int row = ResolveRowId(args, 0);
      const std::string path = FindString(args, "path");
      const double start_sec = FindDouble(args, "startSec", 0.0);
      const double length_sec = FindDouble(args, "lengthSec", 0.0);
      const double offset_sec = FindDouble(args, "inFileOffsetSec", 0.0);

      if (method_call.method_name() == "loadClipDetailed") {
        const auto status = CallOnMessageThreadSync([=] {
          return JuceEngine::get().loadClipDetailed(
              clip, row, juce::File(ToJuceString(path)), start_sec,
              length_sec, offset_sec);
        });
        result->Success(flutter::EncodableValue(
            static_cast<int32_t>(status)));
      } else {
        const bool loaded = CallOnMessageThreadSync([=] {
          return JuceEngine::get().loadClip(
              clip, row, juce::File(ToJuceString(path)), start_sec,
              length_sec, offset_sec);
        });
        result->Success(flutter::EncodableValue(loaded));
      }
      return;
    }

    if (method_call.method_name() == "unloadClip") {
      const int clip = FindInt(args, "clip", 0);
      CallOnMessageThreadSync([clip] { JuceEngine::get().unloadClip(clip); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "unloadClips") {
      juce::Array<int> clips;
      if (const auto* raw = FindValue(args, "clips")) {
        if (const auto* list = std::get_if<flutter::EncodableList>(raw)) {
          clips.ensureStorageAllocated(static_cast<int>(list->size()));
          for (const auto& value : *list) {
            if (const auto* clip = std::get_if<int32_t>(&value))
              clips.addIfNotAlreadyThere(static_cast<int>(*clip));
            else if (const auto* clip64 = std::get_if<int64_t>(&value))
              clips.addIfNotAlreadyThere(static_cast<int>(*clip64));
          }
        }
      }
      const int removed = CallOnMessageThreadSync(
          [&clips] { return JuceEngine::get().unloadClips(clips); });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(removed)));
      return;
    }

    if (method_call.method_name() == "setClipGain") {
      const int clip = FindInt(args, "clip", 0);
      const float gain = static_cast<float>(FindDouble(args, "gain", 0.0));
      CallOnMessageThreadSync(
          [clip, gain] { JuceEngine::get().setClipGain(clip, gain); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipExtraGainLinear") {
      const int clip = FindInt(args, "clip", 0);
      const float gain = static_cast<float>(FindDouble(args, "gain", 1.0));
      CallOnMessageThreadSync([clip, gain] {
        JuceEngine::get().setClipExtraGainLinear(clip, gain);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipPan") {
      const int clip = FindInt(args, "clip", 0);
      const float pan = static_cast<float>(FindDouble(args, "pan", 0.0));
      CallOnMessageThreadSync(
          [clip, pan] { JuceEngine::get().setClipPan(clip, pan); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipFades") {
      const int clip = FindInt(args, "clip", 0);
      const double fade_in = FindDouble(args, "fadeInSec", 0.0);
      const double fade_out = FindDouble(args, "fadeOutSec", 0.0);
      const int curve = FindInt(args, "fadeCurve", 0);
      CallOnMessageThreadSync([=] {
        JuceEngine::get().setClipFades(clip, fade_in, fade_out, curve);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "updateClipFadesBatch") {
      juce::Array<juce::NamedValueSet> updates;
      if (const auto* raw = FindValue(args, "updates")) {
        if (const auto* list = std::get_if<flutter::EncodableList>(raw)) {
          updates.ensureStorageAllocated(static_cast<int>(list->size()));
          for (const auto& value : *list) {
            const auto* map = std::get_if<flutter::EncodableMap>(&value);
            if (map == nullptr) continue;
            const int clip = FindInt(map, "clip", -1);
            if (clip < 0) continue;
            juce::NamedValueSet update;
            update.set("clip", clip);
            update.set("fadeInSec", FindDouble(map, "fadeInSec", 0.0));
            update.set("fadeOutSec", FindDouble(map, "fadeOutSec", 0.0));
            update.set("fadeCurve", FindInt(map, "fadeCurve", 0));
            updates.add(update);
          }
        }
      }
      const int applied = CallOnMessageThreadSync(
          [&updates] { return JuceEngine::get().updateClipFadesBatch(updates); });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(applied)));
      return;
    }

    if (method_call.method_name() == "setClipPitch") {
      const int clip = FindInt(args, "clip", 0);
      const float semitones =
          static_cast<float>(FindDouble(args, "semitones", 0.0));
      CallOnMessageThreadSync([clip, semitones] {
        JuceEngine::get().setClipPitch(clip, semitones);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipReversed") {
      const int clip = FindInt(args, "clip", 0);
      const bool reversed = FindBool(args, "reversed", false);
      CallOnMessageThreadSync([clip, reversed] {
        JuceEngine::get().setClipReversed(clip, reversed);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipStretchOptions") {
      const int clip = FindInt(args, "clip", 0);
      const double tempo_ratio = FindDouble(args, "tempoRatio", 1.0);
      const bool preserve_pitch = FindBool(args, "preservePitch", true);
      CallOnMessageThreadSync([clip, tempo_ratio, preserve_pitch] {
        JuceEngine::get().setClipStretchOptions(clip, tempo_ratio, preserve_pitch);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "muteClip") {
      const int clip = FindInt(args, "clip", 0);
      const bool mute = FindBool(args, "mute", false);
      CallOnMessageThreadSync(
          [clip, mute] { JuceEngine::get().muteClip(clip, mute); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "moveClipToRow") {
      const int clip = FindInt(args, "clip", 0);
      const int row = ResolveRowId(args, 0);
      CallOnMessageThreadSync(
          [clip, row] { JuceEngine::get().moveClipToRow(clip, row); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setClipTime") {
      const int clip = FindInt(args, "clip", 0);
      const double start_sec = FindDouble(args, "startSec", 0.0);
      const double length_sec = FindDouble(args, "lengthSec", 0.0);
      const double offset_sec = FindDouble(args, "inFileOffsetSec", 0.0);
      CallOnMessageThreadSync([=] {
        JuceEngine::get().setClipTime(clip, start_sec, length_sec, offset_sec);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "updateClipTimelineBatch") {
      juce::Array<juce::NamedValueSet> updates;
      if (const auto* raw = FindValue(args, "updates")) {
        if (const auto* list = std::get_if<flutter::EncodableList>(raw)) {
          updates.ensureStorageAllocated(static_cast<int>(list->size()));
          for (const auto& value : *list) {
            const auto* map = std::get_if<flutter::EncodableMap>(&value);
            if (map == nullptr) continue;
            const int clip = FindInt(map, "clip", -1);
            if (clip < 0) continue;
            juce::NamedValueSet update;
            update.set("clip", clip);
            if (FindValue(map, "rowId") != nullptr)
              update.set("rowId", FindInt(map, "rowId", -1));
            if (FindValue(map, "startSec") != nullptr)
              update.set("startSec", FindDouble(map, "startSec", 0.0));
            if (FindValue(map, "lengthSec") != nullptr)
              update.set("lengthSec", FindDouble(map, "lengthSec", 0.0));
            if (FindValue(map, "inFileOffsetSec") != nullptr)
              update.set("inFileOffsetSec",
                         FindDouble(map, "inFileOffsetSec", 0.0));
            if (FindValue(map, "gain") != nullptr)
              update.set("gain", FindDouble(map, "gain", 1.0));
            if (FindValue(map, "extraGainLinear") != nullptr)
              update.set("extraGainLinear",
                         FindDouble(map, "extraGainLinear", 1.0));
            if (FindValue(map, "reversed") != nullptr)
              update.set("reversed", FindBool(map, "reversed", false));
            if (FindValue(map, "tempoRatio") != nullptr)
              update.set("tempoRatio", FindDouble(map, "tempoRatio", 1.0));
            if (FindValue(map, "preservePitch") != nullptr)
              update.set("preservePitch",
                         FindBool(map, "preservePitch", true));
            if (FindValue(map, "pitchSemitones") != nullptr)
              update.set("pitchSemitones",
                         FindDouble(map, "pitchSemitones", 0.0));
            if (FindValue(map, "muted") != nullptr)
              update.set("muted", FindBool(map, "muted", false));
            updates.add(update);
          }
        }
      }
      const int applied = CallOnMessageThreadSync(
          [&updates] { return JuceEngine::get().updateClipTimelineBatch(updates); });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(applied)));
      return;
    }

    if (method_call.method_name() == "addRow") {
      const std::string name = FindString(args, "name", "Row");
      const int icon = FindInt(args, "iconId", 0);
      const int preferred_row = FindInt(args, "preferredRowId", -1);
      const int row_id = CallOnMessageThreadSync(
          [name, icon, preferred_row] {
            return JuceEngine::get().addRow(ToJuceString(name), icon,
                                            preferred_row);
          });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(row_id)));
      return;
    }

    if (method_call.method_name() == "insertRowAbove") {
      const int reference_row = FindInt(args, "referenceRowId", 0);
      const std::string name = FindString(args, "name", "Row");
      const int icon = FindInt(args, "iconId", 0);
      const int preferred_row = FindInt(args, "preferredRowId", -1);
      const int row_id = CallOnMessageThreadSync([=] {
        return JuceEngine::get().insertRowAbove(reference_row, ToJuceString(name),
                                                icon, preferred_row);
      });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(row_id)));
      return;
    }

    if (method_call.method_name() == "insertRowBelow") {
      const int reference_row = FindInt(args, "referenceRowId", 0);
      const std::string name = FindString(args, "name", "Row");
      const int icon = FindInt(args, "iconId", 0);
      const int preferred_row = FindInt(args, "preferredRowId", -1);
      const int row_id = CallOnMessageThreadSync([=] {
        return JuceEngine::get().insertRowBelow(reference_row, ToJuceString(name),
                                                icon, preferred_row);
      });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(row_id)));
      return;
    }

    if (method_call.method_name() == "deleteRow" ||
        method_call.method_name() == "removeRow") {
      const int row = ResolveRowId(args, -1);
      const bool ok =
          CallOnMessageThreadSync([row] { return JuceEngine::get().removeRow(row); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "moveRowOrder") {
      const int from = FindInt(args, "from", 0);
      const int to = FindInt(args, "to", 0);
      const bool ok = CallOnMessageThreadSync(
          [from, to] { return JuceEngine::get().moveRowOrder(from, to); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "renameRow") {
      const int row = ResolveRowId(args, -1);
      const std::string name = FindString(args, "name", "Row");
      const bool ok = CallOnMessageThreadSync([row, name] {
        return JuceEngine::get().renameRow(row, ToJuceString(name));
      });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "setRowIcon") {
      const int row = ResolveRowId(args, -1);
      const int icon = FindInt(args, "iconId", 0);
      const bool ok = CallOnMessageThreadSync(
          [row, icon] { return JuceEngine::get().setRowIcon(row, icon); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "getRowList" ||
        method_call.method_name() == "getRows") {
      const auto rows =
          CallOnMessageThreadSync([] { return JuceEngine::get().getRows(); });
      result->Success(flutter::EncodableValue(RowsToEncodableList(rows)));
      return;
    }

    if (method_call.method_name() == "setTransportSeconds") {
      const double time_seconds = FindDouble(args, "timeSeconds", 0.0);
      CallOnMessageThreadSync([time_seconds] {
        JuceEngine::get().setTransportSeconds(time_seconds);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getTransportSeconds") {
      const double value =
          CallOnMessageThreadSync([] { return JuceEngine::get().getTransportSeconds(); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "seekTransport") {
      const double time_seconds = FindDouble(args, "timeSeconds", 0.0);
      CallOnMessageThreadSync([time_seconds] {
        JuceEngine::get().setTransportSeconds(time_seconds);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setLoopRegion") {
      const bool enabled = FindBool(args, "enabled", false);
      const double start_seconds = FindDouble(args, "startSeconds", 0.0);
      const double end_seconds = FindDouble(args, "endSeconds", 0.0);
      CallOnMessageThreadSync([enabled, start_seconds, end_seconds] {
        JuceEngine::get().setLoopRegion(enabled, start_seconds, end_seconds);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "insertTrackEffect") {
      const int row = FindInt(args, "row", 0);
      const std::string path = FindString(args, "path");
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const bool ok = CallOnMessageThreadSync(
          [row, path, force_individual_row] { return JuceEngine::get().insertTrackEffect(row, ToJuceString(path), force_individual_row); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "removeTrackEffect") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      CallOnMessageThreadSync(
          [row, effect, force_individual_row] { JuceEngine::get().removeTrackEffect(row, effect, force_individual_row); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "reorderTrackEffects") {
      const int row = FindInt(args, "row", 0);
      const int from = FindInt(args, "from", 0);
      const int to = FindInt(args, "to", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      CallOnMessageThreadSync([row, from, to, force_individual_row] {
        JuceEngine::get().reorderTrackEffects(row, from, to, force_individual_row);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getTrackEffectsForRow") {
      const int row = FindInt(args, "row", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const auto values = CallOnMessageThreadSync(
          [row, force_individual_row] { return JuceEngine::get().getTrackEffectsForRow(row, force_individual_row); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getTrackEffectIdsForRow") {
      const int row = FindInt(args, "row", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const auto values = CallOnMessageThreadSync(
          [row, force_individual_row] { return JuceEngine::get().getTrackEffectIdsForRow(row, force_individual_row); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getTrackEffectInstanceIdsForRow") {
      const int row = FindInt(args, "row", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const auto values = CallOnMessageThreadSync(
          [row, force_individual_row] { return JuceEngine::get().getTrackEffectInstanceIdsForRow(row, force_individual_row); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "setTrackEffect") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const std::string param_id = FindString(args, "paramId");
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const flutter::EncodableValue* raw_value = FindValue(args, "value");
      if (raw_value != nullptr) {
        const juce::var value = EncodableToJuceVar(*raw_value);
        CallOnMessageThreadSync([=] {
          JuceEngine::get().setTrackEffectParameter(row, effect,
                                                    ToJuceString(param_id), value,
                                                    force_individual_row);
        });
      }
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "bypassRowEffect") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool bypass = FindBool(args, "bypass", false);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      CallOnMessageThreadSync([row, effect, bypass, force_individual_row] {
        JuceEngine::get().bypassRowEffect(row, effect, bypass, force_individual_row);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getRowEffectBypassState") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const bool force_individual_row = FindBool(args, "forceIndividualRow", false);
      const bool value = CallOnMessageThreadSync(
          [row, effect, force_individual_row] { return JuceEngine::get().getRowEffectBypassState(row, effect, force_individual_row); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "setTrackAutomationPoints") {
      const int row = FindInt(args, "row", 0);
      auto points = ParseAutomationPoints(FindValue(args, "points"), 3.0f);
      CallOnMessageThreadSync([row, points = std::move(points)]() mutable {
        JuceEngine::get().setTrackAutomationPoints(row, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setTrackEffectAutomationPoints") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const std::string param_id = FindString(args, "paramId");
      const float min_value = static_cast<float>(FindDouble(args, "min", 0.0));
      const float max_value = static_cast<float>(FindDouble(args, "max", 1.0));
      auto points = ParseAutomationPoints(FindValue(args, "points"),
                                          juce::jmax(0.0f, max_value));
      CallOnMessageThreadSync([=, points = std::move(points)]() mutable {
        JuceEngine::get().setTrackEffectAutomationPoints(
            row, effect, ToJuceString(param_id), min_value, max_value, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "clearTrackEffectAutomationForRow") {
      const int row = FindInt(args, "row", 0);
      CallOnMessageThreadSync(
          [row] { JuceEngine::get().clearTrackEffectAutomationForRow(row); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setRowGainAutomationPoints") {
      const int row = FindInt(args, "row", 0);
      auto points = ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([row, points = std::move(points)]() mutable {
        JuceEngine::get().setRowGainAutomationPoints(row, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setRowGain") {
      const int row = FindInt(args, "row", 0);
      const float gain = static_cast<float>(FindDouble(args, "gain", 0.0));
      CallOnMessageThreadSync(
          [row, gain] { JuceEngine::get().setRowGain(row, gain); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "muteRow") {
      const int row = FindInt(args, "row", 0);
      const bool mute = FindBool(args, "mute", false);
      CallOnMessageThreadSync(
          [row, mute] { JuceEngine::get().muteRow(row, mute); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "isRowMuted") {
      const int row = FindInt(args, "row", 0);
      const bool muted =
          CallOnMessageThreadSync([row] { return JuceEngine::get().isRowMuted(row); });
      result->Success(flutter::EncodableValue(muted));
      return;
    }

    if (method_call.method_name() == "setRowPan") {
      const int row = FindInt(args, "row", 0);
      const float pan = static_cast<float>(FindDouble(args, "pan", 0.0));
      CallOnMessageThreadSync(
          [row, pan] { JuceEngine::get().setRowPan(row, pan); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setRowPanAutomationPoints") {
      const int row = FindInt(args, "row", 0);
      auto points = ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([row, points = std::move(points)]() mutable {
        JuceEngine::get().setRowPanAutomationPoints(row, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "insertMasterEffect") {
      const std::string path = FindString(args, "path");
      const bool ok = CallOnMessageThreadSync([path] {
        return JuceEngine::get().insertMasterEffect(ToJuceString(path));
      });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "removeMasterEffect") {
      const int effect = FindInt(args, "effect", 0);
      CallOnMessageThreadSync(
          [effect] { JuceEngine::get().removeMasterEffect(effect); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "reorderMasterEffects") {
      const int from = FindInt(args, "from", 0);
      const int to = FindInt(args, "to", 0);
      CallOnMessageThreadSync([from, to] {
        JuceEngine::get().reorderMasterEffects(from, to);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getMasterEffects") {
      const auto values =
          CallOnMessageThreadSync([] { return JuceEngine::get().getMasterEffects(); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterEffectIds") {
      const auto values =
          CallOnMessageThreadSync([] { return JuceEngine::get().getMasterEffectIds(); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "setMasterEffect") {
      const int effect = FindInt(args, "effect", 0);
      const std::string param_id = FindString(args, "paramId");
      const flutter::EncodableValue* raw_value = FindValue(args, "value");
      if (raw_value != nullptr) {
        const juce::var value = EncodableToJuceVar(*raw_value);
        CallOnMessageThreadSync([=] {
          JuceEngine::get().setMasterEffectParameter(effect, ToJuceString(param_id),
                                                     value);
        });
      }
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "bypassMasterEffect") {
      const int effect = FindInt(args, "effect", 0);
      const bool bypass = FindBool(args, "bypass", false);
      CallOnMessageThreadSync([effect, bypass] {
        JuceEngine::get().bypassMasterEffect(effect, bypass);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getMasterEffectBypassState") {
      const int effect = FindInt(args, "effect", 0);
      const bool value = CallOnMessageThreadSync(
          [effect] { return JuceEngine::get().getMasterEffectBypassState(effect); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "setMasterEffectAutomationPoints") {
      const int effect = FindInt(args, "effect", 0);
      const std::string param_id = FindString(args, "paramId");
      const float min_value = static_cast<float>(FindDouble(args, "min", 0.0));
      const float max_value = static_cast<float>(FindDouble(args, "max", 1.0));
      auto points = ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([=, points = std::move(points)]() mutable {
        JuceEngine::get().setMasterEffectAutomationPoints(
            effect, ToJuceString(param_id), min_value, max_value, points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "clearMasterEffectAutomation") {
      CallOnMessageThreadSync(
          [] { JuceEngine::get().clearMasterEffectAutomation(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMasterGainAutomationPoints") {
      auto points = ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([points = std::move(points)]() mutable {
        JuceEngine::get().setMasterGainAutomationPoints(points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMasterGain") {
      const float gain = static_cast<float>(FindDouble(args, "gain", 0.0));
      CallOnMessageThreadSync(
          [gain] { JuceEngine::get().setMasterGain(gain); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "muteMaster") {
      const bool mute = FindBool(args, "mute", false);
      CallOnMessageThreadSync(
          [mute] { JuceEngine::get().muteMaster(mute); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMasterPan") {
      const float pan = static_cast<float>(FindDouble(args, "pan", 0.0));
      CallOnMessageThreadSync(
          [pan] { JuceEngine::get().setMasterPan(pan); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMasterPanAutomationPoints") {
      auto points = ParseAutomationPoints(FindValue(args, "points"), 1.0f);
      CallOnMessageThreadSync([points = std::move(points)]() mutable {
        JuceEngine::get().setMasterPanAutomationPoints(points);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMasterMeterEnabled") {
      const bool enabled = FindBool(args, "enabled", true);
      CallOnMessageThreadSync([enabled] {
        JuceEngine::get().setMasterMeterEnabled(enabled);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getMasterMeterValues") {
      const auto values = CallOnMessageThreadSync(
          [] { return JuceEngine::get().getMasterMeterValues(); });
      result->Success(flutter::EncodableValue(FloatArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterClipLatched") {
      const bool value = CallOnMessageThreadSync(
          [] { return JuceEngine::get().getMasterClipLatched(); });
      result->Success(flutter::EncodableValue(value));
      return;
    }

    if (method_call.method_name() == "clearMasterClipLatched") {
      CallOnMessageThreadSync([] { JuceEngine::get().clearMasterClipLatched(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setRowMetersEnabled") {
      const bool enabled = FindBool(args, "enabled", true);
      CallOnMessageThreadSync(
          [enabled] { JuceEngine::get().setRowMetersEnabled(enabled); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "getRowMeterValues") {
      const int row = FindInt(args, "row", 0);
      const auto values = CallOnMessageThreadSync(
          [row] { return JuceEngine::get().getRowMeterValues(row); });
      result->Success(flutter::EncodableValue(FloatArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getAllMeterValues") {
      const auto values =
          CallOnMessageThreadSync([] { return JuceEngine::get().getAllMeterValues(); });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getClipCompressorMeter" ||
        method_call.method_name() == "getTrackCompressorMeter") {
      const int clip = FindInt(args, "clip", FindInt(args, "track", 0));
      const int effect = FindInt(args, "effect", 0);
      const auto values = CallOnMessageThreadSync([clip, effect] {
        return JuceEngine::get().getClipCompressorMeter(clip, effect);
      });
      result->Success(flutter::EncodableValue(FloatArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getRowCompressorMeter") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const auto values = CallOnMessageThreadSync([row, effect] {
        return JuceEngine::get().getRowCompressorMeter(row, effect);
      });
      result->Success(flutter::EncodableValue(FloatArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterCompressorMeter") {
      const int effect = FindInt(args, "effect", 0);
      const auto values = CallOnMessageThreadSync([effect] {
        return JuceEngine::get().getMasterCompressorMeter(effect);
      });
      result->Success(flutter::EncodableValue(FloatArrayToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getHostSampleRate") {
      const double sample_rate =
          CallOnMessageThreadSync([] { return JuceEngine::get().getHostSampleRate(); });
      result->Success(flutter::EncodableValue(sample_rate));
      return;
    }

    if (method_call.method_name() == "getRecentMasterStereoWaveform") {
      const int sample_count = FindInt(args, "sampleCount", 2048);
      const auto values = CallOnMessageThreadSync([sample_count] {
        return JuceEngine::get().getRecentMasterStereoWaveform(sample_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getRowEqWaveform") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const int sample_count = FindInt(args, "sampleCount", 1024);
      const auto values = CallOnMessageThreadSync([row, effect, sample_count] {
        return JuceEngine::get().getRowEqWaveform(row, effect, sample_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterEqWaveform") {
      const int effect = FindInt(args, "effect", 0);
      const int sample_count = FindInt(args, "sampleCount", 1024);
      const auto values = CallOnMessageThreadSync([effect, sample_count] {
        return JuceEngine::get().getMasterEqWaveform(effect, sample_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getRowStereoScope") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 256);
      const auto values = CallOnMessageThreadSync([row, effect, point_count] {
        return JuceEngine::get().getRowStereoScope(row, effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterStereoScope") {
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 256);
      const auto values = CallOnMessageThreadSync([effect, point_count] {
        return JuceEngine::get().getMasterStereoScope(effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getRowShaperPreview") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 192);
      const auto values = CallOnMessageThreadSync([row, effect, point_count] {
        return JuceEngine::get().getRowShaperPreview(row, effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterShaperPreview") {
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 192);
      const auto values = CallOnMessageThreadSync([effect, point_count] {
        return JuceEngine::get().getMasterShaperPreview(effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getRowTransientShaperVisual") {
      const int row = FindInt(args, "row", 0);
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 192);
      const auto values = CallOnMessageThreadSync([row, effect, point_count] {
        return JuceEngine::get().getRowTransientShaperVisual(row, effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "getMasterTransientShaperVisual") {
      const int effect = FindInt(args, "effect", 0);
      const int point_count = FindInt(args, "pointCount", 192);
      const auto values = CallOnMessageThreadSync([effect, point_count] {
        return JuceEngine::get().getMasterTransientShaperVisual(effect, point_count);
      });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "setAutomationTransport") {
      const double time_seconds = FindDouble(args, "timeSeconds", 0.0);
      CallOnMessageThreadSync([time_seconds] {
        JuceEngine::get().setAutomationTransport(time_seconds);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "debugPrintGraph") {
      const std::string title = FindString(args, "title", "(no title)");
      CallOnMessageThreadSync(
          [title] { JuceEngine::get().debugPrintGraph(ToJuceString(title)); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "debugPrintGraphStructure") {
      CallOnMessageThreadSync([] { JuceEngine::get().debugPrintGraphStructure(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMetronomeEnabled") {
      const bool enabled = FindBool(args, "enabled", false);
      CallOnMessageThreadSync(
          [enabled] { JuceEngine::get().setMetronomeEnabled(enabled); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMetronomeVolume") {
      const float volume = static_cast<float>(FindDouble(args, "volume", 0.0));
      CallOnMessageThreadSync(
          [volume] { JuceEngine::get().setMetronomeVolume(volume); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMetronomeBpm") {
      const double bpm = FindDouble(args, "bpm", 120.0);
      CallOnMessageThreadSync(
          [bpm] { JuceEngine::get().setMetronomeBpm(bpm); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMetronomeTimeSignature") {
      const int numerator = FindInt(args, "numerator", 4);
      const int denominator = FindInt(args, "denominator", 4);
      CallOnMessageThreadSync([numerator, denominator] {
        JuceEngine::get().setMetronomeTimeSignature(numerator, denominator);
      });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "setMetronomeTransportMs") {
      const double ms = FindDouble(args, "ms", 0.0);
      CallOnMessageThreadSync(
          [ms] { JuceEngine::get().setMetronomeTransportMs(ms); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "decodeAudioMono16k") {
      const std::string path = FindString(args, "path");
      const auto values = CallOnMessageThreadSync(
          [path] { return JuceEngine::get().decodeAudioMono16k(juce::File(ToJuceString(path))); });
      result->Success(flutter::EncodableValue(FloatVectorToEncodableList(values)));
      return;
    }

    if (method_call.method_name() == "analyzeAudioStereo16k") {
      const std::string path = FindString(args, "path");
      const auto stats = CallOnMessageThreadSync(
          [path] { return JuceEngine::get().analyzeAudioStereo16k(juce::File(ToJuceString(path))); });
      result->Success(flutter::EncodableValue(NamedValueStatsToEncodableMap(stats)));
      return;
    }

    if (method_call.method_name() == "getInputDevices") {
      const auto devices =
          CallOnMessageThreadSync([] { return JuceEngine::get().getAvailableInputDevices(); });
      result->Success(flutter::EncodableValue(StringArrayToEncodableList(devices)));
      return;
    }

    if (method_call.method_name() == "selectInputDevice") {
      const std::string name = FindString(args, "name");
      const bool ok = CallOnMessageThreadSync(
          [name] { return JuceEngine::get().selectInputDevice(ToJuceString(name)); });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "getNumInputChannels") {
      const int channels =
          CallOnMessageThreadSync([] { return JuceEngine::get().getNumInputChannels(); });
      result->Success(flutter::EncodableValue(static_cast<int32_t>(channels)));
      return;
    }

    if (method_call.method_name() == "prepareRecordingInputs") {
      const int desired_channels = FindInt(args, "desiredInputChannels", 1);
      const std::string reason = FindString(args, "reason");
      CallOnMessageThreadSync([desired_channels, reason] {
        JuceEngine::get().prepareRecordingInputsAsync(
            desired_channels, ToJuceString(reason.empty() ? "dart" : reason));
      });
      result->Success();
      return;
    }

    if (method_call.method_name() == "getRecordingPeak") {
      const double peak =
          CallOnMessageThreadSync([] { return JuceEngine::get().getRecordingPeak(); });
      result->Success(flutter::EncodableValue(peak));
      return;
    }

    if (method_call.method_name() == "getCurrentDeviceName") {
      const std::string name = CallOnMessageThreadSync(
          [] { return JuceEngine::get().getCurrentInputDeviceName().toStdString(); });
      result->Success(flutter::EncodableValue(name));
      return;
    }

    if (method_call.method_name() == "startRecording") {
      const std::string path = FindString(args, "path");
      const int channel_start = FindInt(args, "channelStart", 0);
      const int channel_count = FindInt(args, "channelCount", 1);
      const bool ok = CallOnMessageThreadSync([=] {
        return JuceEngine::get().startRecordingToWav(
            juce::File(ToJuceString(path)), channel_start, channel_count);
      });
      result->Success(flutter::EncodableValue(ok));
      return;
    }

    if (method_call.method_name() == "stopRecording") {
      CallOnMessageThreadSync([] { JuceEngine::get().stopRecording(); });
      result->Success(flutter::EncodableValue());
      return;
    }

    if (method_call.method_name() == "isRecording") {
      const bool recording =
          CallOnMessageThreadSync([] { return JuceEngine::get().isRecording(); });
      result->Success(flutter::EncodableValue(recording));
      return;
    }

    // Keep desktop bridge forward-compatible with additive API methods.
    result->Success(flutter::EncodableValue());
  } catch (const std::exception& e) {
    result->Error("JUCE_ERROR", e.what());
  } catch (...) {
    result->Error("JUCE_ERROR", "Unknown native exception");
  }
}

}  // namespace juce_audio_engine
