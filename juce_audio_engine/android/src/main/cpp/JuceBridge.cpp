#define JUCE_GUI_BASICS_INCLUDE_ANDROID 1
#include "JuceEngine.h"
#include "JuceBridge.h"
#include "InstrumentRenderers.h"
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_core/native/juce_JNIHelpers_android.h>
#include <android/log.h>
#include <jni.h>
#include <array>
#include <vector>

namespace
{
juce::String juceStringFromJString(JNIEnv *env, jstring value)
{
    if (value == nullptr)
        return {};
    const char *chars = env->GetStringUTFChars(value, nullptr);
    juce::String out = chars != nullptr ? juce::String::fromUTF8(chars) : juce::String();
    env->ReleaseStringUTFChars(value, chars);
    return out;
}

double javaObjectToDouble(JNIEnv *env, jobject value, double fallback = 0.0)
{
    if (value == nullptr)
        return fallback;

    jclass numberClass = env->FindClass("java/lang/Number");
    if (env->IsInstanceOf(value, numberClass))
    {
        jmethodID toDouble = env->GetMethodID(numberClass, "doubleValue", "()D");
        return env->CallDoubleMethod(value, toDouble);
    }

    jclass stringClass = env->FindClass("java/lang/String");
    if (env->IsInstanceOf(value, stringClass))
    {
        juce::String s = juceStringFromJString(env, (jstring)value);
        const double parsed = s.getDoubleValue();
        return std::isfinite(parsed) ? parsed : fallback;
    }
    return fallback;
}

int javaObjectToInt(JNIEnv *env, jobject value, int fallback = 0)
{
    if (value == nullptr)
        return fallback;

    jclass numberClass = env->FindClass("java/lang/Number");
    if (env->IsInstanceOf(value, numberClass))
    {
        jmethodID toInt = env->GetMethodID(numberClass, "intValue", "()I");
        return env->CallIntMethod(value, toInt);
    }

    jclass stringClass = env->FindClass("java/lang/String");
    if (env->IsInstanceOf(value, stringClass))
    {
        juce::String s = juceStringFromJString(env, (jstring)value);
        return s.getIntValue();
    }
    return fallback;
}

juce::Array<TimelineMidiNote> parseTimelineMidiNotes(JNIEnv *env, jobject notesList)
{
    juce::Array<TimelineMidiNote> out;
    if (notesList == nullptr)
        return out;

    jclass listClass = env->FindClass("java/util/List");
    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");

    jclass mapClass = env->FindClass("java/util/Map");
    jmethodID mapGet = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
    jclass stringClass = env->FindClass("java/lang/String");

    const jint count = env->CallIntMethod(notesList, sizeMethod);
    out.ensureStorageAllocated((int)count);

    jstring keyId = env->NewStringUTF("id");
    jstring keyPitch = env->NewStringUTF("pitch");
    jstring keyStartBeat = env->NewStringUTF("startBeat");
    jstring keyLengthBeats = env->NewStringUTF("lengthBeats");
    jstring keyVelocity = env->NewStringUTF("velocity");

    for (jint i = 0; i < count; ++i)
    {
        jobject entry = env->CallObjectMethod(notesList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        TimelineMidiNote note;
        jobject idObj = env->CallObjectMethod(entry, mapGet, keyId);
        jobject pitchObj = env->CallObjectMethod(entry, mapGet, keyPitch);
        jobject startObj = env->CallObjectMethod(entry, mapGet, keyStartBeat);
        jobject lengthObj = env->CallObjectMethod(entry, mapGet, keyLengthBeats);
        jobject velocityObj = env->CallObjectMethod(entry, mapGet, keyVelocity);

        if (idObj != nullptr && env->IsInstanceOf(idObj, stringClass))
            note.noteId = juceStringFromJString(env, (jstring)idObj);
        note.pitch = juce::jlimit(0, 127, javaObjectToInt(env, pitchObj, 60));
        note.startBeat = juce::jmax(0.0, javaObjectToDouble(env, startObj, 0.0));
        note.lengthBeats = juce::jmax(0.03125, javaObjectToDouble(env, lengthObj, 1.0));
        note.velocity = juce::jlimit(0.0, 1.0, javaObjectToDouble(env, velocityObj, 0.8));
        out.add(note);

        if (idObj != nullptr)
            env->DeleteLocalRef(idObj);
        if (pitchObj != nullptr)
            env->DeleteLocalRef(pitchObj);
        if (startObj != nullptr)
            env->DeleteLocalRef(startObj);
        if (lengthObj != nullptr)
            env->DeleteLocalRef(lengthObj);
        if (velocityObj != nullptr)
            env->DeleteLocalRef(velocityObj);
        env->DeleteLocalRef(entry);
    }

    env->DeleteLocalRef(keyId);
    env->DeleteLocalRef(keyPitch);
    env->DeleteLocalRef(keyStartBeat);
    env->DeleteLocalRef(keyLengthBeats);
    env->DeleteLocalRef(keyVelocity);
    return out;
}

juce::NamedValueSet parseNamedValueSet(JNIEnv *env, jobject paramsMap)
{
    juce::NamedValueSet out;
    if (paramsMap == nullptr)
        return out;

    jclass mapClass = env->FindClass("java/util/Map");
    if (!env->IsInstanceOf(paramsMap, mapClass))
        return out;

    jmethodID entrySetMethod = env->GetMethodID(mapClass, "entrySet", "()Ljava/util/Set;");
    jobject entrySet = env->CallObjectMethod(paramsMap, entrySetMethod);
    if (entrySet == nullptr)
        return out;

    jclass setClass = env->FindClass("java/util/Set");
    jmethodID iteratorMethod = env->GetMethodID(setClass, "iterator", "()Ljava/util/Iterator;");
    jobject iterator = env->CallObjectMethod(entrySet, iteratorMethod);
    if (iterator == nullptr)
    {
        env->DeleteLocalRef(entrySet);
        return out;
    }

    jclass iteratorClass = env->FindClass("java/util/Iterator");
    jmethodID hasNextMethod = env->GetMethodID(iteratorClass, "hasNext", "()Z");
    jmethodID nextMethod = env->GetMethodID(iteratorClass, "next", "()Ljava/lang/Object;");

    jclass entryClass = env->FindClass("java/util/Map$Entry");
    jmethodID getKeyMethod = env->GetMethodID(entryClass, "getKey", "()Ljava/lang/Object;");
    jmethodID getValueMethod = env->GetMethodID(entryClass, "getValue", "()Ljava/lang/Object;");

    jclass stringClass = env->FindClass("java/lang/String");

    while (env->CallBooleanMethod(iterator, hasNextMethod))
    {
        jobject entry = env->CallObjectMethod(iterator, nextMethod);
        if (entry == nullptr || !env->IsInstanceOf(entry, entryClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        jobject keyObj = env->CallObjectMethod(entry, getKeyMethod);
        jobject valueObj = env->CallObjectMethod(entry, getValueMethod);

        if (keyObj != nullptr && valueObj != nullptr && env->IsInstanceOf(keyObj, stringClass))
        {
            const juce::String key = juceStringFromJString(env, (jstring)keyObj);
            const double value = javaObjectToDouble(env, valueObj, 0.0);
            out.set(juce::Identifier(key), juce::var(value));
        }

        if (keyObj != nullptr)
            env->DeleteLocalRef(keyObj);
        if (valueObj != nullptr)
            env->DeleteLocalRef(valueObj);
        env->DeleteLocalRef(entry);
    }

    env->DeleteLocalRef(iterator);
    env->DeleteLocalRef(entrySet);
    return out;
}

juce::var javaObjectToVar(JNIEnv *env, jobject valueObj)
{
    if (valueObj == nullptr)
        return {};

    jclass doubleClass = env->FindClass("java/lang/Double");
    jclass integerClass = env->FindClass("java/lang/Integer");
    jclass longClass = env->FindClass("java/lang/Long");
    jclass floatClass = env->FindClass("java/lang/Float");
    jclass booleanClass = env->FindClass("java/lang/Boolean");
    jclass stringClass = env->FindClass("java/lang/String");

    if (env->IsInstanceOf(valueObj, doubleClass))
    {
        jmethodID doubleValue = env->GetMethodID(doubleClass, "doubleValue", "()D");
        return juce::var((double)env->CallDoubleMethod(valueObj, doubleValue));
    }
    if (env->IsInstanceOf(valueObj, integerClass))
    {
        jmethodID intValue = env->GetMethodID(integerClass, "intValue", "()I");
        return juce::var((int)env->CallIntMethod(valueObj, intValue));
    }
    if (env->IsInstanceOf(valueObj, longClass))
    {
        jmethodID longValue = env->GetMethodID(longClass, "longValue", "()J");
        return juce::var((juce::int64)env->CallLongMethod(valueObj, longValue));
    }
    if (env->IsInstanceOf(valueObj, floatClass))
    {
        jmethodID floatValue = env->GetMethodID(floatClass, "floatValue", "()F");
        return juce::var((double)env->CallFloatMethod(valueObj, floatValue));
    }
    if (env->IsInstanceOf(valueObj, booleanClass))
    {
        jmethodID boolValue = env->GetMethodID(booleanClass, "booleanValue", "()Z");
        return juce::var((bool)(env->CallBooleanMethod(valueObj, boolValue) == JNI_TRUE));
    }
    if (env->IsInstanceOf(valueObj, stringClass))
    {
        return juce::var(juceStringFromJString(env, (jstring)valueObj));
    }

    return {};
}

std::vector<AutomationPoint> parseAutomationPoints(JNIEnv *env, jobject pointsList, float maxValue = 3.0f)
{
    std::vector<AutomationPoint> out;
    if (pointsList == nullptr)
        return out;

    jclass listClass = env->FindClass("java/util/List");
    if (!env->IsInstanceOf(pointsList, listClass))
        return out;

    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");

    jclass mapClass = env->FindClass("java/util/Map");
    jmethodID mapGet = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");

    const jint count = env->CallIntMethod(pointsList, sizeMethod);
    out.reserve((size_t)count);

    jstring keyX = env->NewStringUTF("x");
    jstring keyTimeSeconds = env->NewStringUTF("timeSeconds");
    jstring keyTimeMs = env->NewStringUTF("timeMs");
    jstring keyVolume = env->NewStringUTF("volume");
    jstring keyValue = env->NewStringUTF("value");

    for (jint i = 0; i < count; ++i)
    {
        jobject entry = env->CallObjectMethod(pointsList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        jobject xObj = env->CallObjectMethod(entry, mapGet, keyX);
        jobject timeSecondsObj = env->CallObjectMethod(entry, mapGet, keyTimeSeconds);
        jobject timeMsObj = env->CallObjectMethod(entry, mapGet, keyTimeMs);
        jobject volumeObj = env->CallObjectMethod(entry, mapGet, keyVolume);
        jobject valueObj = env->CallObjectMethod(entry, mapGet, keyValue);

        double timeMs = 0.0;
        if (xObj != nullptr)
            timeMs = javaObjectToDouble(env, xObj, 0.0);
        else if (timeSecondsObj != nullptr)
            timeMs = javaObjectToDouble(env, timeSecondsObj, 0.0) * 1000.0;
        else if (timeMsObj != nullptr)
            timeMs = javaObjectToDouble(env, timeMsObj, 0.0);

        float value = 1.0f;
        if (valueObj != nullptr)
            value = (float)javaObjectToDouble(env, valueObj, 1.0);
        else if (volumeObj != nullptr)
            value = (float)javaObjectToDouble(env, volumeObj, 1.0);

        AutomationPoint point;
        point.timeMs = juce::jmax(0.0, timeMs);
        point.value = juce::jlimit(0.0f, maxValue, value);
        out.push_back(point);

        if (xObj != nullptr)
            env->DeleteLocalRef(xObj);
        if (timeSecondsObj != nullptr)
            env->DeleteLocalRef(timeSecondsObj);
        if (timeMsObj != nullptr)
            env->DeleteLocalRef(timeMsObj);
        if (volumeObj != nullptr)
            env->DeleteLocalRef(volumeObj);
        if (valueObj != nullptr)
            env->DeleteLocalRef(valueObj);
        env->DeleteLocalRef(entry);
    }

    env->DeleteLocalRef(keyX);
    env->DeleteLocalRef(keyTimeSeconds);
    env->DeleteLocalRef(keyTimeMs);
    env->DeleteLocalRef(keyVolume);
    env->DeleteLocalRef(keyValue);
    return out;
}

juce::Array<mixroom::instruments::MidiRenderNote> parseMidiRenderNotes(JNIEnv *env, jobject notesList)
{
    juce::Array<mixroom::instruments::MidiRenderNote> out;
    if (notesList == nullptr)
        return out;

    jclass listClass = env->FindClass("java/util/List");
    if (!env->IsInstanceOf(notesList, listClass))
        return out;

    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");

    jclass mapClass = env->FindClass("java/util/Map");
    jmethodID mapGet = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");

    const jint count = env->CallIntMethod(notesList, sizeMethod);
    out.ensureStorageAllocated((int)count);

    jstring keyPitch = env->NewStringUTF("pitch");
    jstring keyStartBeat = env->NewStringUTF("startBeat");
    jstring keyLengthBeats = env->NewStringUTF("lengthBeats");
    jstring keyVelocity = env->NewStringUTF("velocity");

    for (jint i = 0; i < count; ++i)
    {
        jobject entry = env->CallObjectMethod(notesList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        jobject pitchObj = env->CallObjectMethod(entry, mapGet, keyPitch);
        jobject startObj = env->CallObjectMethod(entry, mapGet, keyStartBeat);
        jobject lengthObj = env->CallObjectMethod(entry, mapGet, keyLengthBeats);
        jobject velocityObj = env->CallObjectMethod(entry, mapGet, keyVelocity);

        mixroom::instruments::MidiRenderNote note;
        note.pitch = juce::jlimit(0, 127, javaObjectToInt(env, pitchObj, 60));
        note.startBeat = juce::jmax(0.0, javaObjectToDouble(env, startObj, 0.0));
        note.lengthBeats = juce::jmax(0.03125, javaObjectToDouble(env, lengthObj, 1.0));
        note.velocity = juce::jlimit(0.0, 1.0, javaObjectToDouble(env, velocityObj, 0.8));
        out.add(note);

        if (pitchObj != nullptr)
            env->DeleteLocalRef(pitchObj);
        if (startObj != nullptr)
            env->DeleteLocalRef(startObj);
        if (lengthObj != nullptr)
            env->DeleteLocalRef(lengthObj);
        if (velocityObj != nullptr)
            env->DeleteLocalRef(velocityObj);
        env->DeleteLocalRef(entry);
    }

    env->DeleteLocalRef(keyPitch);
    env->DeleteLocalRef(keyStartBeat);
    env->DeleteLocalRef(keyLengthBeats);
    env->DeleteLocalRef(keyVelocity);
    return out;
}

jobject stringArrayToJavaList(JNIEnv *env, const juce::StringArray &strings)
{
    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listClass, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");
    jobject list = env->NewObject(listClass, listCtor);

    for (const auto &s : strings)
    {
        jstring js = env->NewStringUTF(s.toRawUTF8());
        env->CallBooleanMethod(list, listAdd, js);
        env->DeleteLocalRef(js);
    }

    return list;
}

jdoubleArray floatVectorToJDoubleArray(JNIEnv *env, const std::vector<float> &values)
{
    const auto size = (jsize)values.size();
    jdoubleArray out = env->NewDoubleArray(size);
    if (size == 0)
        return out;

    std::vector<jdouble> tmp((size_t)size, 0.0);
    for (jsize i = 0; i < size; ++i)
        tmp[(size_t)i] = (jdouble)values[(size_t)i];
    env->SetDoubleArrayRegion(out, 0, size, tmp.data());
    return out;
}

template <size_t N>
jdoubleArray floatArrayToJDoubleArray(JNIEnv *env, const std::array<float, N> &values)
{
    jdouble tmp[N] = {};
    for (size_t i = 0; i < N; ++i)
        tmp[i] = (jdouble)values[i];
    jdoubleArray out = env->NewDoubleArray((jsize)N);
    env->SetDoubleArrayRegion(out, 0, (jsize)N, tmp);
    return out;
}

jobject namedValueSetArrayToJavaParameterList(JNIEnv *env, const juce::Array<juce::NamedValueSet> &list)
{
    jclass arrayListCls = env->FindClass("java/util/ArrayList");
    jmethodID arrayListCtor = env->GetMethodID(arrayListCls, "<init>", "()V");
    jmethodID arrayListAdd = env->GetMethodID(arrayListCls, "add", "(Ljava/lang/Object;)Z");
    jobject jList = env->NewObject(arrayListCls, arrayListCtor);

    jclass hashMapCls = env->FindClass("java/util/HashMap");
    jmethodID hashMapCtor = env->GetMethodID(hashMapCls, "<init>", "()V");
    jmethodID hashMapPut = env->GetMethodID(hashMapCls, "put",
                                            "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass floatCls = env->FindClass("java/lang/Float");
    jmethodID floatCtor = env->GetMethodID(floatCls, "<init>", "(F)V");
    jclass boolCls = env->FindClass("java/lang/Boolean");
    jmethodID boolCtor = env->GetMethodID(boolCls, "<init>", "(Z)V");

    auto jstr = [&](const juce::String &s) -> jstring
    { return env->NewStringUTF(s.toRawUTF8()); };

    auto putStr = [&](jobject map, const char *k, const juce::String &s)
    {
        jstring jk = env->NewStringUTF(k);
        jstring jv = jstr(s);
        env->CallObjectMethod(map, hashMapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    auto putFloat = [&](jobject map, const char *k, float v)
    {
        jstring jk = env->NewStringUTF(k);
        jobject jv = env->NewObject(floatCls, floatCtor, v);
        env->CallObjectMethod(map, hashMapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    auto putVar = [&](jobject map, const char *k, const juce::var &v)
    {
        jstring jk = env->NewStringUTF(k);
        jobject jv = nullptr;
        if (v.isBool())
        {
            jv = env->NewObject(boolCls, boolCtor, (jboolean)((bool)v));
        }
        else if (v.isDouble() || v.isInt() || v.isInt64())
        {
            jv = env->NewObject(floatCls, floatCtor, (jfloat)(double)v);
        }
        else
        {
            juce::String s = v.toString();
            jv = jstr(s);
        }
        env->CallObjectMethod(map, hashMapPut, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    for (const auto &entry : list)
    {
        jobject map = env->NewObject(hashMapCls, hashMapCtor);
        putStr(map, "id", entry["id"].toString());
        putStr(map, "name", entry["name"].toString());
        putStr(map, "type", entry["type"].toString());

        if (entry.contains("min"))
            putFloat(map, "min", (float)entry["min"]);
        if (entry.contains("max"))
            putFloat(map, "max", (float)entry["max"]);
        if (entry.contains("default"))
            putVar(map, "defaultValue", entry["default"]);
        if (entry.contains("value"))
            putVar(map, "value", entry["value"]);

        for (int i = 0;; ++i)
        {
            juce::String key = "choice_" + juce::String(i);
            if (!entry.contains(key))
                break;
            putStr(map, key.toRawUTF8(), entry[key].toString());
        }

        env->CallBooleanMethod(jList, arrayListAdd, map);
        env->DeleteLocalRef(map);
    }

    return jList;
}

jobject rowsToJavaList(JNIEnv *env, const juce::Array<juce::NamedValueSet> &rows)
{
    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listClass, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");
    jobject outList = env->NewObject(listClass, listCtor);

    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapCtor = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
                                        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID intCtor = env->GetMethodID(intCls, "<init>", "(I)V");

    for (const auto &row : rows)
    {
        jobject map = env->NewObject(mapClass, mapCtor);

        jstring keyRowId = env->NewStringUTF("rowId");
        jobject valRowId = env->NewObject(intCls, intCtor, (jint)(int)row["rowId"]);
        env->CallObjectMethod(map, mapPut, keyRowId, valRowId);
        env->DeleteLocalRef(keyRowId);
        env->DeleteLocalRef(valRowId);

        jstring keyName = env->NewStringUTF("name");
        jstring valName = env->NewStringUTF(row["name"].toString().toRawUTF8());
        env->CallObjectMethod(map, mapPut, keyName, valName);
        env->DeleteLocalRef(keyName);
        env->DeleteLocalRef(valName);

        jstring keyIcon = env->NewStringUTF("iconId");
        jobject valIcon = env->NewObject(intCls, intCtor, (jint)(int)row["iconId"]);
        env->CallObjectMethod(map, mapPut, keyIcon, valIcon);
        env->DeleteLocalRef(keyIcon);
        env->DeleteLocalRef(valIcon);

        env->CallBooleanMethod(outList, listAdd, map);
        env->DeleteLocalRef(map);
    }

    return outList;
}

jobject namedValueStatsToJavaMap(JNIEnv *env, const juce::NamedValueSet &stats)
{
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapCtor = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
                                        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject outMap = env->NewObject(mapClass, mapCtor);

    jclass doubleCls = env->FindClass("java/lang/Double");
    jmethodID doubleCtor = env->GetMethodID(doubleCls, "<init>", "(D)V");

    auto putDouble = [&](const char *key, double value)
    {
        jstring jKey = env->NewStringUTF(key);
        jobject jValue = env->NewObject(doubleCls, doubleCtor, (jdouble)value);
        env->CallObjectMethod(outMap, mapPut, jKey, jValue);
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(jValue);
    };

    putDouble("phase_corr", stats.getWithDefault("phase_corr", 1.0));
    putDouble("side_ratio", stats.getWithDefault("side_ratio", 0.0));
    putDouble("stereo_imbalance", stats.getWithDefault("stereo_imbalance", 0.0));
    return outMap;
}
} // namespace

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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setFlutterAssetRootJNI(JNIEnv *env, jclass, jstring rootPath)
{
    juce::ignoreUnused(env, rootPath);
    // iOS-derived engine resolves Flutter assets from standard app locations.
    // Keep this JNI method for ABI compatibility with Kotlin call sites.
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
    static bool juceGuiInitialized = false;
    if (!juceGuiInitialized)
    {
        juce::initialiseJuce_GUI();
        juceGuiInitialized = true;
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
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([]
                     { JuceEngine::get().play(); });
        return;
    }
    JuceEngine::get().play();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_pauseJNI(JNIEnv *, jclass)
{
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([]
                     { JuceEngine::get().pause(); });
        return;
    }
    JuceEngine::get().pause();
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

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipTimeJNI(JNIEnv *, jclass, jint clipIndex, jdouble startSec, jdouble lengthSec, jdouble inFileOffsetSec)
{
    juce::MessageManager::callAsync([clipIndex, startSec, lengthSec, inFileOffsetSec]
                                    { JuceEngine::get().setClipTime((int)clipIndex, (double)startSec, (double)lengthSec, (double)inFileOffsetSec); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPanJNI(JNIEnv *, jclass, jint clipIndex, jfloat pan)
{
    juce::MessageManager::callAsync([clipIndex, pan]
                                    { JuceEngine::get().setClipPan((int)clipIndex, (float)pan); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPitchJNI(JNIEnv *, jclass, jint clipIndex, jfloat semitones)
{
    juce::MessageManager::callAsync([clipIndex, semitones]
                                    { JuceEngine::get().setClipPitch((int)clipIndex, (float)semitones); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipReversedJNI(JNIEnv *, jclass, jint clipIndex, jboolean reversed)
{
    juce::MessageManager::callAsync([clipIndex, reversed]
                                    { JuceEngine::get().setClipReversed((int)clipIndex, reversed != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipStretchOptionsJNI(JNIEnv *, jclass, jint clipIndex, jdouble tempoRatio, jboolean preservePitch)
{
    juce::MessageManager::callAsync([clipIndex, tempoRatio, preservePitch]
                                    { JuceEngine::get().setClipStretchOptions((int)clipIndex, (double)tempoRatio, preservePitch != JNI_FALSE); });
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

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_supportsLiveMidiClipPlaybackJNI(JNIEnv *, jclass)
{
    std::atomic<bool> result{false};
    juce::MessageManager::getInstance()->callSync([&result]
                                                  { result = JuceEngine::get().supportsLiveMidiClipPlayback(); });
    return result.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadMidiClipJNI(JNIEnv *env,
                                                                 jclass,
                                                                 jint clipIndex,
                                                                 jint rowId,
                                                                 jstring instrumentId,
                                                                 jstring instrumentName,
                                                                 jobject notesList,
                                                                 jobject paramsMap,
                                                                 jdouble sourceTempoBpm,
                                                                 jdouble startSec,
                                                                 jdouble lengthSec,
                                                                 jdouble inFileOffsetSec)
{
    const juce::String id = juceStringFromJString(env, instrumentId);
    const juce::String name = juceStringFromJString(env, instrumentName);
    const auto notes = parseTimelineMidiNotes(env, notesList);
    const auto params = parseNamedValueSet(env, paramsMap);

    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().loadMidiClip(
            (int)clipIndex,
            (int)rowId,
            id,
            name,
            notes,
            params,
            (double)sourceTempoBpm,
            (double)startSec,
            (double)lengthSec,
            (double)inFileOffsetSec); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_updateMidiClipEventsJNI(JNIEnv *env,
                                                                         jclass,
                                                                         jint clipIndex,
                                                                         jstring instrumentId,
                                                                         jstring instrumentName,
                                                                         jobject notesList,
                                                                         jobject paramsMap,
                                                                         jdouble sourceTempoBpm)
{
    const juce::String id = juceStringFromJString(env, instrumentId);
    const juce::String name = juceStringFromJString(env, instrumentName);
    const auto notes = parseTimelineMidiNotes(env, notesList);
    const auto params = parseNamedValueSet(env, paramsMap);

    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().updateMidiClipEvents(
            (int)clipIndex,
            id,
            name,
            notes,
            params,
            (double)sourceTempoBpm); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLiveMidiInputTargetClipJNI(JNIEnv *, jclass, jint clipIndex)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().setLiveMidiInputTargetClip((int)clipIndex); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_consumeLiveMidiInputEventsJNI(JNIEnv *env, jclass)
{
    std::vector<JuceEngine::LiveMidiInputEvent> events;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { events = JuceEngine::get().consumeLiveMidiInputEvents(); });

    jclass listCls = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listCls, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listCls, "add", "(Ljava/lang/Object;)Z");
    jobject outList = env->NewObject(listCls, listCtor);

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID mapCtor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(
        mapCls,
        "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID intCtor = env->GetMethodID(intCls, "<init>", "(I)V");
    jclass floatCls = env->FindClass("java/lang/Float");
    jmethodID floatCtor = env->GetMethodID(floatCls, "<init>", "(F)V");
    jclass doubleCls = env->FindClass("java/lang/Double");
    jmethodID doubleCtor = env->GetMethodID(doubleCls, "<init>", "(D)V");
    jclass boolCls = env->FindClass("java/lang/Boolean");
    jmethodID boolCtor = env->GetMethodID(boolCls, "<init>", "(Z)V");

    for (const auto &event : events)
    {
        jobject map = env->NewObject(mapCls, mapCtor);

        auto putObj = [&](const char *key, jobject value)
        {
            jstring jKey = env->NewStringUTF(key);
            env->CallObjectMethod(map, mapPut, jKey, value);
            env->DeleteLocalRef(jKey);
            env->DeleteLocalRef(value);
        };

        putObj("clip", env->NewObject(intCls, intCtor, (jint)event.clipId));
        putObj("noteOn", env->NewObject(boolCls, boolCtor, (jboolean)(event.noteOn ? JNI_TRUE : JNI_FALSE)));
        putObj("channel", env->NewObject(intCls, intCtor, (jint)event.channel));
        putObj("pitch", env->NewObject(intCls, intCtor, (jint)event.pitch));
        putObj("velocity", env->NewObject(floatCls, floatCtor, (jfloat)event.velocity));
        putObj("transportSec", env->NewObject(doubleCls, doubleCtor, (jdouble)event.transportSec));

        // Mirror iOS payload ("type": "noteOn"/"noteOff") for Dart compatibility.
        jstring keyType = env->NewStringUTF("type");
        jstring valueType = env->NewStringUTF(event.noteOn ? "noteOn" : "noteOff");
        env->CallObjectMethod(map, mapPut, keyType, valueType);
        env->DeleteLocalRef(keyType);
        env->DeleteLocalRef(valueType);

        env->CallBooleanMethod(outList, listAdd, map);
        env->DeleteLocalRef(map);
    }

    return outList;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getConnectedMidiInputDevicesJNI(JNIEnv *env, jclass)
{
    juce::Array<juce::MidiDeviceInfo> devices;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { devices = juce::MidiInput::getAvailableDevices(); });

    jclass listCls = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listCls, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listCls, "add", "(Ljava/lang/Object;)Z");
    jobject outList = env->NewObject(listCls, listCtor);

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID mapCtor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(
        mapCls,
        "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    for (const auto &device : devices)
    {
        const auto identifier = device.identifier.trim();
        if (identifier.isEmpty())
            continue;

        const auto displayName = device.name.trim().isEmpty()
                                     ? identifier
                                     : device.name.trim();

        jobject map = env->NewObject(mapCls, mapCtor);

        auto putString = [&](const char *key, const juce::String &value)
        {
            jstring jKey = env->NewStringUTF(key);
            jstring jValue = env->NewStringUTF(value.toRawUTF8());
            env->CallObjectMethod(map, mapPut, jKey, jValue);
            env->DeleteLocalRef(jKey);
            env->DeleteLocalRef(jValue);
        };

        putString("id", identifier);
        putString("name", displayName);

        env->CallBooleanMethod(outList, listAdd, map);
        env->DeleteLocalRef(map);
    }

    return outList;
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getHostSampleRateJNI(JNIEnv *, jclass)
{
    std::atomic<double> result{44100.0};
    juce::MessageManager::getInstance()->callSync([&result]
                                                  { result = JuceEngine::get().getHostSampleRate(); });
    return result.load();
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackCompressorMeterJNI(JNIEnv *env, jclass, jint trackIndex, jint effectIndex)
{
    std::array<float, 5> meter{0, 0, 0, 0, 0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { meter = JuceEngine::get().getClipCompressorMeter((int)trackIndex, (int)effectIndex); });

    jdouble values[5] = {
        (jdouble)meter[0],
        (jdouble)meter[1],
        (jdouble)meter[2],
        (jdouble)meter[3],
        (jdouble)meter[4],
    };

    auto out = env->NewDoubleArray(5);
    env->SetDoubleArrayRegion(out, 0, 5, values);
    return out;
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportMixJNI(JNIEnv *env,
                                                              jclass,
                                                              jstring outPath,
                                                              jstring format,
                                                              jint sampleRate,
                                                              jint wavBitDepth,
                                                              jboolean wavDithering,
                                                              jint mp3BitrateKbps)
{
    const char *c = env->GetStringUTFChars(outPath, nullptr);
    juce::String jucePath = c != nullptr ? juce::String::fromUTF8(c) : juce::String();
    env->ReleaseStringUTFChars(outPath, c);

    const char *formatChars = env->GetStringUTFChars(format, nullptr);
    juce::String formatValue = formatChars != nullptr ? juce::String::fromUTF8(formatChars) : juce::String();
    env->ReleaseStringUTFChars(format, formatChars);

    JuceEngine::ExportOptions options;
    options.format = formatValue;
    options.sampleRate = (double)sampleRate;
    options.wavBitDepth = (int)wavBitDepth;
    options.wavDithering = (wavDithering == JNI_TRUE);
    options.mp3BitrateKbps = (int)mp3BitrateKbps;

    juce::String result;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportMix(juce::File(jucePath), options); });
    return env->NewStringUTF(result.toRawUTF8());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportTrackJNI(JNIEnv *env,
                                                                jclass,
                                                                jint trackIdx,
                                                                jstring outPath,
                                                                jstring format,
                                                                jint sampleRate,
                                                                jint wavBitDepth,
                                                                jboolean wavDithering,
                                                                jint mp3BitrateKbps)
{
    const char *c = env->GetStringUTFChars(outPath, nullptr);
    juce::String jucePath = c != nullptr ? juce::String::fromUTF8(c) : juce::String();
    env->ReleaseStringUTFChars(outPath, c);

    const char *formatChars = env->GetStringUTFChars(format, nullptr);
    juce::String formatValue = formatChars != nullptr ? juce::String::fromUTF8(formatChars) : juce::String();
    env->ReleaseStringUTFChars(format, formatChars);

    JuceEngine::ExportOptions options;
    options.format = formatValue;
    options.sampleRate = (double)sampleRate;
    options.wavBitDepth = (int)wavBitDepth;
    options.wavDithering = (wavDithering == JNI_TRUE);
    options.mp3BitrateKbps = (int)mp3BitrateKbps;

    juce::String result;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { result = JuceEngine::get().exportTrack(trackIdx, juce::File(jucePath), options); });
    return env->NewStringUTF(result.toRawUTF8());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginBypassStateJNI(JNIEnv *, jclass, jint trackIndex, jint effectIndex)
{
    bool result = false;
    juce::MessageManager::getInstance()->callSync([trackIndex, effectIndex, &result]
                                                  { result = JuceEngine::get().getPluginBypassState((int)trackIndex, (int)effectIndex); });
    return result ? JNI_TRUE : JNI_FALSE;
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

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadClipJNI(JNIEnv *env,
                                                             jclass,
                                                             jint clipIndex,
                                                             jint rowId,
                                                             jstring path,
                                                             jdouble startSec,
                                                             jdouble lengthSec,
                                                             jdouble inFileOffsetSec)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    juce::MessageManager::getInstance()->callSync([=]
                                                  { JuceEngine::get().loadClip((int)clipIndex,
                                                                               (int)rowId,
                                                                               juce::File(jucePath),
                                                                               (double)startSec,
                                                                               (double)lengthSec,
                                                                               (double)inFileOffsetSec); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadClipJNI(JNIEnv *, jclass, jint clipIndex)
{
    juce::MessageManager::callAsync([clipIndex]
                                    { JuceEngine::get().unloadClip((int)clipIndex); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipGainJNI(JNIEnv *, jclass, jint clipIndex, jfloat gain)
{
    juce::MessageManager::callAsync([clipIndex, gain]
                                    { JuceEngine::get().setClipGain((int)clipIndex, (float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteClipJNI(JNIEnv *, jclass, jint clipIndex, jboolean mute)
{
    juce::MessageManager::callAsync([clipIndex, mute]
                                    { JuceEngine::get().muteClip((int)clipIndex, mute != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_moveClipToRowJNI(JNIEnv *, jclass, jint clipIndex, jint newRowId)
{
    juce::MessageManager::callAsync([clipIndex, newRowId]
                                    { JuceEngine::get().moveClipToRow((int)clipIndex, (int)newRowId); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTransportSecondsJNI(JNIEnv *, jclass, jdouble seconds)
{
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([seconds]
                     { JuceEngine::get().setTransportSeconds((double)seconds); });
        return;
    }
    JuceEngine::get().setTransportSeconds((double)seconds);
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTransportSecondsJNI(JNIEnv *, jclass)
{
    std::atomic<double> value{0.0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { value = JuceEngine::get().getTransportSeconds(); });
    return value.load();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAutomationTransportJNI(JNIEnv *, jclass, jdouble timeSeconds)
{
    juce::MessageManager::callAsync([timeSeconds]
                                    { JuceEngine::get().setAutomationTransport((double)timeSeconds); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_addRowJNI(JNIEnv *env, jclass, jstring name, jint iconId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().addRow(rowName, (int)iconId); });
    return (jint)rowId.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowAboveJNI(JNIEnv *env,
                                                                   jclass,
                                                                   jint referenceRowId,
                                                                   jstring name,
                                                                   jint iconId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().insertRowAbove((int)referenceRowId, rowName, (int)iconId); });
    return (jint)rowId.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowBelowJNI(JNIEnv *env,
                                                                   jclass,
                                                                   jint referenceRowId,
                                                                   jstring name,
                                                                   jint iconId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().insertRowBelow((int)referenceRowId, rowName, (int)iconId); });
    return (jint)rowId.load();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeRowJNI(JNIEnv *, jclass, jint rowId)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().removeRow((int)rowId); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_moveRowOrderJNI(JNIEnv *, jclass, jint fromIndex, jint toIndex)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().moveRowOrder((int)fromIndex, (int)toIndex); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_renameRowJNI(JNIEnv *env, jclass, jint rowId, jstring name)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().renameRow((int)rowId, rowName); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowIconJNI(JNIEnv *, jclass, jint rowId, jint iconId)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().setRowIcon((int)rowId, (int)iconId); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowsJNI(JNIEnv *env, jclass)
{
    juce::Array<juce::NamedValueSet> rows;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rows = JuceEngine::get().getRows(); });
    return rowsToJavaList(env, rows);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertTrackEffectJNI(JNIEnv *env, jclass, jint row, jstring pluginPath)
{
    const juce::String path = juceStringFromJString(env, pluginPath);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().insertTrackEffect((int)row, path); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackEffectJNI(JNIEnv *, jclass, jint row, jint effectIndex)
{
    juce::MessageManager::callAsync([row, effectIndex]
                                    { JuceEngine::get().removeTrackEffect((int)row, (int)effectIndex); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderTrackEffectsJNI(JNIEnv *, jclass, jint row, jint fromIndex, jint toIndex)
{
    juce::MessageManager::callAsync([row, fromIndex, toIndex]
                                    { JuceEngine::get().reorderTrackEffects((int)row, (int)fromIndex, (int)toIndex); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsForRowJNI(JNIEnv *env, jclass, jint row)
{
    juce::StringArray names;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { names = JuceEngine::get().getTrackEffectsForRow((int)row); });
    return stringArrayToJavaList(env, names);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectIdsForRowJNI(JNIEnv *env, jclass, jint row)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getTrackEffectIdsForRow((int)row); });
    return stringArrayToJavaList(env, ids);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectInstanceIdsForRowJNI(JNIEnv *env, jclass, jint row)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getTrackEffectInstanceIdsForRow((int)row); });
    return stringArrayToJavaList(env, ids);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackPluginParametersJNI(JNIEnv *env, jclass, jint row, jint effectIndex)
{
    juce::Array<juce::NamedValueSet> params;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { params = JuceEngine::get().getTrackPluginParameterInfo((int)row, (int)effectIndex); });
    return namedValueSetArrayToJavaParameterList(env, params);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackEffectJNI(
    JNIEnv *env, jclass, jint row, jint effectIndex, jstring paramId, jobject valueObj)
{
    const juce::String param = juceStringFromJString(env, paramId);
    const juce::var value = javaObjectToVar(env, valueObj);
    juce::MessageManager::callAsync([row, effectIndex, param, value]
                                    { JuceEngine::get().setTrackEffectParameter((int)row, (int)effectIndex, param, value); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassRowEffectJNI(JNIEnv *, jclass, jint row, jint effectIndex, jboolean bypass)
{
    juce::MessageManager::callAsync([row, effectIndex, bypass]
                                    { JuceEngine::get().bypassRowEffect((int)row, (int)effectIndex, bypass != JNI_FALSE); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowEffectBypassStateJNI(JNIEnv *, jclass, jint row, jint effectIndex)
{
    std::atomic<bool> state{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { state = JuceEngine::get().getRowEffectBypassState((int)row, (int)effectIndex); });
    return state.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackAutomationPointsJNI(JNIEnv *env, jclass, jint row, jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 3.0f);
    juce::MessageManager::callAsync([row, points = std::move(points)]() mutable
                                    { JuceEngine::get().setTrackAutomationPoints((int)row, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackEffectAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jint row,
    jint effectIndex,
    jstring paramId,
    jdouble minValue,
    jdouble maxValue,
    jobject pointsList)
{
    const juce::String param = juceStringFromJString(env, paramId);
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([row, effectIndex, param, minValue, maxValue, points = std::move(points)]() mutable
                                    { JuceEngine::get().setTrackEffectAutomationPoints((int)row, (int)effectIndex, param, (float)minValue, (float)maxValue, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearTrackEffectAutomationForRowJNI(
    JNIEnv *,
    jclass,
    jint row)
{
    juce::MessageManager::callAsync([row]
                                    { JuceEngine::get().clearTrackEffectAutomationForRow((int)row); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowGainAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jint row,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([row, points = std::move(points)]() mutable
                                    { JuceEngine::get().setRowGainAutomationPoints((int)row, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowGainJNI(JNIEnv *, jclass, jint row, jfloat gain)
{
    juce::MessageManager::callAsync([row, gain]
                                    { JuceEngine::get().setRowGain((int)row, (float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteRowJNI(JNIEnv *, jclass, jint row, jboolean mute)
{
    juce::MessageManager::callAsync([row, mute]
                                    { JuceEngine::get().muteRow((int)row, mute != JNI_FALSE); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_isRowMutedJNI(JNIEnv *, jclass, jint row)
{
    std::atomic<bool> muted{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { muted = JuceEngine::get().isRowMuted((int)row); });
    return muted.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowPanAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jint row,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([row, points = std::move(points)]() mutable
                                    { JuceEngine::get().setRowPanAutomationPoints((int)row, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowPanJNI(JNIEnv *, jclass, jint row, jfloat pan)
{
    juce::MessageManager::callAsync([row, pan]
                                    { JuceEngine::get().setRowPan((int)row, (float)pan); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertMasterEffectJNI(JNIEnv *env, jclass, jstring pluginPath)
{
    const juce::String path = juceStringFromJString(env, pluginPath);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().insertMasterEffect(path); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeMasterEffectJNI(JNIEnv *, jclass, jint effectIndex)
{
    juce::MessageManager::getInstance()->callSync([effectIndex]
                                                  { JuceEngine::get().removeMasterEffect((int)effectIndex); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderMasterEffectsJNI(JNIEnv *, jclass, jint fromIndex, jint toIndex)
{
    juce::MessageManager::getInstance()->callSync([fromIndex, toIndex]
                                                  { JuceEngine::get().reorderMasterEffects((int)fromIndex, (int)toIndex); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectsJNI(JNIEnv *env, jclass)
{
    juce::StringArray names;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { names = JuceEngine::get().getMasterEffects(); });
    return stringArrayToJavaList(env, names);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectIdsJNI(JNIEnv *env, jclass)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getMasterEffectIds(); });
    return stringArrayToJavaList(env, ids);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterPluginParametersJNI(JNIEnv *env, jclass, jint effectIndex)
{
    juce::Array<juce::NamedValueSet> params;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { params = JuceEngine::get().getMasterPluginParameterInfo((int)effectIndex); });
    return namedValueSetArrayToJavaParameterList(env, params);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterEffectJNI(
    JNIEnv *env, jclass, jint effectIndex, jstring paramId, jobject valueObj)
{
    const juce::String param = juceStringFromJString(env, paramId);
    const juce::var value = javaObjectToVar(env, valueObj);
    juce::MessageManager::callAsync([effectIndex, param, value]
                                    { JuceEngine::get().setMasterEffectParameter((int)effectIndex, param, value); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassMasterEffectJNI(JNIEnv *, jclass, jint effectIndex, jboolean bypass)
{
    juce::MessageManager::callAsync([effectIndex, bypass]
                                    { JuceEngine::get().bypassMasterEffect((int)effectIndex, bypass != JNI_FALSE); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectBypassStateJNI(JNIEnv *, jclass, jint effectIndex)
{
    std::atomic<bool> state{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { state = JuceEngine::get().getMasterEffectBypassState((int)effectIndex); });
    return state.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterEffectAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jint effectIndex,
    jstring paramId,
    jdouble minValue,
    jdouble maxValue,
    jobject pointsList)
{
    const juce::String param = juceStringFromJString(env, paramId);
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([effectIndex, param, minValue, maxValue, points = std::move(points)]() mutable
                                    { JuceEngine::get().setMasterEffectAutomationPoints((int)effectIndex, param, (float)minValue, (float)maxValue, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearMasterEffectAutomationJNI(
    JNIEnv *,
    jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().clearMasterEffectAutomation(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([points = std::move(points)]() mutable
                                    { JuceEngine::get().setMasterGainAutomationPoints(points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainJNI(JNIEnv *, jclass, jfloat gain)
{
    juce::MessageManager::callAsync([gain]
                                    { JuceEngine::get().setMasterGain((float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteMasterJNI(JNIEnv *, jclass, jboolean mute)
{
    juce::MessageManager::callAsync([mute]
                                    { JuceEngine::get().muteMaster(mute != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::callAsync([points = std::move(points)]() mutable
                                    { JuceEngine::get().setMasterPanAutomationPoints(points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanJNI(JNIEnv *, jclass, jfloat pan)
{
    juce::MessageManager::callAsync([pan]
                                    { JuceEngine::get().setMasterPan((float)pan); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_debugPrintGraphJNI(JNIEnv *env, jclass, jstring title)
{
    const juce::String juceTitle = juceStringFromJString(env, title);
    juce::MessageManager::callAsync([juceTitle]
                                    { JuceEngine::get().debugPrintGraph(juceTitle); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_debugPrintGraphStructureJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().debugPrintGraphStructure(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeEnabledJNI(JNIEnv *, jclass, jboolean enabled)
{
    juce::MessageManager::callAsync([enabled]
                                    { JuceEngine::get().setMetronomeEnabled(enabled != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeVolumeJNI(JNIEnv *, jclass, jfloat volume)
{
    juce::MessageManager::callAsync([volume]
                                    { JuceEngine::get().setMetronomeVolume((float)volume); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeBpmJNI(JNIEnv *, jclass, jdouble bpm)
{
    juce::MessageManager::callAsync([bpm]
                                    { JuceEngine::get().setMetronomeBpm((double)bpm); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeTransportMsJNI(JNIEnv *, jclass, jdouble ms)
{
    juce::MessageManager::callAsync([ms]
                                    { JuceEngine::get().setMetronomeTransportMs((double)ms); });
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_decodeAudioMono16kJNI(JNIEnv *env, jclass, jstring path)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    std::vector<float> samples;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { samples = JuceEngine::get().decodeAudioMono16k(juce::File(jucePath)); });
    return floatVectorToJDoubleArray(env, samples);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_analyzeAudioStereo16kJNI(JNIEnv *env, jclass, jstring path)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    juce::NamedValueSet stats;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { stats = JuceEngine::get().analyzeAudioStereo16k(juce::File(jucePath)); });
    return namedValueStatsToJavaMap(env, stats);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getInputDevicesJNI(JNIEnv *env, jclass)
{
    juce::StringArray devices;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { devices = JuceEngine::get().getAvailableInputDevices(); });
    return stringArrayToJavaList(env, devices);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_selectInputDeviceJNI(JNIEnv *env, jclass, jstring name)
{
    const juce::String deviceName = juceStringFromJString(env, name);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().selectInputDevice(deviceName); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getNumInputChannelsJNI(JNIEnv *, jclass)
{
    std::atomic<int> channels{0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { channels = JuceEngine::get().getNumInputChannels(); });
    return (jint)channels.load();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_prepareRecordingInputsJNI(JNIEnv *env,
                                                                          jclass,
                                                                          jint desiredInputChannels,
                                                                          jstring reason)
{
    const juce::String juceReason = reason == nullptr
                                        ? juce::String("dart")
                                        : juceStringFromJString(env, reason);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().prepareRecordingInputs((int)desiredInputChannels,
                                                      juceReason); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_refreshAudioRouteJNI(JNIEnv *env,
                                                                     jclass,
                                                                     jstring reason)
{
    const juce::String juceReason = reason == nullptr
                                        ? juce::String("dart")
                                        : juceStringFromJString(env, reason);
    juce::MessageManager::getInstance()->callSync([&]
                                                  { JuceEngine::get().refreshAudioRouteAsync(juceReason); });
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRecordingPeakJNI(JNIEnv *, jclass)
{
    std::atomic<double> peak{0.0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { peak = JuceEngine::get().getRecordingPeak(); });
    return peak.load();
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentDeviceNameJNI(JNIEnv *env, jclass)
{
    juce::String name;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { name = JuceEngine::get().getCurrentInputDeviceName(); });
    return env->NewStringUTF(name.toRawUTF8());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentOutputDeviceNameJNI(JNIEnv *env, jclass)
{
    juce::String name;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { name = JuceEngine::get().getCurrentOutputDeviceName(); });
    return env->NewStringUTF(name.toRawUTF8());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_startRecordingJNI(JNIEnv *env,
                                                                   jclass,
                                                                   jstring path,
                                                                   jint channelStart,
                                                                   jint channelCount)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().startRecordingToWav(juce::File(jucePath),
                                                                                                (int)channelStart,
                                                                                                (int)channelCount); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_stopRecordingJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().stopRecording(); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_isRecordingJNI(JNIEnv *, jclass)
{
    std::atomic<bool> recording{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { recording = JuceEngine::get().isRecording(); });
    return recording.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterMeterEnabledJNI(JNIEnv *, jclass, jboolean enabled)
{
    juce::MessageManager::getInstance()->callSync([enabled]
                                                  { JuceEngine::get().setMasterMeterEnabled(enabled != JNI_FALSE); });
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterMeterValuesJNI(JNIEnv *env, jclass)
{
    std::array<float, 4> values{0, 0, 0, 0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { values = JuceEngine::get().getMasterMeterValues(); });
    return floatArrayToJDoubleArray(env, values);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterClipLatchedJNI(JNIEnv *, jclass)
{
    std::atomic<bool> latched{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { latched = JuceEngine::get().getMasterClipLatched(); });
    return latched.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearMasterClipLatchedJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().clearMasterClipLatched(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowMetersEnabledJNI(JNIEnv *, jclass, jboolean enabled)
{
    juce::MessageManager::getInstance()->callSync([enabled]
                                                  { JuceEngine::get().setRowMetersEnabled(enabled != JNI_FALSE); });
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowMeterValuesJNI(JNIEnv *env, jclass, jint row)
{
    std::array<float, 4> values{0, 0, 0, 0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { values = JuceEngine::get().getRowMeterValues((int)row); });
    return floatArrayToJDoubleArray(env, values);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getAllMeterValuesJNI(JNIEnv *env, jclass)
{
    std::vector<float> values;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { values = JuceEngine::get().getAllMeterValues(); });
    return floatVectorToJDoubleArray(env, values);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowCompressorMeterJNI(JNIEnv *env, jclass, jint row, jint effectIndex)
{
    std::array<float, 5> values{0, 0, 0, 0, 0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { values = JuceEngine::get().getRowCompressorMeter((int)row, (int)effectIndex); });
    return floatArrayToJDoubleArray(env, values);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterCompressorMeterJNI(JNIEnv *env, jclass, jint effectIndex)
{
    std::array<float, 5> values{0, 0, 0, 0, 0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { values = JuceEngine::get().getMasterCompressorMeter((int)effectIndex); });
    return floatArrayToJDoubleArray(env, values);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowEqWaveformJNI(JNIEnv *env, jclass, jint row, jint effectIndex, jint sampleCount)
{
    std::vector<float> waveform;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { waveform = JuceEngine::get().getRowEqWaveform((int)row,
                                                                                                   (int)effectIndex,
                                                                                                   (int)sampleCount); });
    return floatVectorToJDoubleArray(env, waveform);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEqWaveformJNI(JNIEnv *env, jclass, jint effectIndex, jint sampleCount)
{
    std::vector<float> waveform;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { waveform = JuceEngine::get().getMasterEqWaveform((int)effectIndex,
                                                                                                      (int)sampleCount); });
    return floatVectorToJDoubleArray(env, waveform);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_renderInstrumentClipJNI(JNIEnv *env,
                                                                         jclass,
                                                                         jstring outPath,
                                                                         jstring instrumentId,
                                                                         jstring instrumentName,
                                                                         jdouble bpm,
                                                                         jobject notesList,
                                                                         jobject paramsMap)
{
    mixroom::instruments::InstrumentRenderRequest request;
    request.outFile = juce::File(juceStringFromJString(env, outPath));
    request.instrumentId = juceStringFromJString(env, instrumentId);
    request.instrumentName = juceStringFromJString(env, instrumentName);
    request.bpm = (double)bpm;
    request.notes = parseMidiRenderNotes(env, notesList);
    request.params = parseNamedValueSet(env, paramsMap);

    const juce::String rendered = mixroom::instruments::renderInstrumentClipToWav(request);
    return env->NewStringUTF(rendered.toRawUTF8());
}
