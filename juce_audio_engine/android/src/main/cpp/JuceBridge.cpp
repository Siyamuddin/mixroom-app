#define JUCE_GUI_BASICS_INCLUDE_ANDROID 1
#include "JuceEngine.h"
#include "JuceBridge.h"
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_core/native/juce_JNIHelpers_android.h>
#include <android/log.h>
#include <jni.h>

namespace juce
{
    extern const char *const juce_compilationDate = __DATE__;
    extern const char *const juce_compilationTime = __TIME__;
    jobject juceContext = nullptr;
    extern jobject androidApkContext;

    class AndroidMessageQueue
    {
    public:
        static AndroidMessageQueue *getInstance();
    };
}

// This mimics what JUCE does internally
void setJuceAndroidContext(JNIEnv *env, jobject context)
{
    if (context == nullptr)
    {
        __android_log_print(ANDROID_LOG_ERROR, "JUCE", "❌ Context is NULL!");
        return;
    }

    jclass contextClass = env->GetObjectClass(context);
    if (contextClass == nullptr)
    {
        __android_log_print(ANDROID_LOG_ERROR, "JUCE", "❌ Failed to get class of context object.");
        return;
    }

    juce::androidApkContext = env->NewGlobalRef(context);
    juce::juceContext = juce::androidApkContext;
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "✅ Global context set successfully.");
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAndroidContextJNI(JNIEnv *env, jclass, jobject context)
{
    setJuceAndroidContext(env, context);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_initialiseEngineJNI(JNIEnv *env, jclass)
{
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI initialiseEngineJNI called");
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI initialiseEngineJNI called3");
    // jobject context = JuceEngine::getAndroidContext();
    // if (context == nullptr) {
    //     __android_log_print(ANDROID_LOG_ERROR, "JUCE", "❌ Context is null in initialiseEngineJNI");
    //     return;
    // }

    // ✅ This is the correct call in recent JUCE versions
    // juce::Thread::initialiseJUCE(env, context);

    juce::JNIClassBase::initialiseAllClasses(env, juce::androidApkContext);
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI passed step1");
    // Fix: this must be called once before any audio code is used on Android
    static bool juceThreadInitialized = false;
    if (!juceThreadInitialized)
    {
        juce::Thread::initialiseJUCE(env, juce::juceContext); // context must be set first
        juceThreadInitialized = true;
    }
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI passed step2");
    JuceEngine::get().initialiseEngine();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_shutdownEngineJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().shutdownEngine(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_playJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().play(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_pauseJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().pause(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadTrackJNI(JNIEnv *env, jclass, jint idx, jstring path)
{
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI loadTrackJNI called");
    const char *c = env->GetStringUTFChars(path, nullptr);
    juce::String jucePath = juce::String::fromUTF8(c);
    env->ReleaseStringUTFChars(path, c);
    JuceEngine::get().loadTrack(idx, juce::File(jucePath));
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackJNI(JNIEnv *, jclass, jint trackIndex)
{
    juce::MessageManager::callAsync([trackIndex]
                                    { JuceEngine::get().removeTrack(trackIndex); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekJNI(JNIEnv *, jclass, jint trackIdx, jdouble pos)
{
    juce::MessageManager::callAsync([trackIdx, pos]
                                    { JuceEngine::get().seek(trackIdx, pos); });
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentPositionJNI(JNIEnv *, jclass, jint trackIdx)
{
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI getCurrentPositionJNI called");
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIdx, &result]
                                                  { result = JuceEngine::get().getCurrentPosition(trackIdx); });
    return result.load();
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackDurationJNI(JNIEnv *, jclass, jint trackIdx)
{
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI getTrackDurationJNI called short");
    std::atomic<double> result{0.0};
    juce::MessageManager::getInstance()->callSync([trackIdx, &result]
                                                  { result = JuceEngine::get().getTrackDuration(trackIdx); });
    return result.load();
    // double result = JuceEngine::get().getTrackDuration(trackIdx);
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "%f", result);
    // return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertEffectJNI(JNIEnv *env, jclass, jint track, jstring pluginPath)
{
    const char *c = env->GetStringUTFChars(pluginPath, nullptr);
    juce::String path = juce::String::fromUTF8(c);
    env->ReleaseStringUTFChars(pluginPath, c);
    JuceEngine::get().insertPluginEffect(track, path, [](bool) {});
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeEffectJNI(JNIEnv *, jclass, jint trackIdx, jint effectIdx)
{
    juce::MessageManager::callAsync([trackIdx, effectIdx]
                                    { JuceEngine::get().removePluginEffect(trackIdx, effectIdx); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsJNI(JNIEnv *env, jclass, jint trackIndex)
{
    juce::StringArray effects = JuceEngine::get().getTrackEffects(trackIndex);

    // Create a new Java ArrayList
    jclass arrayListClass = env->FindClass("java/util/ArrayList");
    jmethodID arrayListInit = env->GetMethodID(arrayListClass, "<init>", "()V");
    jobject arrayListObj = env->NewObject(arrayListClass, arrayListInit);

    jmethodID arrayListAdd = env->GetMethodID(arrayListClass, "add", "(Ljava/lang/Object;)Z");

    for (auto &effectName : effects)
    {
        jstring javaStr = env->NewStringUTF(effectName.toRawUTF8());
        env->CallBooleanMethod(arrayListObj, arrayListAdd, javaStr);
        env->DeleteLocalRef(javaStr);
    }

    return arrayListObj;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderEffectsJNI(JNIEnv *, jclass, jint trackIdx, jint fromIdx, jint toIdx)
{
    juce::MessageManager::callAsync([trackIdx, fromIdx, toIdx]
                                    { JuceEngine::get().reorderPluginEffects(trackIdx, fromIdx, toIdx); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassPluginJNI(JNIEnv *, jclass, jint trackIndex, jint effectIndex, jboolean shouldBypass)
{
    juce::MessageManager::callAsync([trackIndex, effectIndex, shouldBypass]
                                    { JuceEngine::get().bypassPlugin(trackIndex, effectIndex, shouldBypass != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassTrackJNI(JNIEnv *, jclass, jint trackIndex, jboolean shouldBypass)
{
    juce::MessageManager::callAsync([trackIndex, shouldBypass]
                                    { JuceEngine::get().bypassTrack(trackIndex, shouldBypass != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setEffectJNI(
    JNIEnv *env, jclass, jint trackIdx, jint pluginId, jstring paramId, jobject valueObj)
{
    // Convert paramId to juce::String
    const char *cParam = env->GetStringUTFChars(paramId, nullptr);
    juce::String paramStr = cParam ? juce::String::fromUTF8(cParam) : juce::String();
    env->ReleaseStringUTFChars(paramId, cParam);

    juce::var varValue;

    if (valueObj != nullptr)
    {
        jclass doubleClass = env->FindClass("java/lang/Double");
        jclass integerClass = env->FindClass("java/lang/Integer");
        jclass booleanClass = env->FindClass("java/lang/Boolean");
        jclass stringClass = env->FindClass("java/lang/String");

        if (env->IsInstanceOf(valueObj, doubleClass))
        {
            jmethodID doubleValue = env->GetMethodID(doubleClass, "doubleValue", "()D");
            jdouble val = env->CallDoubleMethod(valueObj, doubleValue);
            varValue = juce::var((double)val);
        }
        else if (env->IsInstanceOf(valueObj, integerClass))
        {
            jmethodID intValue = env->GetMethodID(integerClass, "intValue", "()I");
            jint val = env->CallIntMethod(valueObj, intValue);
            varValue = juce::var((int)val);
        }
        else if (env->IsInstanceOf(valueObj, booleanClass))
        {
            jmethodID boolValue = env->GetMethodID(booleanClass, "booleanValue", "()Z");
            jboolean val = env->CallBooleanMethod(valueObj, boolValue);
            varValue = juce::var((bool)(val == JNI_TRUE));
        }
        else if (env->IsInstanceOf(valueObj, stringClass))
        {
            const char *cStr = env->GetStringUTFChars((jstring)valueObj, nullptr);
            varValue = juce::var(juce::String::fromUTF8(cStr));
            env->ReleaseStringUTFChars((jstring)valueObj, cStr);
        }
    }

    juce::MessageManager::callAsync([trackIdx, pluginId, paramStr, varValue]
                                    { JuceEngine::get().setEffectParameter(trackIdx, pluginId, paramStr, varValue); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackVolumeJNI(JNIEnv *, jclass, jint track, jfloat volume)
{
    // __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI setTrackVolumeJNI called");
    juce::MessageManager::callAsync([track, volume]
                                    { JuceEngine::get().setTrackVolume(track, volume); });
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportMixJNI(JNIEnv *env, jclass, jstring outPath)
{
    const char *c = env->GetStringUTFChars(outPath, nullptr);
    juce::String jucePath(c);
    env->ReleaseStringUTFChars(outPath, c);
    juce::String result;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportMix(juce::File(jucePath)); });
    return env->NewStringUTF(result.toRawUTF8());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportTrackJNI(JNIEnv *env, jclass, jint trackIdx, jstring outPath)
{
    const char *c = env->GetStringUTFChars(outPath, nullptr);
    juce::String jucePath(c);
    env->ReleaseStringUTFChars(outPath, c);
    juce::String result;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportTrack(trackIdx, juce::File(jucePath)); });
    return env->NewStringUTF(result.toRawUTF8());
}

extern "C" JNIEXPORT bool JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginBypassStateJNI(JNIEnv *env, jclass, jint trackIndex, jint effectIndex)
{
    bool result;
    juce::MessageManager::getInstance()->callSync([trackIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getPluginBypassState((int)trackIndex, (int)effectIndex); });
    return result;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginParametersJNI(
    JNIEnv *env, jclass, jint trackIndex, jint effectIndex)
{
    jobject jList = nullptr;

    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        auto list = JuceEngine::get().getPluginParameterInfo((int)trackIndex, (int)effectIndex);

        jclass arrayListCls = env->FindClass("java/util/ArrayList");
        jmethodID arrayListCtor = env->GetMethodID(arrayListCls, "<init>", "()V");
        jmethodID arrayListAdd  = env->GetMethodID(arrayListCls, "add", "(Ljava/lang/Object;)Z");
        jList = env->NewObject(arrayListCls, arrayListCtor);

        jclass hashMapCls = env->FindClass("java/util/HashMap");
        jmethodID hashMapCtor = env->GetMethodID(hashMapCls, "<init>", "()V");
        jmethodID hashMapPut  = env->GetMethodID(hashMapCls, "put",
                                   "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

        jclass floatCls  = env->FindClass("java/lang/Float");
        jmethodID floatCtor = env->GetMethodID(floatCls, "<init>", "(F)V");
        jclass boolCls   = env->FindClass("java/lang/Boolean");
        jmethodID boolCtor  = env->GetMethodID(boolCls, "<init>", "(Z)V");

        auto jstr = [&](const juce::String& s)->jstring {
            return env->NewStringUTF(s.toRawUTF8());
        };
        auto putStr = [&](jobject map, const char* k, const juce::String& s){
            jstring jk = env->NewStringUTF(k);
            jstring jv = jstr(s);
            env->CallObjectMethod(map, hashMapPut, jk, jv);
            env->DeleteLocalRef(jk);
            env->DeleteLocalRef(jv);
        };
        auto putFloat = [&](jobject map, const char* k, float v){
            jstring jk = env->NewStringUTF(k);
            jobject jv = env->NewObject(floatCls, floatCtor, v);
            env->CallObjectMethod(map, hashMapPut, jk, jv);
            env->DeleteLocalRef(jk);
            env->DeleteLocalRef(jv);
        };
        auto putBool = [&](jobject map, const char* k, bool v){
            jstring jk = env->NewStringUTF(k);
            jobject jv = env->NewObject(boolCls, boolCtor, (jboolean)v);
            env->CallObjectMethod(map, hashMapPut, jk, jv);
            env->DeleteLocalRef(jk);
            env->DeleteLocalRef(jv);
        };
        auto putVar = [&](jobject map, const char* k, const juce::var& v){
            jstring jk = env->NewStringUTF(k);
            jobject jv = nullptr;
            if (v.isBool()) {
                jv = env->NewObject(boolCls, boolCtor, (jboolean)(bool)v);
            } else if (v.isDouble() || v.isInt()) {
                jv = env->NewObject(floatCls, floatCtor, (jfloat)(double)v);
            } else {
                juce::String s = v.toString();
                jv = jstr(s);
            }
            env->CallObjectMethod(map, hashMapPut, jk, jv);
            env->DeleteLocalRef(jk);
            env->DeleteLocalRef(jv);
        };

        for (auto& e : list)
        {
            jobject map = env->NewObject(hashMapCls, hashMapCtor);

            // Required fields
            putStr(map, "id",   e["id"].toString());
            putStr(map, "name", e["name"].toString());
            putStr(map, "type", e["type"].toString());

            // Optional numerics
            if (e.contains("min"))     putFloat(map, "min",     (float)e["min"]);
            if (e.contains("max"))     putFloat(map, "max",     (float)e["max"]);

            // defaultValue and current value (type‑aware)
            if (e.contains("default")) putVar  (map, "defaultValue", e["default"]);
            if (e.contains("value"))   putVar  (map, "value",        e["value"]);

            // choice_0, choice_1, ...
            for (int i = 0; ; ++i) {
                juce::String key = "choice_" + juce::String(i);
                if (!e.contains(key)) break;
                putStr(map, key.toRawUTF8(), e[key].toString());
            }

            env->CallBooleanMethod(jList, arrayListAdd, map);
            env->DeleteLocalRef(map);
        } });

    return jList;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getAvailablePluginsJNI(JNIEnv *env, jclass)
{
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI getAvailablePluginsJNI called");
    jobject jList;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        auto pluginPaths = JuceEngine::get().getKnownPlugins();

        jclass listClass = env->FindClass("java/util/ArrayList");
        jmethodID init   = env->GetMethodID(listClass, "<init>", "()V");
        jmethodID add    = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");
        jList            = env->NewObject(listClass, init);

        jclass mapClass  = env->FindClass("java/util/HashMap");
        jmethodID mapInit = env->GetMethodID(mapClass, "<init>", "()V");
        jmethodID put    = env->GetMethodID(mapClass, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

        for (const auto& plugin : pluginPaths) {
            jobject map = env->NewObject(mapClass, mapInit);
            env->CallObjectMethod(map, put, env->NewStringUTF("id"),   env->NewStringUTF(juce::String(plugin.uniqueId).toRawUTF8()));
            env->CallObjectMethod(map, put, env->NewStringUTF("name"), env->NewStringUTF(plugin.name.toRawUTF8()));
            env->CallObjectMethod(map, put, env->NewStringUTF("path"), env->NewStringUTF(plugin.fileOrIdentifier.toRawUTF8()));
            env->CallBooleanMethod(jList, add, map);
            env->DeleteLocalRef(map);
        } });
    return jList;
}

// "video audio" lane
extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadVideoAudioJNI(JNIEnv *env, jclass, jstring path)
{
    const char *c = env->GetStringUTFChars(path, nullptr);
    juce::String jucePath = juce::String::fromUTF8(c);
    env->ReleaseStringUTFChars(path, c);

    juce::MessageManager::callAsync([jucePath]
                                    { JuceEngine::get().loadVideoAudio(juce::File(jucePath)); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadVideoAudioJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().unloadVideoAudio(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setVideoAudioGainJNI(JNIEnv *, jclass, jfloat gain)
{
    juce::MessageManager::callAsync([gain]
                                    { JuceEngine::get().setVideoAudioGain((float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekVideoAudioJNI(JNIEnv *, jclass, jdouble seconds)
{
    juce::MessageManager::callAsync([seconds]
                                    { JuceEngine::get().seekVideoAudio((double)seconds); });
}
