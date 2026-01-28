#include <float.h>
#import "JuceBridge.h"
#import "JuceEngine.h"
#include "JuceHeader.h"
#import "JuceAudioEnginePlugin.h" // To access debugLogChannel

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

// DEPRECATED: use loadClipObjC:rowIndex:path: instead
+ (void)loadTrackObjC:(NSInteger)idx path:(NSString *)path
{

    // [[JuceAudioEnginePlugin sharedInstance] sendFlutterLog:@"✅ Objective-C: Entering loadTrackObjC"];

    // juce::String jucePath([path UTF8String]);
    // juce::MessageManager::callAsync([idx, jucePath] {
    //     JuceEngine::get().loadTrack((int)idx, juce::File(jucePath));
    // });
    juce::String jucePath = juce::String::fromUTF8([path UTF8String]);

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
    auto names = JuceEngine::get().getTrackEffects(trackIndex);
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
    juce::String jucePath([pluginPath UTF8String]);

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
        newVal = juce::String([(NSString *)value UTF8String]);
    }

    juce::String juceParam([param UTF8String]);
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

+ (NSString *)exportMixObjC:(NSString *)outPath
{
    juce::String jucePath([outPath UTF8String]);
    juce::String result;

    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportMix(juce::File(jucePath)); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (NSString *)exportTrackObjC:(NSInteger)track outPath:(NSString *)outPath
{
    juce::String result;
    juce::String jucePath([outPath UTF8String]);

    juce::MessageManager::getInstance()->callSync([track, jucePath, &result]
                                                  { result = JuceEngine::get().exportTrack((int)track, juce::File(jucePath)); });

    return [NSString stringWithUTF8String:result.toRawUTF8()];
}

+ (NSArray<NSDictionary *> *)scanPluginsObjC
{
    // plain Obj-C pointer, no __block needed
    NSMutableArray *resultArray = nil;

    // This lambda is a C++ std::function, so capturing a C++ local by reference works fine
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        NSMutableArray* arr = [NSMutableArray array];
        auto types = JuceEngine::get().getKnownPlugins();
        for (auto& desc : types) {
            NSString* name = [NSString stringWithUTF8String:desc.name.toRawUTF8()] ?: @"";
            NSString* ident = [NSString stringWithUTF8String:desc.fileOrIdentifier.toRawUTF8()] ?: @"";
            [arr addObject:@{ @"name": name, @"id": ident }];
        }
        resultArray = [arr copy]; });

    return resultArray;
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
    juce::String jucePath([path UTF8String]);
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
    juce::String juceTitle([title UTF8String]);
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
            rowIndex:(NSInteger)rowIndex
                path:(NSString *)path
{
    juce::String jucePath = juce::String::fromUTF8([path UTF8String]);
    // Call directly, like loadTrackObjC
    JuceEngine::get().loadClip((int)clipIndex, (int)rowIndex, juce::File(jucePath));
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

+ (void)moveClipToRowObjC:(NSInteger)clipIndex newRow:(NSInteger)newRow
{
    juce::MessageManager::callAsync([clipIndex, newRow]
                                    { JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRow); });
}

#pragma mark - Row (track bus) FX and controls

+ (void)insertTrackEffectObjC:(NSInteger)trackRow path:(NSString *)pluginPath
{
    juce::String jucePath([pluginPath UTF8String]);

    JuceEngine::get().insertTrackEffect(
        (int)trackRow,
        jucePath,
        [trackRow, pluginPath](bool success)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCERowEffectLoaded"
                                                                object:nil
                                                              userInfo:@{
                                                                  @"event" : @"rowEffectLoaded",
                                                                  @"row" : @(trackRow),
                                                                  @"path" : pluginPath,
                                                                  @"success" : @(success)
                                                              }];
        });
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
        newVal = juce::String([(NSString *)value UTF8String]);
    }

    juce::String juceParam([param UTF8String]);
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

+ (void)insertMasterEffectObjC:(NSString *)pluginPath
{
    juce::String jucePath([pluginPath UTF8String]);

    JuceEngine::get().insertMasterEffect(
        jucePath,
        [pluginPath](bool success)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"JUCEMasterEffectLoaded"
                                                                object:nil
                                                              userInfo:@{
                                                                  @"event" : @"masterEffectLoaded",
                                                                  @"path" : pluginPath,
                                                                  @"success" : @(success)
                                                              }];
        });
}

+ (void)removeMasterEffectObjC:(NSInteger)effectIndex
{
    juce::MessageManager::callAsync([effectIndex]
                                    { JuceEngine::get().removeMasterEffect((int)effectIndex); });
}

+ (void)reorderMasterEffectsObjC:(NSInteger)fromIndex
                         toIndex:(NSInteger)toIndex
{
    juce::MessageManager::callAsync([fromIndex, toIndex]
                                    { JuceEngine::get().reorderMasterEffects((int)fromIndex, (int)toIndex); });
}

+ (NSArray<NSString *> *)getMasterEffectsObjC
{
    NSMutableArray *out = [NSMutableArray array];
    if (auto chainNames = JuceEngine::get().getMasterEffects(); true)
    {
        for (auto &s : chainNames)
        {
            [out addObject:[NSString stringWithUTF8String:s.toRawUTF8()]];
        }
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
        newVal = juce::String([(NSString *)value UTF8String]);
    }

    juce::String juceParam([param UTF8String]);
    juce::MessageManager::callAsync([effectIndex, juceParam, newVal]
                                    { JuceEngine::get().setMasterEffectParameter((int)effectIndex, juceParam, newVal); });
}

+ (void)bypassMasterEffectObjC:(NSInteger)effectIndex
                        bypass:(BOOL)shouldBypass
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
    juce::File file([path UTF8String]);

    auto samples = JuceEngine::get().decodeAudioMono16k(file);

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:samples.size()];
    for (float v : samples)
    {
        [arr addObject:@(v)];
    }
    return arr;
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
    juce::String dev([name UTF8String]);
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
    // juce::File f(juce::String([path UTF8String]));
    juce::String jucePath = juce::String::fromUTF8([path UTF8String]);
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

@end
