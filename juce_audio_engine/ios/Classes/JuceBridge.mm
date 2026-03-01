#include <float.h>
#import "JuceBridge.h"
#import "JuceEngine.h"
#include "InstrumentRenderers.h"
#include "JuceHeader.h"
#import "JuceAudioEnginePlugin.h" // To access debugLogChannel

namespace
{
juce::String juceStringFromNSString(NSString *value)
{
    if (value == nil)
        return {};
    const char *utf8 = [value UTF8String];
    return utf8 != nullptr ? juce::String::fromUTF8(utf8) : juce::String();
}

juce::File juceFileFromNSString(NSString *value)
{
    return juce::File(juceStringFromNSString(value));
}

juce::Array<TimelineMidiNote> parseTimelineMidiNotes(NSArray<NSDictionary *> *notes)
{
    juce::Array<TimelineMidiNote> parsed;
    if (notes == nil)
        return parsed;

    parsed.ensureStorageAllocated((int)notes.count);
    for (NSDictionary *d in notes)
    {
        TimelineMidiNote note;
        id noteIdV = d[@"id"];
        id pitchV = d[@"pitch"];
        id startV = d[@"startBeat"];
        id lenV = d[@"lengthBeats"];
        id velV = d[@"velocity"];

        if ([noteIdV isKindOfClass:[NSString class]])
            note.noteId = juce::String::fromUTF8([(NSString *)noteIdV UTF8String]);
        if ([pitchV respondsToSelector:@selector(intValue)])
            note.pitch = (int)[pitchV intValue];
        if ([startV respondsToSelector:@selector(doubleValue)])
            note.startBeat = [startV doubleValue];
        if ([lenV respondsToSelector:@selector(doubleValue)])
            note.lengthBeats = [lenV doubleValue];
        if ([velV respondsToSelector:@selector(doubleValue)])
            note.velocity = [velV doubleValue];

        parsed.add(note);
    }
    return parsed;
}

juce::NamedValueSet parseMidiParams(NSDictionary<NSString *, NSNumber *> *params)
{
    juce::NamedValueSet parsed;
    if (params == nil)
        return parsed;

    for (NSString *key in params)
    {
        id raw = params[key];
        if (raw == nil || raw == [NSNull null])
            continue;
        if (![raw respondsToSelector:@selector(doubleValue)])
            continue;

        const juce::String juceKey = juce::String::fromUTF8([key UTF8String]);
        parsed.set(juce::Identifier(juceKey), juce::var((double)[raw doubleValue]));
    }

    return parsed;
}
} // namespace

@implementation JuceBridge

+ (void)initialiseEngineObjC
{
    // JuceEngine& engine = JuceEngine::get();
    // engine.initialiseEngine();
    // JuceEngine& engine = JuceEngine::get(); // 💥 Forces constructor immediately
    // juce::MessageManager::callAsync([&engine] {
    //     engine.initialiseEngine(); // Safe to call async now
    // });
    // JuceEngine::get().initialiseEngine();
    // juce::MessageManager::callAsync([] {
    //     JuceEngine::get().initialiseEngine();
    // });
    JuceEngine &engine = JuceEngine::get(); // Constructor runs here
    engine.initialiseEngine();              // on main thread! don't do async or diff thread
    // std::thread([&engine] {
    //     engine.initialiseEngine();
    // }).detach();
}

+ (void)initializeMessageManager
{
    static bool initialized = false;
    if (!initialized)
    {
        juce::MessageManager::getInstance();
        initialized = true;
    }
}

+ (void)shutdownEngineObjC
{
    // juceLogToFlutter("🔻 JuceBridge: shutdownEngineObjC called");
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().shutdownEngine(); });
}

// DEPRECATED: use loadClipObjC:rowId:path:startSec:lengthSec:inFileOffsetSec: instead
+ (void)loadTrackObjC:(NSInteger)idx path:(NSString *)path
{

    // [[JuceAudioEnginePlugin sharedInstance] sendFlutterLog:@"✅ Objective-C: Entering loadTrackObjC"];

    // juce::String jucePath = juceStringFromNSString(path);
    // juce::MessageManager::callAsync([idx, jucePath] {
    //     JuceEngine::get().loadTrack((int)idx, juce::File(jucePath));
    // });
    juce::String jucePath = juceStringFromNSString(path);

    JuceEngine::get().loadTrack((int)idx, juce::File(jucePath)); // CALL DIRECTLY!
}

+ (void)playObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().play(); });
}

+ (void)pauseObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().pause(); });
}

+ (void)removeTrackObjC:(NSInteger)trackIndex
{
    juce::MessageManager::callAsync([trackIndex]
                                    { JuceEngine::get().removeTrack((int)trackIndex); });
}

+ (NSArray<NSString *> *)getTrackEffectsObjC:(NSInteger)trackIndex
{
    auto names = JuceEngine::get().getTrackEffects((int)trackIndex);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    return out;
}

+ (void)removeEffectObjC:(NSInteger)trackIndex effectIndex:(NSInteger)effectIndex
{
    juce::MessageManager::callAsync([trackIndex, effectIndex]
                                    { JuceEngine::get().removePluginEffect((int)trackIndex, (int)effectIndex); });
}

+ (void)reorderEffectsObjC:(NSInteger)trackIndex
                 fromIndex:(NSInteger)fromIdx
                   toIndex:(NSInteger)toIdx
{
    juce::MessageManager::callAsync([trackIndex, fromIdx, toIdx]
                                    { JuceEngine::get().reorderPluginEffects((int)trackIndex, (int)fromIdx, (int)toIdx); });
}

+ (void)seekObjC:(NSInteger)trackIndex position:(double)seconds
{
    juce::MessageManager::callAsync([trackIndex, seconds]
                                    { JuceEngine::get().seek((int)trackIndex, seconds); });
}

+ (double)getCurrentPositionObjC:(NSInteger)trackIndex
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIndex, &result]
                                                  { result = JuceEngine::get().getCurrentPosition((int)trackIndex); });
    return result.load();
}

+ (double)getTrackDurationObjC:(NSInteger)trackIndex
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIndex, &result]
                                                  { result = JuceEngine::get().getTrackDuration((int)trackIndex); });
    return result.load();
}

+ (void)insertEffectObjC:(NSInteger)track path:(NSString *)pluginPath
{
    juce::String jucePath = juceStringFromNSString(pluginPath);

    // Remove juce::MessageManager::callAsync here!
    // Let JuceEngine::insertPluginEffect handle threading internally.
    JuceEngine::get().insertPluginEffect(
        (int)track,
        jucePath,
        [track, pluginPath](bool success) { // Add callback
            // Notify Flutter via event channel
            [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCEPluginLoaded"
                                                                object:nil
                                                              userInfo:@{
                                                                  @"event" : @"pluginLoaded",
                                                                  @"track" : @(track),
                                                                  @"path" : pluginPath,
                                                                  @"success" : @(success)
                                                              }];
        });
}

// DEPRECATED: use setEffectObjC-style APIs that are track/row/master specific
+ (void)setEffectObjC:(NSInteger)track
          pluginIndex:(NSInteger)pindex
              paramId:(NSString *)param
                value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::callAsync([track, pindex, juceParam, newVal]
                                    { JuceEngine::get().setEffectParameter((int)track, (int)pindex, juceParam, newVal); });
}

+ (void)setTrackVolumeObjC:(NSInteger)track volume:(float)v
{
    juce::MessageManager::callAsync([track, v]
                                    { JuceEngine::get().setTrackVolume((int)track, v); });
}

+ (NSArray<NSDictionary *> *)getPluginParametersObjC:(NSInteger)track
                                         effectIndex:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([track, effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getPluginParameterInfo((int)track, (int)effect);
        for (auto& e : list) {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";
            if (e.contains("min"))     d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))     d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isDouble() || v.isInt())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };
            if (e.contains("default")) {
                juce::var defVar = e["default"];
                d[@"defaultValue"] = extractVar(defVar);
            }
            if (e.contains("value")) {
                juce::var valVar = e["value"];
                d[@"value"] = extractVar(valVar);
            }

            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                // JUCE var → NSString
                juce::var v = e[key];
                juce::String vs = v.toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:vs.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }
        __result = [arr copy]; });

    return __result;
}

+ (NSArray<NSDictionary *> *)getTrackPluginParametersObjC:(NSInteger)row
                                              effectIndex:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([row, effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getTrackPluginParameterInfo((int)row, (int)effect);

        for (auto& e : list)
        {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";

            if (e.contains("min"))  d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))  d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isInt() || v.isDouble())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };

            if (e.contains("default"))
                d[@"defaultValue"] = extractVar(e["default"]);

            if (e.contains("value"))
                d[@"value"] = extractVar(e["value"]);

            // Choices: choice_0, choice_1, ...
            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                auto txt  = e[key].toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:txt.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }

        __result = [arr copy]; });

    return __result;
}

+ (NSArray<NSDictionary *> *)getMasterPluginParametersObjC:(NSInteger)effect
{
    __unsafe_unretained NSMutableArray *__result = nil;

    juce::MessageManager::getInstance()->callSync([effect, &__result]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto list = JuceEngine::get().getMasterPluginParameterInfo((int)effect);

        for (auto& e : list)
        {
            const char* cid   = e["id"].toString().toRawUTF8();
            const char* cname = e["name"].toString().toRawUTF8();
            const char* ctype = e["type"].toString().toRawUTF8();

            NSMutableDictionary* d = [NSMutableDictionary dictionary];
            d[@"id"]   = [NSString stringWithUTF8String:cid] ?: @"";
            d[@"name"] = [NSString stringWithUTF8String:cname] ?: @"";
            d[@"type"] = [NSString stringWithUTF8String:ctype] ?: @"";

            if (e.contains("min"))  d[@"min"] = @(static_cast<float>(e["min"]));
            if (e.contains("max"))  d[@"max"] = @(static_cast<float>(e["max"]));

            auto extractVar = ^(const juce::var& v) {
                if (v.isBool())
                    return (id)@(static_cast<bool>(v));
                else if (v.isInt() || v.isDouble())
                    return (id)@(static_cast<float>(v));
                else {
                    auto s = v.toString();
                    return (id)([NSString stringWithUTF8String:s.toRawUTF8()] ?: @"");
                }
            };

            if (e.contains("default"))
                d[@"defaultValue"] = extractVar(e["default"]);

            if (e.contains("value"))
                d[@"value"] = extractVar(e["value"]);

            for (int i = 0; ; ++i)
            {
                juce::String key = "choice_" + juce::String(i);
                if (! e.contains(key))
                    break;

                auto txt = e[key].toString();
                NSString* skey   = [NSString stringWithUTF8String:key.toRawUTF8()];
                NSString* svalue = [NSString stringWithUTF8String:txt.toRawUTF8()] ?: @"";
                d[skey] = svalue;
            }

            [arr addObject:d];
        }

        __result = [arr copy]; });

    return __result;
}

+ (NSString *)exportMixObjC:(NSString *)outPath settings:(NSDictionary *)settings
{
    juce::String jucePath = juceStringFromNSString(outPath);
    JuceEngine::ExportOptions options;
    NSString *format = settings[@"format"];
    if ([format isKindOfClass:[NSString class]] && format.length > 0)
        options.format = juceStringFromNSString(format);
    NSNumber *sampleRate = settings[@"sampleRate"];
    if ([sampleRate isKindOfClass:[NSNumber class]])
        options.sampleRate = [sampleRate doubleValue];
    NSNumber *wavBitDepth = settings[@"wavBitDepth"];
    if ([wavBitDepth isKindOfClass:[NSNumber class]])
        options.wavBitDepth = [wavBitDepth intValue];
    NSNumber *wavDithering = settings[@"wavDithering"];
    if ([wavDithering isKindOfClass:[NSNumber class]])
        options.wavDithering = [wavDithering boolValue];
    NSNumber *mp3BitrateKbps = settings[@"mp3BitrateKbps"];
    if ([mp3BitrateKbps isKindOfClass:[NSNumber class]])
        options.mp3BitrateKbps = [mp3BitrateKbps intValue];
    juce::String result;

    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportMix(juce::File(jucePath), options); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (NSString *)exportTrackObjC:(NSInteger)track outPath:(NSString *)outPath settings:(NSDictionary *)settings
{
    juce::String result;
    juce::String jucePath = juceStringFromNSString(outPath);
    JuceEngine::ExportOptions options;
    NSString *format = settings[@"format"];
    if ([format isKindOfClass:[NSString class]] && format.length > 0)
        options.format = juceStringFromNSString(format);
    NSNumber *sampleRate = settings[@"sampleRate"];
    if ([sampleRate isKindOfClass:[NSNumber class]])
        options.sampleRate = [sampleRate doubleValue];
    NSNumber *wavBitDepth = settings[@"wavBitDepth"];
    if ([wavBitDepth isKindOfClass:[NSNumber class]])
        options.wavBitDepth = [wavBitDepth intValue];
    NSNumber *wavDithering = settings[@"wavDithering"];
    if ([wavDithering isKindOfClass:[NSNumber class]])
        options.wavDithering = [wavDithering boolValue];
    NSNumber *mp3BitrateKbps = settings[@"mp3BitrateKbps"];
    if ([mp3BitrateKbps isKindOfClass:[NSNumber class]])
        options.mp3BitrateKbps = [mp3BitrateKbps intValue];

    juce::MessageManager::getInstance()->callSync([track, jucePath, options, &result]
                                                  { result = JuceEngine::get().exportTrack((int)track, juce::File(jucePath), options); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (NSString *)renderInstrumentClipObjC:(NSString *)outPath
                          instrumentId:(NSString *)instrumentId
                        instrumentName:(NSString *)instrumentName
                                   bpm:(double)bpm
                                 notes:(NSArray<NSDictionary *> *)notes
                                params:(NSDictionary<NSString *, NSNumber *> *)params
{
    mixroom::instruments::InstrumentRenderRequest request;
    request.outFile = juce::File(
        outPath != nil ? juceStringFromNSString(outPath)
                       : juce::String());
    request.instrumentId =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    request.instrumentName =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    request.bpm = bpm;

    if (notes != nil)
    {
        request.notes.ensureStorageAllocated((int)notes.count);
        for (NSDictionary *d in notes)
        {
            mixroom::instruments::MidiRenderNote note;
            id pitchV = d[@"pitch"];
            id startV = d[@"startBeat"];
            id lenV = d[@"lengthBeats"];
            id velV = d[@"velocity"];

            if ([pitchV respondsToSelector:@selector(intValue)])
                note.pitch = (int)[pitchV intValue];
            if ([startV respondsToSelector:@selector(doubleValue)])
                note.startBeat = [startV doubleValue];
            if ([lenV respondsToSelector:@selector(doubleValue)])
                note.lengthBeats = [lenV doubleValue];
            if ([velV respondsToSelector:@selector(doubleValue)])
                note.velocity = [velV doubleValue];

            request.notes.add(note);
        }
    }

    if (params != nil)
    {
        for (NSString *key in params)
        {
            id raw = params[key];
            if (raw == nil || raw == [NSNull null])
                continue;
            if (![raw respondsToSelector:@selector(doubleValue)])
                continue;

            const juce::String juceKey = juce::String::fromUTF8([key UTF8String]);
            request.params.set(juce::Identifier(juceKey), juce::var((double)[raw doubleValue]));
        }
    }

    const juce::String renderedPath = mixroom::instruments::renderInstrumentClipToWav(request);
    if (renderedPath.isEmpty())
        return @"";
    return [NSString stringWithUTF8String:renderedPath.toRawUTF8()];
}

+ (NSArray<NSDictionary *> *)scanPluginsObjC
{
    NSMutableArray *resultArray = nil;

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     {
            NSMutableArray *arr = [NSMutableArray array];
            NSMutableSet<NSString *> *seenIds = [NSMutableSet set];
            auto types = JuceEngine::get().getKnownPlugins();
            for (const auto &desc : types) {
                NSString *formatName = [NSString stringWithUTF8String:desc.pluginFormatName.toRawUTF8()] ?: @"";
                // iOS "On Device" tab should expose AudioUnit plugins only.
#if TARGET_OS_IOS
                if (formatName.length > 0 && ![formatName isEqualToString:@"AudioUnit"])
                    continue;
#endif

                NSString *name = [NSString stringWithUTF8String:desc.name.toRawUTF8()] ?: @"";
                NSString *ident = [NSString stringWithUTF8String:desc.fileOrIdentifier.toRawUTF8()] ?: @"";
                if (ident.length == 0 || name.length == 0)
                    continue;
                if ([seenIds containsObject:ident])
                    continue;

                [seenIds addObject:ident];
                [arr addObject:@{
                    @"name" : name,
                    @"id" : ident,
                    @"format" : formatName
                }];
            }
            resultArray = [arr copy]; });
    }

    if (resultArray == nil)
        resultArray = [NSMutableArray array];

    return resultArray;
}

#pragma mark - Transport

+ (void)setTransportSecondsObjC:(double)seconds
{
    juce::MessageManager::callAsync([seconds]
                                    { JuceEngine::get().setTransportSeconds(seconds); });
}

+ (double)getTransportSecondsObjC
{
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([&result]
                                                  { result = JuceEngine::get().getTransportSeconds(); });
    return result.load();
}

+ (BOOL)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath
{
    if (pluginPath == nil || pluginPath.length == 0)
        return NO;

    juce::String jucePath = juceStringFromNSString(pluginPath);
    bool success = false;

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertTrackEffect((int)trackRow, jucePath); });
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCERowEffectLoaded"
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : @"rowEffectLoaded",
                                                          @"row" : @(trackRow),
                                                          @"path" : pluginPath ?: @"",
                                                          @"success" : @(success)
                                                      }];
    return success ? YES : NO;
}

+ (void)removeTrackEffectObjC:(NSInteger)trackRow effectIndex:(NSInteger)effectIndex
{
    juce::MessageManager::callAsync([trackRow, effectIndex]
                                    { JuceEngine::get().removeTrackEffect((int)trackRow, (int)effectIndex); });
}

+ (void)reorderTrackEffectsObjC:(NSInteger)trackRow
                      fromIndex:(NSInteger)fromIdx
                        toIndex:(NSInteger)toIdx
{
    juce::MessageManager::callAsync([trackRow, fromIdx, toIdx]
                                    { JuceEngine::get().reorderTrackEffects((int)trackRow, (int)fromIdx, (int)toIdx); });
}

+ (NSArray<NSString *> *)getTrackEffectsForRowObjC:(NSInteger)trackRow
{
    auto names = JuceEngine::get().getTrackEffectsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getTrackEffectIdsForRowObjC:(NSInteger)trackRow
{
    auto ids = JuceEngine::get().getTrackEffectIdsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getTrackEffectInstanceIdsForRowObjC:(NSInteger)trackRow
{
    auto ids = JuceEngine::get().getTrackEffectInstanceIdsForRow((int)trackRow);
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (void)setTrackEffectObjC:(NSInteger)trackRow
               effectIndex:(NSInteger)effectIndex
                   paramId:(NSString *)param
                     value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::callAsync([trackRow, effectIndex, juceParam, newVal]
                                    { JuceEngine::get().setTrackEffectParameter((int)trackRow, (int)effectIndex, juceParam, newVal); });
}

+ (void)bypassRowEffectObjC:(NSInteger)rowIndex
                effectIndex:(NSInteger)effectIndex
                     bypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([rowIndex, effectIndex, shouldBypass]
                                    { JuceEngine::get().bypassRowEffect((int)rowIndex, (int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getRowEffectBypassStateObjC:(NSInteger)rowIndex
                        effectIndex:(NSInteger)effectIndex
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([rowIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getRowEffectBypassState((int)rowIndex, (int)effectIndex); });
    return result;
}

+ (void)setRowGainObjC:(NSInteger)row gain:(float)gain
{
    juce::MessageManager::callAsync([row, gain]
                                    { JuceEngine::get().setRowGain((int)row, gain); });
}

+ (void)muteRowObjC:(NSInteger)row shouldMute:(BOOL)shouldMute
{
    juce::MessageManager::callAsync([row, shouldMute]
                                    { JuceEngine::get().muteRow((int)row, (bool)shouldMute); });
}

+ (bool)isRowMutedObjC:(NSInteger)row
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([row, &result]
                                                  { result = JuceEngine::get().isRowMuted((int)row); });
    return result;
}

+ (void)setRowPanObjC:(NSInteger)row pan:(float)pan
{
    juce::MessageManager::callAsync([row, pan]
                                    { JuceEngine::get().setRowPan((int)row, pan); });
}

#pragma mark - Master bus FX and controls

+ (BOOL)insertMasterEffectObjC:(NSString *)pluginPath
{
    if (pluginPath == nil || pluginPath.length == 0)
        return NO;

    juce::String jucePath = juceStringFromNSString(pluginPath);
    bool success = false;

    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     { success = JuceEngine::get().insertMasterEffect(jucePath); });
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCEMasterEffectLoaded"
                                                        object:nil
                                                      userInfo:@{
                                                          @"event" : @"masterEffectLoaded",
                                                          @"path" : pluginPath ?: @"",
                                                          @"success" : @(success)
                                                      }];
    return success ? YES : NO;
}

+ (void)removeMasterEffectObjC:(NSInteger)effectIndex
{
    juce::MessageManager::getInstance()->callSync([effectIndex]
                                                  { JuceEngine::get().removeMasterEffect((int)effectIndex); });
}

+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex
{
    juce::MessageManager::getInstance()->callSync([fromIndex, toIndex]
                                                  { JuceEngine::get().reorderMasterEffects((int)fromIndex, (int)toIndex); });
}

+ (NSArray<NSString *> *)getMasterEffectsObjC
{
    auto names = JuceEngine::get().getMasterEffects();
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : names)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (NSArray<NSString *> *)getMasterEffectIdsObjC
{
    auto ids = JuceEngine::get().getMasterEffectIds();
    NSMutableArray *out = [NSMutableArray array];
    for (auto &s : ids)
    {
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
    }
    return out;
}

+ (void)setMasterEffectObjC:(NSInteger)effectIndex
                    paramId:(NSString *)param
                      value:(id)value
{
    juce::var newVal;
    if ([value isKindOfClass:[NSNumber class]])
    {
        const char *t = [(NSNumber *)value objCType];
        if (strcmp(t, @encode(BOOL)) == 0)
            newVal = (bool)[(NSNumber *)value boolValue];
        else if (strcmp(t, @encode(int)) == 0 || strcmp(t, @encode(NSInteger)) == 0)
            newVal = (int)[(NSNumber *)value integerValue];
        else
            newVal = (float)[(NSNumber *)value floatValue];
    }
    else if ([value isKindOfClass:[NSString class]])
    {
        newVal = juceStringFromNSString((NSString *)value);
    }

    juce::String juceParam = juceStringFromNSString(param);
    juce::MessageManager::callAsync([effectIndex, juceParam, newVal]
                                    { JuceEngine::get().setMasterEffectParameter((int)effectIndex, juceParam, newVal); });
}

+ (void)bypassMasterEffectObjC:(NSInteger)effectIndex bypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([effectIndex, shouldBypass]
                                    { JuceEngine::get().bypassMasterEffect((int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getMasterEffectBypassStateObjC:(NSInteger)effectIndex
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([effectIndex, &result]
                                                  { result = JuceEngine::get().getMasterEffectBypassState((int)effectIndex); });
    return result;
}

+ (void)setMasterGainObjC:(float)gain
{
    juce::MessageManager::callAsync([gain]
                                    { JuceEngine::get().setMasterGain(gain); });
}

+ (void)muteMasterObjC:(BOOL)shouldMute
{
    juce::MessageManager::callAsync([shouldMute]
                                    { JuceEngine::get().muteMaster((bool)shouldMute); });
}

+ (void)setMasterPanObjC:(float)pan
{
    juce::MessageManager::callAsync([pan]
                                    { JuceEngine::get().setMasterPan(pan); });
}

+ (void)bypassPluginObjC:(NSInteger)trackIndex
             effectIndex:(NSInteger)effectIndex
                  bypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([trackIndex, effectIndex, shouldBypass]
                                    { JuceEngine::get().bypassPlugin((int)trackIndex, (int)effectIndex, (bool)shouldBypass); });
}

+ (bool)getPluginBypassStateObjC:(NSInteger)trackIndex
                     effectIndex:(NSInteger)effectIndex
{
    bool result;
    juce::MessageManager::getInstance()->callSync([trackIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getPluginBypassState((int)trackIndex, (int)effectIndex); });
    return result;
}

+ (void)bypassTrackObjC:(NSInteger)trackIndex
           shouldBypass:(BOOL)shouldBypass
{
    juce::MessageManager::callAsync([trackIndex, shouldBypass]
                                    { JuceEngine::get().bypassTrack((int)trackIndex, (bool)shouldBypass); });
}

+ (void)loadVideoAudioObjC:(NSString *)path
{
    juce::String jucePath = juceStringFromNSString(path);
    juce::MessageManager::callAsync([jucePath]
                                    { JuceEngine::get().loadVideoAudio(juce::File(jucePath)); });
}

+ (void)unloadVideoAudioObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().unloadVideoAudio(); });
}

+ (void)setVideoAudioGainObjC:(float)gain
{
    juce::MessageManager::callAsync([gain]
                                    { JuceEngine::get().setVideoAudioGain(gain); });
}

+ (void)seekVideoAudioObjC:(double)seconds
{
    juce::MessageManager::callAsync([seconds]
                                    { JuceEngine::get().seekVideoAudio(seconds); });
}

// ===============================================================
// NEW DAW-STYLE API (clip / row / master / automation)
// ===============================================================

#pragma mark - Debug graph

+ (void)debugPrintGraphObjC:(NSString *)title
{
    juce::String juceTitle = juceStringFromNSString(title);
    juce::MessageManager::callAsync([juceTitle]
                                    { JuceEngine::get().debugPrintGraph(juceTitle); });
}

+ (void)debugPrintGraphStructureObjC
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().debugPrintGraphStructure(); });
}

#pragma mark - Clip-level control

+ (void)loadClipObjC:(NSInteger)clipIndex
               rowId:(NSInteger)rowId
                path:(NSString *)path
            startSec:(double)startSec
           lengthSec:(double)lengthSec
     inFileOffsetSec:(double)inFileOffsetSec
{
    juce::String jucePath = juceStringFromNSString(path);
    JuceEngine::get().loadClip((int)clipIndex,
                               (int)rowId,
                               juce::File(jucePath),
                               startSec,
                               lengthSec,
                               inFileOffsetSec);
}

+ (BOOL)supportsLiveMidiClipPlaybackObjC
{
    bool supported = false;
    juce::MessageManager::getInstance()->callSync([&supported]
                                                  { supported = JuceEngine::get().supportsLiveMidiClipPlayback(); });
    return (BOOL)supported;
}

+ (BOOL)loadMidiClipObjC:(NSInteger)clipIndex
                   rowId:(NSInteger)rowId
            instrumentId:(NSString *)instrumentId
          instrumentName:(NSString *)instrumentName
                   notes:(NSArray<NSDictionary *> *)notes
                  params:(NSDictionary<NSString *, NSNumber *> *)params
          sourceTempoBpm:(double)sourceTempoBpm
                startSec:(double)startSec
               lengthSec:(double)lengthSec
         inFileOffsetSec:(double)inFileOffsetSec
{
    const juce::String iid =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    const juce::String iname =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    const auto parsedNotes = parseTimelineMidiNotes(notes);
    const auto parsedParams = parseMidiParams(params);

    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().loadMidiClip((int)clipIndex,
                                            (int)rowId,
                                            iid,
                                            iname,
                                            parsedNotes,
                                            parsedParams,
                                            sourceTempoBpm,
                                            startSec,
                                            lengthSec,
                                            inFileOffsetSec); });
    return (BOOL)ok;
}

+ (BOOL)updateMidiClipObjC:(NSInteger)clipIndex
              instrumentId:(NSString *)instrumentId
            instrumentName:(NSString *)instrumentName
                     notes:(NSArray<NSDictionary *> *)notes
                    params:(NSDictionary<NSString *, NSNumber *> *)params
            sourceTempoBpm:(double)sourceTempoBpm
{
    const juce::String iid =
        instrumentId != nil ? juceStringFromNSString(instrumentId)
                            : juce::String();
    const juce::String iname =
        instrumentName != nil ? juceStringFromNSString(instrumentName)
                              : juce::String();
    const auto parsedNotes = parseTimelineMidiNotes(notes);
    const auto parsedParams = parseMidiParams(params);

    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().updateMidiClipEvents((int)clipIndex,
                                                    iid,
                                                    iname,
                                                    parsedNotes,
                                                    parsedParams,
                                                    sourceTempoBpm); });
    return (BOOL)ok;
}

+ (BOOL)setLiveMidiInputTargetClipObjC:(NSInteger)clipIndex
{
    bool ok = false;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().setLiveMidiInputTargetClip((int)clipIndex); });
    return (BOOL)ok;
}

+ (NSArray<NSDictionary *> *)consumeLiveMidiInputEventsObjC
{
    std::vector<JuceEngine::LiveMidiInputEvent> events;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { events = JuceEngine::get().consumeLiveMidiInputEvents(); });

    NSMutableArray<NSDictionary *> *out =
        [NSMutableArray arrayWithCapacity:events.size()];
    for (const auto &event : events)
    {
        [out addObject:@{
            @"clip" : @(event.clipId),
            @"type" : event.noteOn ? @"noteOn" : @"noteOff",
            @"channel" : @(event.channel),
            @"pitch" : @(event.pitch),
            @"velocity" : @((double)event.velocity),
            @"transportSec" : @(event.transportSec),
        }];
    }
    return out;
}

+ (NSArray<NSDictionary *> *)getConnectedMidiInputDevicesObjC
{
    NSArray<NSDictionary *> *resultArray = nil;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([&]
                     {
            NSMutableArray<NSDictionary *> *arr = [NSMutableArray array];
            const auto devices = juce::MidiInput::getAvailableDevices();
            for (const auto &device : devices)
            {
                NSString *identifier =
                    [NSString stringWithUTF8String:device.identifier.toRawUTF8()] ?: @"";
                if (identifier.length == 0)
                    continue;

                NSString *name =
                    [NSString stringWithUTF8String:device.name.toRawUTF8()] ?: @"";
                if (name.length == 0)
                    name = identifier;

                [arr addObject:@{
                    @"id" : identifier,
                    @"name" : name,
                }];
            }
            resultArray = [arr copy]; });
    }

    if (resultArray == nil)
        resultArray = @[];

    return resultArray;
}

+ (void)unloadClipObjC:(NSInteger)clipIndex
{
    juce::MessageManager::callAsync([clipIndex]
                                    { JuceEngine::get().unloadClip((int)clipIndex); });
}

+ (void)setClipGainObjC:(NSInteger)clipIndex gain:(float)gain
{
    juce::MessageManager::callAsync([clipIndex, gain]
                                    { JuceEngine::get().setClipGain((int)clipIndex, gain); });
}

+ (void)muteClipObjC:(NSInteger)clipIndex shouldMute:(BOOL)shouldMute
{
    juce::MessageManager::callAsync([clipIndex, shouldMute]
                                    { JuceEngine::get().muteClip((int)clipIndex, (bool)shouldMute); });
}

+ (void)setClipPanObjC:(NSInteger)clipIndex pan:(float)pan
{
    juce::MessageManager::callAsync([clipIndex, pan]
                                    { JuceEngine::get().setClipPan((int)clipIndex, pan); });
}

+ (void)setClipPitchObjC:(NSInteger)clipIndex semitones:(float)semitones
{
    juce::MessageManager::callAsync([clipIndex, semitones]
                                    { JuceEngine::get().setClipPitch((int)clipIndex, semitones); });
}

+ (void)setClipStretchOptionsObjC:(NSInteger)clipIndex
                       tempoRatio:(double)tempoRatio
                    preservePitch:(BOOL)preservePitch
{
    juce::MessageManager::callAsync([clipIndex, tempoRatio, preservePitch]
                                    { JuceEngine::get().setClipStretchOptions((int)clipIndex, tempoRatio, (bool)preservePitch); });
}

+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRowId:(NSInteger)newRowId
{
    juce::MessageManager::callAsync([clipIndex, newRowId]
                                    { JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRowId); });
}

+ (void)setClipTimeObjC:(NSInteger)clipIndex
               startSec:(double)startSec
              lengthSec:(double)lengthSec
        inFileOffsetSec:(double)inFileOffsetSec
{
    juce::MessageManager::callAsync([clipIndex, startSec, lengthSec, inFileOffsetSec]
                                    { JuceEngine::get().setClipTime((int)clipIndex, startSec, lengthSec, inFileOffsetSec); });
}

#pragma mark - Row management

+ (NSNumber *)addRowObjC:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().addRow(n, (int)iconId);
    return @(rowId);
}

+ (NSNumber *)insertRowAboveObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().insertRowAbove((int)referenceRowId, n, (int)iconId);
    return @(rowId);
}

+ (NSNumber *)insertRowBelowObjC:(NSInteger)referenceRowId name:(NSString *)name iconId:(NSInteger)iconId
{
    juce::String n = juceStringFromNSString(name);
    int rowId = JuceEngine::get().insertRowBelow((int)referenceRowId, n, (int)iconId);
    return @(rowId);
}

+ (BOOL)removeRowObjC:(NSInteger)rowId
{
    return (BOOL)JuceEngine::get().removeRow((int)rowId);
}

+ (BOOL)moveRowOrderObjC:(NSInteger)fromIndex toIndex:(NSInteger)toIndex
{
    return (BOOL)JuceEngine::get().moveRowOrder((int)fromIndex, (int)toIndex);
}

+ (BOOL)renameRowObjC:(NSInteger)rowId name:(NSString *)name
{
    juce::String n = juceStringFromNSString(name);
    return (BOOL)JuceEngine::get().renameRow((int)rowId, n);
}

+ (BOOL)setRowIconObjC:(NSInteger)rowId iconId:(NSInteger)iconId
{
    return (BOOL)JuceEngine::get().setRowIcon((int)rowId, (int)iconId);
}

+ (NSArray<NSDictionary *> *)getRowsObjC
{
    auto rows = JuceEngine::get().getRows();
    NSMutableArray *out = [NSMutableArray array];

    for (const auto &r : rows)
    {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"rowId"] = @((int)r["rowId"]);
        d[@"name"] = [NSString stringWithUTF8String:r["name"].toString().toRawUTF8()] ?: @"";
        d[@"iconId"] = @((int)r["iconId"]);
        [out addObject:d];
    }

    return out;
}

#pragma mark - Automation

+ (void)setTrackAutomationPointsObjC:(NSInteger)trackRow
                              points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;

        id xVal = dict[@"x"];
        id volVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else
            p.timeMs = 0.0;

        if ([volVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volVal doubleValue];
        else
            p.value = 1.0f;

        cppPoints.push_back(p);
    }

    juce::MessageManager::callAsync([trackRow, cppPoints]() mutable
                                    { JuceEngine::get().setTrackAutomationPoints((int)trackRow, cppPoints); });
}

+ (void)setTrackEffectAutomationPointsObjC:(NSInteger)trackRow
                                effectIndex:(NSInteger)effectIndex
                                    paramId:(NSString *)paramId
                                   minValue:(double)minValue
                                   maxValue:(double)maxValue
                                     points:(NSArray<NSDictionary *> *)points
{
    std::vector<AutomationPoint> cppPoints;
    cppPoints.reserve(points.count);

    for (NSDictionary *dict in points)
    {
        AutomationPoint p;

        id xVal = dict[@"x"];
        id timeMsVal = dict[@"timeMs"];
        id timeSecondsVal = dict[@"timeSeconds"];
        id valueVal = dict[@"value"];
        id volumeVal = dict[@"volume"];

        if ([xVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [xVal doubleValue];
        else if ([timeMsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeMsVal doubleValue];
        else if ([timeSecondsVal respondsToSelector:@selector(doubleValue)])
            p.timeMs = [timeSecondsVal doubleValue] * 1000.0;
        else
            p.timeMs = 0.0;

        if ([valueVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[valueVal doubleValue];
        else if ([volumeVal respondsToSelector:@selector(doubleValue)])
            p.value = (float)[volumeVal doubleValue];
        else
            p.value = 0.0f;

        cppPoints.push_back(p);
    }

    juce::String juceParam = juceStringFromNSString(paramId ?: @"");
    juce::MessageManager::callAsync([trackRow, effectIndex, juceParam, minValue, maxValue, cppPoints]() mutable
                                    { JuceEngine::get().setTrackEffectAutomationPoints((int)trackRow, (int)effectIndex, juceParam, (float)minValue, (float)maxValue, cppPoints); });
}

+ (void)clearTrackEffectAutomationForRowObjC:(NSInteger)trackRow
{
    juce::MessageManager::callAsync([trackRow]
                                    { JuceEngine::get().clearTrackEffectAutomationForRow((int)trackRow); });
}

+ (void)setAutomationTransportObjC:(double)timeSeconds
{
    juce::MessageManager::callAsync([timeSeconds]
                                    { JuceEngine::get().setAutomationTransport(timeSeconds); });
}

+ (void)setMetronomeEnabledObjC:(BOOL)enabled
{
    juce::MessageManager::callAsync([enabled]
                                    { JuceEngine::get().setMetronomeEnabled((bool)enabled); });
}

+ (void)setMetronomeVolumeObjC:(float)vol
{
    juce::MessageManager::callAsync([vol]
                                    { JuceEngine::get().setMetronomeVolume(vol); });
}

+ (void)setMetronomeBpmObjC:(double)bpm
{
    juce::MessageManager::callAsync([bpm]
                                    { JuceEngine::get().setMetronomeBpm(bpm); });
}

+ (void)setMetronomeTransportMsObjC:(double)ms
{
    juce::MessageManager::callAsync([ms]
                                    { JuceEngine::get().setMetronomeTransportMs(ms); });
}

+ (NSArray<NSNumber *> *)decodeAudioMono16kObjC:(NSString *)path
{
    juce::File file = juceFileFromNSString(path);

    auto samples = JuceEngine::get().decodeAudioMono16k(file);

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:samples.size()];
    for (float v : samples)
    {
        [arr addObject:@(v)];
    }
    return arr;
}

+ (NSDictionary<NSString *, NSNumber *> *)analyzeAudioStereo16kObjC:(NSString *)path
{
    juce::File file = juceFileFromNSString(path);
    auto stats = JuceEngine::get().analyzeAudioStereo16k(file);

    return @{
        @"phase_corr" : @((double)stats.getWithDefault("phase_corr", 1.0)),
        @"side_ratio" : @((double)stats.getWithDefault("side_ratio", 0.0)),
        @"stereo_imbalance" : @((double)stats.getWithDefault("stereo_imbalance", 0.0)),
    };
}

+ (NSArray<NSString *> *)getInputDevicesObjC
{
    auto arr = JuceEngine::get().getAvailableInputDevices();

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:arr.size()];
    for (auto &s : arr)
        [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];

    return out;
}

+ (BOOL)selectInputDeviceObjC:(NSString *)name
{
    juce::String dev = juceStringFromNSString(name);
    return JuceEngine::get().selectInputDevice(dev);
}

+ (NSNumber *)getNumInputChannelsObjC
{
    return @(JuceEngine::get().getNumInputChannels());
}

+ (NSString *)getCurrentDeviceNameObjC
{
    auto s = JuceEngine::get().getCurrentInputDeviceName();
    return [NSString stringWithUTF8String:s.toRawUTF8()];
}

+ (BOOL)startRecordingObjC:(NSString *)path
              channelStart:(NSInteger)start
              channelCount:(NSInteger)count
{
    // juce::File f = juceFileFromNSString(path);
    juce::String jucePath = juceStringFromNSString(path);
    juce::File f(jucePath);

    return JuceEngine::get()
        .startRecordingToWav(
            f, (int)start, (int)count);
}

+ (NSNumber *)getRecordingPeakObjC
{
    return @(JuceEngine::get().getRecordingPeak());
}

+ (void)stopRecordingObjC
{
    JuceEngine::get().stopRecording();
}

+ (BOOL)isRecordingObjC
{
    return JuceEngine::get().isRecording();
}

// ===============================
// MASTER METER
// ===============================
+ (void)setMasterMeterEnabledObjC:(BOOL)enabled
{
    JuceEngine::get().setMasterMeterEnabled((bool)enabled);
}

// [peakL, peakR, rmsL, rmsR]
+ (NSArray<NSNumber*>*)getMasterMeterValuesObjC
{
    auto v = JuceEngine::get().getMasterMeterValues();
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3])];
}

+ (BOOL)getMasterClipLatchedObjC
{
    return (BOOL)JuceEngine::get().getMasterClipLatched();
}

+ (void)clearMasterClipLatchedObjC
{
    JuceEngine::get().clearMasterClipLatched();
}

// ===============================
// ROW METERS
// ===============================
+ (void)setRowMetersEnabledObjC:(BOOL)enabled
{
    JuceEngine::get().setRowMetersEnabled((bool)enabled);
}

// [peakL, peakR, rmsL, rmsR]
+ (NSArray<NSNumber*>*)getRowMeterValuesObjC:(NSInteger)row
{
    auto v = JuceEngine::get().getRowMeterValues((int)row);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3])];
}

+ (NSArray<NSNumber*>*)getAllMeterValues
{
    const auto packed = JuceEngine::get().getAllMeterValues();

    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:packed.size()];
    for (float v : packed) {
        [arr addObject:@(v)];
    }
    return arr;
}

// ===============================
// COMPRESSOR METER STRIPS
// [inRmsL, inRmsR, grDb, outRmsL, outRmsR]
// ===============================
+ (NSArray<NSNumber*>*)getClipCompressorMeterObjC:(NSInteger)clipIndex effectIndex:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getClipCompressorMeter((int)clipIndex, (int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (NSArray<NSNumber*>*)getRowCompressorMeterObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getRowCompressorMeter((int)row, (int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (NSArray<NSNumber*>*)getMasterCompressorMeterObjC:(NSInteger)effectIndex
{
    auto v = JuceEngine::get().getMasterCompressorMeter((int)effectIndex);
    return @[@(v[0]), @(v[1]), @(v[2]), @(v[3]), @(v[4])];
}

+ (double)getHostSampleRateObjC
{
    return JuceEngine::get().getHostSampleRate();
}

+ (NSArray<NSNumber*>*)getRowEqWaveformObjC:(NSInteger)row effectIndex:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount
{
    const auto v = JuceEngine::get().getRowEqWaveform((int)row, (int)effectIndex, (int)sampleCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}

+ (NSArray<NSNumber*>*)getMasterEqWaveformObjC:(NSInteger)effectIndex sampleCount:(NSInteger)sampleCount
{
    const auto v = JuceEngine::get().getMasterEqWaveform((int)effectIndex, (int)sampleCount);
    NSMutableArray<NSNumber*>* arr = [NSMutableArray arrayWithCapacity:v.size()];
    for (float s : v)
        [arr addObject:@(s)];
    return arr;
}


@end
