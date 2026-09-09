#define JUCE_GUI_BASICS_INCLUDE_ANDROID 1
#include "JuceEngine.h"
#include "JuceBridge.h"
#include "MixroomOboePlaybackV2.h"
#include "InstrumentRenderers.h"
#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_core/native/juce_JNIHelpers_android.h>
#include <android/log.h>
#include <jni.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <vector>

namespace juce
{
    extern jobject androidApkContext;
    extern jobject juceContext;
}

namespace
{
std::mutex juceAndroidRuntimeMutex;
bool juceAndroidClassesInitialized = false;
bool juceAndroidThreadInitialized = false;
bool juceAndroidGuiInitialized = false;

bool ensureJuceAndroidRuntimeInitialised(JNIEnv *env)
{
    if (env == nullptr)
        return false;

    if (juce::androidApkContext == nullptr || juce::juceContext == nullptr)
    {
        __android_log_print(ANDROID_LOG_ERROR, "JUCE", "Android context is not set before JUCE runtime initialisation.");
        return false;
    }

    std::lock_guard<std::mutex> lock(juceAndroidRuntimeMutex);

    if (!juceAndroidClassesInitialized)
    {
        juce::JNIClassBase::initialiseAllClasses(env, juce::androidApkContext);
        if (env->ExceptionCheck())
        {
            __android_log_print(ANDROID_LOG_ERROR, "JUCE", "Failed to initialise JUCE JNI classes.");
            return false;
        }
        juceAndroidClassesInitialized = true;
    }

    if (!juceAndroidThreadInitialized)
    {
        juce::Thread::initialiseJUCE(env, juce::juceContext);
        juceAndroidThreadInitialized = true;
    }

    if (!juceAndroidGuiInitialized)
    {
        juce::initialiseJuce_GUI();
        juceAndroidGuiInitialized = true;
    }

    return true;
}

void flushPendingMessageThreadTasks()
{
    if (auto *mm = juce::MessageManager::getInstanceWithoutCreating())
        mm->callSync([] {});
}

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
        const double result = env->CallDoubleMethod(value, toDouble);
        env->DeleteLocalRef(numberClass);
        return result;
    }
    env->DeleteLocalRef(numberClass);

    jclass stringClass = env->FindClass("java/lang/String");
    if (env->IsInstanceOf(value, stringClass))
    {
        juce::String s = juceStringFromJString(env, (jstring)value);
        const double parsed = s.getDoubleValue();
        env->DeleteLocalRef(stringClass);
        return std::isfinite(parsed) ? parsed : fallback;
    }
    env->DeleteLocalRef(stringClass);
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
        const int result = env->CallIntMethod(value, toInt);
        env->DeleteLocalRef(numberClass);
        return result;
    }
    env->DeleteLocalRef(numberClass);

    jclass stringClass = env->FindClass("java/lang/String");
    if (env->IsInstanceOf(value, stringClass))
    {
        juce::String s = juceStringFromJString(env, (jstring)value);
        const int result = s.getIntValue();
        env->DeleteLocalRef(stringClass);
        return result;
    }
    env->DeleteLocalRef(stringClass);
    return fallback;
}

bool javaObjectToBool(JNIEnv *env, jobject value, bool fallback = false)
{
    if (value == nullptr)
        return fallback;

    jclass booleanClass = env->FindClass("java/lang/Boolean");
    if (env->IsInstanceOf(value, booleanClass))
    {
        jmethodID boolValue = env->GetMethodID(booleanClass, "booleanValue", "()Z");
        const bool result = env->CallBooleanMethod(value, boolValue) == JNI_TRUE;
        env->DeleteLocalRef(booleanClass);
        return result;
    }
    env->DeleteLocalRef(booleanClass);

    jclass numberClass = env->FindClass("java/lang/Number");
    if (env->IsInstanceOf(value, numberClass))
    {
        jmethodID intValue = env->GetMethodID(numberClass, "intValue", "()I");
        const bool result = env->CallIntMethod(value, intValue) != 0;
        env->DeleteLocalRef(numberClass);
        return result;
    }
    env->DeleteLocalRef(numberClass);

    jclass stringClass = env->FindClass("java/lang/String");
    if (env->IsInstanceOf(value, stringClass))
    {
        const auto text = juceStringFromJString(env, (jstring)value).trim().toLowerCase();
        env->DeleteLocalRef(stringClass);
        if (text == "true" || text == "1")
            return true;
        if (text == "false" || text == "0")
            return false;
    }
    else
    {
        env->DeleteLocalRef(stringClass);
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

    juce::var result;
    if (env->IsInstanceOf(valueObj, doubleClass))
    {
        jmethodID doubleValue = env->GetMethodID(doubleClass, "doubleValue", "()D");
        result = juce::var((double)env->CallDoubleMethod(valueObj, doubleValue));
    }
    else if (env->IsInstanceOf(valueObj, integerClass))
    {
        jmethodID intValue = env->GetMethodID(integerClass, "intValue", "()I");
        result = juce::var((int)env->CallIntMethod(valueObj, intValue));
    }
    else if (env->IsInstanceOf(valueObj, longClass))
    {
        jmethodID longValue = env->GetMethodID(longClass, "longValue", "()J");
        result = juce::var((juce::int64)env->CallLongMethod(valueObj, longValue));
    }
    else if (env->IsInstanceOf(valueObj, floatClass))
    {
        jmethodID floatValue = env->GetMethodID(floatClass, "floatValue", "()F");
        result = juce::var((double)env->CallFloatMethod(valueObj, floatValue));
    }
    else if (env->IsInstanceOf(valueObj, booleanClass))
    {
        jmethodID boolValue = env->GetMethodID(booleanClass, "booleanValue", "()Z");
        result = juce::var((bool)(env->CallBooleanMethod(valueObj, boolValue) == JNI_TRUE));
    }
    else if (env->IsInstanceOf(valueObj, stringClass))
    {
        result = juce::var(juceStringFromJString(env, (jstring)valueObj));
    }

    env->DeleteLocalRef(doubleClass);
    env->DeleteLocalRef(integerClass);
    env->DeleteLocalRef(longClass);
    env->DeleteLocalRef(floatClass);
    env->DeleteLocalRef(booleanClass);
    env->DeleteLocalRef(stringClass);
    return result;
}

juce::Array<juce::NamedValueSet> parseTrackGroups(JNIEnv *env, jobject groupsList)
{
    juce::Array<juce::NamedValueSet> out;
    if (groupsList == nullptr)
        return out;

    jclass listClass = env->FindClass("java/util/List");
    if (!env->IsInstanceOf(groupsList, listClass))
        return out;

    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
    jclass mapClass = env->FindClass("java/util/Map");
    jmethodID mapGet = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
    jclass stringClass = env->FindClass("java/lang/String");

    jstring keyId = env->NewStringUTF("id");
    jstring keyRowIds = env->NewStringUTF("rowIds");
    jstring keyGain = env->NewStringUTF("gain");
    jstring keyPan = env->NewStringUTF("pan");
    jstring keyMuted = env->NewStringUTF("muted");
    jstring keySoloed = env->NewStringUTF("soloed");

    const jint count = env->CallIntMethod(groupsList, sizeMethod);
    out.ensureStorageAllocated((int)count);
    for (jint i = 0; i < count; ++i)
    {
        jobject entry = env->CallObjectMethod(groupsList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        jobject idObj = env->CallObjectMethod(entry, mapGet, keyId);
        jobject rowIdsObj = env->CallObjectMethod(entry, mapGet, keyRowIds);
        jobject gainObj = env->CallObjectMethod(entry, mapGet, keyGain);
        jobject panObj = env->CallObjectMethod(entry, mapGet, keyPan);
        jobject mutedObj = env->CallObjectMethod(entry, mapGet, keyMuted);
        jobject soloedObj = env->CallObjectMethod(entry, mapGet, keySoloed);

        juce::NamedValueSet values;
        values.set("id",
                   idObj != nullptr && env->IsInstanceOf(idObj, stringClass)
                       ? juceStringFromJString(env, (jstring)idObj)
                       : juce::String());

        juce::Array<juce::var> rowIds;
        if (rowIdsObj != nullptr && env->IsInstanceOf(rowIdsObj, listClass))
        {
            const jint rowCount = env->CallIntMethod(rowIdsObj, sizeMethod);
            rowIds.ensureStorageAllocated((int)rowCount);
            for (jint rowIndex = 0; rowIndex < rowCount; ++rowIndex)
            {
                jobject rowIdObj = env->CallObjectMethod(rowIdsObj, getMethod, rowIndex);
                rowIds.add(javaObjectToInt(env, rowIdObj, -1));
                if (rowIdObj != nullptr)
                    env->DeleteLocalRef(rowIdObj);
            }
        }
        values.set("rowIds", juce::var(rowIds));
        values.set("gain", (float)javaObjectToDouble(env, gainObj, 2.0));
        values.set("pan", (float)javaObjectToDouble(env, panObj, 0.5));
        values.set("muted", (bool)javaObjectToVar(env, mutedObj));
        values.set("soloed", (bool)javaObjectToVar(env, soloedObj));
        out.add(values);

        if (idObj != nullptr)
            env->DeleteLocalRef(idObj);
        if (rowIdsObj != nullptr)
            env->DeleteLocalRef(rowIdsObj);
        if (gainObj != nullptr)
            env->DeleteLocalRef(gainObj);
        if (panObj != nullptr)
            env->DeleteLocalRef(panObj);
        if (mutedObj != nullptr)
            env->DeleteLocalRef(mutedObj);
        if (soloedObj != nullptr)
            env->DeleteLocalRef(soloedObj);
        env->DeleteLocalRef(entry);
    }

    env->DeleteLocalRef(keyId);
    env->DeleteLocalRef(keyRowIds);
    env->DeleteLocalRef(keyGain);
    env->DeleteLocalRef(keyPan);
    env->DeleteLocalRef(keyMuted);
    env->DeleteLocalRef(keySoloed);
    return out;
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
    if (out == nullptr || env->ExceptionCheck())
        return nullptr;
    if (size == 0)
        return out;

    std::vector<jdouble> tmp((size_t)size, 0.0);
    for (jsize i = 0; i < size; ++i)
        tmp[(size_t)i] = (jdouble)values[(size_t)i];
    env->SetDoubleArrayRegion(out, 0, size, tmp.data());
    if (env->ExceptionCheck())
        return nullptr;
    return out;
}

jfloatArray floatVectorToJFloatArray(JNIEnv *env, const std::vector<float> &values)
{
    const auto size = (jsize)values.size();
    jfloatArray out = env->NewFloatArray(size);
    if (out == nullptr || env->ExceptionCheck())
        return nullptr;
    if (size == 0)
        return out;

    env->SetFloatArrayRegion(out, 0, size, values.data());
    if (env->ExceptionCheck())
        return nullptr;
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
        if (entry.contains("unit"))
            putStr(map, "unit", entry["unit"].toString());

        if (entry.contains("min"))
            putFloat(map, "min", (float)entry["min"]);
        if (entry.contains("max"))
            putFloat(map, "max", (float)entry["max"]);
        if (entry.contains("default"))
            putVar(map, "defaultValue", entry["default"]);
        if (entry.contains("value"))
            putVar(map, "value", entry["value"]);

        for (const auto *key : {"interval", "valueNormalized", "defaultNormalized"})
            if (entry.contains(key))
                putFloat(map, key, (float)entry[key]);
        for (const auto *key : {"displayMin", "displayMid", "displayMax", "displayValue"})
            if (entry.contains(key))
                putStr(map, key, entry[key].toString());

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

    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listClass, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");
    jclass doubleCls = env->FindClass("java/lang/Double");
    jmethodID doubleCtor = env->GetMethodID(doubleCls, "<init>", "(D)V");
    jclass longCls = env->FindClass("java/lang/Long");
    jmethodID longCtor = env->GetMethodID(longCls, "<init>", "(J)V");
    jclass boolCls = env->FindClass("java/lang/Boolean");
    jmethodID boolCtor = env->GetMethodID(boolCls, "<init>", "(Z)V");

    std::function<jobject(const juce::var &)> objectFromVar =
        [&](const juce::var &value) -> jobject
    {
        if (value.isBool())
            return env->NewObject(boolCls, boolCtor, (jboolean)((bool)value ? JNI_TRUE : JNI_FALSE));
        if (value.isInt() || value.isInt64())
            return env->NewObject(longCls, longCtor, (jlong)(juce::int64)value);
        if (value.isDouble())
            return env->NewObject(doubleCls, doubleCtor, (jdouble)(double)value);
        if (value.isArray())
        {
            jobject outList = env->NewObject(listClass, listCtor);
            if (auto *array = value.getArray())
            {
                for (const auto &entry : *array)
                {
                    jobject item = objectFromVar(entry);
                    env->CallBooleanMethod(outList, listAdd, item);
                    env->DeleteLocalRef(item);
                }
            }
            return outList;
        }

        return env->NewStringUTF(value.toString().toRawUTF8());
    };

    auto putObject = [&](const char *key, jobject value)
    {
        jstring jKey = env->NewStringUTF(key);
        env->CallObjectMethod(outMap, mapPut, jKey, value);
        env->DeleteLocalRef(jKey);
        env->DeleteLocalRef(value);
    };

    for (int i = 0; i < stats.size(); ++i)
    {
        const auto key = stats.getName(i).toString();
        putObject(key.toRawUTF8(), objectFromVar(stats.getValueAt(i)));
    }
    return outMap;
}

jobject promptAnalysisToJavaMap(JNIEnv *env, const juce::NamedValueSet &stats, const std::vector<std::vector<float>> &windows)
{
    jclass mapClass = env->FindClass("java/util/HashMap");
    jmethodID mapCtor = env->GetMethodID(mapClass, "<init>", "()V");
    jmethodID mapPut = env->GetMethodID(mapClass, "put",
                                        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject outMap = env->NewObject(mapClass, mapCtor);

    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listCtor = env->GetMethodID(listClass, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");
    jobject windowList = env->NewObject(listClass, listCtor);

    for (const auto &window : windows)
    {
        jfloatArray jWindow = floatVectorToJFloatArray(env, window);
        if (jWindow == nullptr)
            continue;
        env->CallBooleanMethod(windowList, listAdd, jWindow);
        env->DeleteLocalRef(jWindow);
    }

    jobject statsMap = namedValueStatsToJavaMap(env, stats);
    jstring statsKey = env->NewStringUTF("audioStats");
    jstring windowsKey = env->NewStringUTF("windows");
    env->CallObjectMethod(outMap, mapPut, statsKey, statsMap);
    env->CallObjectMethod(outMap, mapPut, windowsKey, windowList);
    env->DeleteLocalRef(statsKey);
    env->DeleteLocalRef(windowsKey);
    env->DeleteLocalRef(statsMap);
    env->DeleteLocalRef(windowList);
    return outMap;
}

struct PitchLabRange
{
    double startMs = 0.0;
    double endMs = 0.0;
};

struct PitchLabSegment
{
    double originalStartMs = 0.0;
    double originalEndMs = 0.0;
    double targetStartMs = 0.0;
    double targetEndMs = 0.0;
    double semitones = 0.0;
};

jobject javaMapValue(JNIEnv *env, jobject map, jstring key)
{
    jclass mapClass = env->FindClass("java/util/Map");
    jmethodID mapGet = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
    jobject result = env->CallObjectMethod(map, mapGet, key);
    env->DeleteLocalRef(mapClass);
    return result;
}

std::vector<PitchLabRange> parsePitchLabRanges(JNIEnv *env, jobject rangesList)
{
    std::vector<PitchLabRange> out;
    if (rangesList == nullptr)
        return out;
    jclass listClass = env->FindClass("java/util/List");
    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
    jclass mapClass = env->FindClass("java/util/Map");
    jstring keyStart = env->NewStringUTF("startMs");
    jstring keyEnd = env->NewStringUTF("endMs");

    const jint count = env->CallIntMethod(rangesList, sizeMethod);
    out.reserve((size_t)count);
    for (jint i = 0; i < count; ++i)
    {
        jobject entry = env->CallObjectMethod(rangesList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }
        jobject startObj = javaMapValue(env, entry, keyStart);
        jobject endObj = javaMapValue(env, entry, keyEnd);
        PitchLabRange range;
        range.startMs = javaObjectToDouble(env, startObj, 0.0);
        range.endMs = javaObjectToDouble(env, endObj, 0.0);
        if (std::isfinite(range.startMs) && std::isfinite(range.endMs))
        {
            if (range.endMs < range.startMs)
                std::swap(range.startMs, range.endMs);
            if (range.endMs > range.startMs + 1.0)
                out.push_back(range);
        }
        if (startObj != nullptr)
            env->DeleteLocalRef(startObj);
        if (endObj != nullptr)
            env->DeleteLocalRef(endObj);
        env->DeleteLocalRef(entry);
    }
    env->DeleteLocalRef(keyStart);
    env->DeleteLocalRef(keyEnd);
    return out;
}

std::vector<PitchLabSegment> parsePitchLabSegments(JNIEnv *env, jobject segmentsList)
{
    std::vector<PitchLabSegment> out;
    if (segmentsList == nullptr)
        return out;
    jclass listClass = env->FindClass("java/util/List");
    jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
    jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
    jclass mapClass = env->FindClass("java/util/Map");
    jstring keyOriginalStart = env->NewStringUTF("originalStartMs");
    jstring keyOriginalEnd = env->NewStringUTF("originalEndMs");
    jstring keyTargetStart = env->NewStringUTF("targetStartMs");
    jstring keyTargetEnd = env->NewStringUTF("targetEndMs");
    jstring keySemitones = env->NewStringUTF("semitones");

    const jint count = env->CallIntMethod(segmentsList, sizeMethod);
    out.reserve((size_t)juce::jmin<jint>(count, 256));
    for (jint i = 0; i < count && i < 256; ++i)
    {
        jobject entry = env->CallObjectMethod(segmentsList, getMethod, i);
        if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
        {
            if (entry != nullptr)
                env->DeleteLocalRef(entry);
            continue;
        }

        jobject originalStartObj = javaMapValue(env, entry, keyOriginalStart);
        jobject originalEndObj = javaMapValue(env, entry, keyOriginalEnd);
        jobject targetStartObj = javaMapValue(env, entry, keyTargetStart);
        jobject targetEndObj = javaMapValue(env, entry, keyTargetEnd);
        jobject semitonesObj = javaMapValue(env, entry, keySemitones);
        PitchLabSegment segment;
        segment.originalStartMs = javaObjectToDouble(env, originalStartObj, 0.0);
        segment.originalEndMs = javaObjectToDouble(env, originalEndObj, 0.0);
        segment.targetStartMs = javaObjectToDouble(env, targetStartObj, 0.0);
        segment.targetEndMs = javaObjectToDouble(env, targetEndObj, 0.0);
        segment.semitones = juce::jlimit(-48.0, 48.0, javaObjectToDouble(env, semitonesObj, 0.0));
        if (std::isfinite(segment.originalStartMs) &&
            std::isfinite(segment.originalEndMs) &&
            std::isfinite(segment.targetStartMs) &&
            std::isfinite(segment.targetEndMs) &&
            segment.originalEndMs > segment.originalStartMs + 1.0 &&
            segment.targetEndMs > segment.targetStartMs + 1.0)
        {
            out.push_back(segment);
        }
        if (originalStartObj != nullptr)
            env->DeleteLocalRef(originalStartObj);
        if (originalEndObj != nullptr)
            env->DeleteLocalRef(originalEndObj);
        if (targetStartObj != nullptr)
            env->DeleteLocalRef(targetStartObj);
        if (targetEndObj != nullptr)
            env->DeleteLocalRef(targetEndObj);
        if (semitonesObj != nullptr)
            env->DeleteLocalRef(semitonesObj);
        env->DeleteLocalRef(entry);
    }
    env->DeleteLocalRef(keyOriginalStart);
    env->DeleteLocalRef(keyOriginalEnd);
    env->DeleteLocalRef(keyTargetStart);
    env->DeleteLocalRef(keyTargetEnd);
    env->DeleteLocalRef(keySemitones);
    return out;
}

double pitchLabLocalMsToFileSec(double localMs, double trimStartMs, double trimEndMs, double sourceTimelineDurationMs)
{
    const double activeSourceMs = juce::jmax(1.0, trimEndMs - trimStartMs);
    const double timelineMs = juce::jmax(1.0, sourceTimelineDurationMs);
    return (trimStartMs + juce::jlimit(0.0, timelineMs, localMs) * (activeSourceMs / timelineMs)) / 1000.0;
}

float pitchLabReadInterpolated(const juce::AudioBuffer<float> &buffer, int channel, double sourcePos)
{
    const int n = buffer.getNumSamples();
    if (n <= 0)
        return 0.0f;
    const int ch = juce::jlimit(0, buffer.getNumChannels() - 1, channel);
    const double clamped = juce::jlimit(0.0, (double)(n - 1), sourcePos);
    const int i0 = (int)std::floor(clamped);
    const int i1 = juce::jmin(n - 1, i0 + 1);
    const float frac = (float)(clamped - (double)i0);
    const float a = buffer.getSample(ch, i0);
    return a + (buffer.getSample(ch, i1) - a) * frac;
}

void pitchLabApplyPitchCompensation(juce::AudioBuffer<float> &buffer, double sampleRate, double semitones)
{
    if (buffer.getNumSamples() <= 0 || std::abs(semitones) < 0.01)
        return;
    const int passes = juce::jlimit(1, 8, (int)std::ceil(std::abs(semitones) / 12.0));
    const float semitonesPerPass = (float)(semitones / (double)passes);
    juce::MidiBuffer midi;
    for (int i = 0; i < passes; ++i)
    {
        PitchShiftAudioProcessor shifter;
        shifter.prepareToPlay(sampleRate, juce::jmax(512, buffer.getNumSamples()));
        if (auto *mix = shifter.parameters.getRawParameterValue("mix"))
            mix->store(100.0f, std::memory_order_relaxed);
        if (auto *semitonesParam = shifter.parameters.getRawParameterValue("semitones"))
            semitonesParam->store(juce::jlimit(-12.0f, 12.0f, semitonesPerPass), std::memory_order_relaxed);
        midi.clear();
        shifter.processBlock(buffer, midi);
    }
}

void pitchLabStreamSourceRange(juce::AudioFormatReader &reader,
                               juce::AudioBuffer<float> &output,
                               juce::int64 sourceStart,
                               int sourceCount,
                               int targetStart,
                               int targetCount)
{
    if (sourceCount <= 1 || targetCount <= 0)
        return;
    constexpr int blockSize = 4096;
    const int sourceChannels = juce::jmax(1, (int)reader.numChannels);
    const double sourceSpan = (double)juce::jmax(1, sourceCount - 1);
    const double denom = (double)juce::jmax(1, targetCount - 1);

    for (int targetOffset = 0; targetOffset < targetCount; targetOffset += blockSize)
    {
        const int blockCount = juce::jmin(blockSize, targetCount - targetOffset);
        const double blockSourceStart = ((double)targetOffset / denom) * sourceSpan;
        const double blockSourceEnd = ((double)(targetOffset + blockCount - 1) / denom) * sourceSpan;
        const int readOffset = juce::jlimit(0, sourceCount - 1, (int)std::floor(blockSourceStart));
        const int readEnd = juce::jlimit(readOffset + 1, sourceCount + 1, (int)std::ceil(blockSourceEnd) + 2);
        const int readCount = juce::jmax(1, readEnd - readOffset);
        juce::AudioBuffer<float> scratch(sourceChannels, readCount);
        scratch.clear();
        reader.read(&scratch, 0, readCount, sourceStart + readOffset, true, true);

        for (int i = 0; i < blockCount; ++i)
        {
            const double sourcePos = (((double)(targetOffset + i) / denom) * sourceSpan) - (double)readOffset;
            for (int ch = 0; ch < 2; ++ch)
            {
                output.addSample(ch,
                                 targetStart + targetOffset + i,
                                 pitchLabReadInterpolated(scratch, sourceChannels == 1 ? 0 : ch, sourcePos));
            }
        }
    }
}

void pitchLabMixSourceRange(juce::AudioFormatReader &reader,
                            juce::AudioBuffer<float> &output,
                            double outputSampleRate,
                            double sourceStartSec,
                            double sourceEndSec,
                            double targetStartMs,
                            double targetEndMs,
                            double pitchSemitones)
{
    if (sourceEndSec <= sourceStartSec + 0.0005 || targetEndMs <= targetStartMs + 0.5)
        return;
    const juce::int64 sourceStart = juce::jlimit<juce::int64>(0, reader.lengthInSamples, (juce::int64)std::floor(sourceStartSec * reader.sampleRate));
    const juce::int64 sourceEnd = juce::jlimit<juce::int64>(0, reader.lengthInSamples, (juce::int64)std::ceil(sourceEndSec * reader.sampleRate));
    const juce::int64 sourceCount64 = std::max<juce::int64>(0, sourceEnd - sourceStart);
    if (sourceCount64 <= 1 || sourceCount64 > (juce::int64)std::numeric_limits<int>::max() - 8)
        return;
    const int sourceCount = (int)sourceCount64;
    const int targetStart = juce::jlimit(0, output.getNumSamples(), (int)std::floor(targetStartMs * outputSampleRate / 1000.0));
    const int targetEnd = juce::jlimit(0, output.getNumSamples(), (int)std::ceil(targetEndMs * outputSampleRate / 1000.0));
    const int targetCount = juce::jmax(0, targetEnd - targetStart);
    if (targetCount <= 0)
        return;

    const double sourceDurationSec = juce::jmax(0.001, sourceEndSec - sourceStartSec);
    const double targetDurationSec = juce::jmax(0.001, (targetEndMs - targetStartMs) / 1000.0);
    const double resampleSpeed = sourceDurationSec / targetDurationSec;
    const double stretchPitchDrift = 12.0 * (std::log(resampleSpeed) / std::log(2.0));
    if (std::abs(pitchSemitones) < 0.01 && std::abs(stretchPitchDrift) < 0.03)
    {
        pitchLabStreamSourceRange(reader, output, sourceStart, sourceCount, targetStart, targetCount);
        return;
    }

    juce::AudioBuffer<float> source(juce::jmax(1, (int)reader.numChannels), sourceCount + 2);
    source.clear();
    reader.read(&source, 0, sourceCount, sourceStart, true, true);

    juce::AudioBuffer<float> rendered(2, targetCount);
    rendered.clear();
    const double sourceSpan = (double)juce::jmax(1, sourceCount - 1);
    const double denom = (double)juce::jmax(1, targetCount - 1);
    for (int i = 0; i < targetCount; ++i)
    {
        const double sourcePos = ((double)i / denom) * sourceSpan;
        for (int ch = 0; ch < 2; ++ch)
            rendered.setSample(ch, i, pitchLabReadInterpolated(source, source.getNumChannels() == 1 ? 0 : ch, sourcePos));
    }

    pitchLabApplyPitchCompensation(rendered, outputSampleRate, juce::jlimit(-96.0, 96.0, pitchSemitones - stretchPitchDrift));
    for (int ch = 0; ch < 2; ++ch)
        output.addFrom(ch, targetStart, rendered, ch, 0, targetCount);
}

juce::String renderPitchLabAudioNative(const juce::File &sourceFile,
                                       const juce::File &outFile,
                                       double trimStartMs,
                                       double trimEndMs,
                                       double sourceTimelineDurationMs,
                                       double outputDurationMs,
                                       std::vector<PitchLabRange> suppressedRanges,
                                       const std::vector<PitchLabSegment> &segments)
{
    juce::AudioFormatManager formatManager;
    formatManager.registerBasicFormats();
    std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(sourceFile));
    if (!reader)
        return {};
    if (trimEndMs <= trimStartMs)
        trimEndMs = (double)reader->lengthInSamples * 1000.0 / juce::jmax(1.0, reader->sampleRate);

    const double outputSampleRate = 48000.0;
    const int outputSamples = juce::jlimit(1, (int)(outputSampleRate * 60.0 * 12.0), (int)std::ceil(outputDurationMs * outputSampleRate / 1000.0));
    juce::AudioBuffer<float> output(2, outputSamples);
    output.clear();
    std::sort(suppressedRanges.begin(), suppressedRanges.end(), [](const PitchLabRange &a, const PitchLabRange &b)
              { return a.startMs < b.startMs; });

    double cursorMs = 0.0;
    for (const auto &range : suppressedRanges)
    {
        const double startMs = juce::jlimit(0.0, sourceTimelineDurationMs, range.startMs);
        const double endMs = juce::jlimit(0.0, sourceTimelineDurationMs, range.endMs);
        if (startMs > cursorMs + 4.0)
            pitchLabMixSourceRange(*reader, output, outputSampleRate,
                                   pitchLabLocalMsToFileSec(cursorMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                                   pitchLabLocalMsToFileSec(startMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                                   cursorMs, startMs, 0.0);
        cursorMs = juce::jmax(cursorMs, endMs);
    }
    if (cursorMs < sourceTimelineDurationMs - 4.0)
        pitchLabMixSourceRange(*reader, output, outputSampleRate,
                               pitchLabLocalMsToFileSec(cursorMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               pitchLabLocalMsToFileSec(sourceTimelineDurationMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               cursorMs, sourceTimelineDurationMs, 0.0);

    for (const auto &segment : segments)
        pitchLabMixSourceRange(*reader, output, outputSampleRate,
                               pitchLabLocalMsToFileSec(segment.originalStartMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               pitchLabLocalMsToFileSec(segment.originalEndMs, trimStartMs, trimEndMs, sourceTimelineDurationMs),
                               segment.targetStartMs, segment.targetEndMs, segment.semitones);

    for (int ch = 0; ch < output.getNumChannels(); ++ch)
    {
        auto *samples = output.getWritePointer(ch);
        for (int i = 0; i < output.getNumSamples(); ++i)
            samples[i] = std::tanh(samples[i] * 0.98f);
    }

    outFile.deleteFile();
    std::unique_ptr<juce::FileOutputStream> stream(outFile.createOutputStream());
    if (!stream)
        return {};
    juce::WavAudioFormat wav;
    std::unique_ptr<juce::AudioFormatWriter> writer(wav.createWriterFor(stream.get(), outputSampleRate, 2, 24, {}, 0));
    if (!writer)
        return {};
    stream.release();
    if (!writer->writeFromAudioSampleBuffer(output, 0, output.getNumSamples()))
        return {};
    return outFile.getFullPathName();
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
    ensureJuceAndroidRuntimeInitialised(env);
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
    if (rootPath == nullptr)
        return;
    const char *c = env->GetStringUTFChars(rootPath, nullptr);
    if (c == nullptr)
        return;
    const juce::String jucePath = juce::String::fromUTF8(c);
    env->ReleaseStringUTFChars(rootPath, c);
    TimelineMidiClipProcessor::setFlutterAssetRootPath(jucePath);
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

    if (!ensureJuceAndroidRuntimeInitialised(env))
        return;

    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI passed step1");
    __android_log_print(ANDROID_LOG_INFO, "JUCE", "🧠 JNI passed step2");
    JuceEngine::get().initialiseEngine();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_initialisePlaybackV2JNI(JNIEnv *env, jclass)
{
    if (!ensureJuceAndroidRuntimeInitialised(env))
        return JNI_FALSE;

    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success]
                     { success = JuceEngine::get().initialisePlaybackV2Android(); });
    else
        success = JuceEngine::get().initialisePlaybackV2Android();
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_quiescePlaybackV2JNI(
    JNIEnv *, jclass, jboolean closeDevice)
{
    bool wasPlaying = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&wasPlaying, closeDevice]
                     { wasPlaying = JuceEngine::get().quiescePlaybackV2Android(closeDevice != JNI_FALSE); });
    else
        wasPlaying = JuceEngine::get().quiescePlaybackV2Android(closeDevice != JNI_FALSE);
    return wasPlaying ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_reconfigurePlaybackV2JNI(JNIEnv *, jclass)
{
    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success]
                     { success = JuceEngine::get().reconfigurePlaybackV2Android(); });
    else
        success = JuceEngine::get().reconfigurePlaybackV2Android();
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_prepareRecordingV2JNI(JNIEnv *, jclass, jint inputChannels)
{
    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success, inputChannels]
                     { success = JuceEngine::get().prepareRecordingV2Android((int)inputChannels); });
    else
        success = JuceEngine::get().prepareRecordingV2Android((int)inputChannels);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_prepareSystemSelectedMediaDuplexV2JNI(
    JNIEnv *, jclass, jint inputChannels)
{
    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success, inputChannels]
                     { success = JuceEngine::get().prepareSystemSelectedMediaDuplexV2Android((int)inputChannels); });
    else
        success = JuceEngine::get().prepareSystemSelectedMediaDuplexV2Android((int)inputChannels);
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_prepareBluetoothDuplexV2JNI(
    JNIEnv *, jclass)
{
    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success]
                     { success = JuceEngine::get().prepareBluetoothDuplexV2Android(); });
    else
        success = JuceEngine::get().prepareBluetoothDuplexV2Android();
    return success ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_waitForV2CallbackReadyJNI(
    JNIEnv *, jclass, jint timeoutMs)
{
    return JuceEngine::get().waitForV2CallbackReady((int)timeoutMs)
               ? JNI_TRUE
               : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_beginBluetoothMediaRouteMigrationV2JNI(
    JNIEnv *, jclass)
{
    return static_cast<jlong> (
        mixroom::android_audio_v2::beginBluetoothMediaRouteMigration());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_waitForBluetoothMediaRouteMigrationV2JNI(
    JNIEnv *, jclass, jlong token, jint timeoutMs)
{
    return mixroom::android_audio_v2::waitForBluetoothMediaRouteMigration (
               static_cast<uint64_t> (token),
               juce::jlimit (1, 5000, static_cast<int> (timeoutMs)))
               ? JNI_TRUE
               : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_finishBluetoothMediaRouteMigrationV2JNI(
    JNIEnv *, jclass, jlong token)
{
    mixroom::android_audio_v2::finishBluetoothMediaRouteMigration (
        static_cast<uint64_t> (token));
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setBluetoothMediaPlaybackPolicyV2JNI(
    JNIEnv *, jclass, jboolean enabled)
{
    mixroom::android_audio_v2::setBluetoothMediaPolicyEnabled(enabled != JNI_FALSE);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAndroidStreamPolicyV2JNI(
    JNIEnv *, jclass, jint policy)
{
    using Policy = mixroom::android_audio_v2::StreamPolicy;
    const auto selected = policy == static_cast<jint> (Policy::bluetoothMedia)
                              ? Policy::bluetoothMedia
                              : policy == static_cast<jint> (Policy::bluetoothCommunicationDuplex)
                                    ? Policy::bluetoothCommunicationDuplex
                                    : Policy::normal;
    mixroom::android_audio_v2::setStreamPolicy(selected);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_resetPlaybackPolicyV2JNI(JNIEnv *, jclass)
{
    mixroom::android_audio_v2::resetPlaybackPolicy();
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getOboeOutputStreamFactsV2JNI(JNIEnv *env, jclass)
{
    const auto facts = mixroom::android_audio_v2::getOutputStreamFacts();
    juce::NamedValueSet values;
    values.set("available", facts.available);
    values.set("running", facts.running);
    if (facts.available)
    {
        values.set("streamEpoch", static_cast<juce::int64>(facts.streamEpoch));
        values.set("routedDeviceId", facts.routedDeviceId);
        values.set("channelCount", facts.channelCount);
        values.set("requestedSampleRateHz", facts.requestedSampleRate);
        values.set("sampleRateHz", facts.sampleRate);
        values.set("requestedBufferFrames", facts.requestedBufferSizeFrames);
        values.set("bufferFrames", facts.bufferSizeFrames);
        values.set("bufferCapacityFrames", facts.bufferCapacityFrames);
        values.set("framesPerBurst", facts.framesPerBurst);
        values.set("framesPerCallback", facts.framesPerCallback);
        if (facts.xRunCount >= 0)
            values.set("xRunCount", facts.xRunCount);
        values.set("audioBackend", juce::String(facts.audioApi));
        values.set("performanceMode", juce::String(facts.performanceMode));
        values.set("sharingMode", juce::String(facts.sharingMode));
        values.set("streamState", juce::String(facts.streamState));
    }
    return namedValueStatsToJavaMap(env, values);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getOboeInputStreamFactsV2JNI(JNIEnv *env, jclass)
{
    const auto facts = mixroom::android_audio_v2::getInputStreamFacts();
    juce::NamedValueSet values;
    values.set("available", facts.available);
    values.set("running", facts.running);
    if (facts.available)
    {
        values.set("streamEpoch", static_cast<juce::int64>(facts.streamEpoch));
        values.set("routedDeviceId", facts.routedDeviceId);
        values.set("channelCount", facts.channelCount);
        values.set("requestedSampleRateHz", facts.requestedSampleRate);
        values.set("sampleRateHz", facts.sampleRate);
        values.set("requestedBufferFrames", facts.requestedBufferSizeFrames);
        values.set("bufferFrames", facts.bufferSizeFrames);
        values.set("bufferCapacityFrames", facts.bufferCapacityFrames);
        values.set("framesPerBurst", facts.framesPerBurst);
        values.set("framesPerCallback", facts.framesPerCallback);
        if (facts.xRunCount >= 0)
            values.set("xRunCount", facts.xRunCount);
        values.set("audioBackend", juce::String(facts.audioApi));
        values.set("performanceMode", juce::String(facts.performanceMode));
        values.set("sharingMode", juce::String(facts.sharingMode));
        values.set("streamState", juce::String(facts.streamState));
    }
    return namedValueStatsToJavaMap(env, values);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_shutdownEngineJNI(JNIEnv *, jclass)
{
    juce::MessageManager::callAsync([]
                                    { JuceEngine::get().shutdownEngine(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_shutdownEngineSynchronouslyJNI(JNIEnv *, jclass)
{
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([]
                     { JuceEngine::get().shutdownEngine(); });
        return;
    }
    JuceEngine::get().shutdownEngine();
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

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_playPlaybackV2JNI(JNIEnv *, jclass)
{
    bool success = false;
    if (auto *mm = juce::MessageManager::getInstance())
        mm->callSync([&success]
                     { success = JuceEngine::get().playPlaybackV2Android(); });
    else
        success = JuceEngine::get().playPlaybackV2Android();
    return success ? JNI_TRUE : JNI_FALSE;
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
    juce::MessageManager::getInstance()->callSync([clipIndex, startSec, lengthSec, inFileOffsetSec]
                                                  { JuceEngine::get().setClipTime((int)clipIndex, (double)startSec, (double)lengthSec, (double)inFileOffsetSec); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_updateClipTimelineBatchJNI(JNIEnv *env,
                                                                           jclass,
                                                                           jobject updatesList)
{
    juce::Array<juce::NamedValueSet> updates;
    if (updatesList != nullptr)
    {
        jclass listClass = env->FindClass("java/util/List");
        jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
        jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
        jclass mapClass = env->FindClass("java/util/Map");
        jstring keyClip = env->NewStringUTF("clip");
        jstring keyRowId = env->NewStringUTF("rowId");
        jstring keyStartSec = env->NewStringUTF("startSec");
        jstring keyLengthSec = env->NewStringUTF("lengthSec");
        jstring keyInFileOffsetSec = env->NewStringUTF("inFileOffsetSec");
        jstring keyGain = env->NewStringUTF("gain");
        jstring keyExtraGainLinear = env->NewStringUTF("extraGainLinear");
        jstring keyReversed = env->NewStringUTF("reversed");
        jstring keyTempoRatio = env->NewStringUTF("tempoRatio");
        jstring keyPreservePitch = env->NewStringUTF("preservePitch");
        jstring keyPitchSemitones = env->NewStringUTF("pitchSemitones");
        jstring keyMuted = env->NewStringUTF("muted");

        const jint count = env->CallIntMethod(updatesList, sizeMethod);
        updates.ensureStorageAllocated((int)count);
        for (jint i = 0; i < count; ++i)
        {
            jobject entry = env->CallObjectMethod(updatesList, getMethod, i);
            if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
            {
                if (entry != nullptr)
                    env->DeleteLocalRef(entry);
                continue;
            }

            jobject clipObj = javaMapValue(env, entry, keyClip);
            const int clip = javaObjectToInt(env, clipObj, -1);
            if (clip >= 0)
            {
                juce::NamedValueSet update;
                update.set("clip", clip);

                jobject rowIdObj = javaMapValue(env, entry, keyRowId);
                if (rowIdObj != nullptr)
                    update.set("rowId", javaObjectToInt(env, rowIdObj, -1));

                jobject startSecObj = javaMapValue(env, entry, keyStartSec);
                if (startSecObj != nullptr)
                    update.set("startSec", javaObjectToDouble(env, startSecObj, 0.0));

                jobject lengthSecObj = javaMapValue(env, entry, keyLengthSec);
                if (lengthSecObj != nullptr)
                    update.set("lengthSec", javaObjectToDouble(env, lengthSecObj, 0.0));

                jobject inFileOffsetSecObj = javaMapValue(env, entry, keyInFileOffsetSec);
                if (inFileOffsetSecObj != nullptr)
                    update.set("inFileOffsetSec", javaObjectToDouble(env, inFileOffsetSecObj, 0.0));

                jobject gainObj = javaMapValue(env, entry, keyGain);
                if (gainObj != nullptr)
                    update.set("gain", javaObjectToDouble(env, gainObj, 1.0));

                jobject extraGainLinearObj = javaMapValue(env, entry, keyExtraGainLinear);
                if (extraGainLinearObj != nullptr)
                    update.set("extraGainLinear", javaObjectToDouble(env, extraGainLinearObj, 1.0));

                jobject reversedObj = javaMapValue(env, entry, keyReversed);
                if (reversedObj != nullptr)
                    update.set("reversed", javaObjectToBool(env, reversedObj));

                jobject tempoRatioObj = javaMapValue(env, entry, keyTempoRatio);
                if (tempoRatioObj != nullptr)
                    update.set("tempoRatio", javaObjectToDouble(env, tempoRatioObj, 1.0));

                jobject preservePitchObj = javaMapValue(env, entry, keyPreservePitch);
                if (preservePitchObj != nullptr)
                    update.set("preservePitch", javaObjectToBool(env, preservePitchObj, true));

                jobject pitchSemitonesObj = javaMapValue(env, entry, keyPitchSemitones);
                if (pitchSemitonesObj != nullptr)
                    update.set("pitchSemitones", javaObjectToDouble(env, pitchSemitonesObj, 0.0));

                jobject mutedObj = javaMapValue(env, entry, keyMuted);
                if (mutedObj != nullptr)
                    update.set("muted", javaObjectToBool(env, mutedObj));

                updates.add(update);

                if (rowIdObj != nullptr)
                    env->DeleteLocalRef(rowIdObj);
                if (startSecObj != nullptr)
                    env->DeleteLocalRef(startSecObj);
                if (lengthSecObj != nullptr)
                    env->DeleteLocalRef(lengthSecObj);
                if (inFileOffsetSecObj != nullptr)
                    env->DeleteLocalRef(inFileOffsetSecObj);
                if (gainObj != nullptr)
                    env->DeleteLocalRef(gainObj);
                if (extraGainLinearObj != nullptr)
                    env->DeleteLocalRef(extraGainLinearObj);
                if (reversedObj != nullptr)
                    env->DeleteLocalRef(reversedObj);
                if (tempoRatioObj != nullptr)
                    env->DeleteLocalRef(tempoRatioObj);
                if (preservePitchObj != nullptr)
                    env->DeleteLocalRef(preservePitchObj);
                if (pitchSemitonesObj != nullptr)
                    env->DeleteLocalRef(pitchSemitonesObj);
                if (mutedObj != nullptr)
                    env->DeleteLocalRef(mutedObj);
            }

            if (clipObj != nullptr)
                env->DeleteLocalRef(clipObj);
            env->DeleteLocalRef(entry);
        }

        env->DeleteLocalRef(keyClip);
        env->DeleteLocalRef(keyRowId);
        env->DeleteLocalRef(keyStartSec);
        env->DeleteLocalRef(keyLengthSec);
        env->DeleteLocalRef(keyInFileOffsetSec);
        env->DeleteLocalRef(keyGain);
        env->DeleteLocalRef(keyExtraGainLinear);
        env->DeleteLocalRef(keyReversed);
        env->DeleteLocalRef(keyTempoRatio);
        env->DeleteLocalRef(keyPreservePitch);
        env->DeleteLocalRef(keyPitchSemitones);
        env->DeleteLocalRef(keyMuted);
    }

    int applied = 0;
    juce::MessageManager::getInstance()->callSync([&updates, &applied]
                                                  { applied = JuceEngine::get().updateClipTimelineBatch(updates); });
    return (jint)applied;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_updateClipFadesBatchJNI(JNIEnv *env,
                                                                        jclass,
                                                                        jobject updatesList)
{
    juce::Array<juce::NamedValueSet> updates;
    if (updatesList != nullptr)
    {
        jclass listClass = env->FindClass("java/util/List");
        jmethodID sizeMethod = env->GetMethodID(listClass, "size", "()I");
        jmethodID getMethod = env->GetMethodID(listClass, "get", "(I)Ljava/lang/Object;");
        jclass mapClass = env->FindClass("java/util/Map");
        jstring keyClip = env->NewStringUTF("clip");
        jstring keyFadeInSec = env->NewStringUTF("fadeInSec");
        jstring keyFadeOutSec = env->NewStringUTF("fadeOutSec");
        jstring keyFadeCurve = env->NewStringUTF("fadeCurve");

        const jint count = env->CallIntMethod(updatesList, sizeMethod);
        updates.ensureStorageAllocated((int)count);
        for (jint i = 0; i < count; ++i)
        {
            jobject entry = env->CallObjectMethod(updatesList, getMethod, i);
            if (entry == nullptr || !env->IsInstanceOf(entry, mapClass))
            {
                if (entry != nullptr)
                    env->DeleteLocalRef(entry);
                continue;
            }

            jobject clipObj = javaMapValue(env, entry, keyClip);
            const int clip = javaObjectToInt(env, clipObj, -1);
            if (clip >= 0)
            {
                jobject fadeInObj = javaMapValue(env, entry, keyFadeInSec);
                jobject fadeOutObj = javaMapValue(env, entry, keyFadeOutSec);
                jobject fadeCurveObj = javaMapValue(env, entry, keyFadeCurve);

                juce::NamedValueSet update;
                update.set("clip", clip);
                update.set("fadeInSec", javaObjectToDouble(env, fadeInObj, 0.0));
                update.set("fadeOutSec", javaObjectToDouble(env, fadeOutObj, 0.0));
                update.set("fadeCurve", javaObjectToInt(env, fadeCurveObj, 0));
                updates.add(update);

                if (fadeInObj != nullptr)
                    env->DeleteLocalRef(fadeInObj);
                if (fadeOutObj != nullptr)
                    env->DeleteLocalRef(fadeOutObj);
                if (fadeCurveObj != nullptr)
                    env->DeleteLocalRef(fadeCurveObj);
            }

            if (clipObj != nullptr)
                env->DeleteLocalRef(clipObj);
            env->DeleteLocalRef(entry);
        }

        env->DeleteLocalRef(keyClip);
        env->DeleteLocalRef(keyFadeInSec);
        env->DeleteLocalRef(keyFadeOutSec);
        env->DeleteLocalRef(keyFadeCurve);
    }

    int applied = 0;
    juce::MessageManager::getInstance()->callSync([&updates, &applied]
                                                  { applied = JuceEngine::get().updateClipFadesBatch(updates); });
    return (jint)applied;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPanJNI(JNIEnv *, jclass, jint clipIndex, jfloat pan)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, pan]
                                                  { JuceEngine::get().setClipPan((int)clipIndex, (float)pan); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipFadesJNI(JNIEnv *, jclass, jint clipIndex, jdouble fadeInSec, jdouble fadeOutSec, jint fadeCurve)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, fadeInSec, fadeOutSec, fadeCurve]
                                                  { JuceEngine::get().setClipFades((int)clipIndex, (double)fadeInSec, (double)fadeOutSec, (int)fadeCurve); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipPitchJNI(JNIEnv *, jclass, jint clipIndex, jfloat semitones)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, semitones]
                                                  { JuceEngine::get().setClipPitch((int)clipIndex, (float)semitones); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipReversedJNI(JNIEnv *, jclass, jint clipIndex, jboolean reversed)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, reversed]
                                                  { JuceEngine::get().setClipReversed((int)clipIndex, reversed != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipStretchOptionsJNI(JNIEnv *, jclass, jint clipIndex, jdouble tempoRatio, jboolean preservePitch)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, tempoRatio, preservePitch]
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

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_beginProjectClipLoadTransactionJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().beginProjectClipLoadTransaction(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_endProjectClipLoadTransactionJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().endProjectClipLoadTransaction(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_beginGraphMutationBatchJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().beginGraphMutationBatch(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_endGraphMutationBatchJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().endGraphMutationBatch(); });
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
                                                                 jdouble inFileOffsetSec,
                                                                 jlong loadRequestId)
{
    const juce::String id = juceStringFromJString(env, instrumentId);
    const juce::String name = juceStringFromJString(env, instrumentName);
    const auto notes = parseTimelineMidiNotes(env, notesList);
    const auto params = parseNamedValueSet(env, paramsMap);

    const auto prepared = JuceEngine::get().prepareBuiltInMidiClipLoad(
        (int)clipIndex,
        (int)rowId,
        id,
        name,
        notes,
        params,
        (double)sourceTempoBpm,
        (double)startSec,
        (double)lengthSec,
        (double)inFileOffsetSec,
        (std::int64_t)loadRequestId);
    if (prepared == nullptr)
        return JNI_FALSE;

    bool ok = false;
    auto installMidiClip = [&]
    {
        ok = JuceEngine::get().installPreparedMidiClipLoad(prepared);
    };

    if (auto *mm = juce::MessageManager::getInstance())
    {
        if (mm->isThisTheMessageThread())
            installMidiClip();
        else
            mm->callSync(installMidiClip);
    }
    else
    {
        installMidiClip();
    }

    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_cancelMidiClipLoadJNI(
    JNIEnv *, jclass, jint clipIndex, jlong loadRequestId)
{
    std::atomic<bool> ok{false};
    auto cancelLoad = [&]
    {
        ok = JuceEngine::get().cancelMidiClipLoad(
            (int)clipIndex, (std::int64_t)loadRequestId);
    };
    if (auto *mm = juce::MessageManager::getInstance())
    {
        if (mm->isThisTheMessageThread())
            cancelLoad();
        else
            mm->callSync(cancelLoad);
    }
    else
    {
        cancelLoad();
    }
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

    if (!JuceEngine::get().prepareMidiClipSampleAssets(id, name, notes))
        return JNI_FALSE;

    bool ok = false;
    auto updateMidiClip = [&]
    {
        ok = JuceEngine::get().updateMidiClipEvents(
            (int)clipIndex,
            id,
            name,
            notes,
            params,
            (double)sourceTempoBpm);
    };

    if (auto *mm = juce::MessageManager::getInstance())
    {
        if (mm->isThisTheMessageThread())
            updateMidiClip();
        else
            mm->callSync(updateMidiClip);
    }
    else
    {
        updateMidiClip();
    }

    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLiveMidiInputTargetClipJNI(JNIEnv *, jclass, jint clipIndex)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().setLiveMidiInputTargetClip((int)clipIndex); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_playPreviewMidiNoteJNI(JNIEnv *,
                                                                        jclass,
                                                                        jint clipIndex,
                                                                        jint pitch,
                                                                        jfloat velocity,
                                                                        jint durationMs)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().playPreviewMidiNote(
            (int)clipIndex,
            (int)pitch,
            (float)velocity,
            (int)durationMs); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_sendLiveMidiInputEventJNI(JNIEnv *,
                                                                          jclass,
                                                                          jboolean noteOn,
                                                                          jint channel,
                                                                          jint pitch,
                                                                          jfloat velocity)
{
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
        ok = JuceEngine::get().sendLiveMidiInputEvent(
            noteOn == JNI_TRUE,
            (int)channel,
            (int)pitch,
            (float)velocity); });
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getHostSampleRateJNI(JNIEnv *env, jclass)
{
    if (!ensureJuceAndroidRuntimeInitialised(env))
        return 44100.0;

    std::atomic<double> result{44100.0};
    juce::MessageManager::getInstance()->callSync([&result]
                                                  { result = JuceEngine::get().getHostSampleRate(); });
    return result.load();
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRecentMasterStereoWaveformJNI(JNIEnv *env, jclass, jint sampleCount)
{
    if (!ensureJuceAndroidRuntimeInitialised(env))
        return env->NewDoubleArray(0);

    std::vector<float> waveform;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { waveform = JuceEngine::get().getRecentMasterStereoWaveform((int)sampleCount); });
    return floatVectorToJDoubleArray(env, waveform);
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
                                                              jint mp3BitrateKbps,
                                                              jstring clipSnapshotJson,
                                                              jboolean dryClipRender)
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
    options.dryClipRender = (dryClipRender == JNI_TRUE);
    if (clipSnapshotJson != nullptr)
    {
        const char *clipSnapshotChars = env->GetStringUTFChars(clipSnapshotJson, nullptr);
        options.clipSnapshotJson = clipSnapshotChars != nullptr ? juce::String::fromUTF8(clipSnapshotChars) : juce::String();
        env->ReleaseStringUTFChars(clipSnapshotJson, clipSnapshotChars);
    }

    flushPendingMessageThreadTasks();
    juce::String result = JuceEngine::get().exportMix(juce::File(jucePath), options);
    return env->NewStringUTF(result.toRawUTF8());
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getExportProgressJNI(JNIEnv *,
                                                                      jclass)
{
    return (jdouble)JuceEngine::get().getExportProgress();
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

    flushPendingMessageThreadTasks();
    juce::String result = JuceEngine::get().exportTrack(trackIdx, juce::File(jucePath), options);
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
            if (e.contains("unit"))
                putStr(map, "unit", e["unit"].toString());

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

    auto file = juce::File(jucePath);
    auto preparedAsset = JuceEngine::get().prepareClipAudioAsset(file);
    juce::MessageManager::callAsync([jucePath, preparedAsset]
                                    { JuceEngine::get().loadVideoAudioWithPreparedAudioAsset(
                                          juce::File(jucePath),
                                          preparedAsset); });
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

extern "C" JNIEXPORT jboolean JNICALL
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
    juce::File file(jucePath);
    auto preparedAsset = JuceEngine::get().prepareClipAudioAsset(file);
    if (preparedAsset == nullptr)
        return false;

    bool ok = false;
    auto installPreparedClip = [&]
    {
        ok = JuceEngine::get().loadClipWithPreparedAudioAsset((int)clipIndex,
                                                              (int)rowId,
                                                              file,
                                                              preparedAsset,
                                                              (double)startSec,
                                                              (double)lengthSec,
                                                              (double)inFileOffsetSec);
    };

    if (auto *mm = juce::MessageManager::getInstance())
    {
        if (mm->isThisTheMessageThread())
            installPreparedClip();
        else
            mm->callSync(installPreparedClip);
    }
    else
    {
        installPreparedClip();
    }

    return ok;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadClipJNI(JNIEnv *, jclass, jint clipIndex)
{
    juce::MessageManager::getInstance()->callSync([clipIndex]
                                                  { JuceEngine::get().unloadClip((int)clipIndex); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadClipsJNI(JNIEnv *env,
                                                               jclass,
                                                               jintArray clipIndices)
{
    juce::Array<int> clips;
    if (clipIndices != nullptr)
    {
        const jsize count = env->GetArrayLength(clipIndices);
        clips.ensureStorageAllocated((int)count);
        jint *values = env->GetIntArrayElements(clipIndices, nullptr);
        if (values != nullptr)
        {
            for (jsize i = 0; i < count; ++i)
                clips.addIfNotAlreadyThere((int)values[i]);
            env->ReleaseIntArrayElements(clipIndices, values, JNI_ABORT);
        }
    }

    int removed = 0;
    juce::MessageManager::getInstance()->callSync([&clips, &removed]
                                                  { removed = JuceEngine::get().unloadClips(clips); });
    return (jint)removed;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipGainJNI(JNIEnv *, jclass, jint clipIndex, jfloat gain)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipGain((int)clipIndex, (float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setClipExtraGainLinearJNI(JNIEnv *, jclass, jint clipIndex, jfloat gain)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, gain]
                                                  { JuceEngine::get().setClipExtraGainLinear((int)clipIndex, (float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteClipJNI(JNIEnv *, jclass, jint clipIndex, jboolean mute)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, mute]
                                                  { JuceEngine::get().muteClip((int)clipIndex, mute != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_moveClipToRowJNI(JNIEnv *, jclass, jint clipIndex, jint newRowId)
{
    juce::MessageManager::getInstance()->callSync([clipIndex, newRowId]
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLoopRegionJNI(
    JNIEnv *, jclass, jboolean enabled, jdouble startSeconds, jdouble endSeconds)
{
    const bool loopEnabled = enabled != JNI_FALSE;
    if (auto *mm = juce::MessageManager::getInstance())
    {
        mm->callSync([loopEnabled, startSeconds, endSeconds]
                     { JuceEngine::get().setLoopRegion(
                           loopEnabled, (double)startSeconds, (double)endSeconds); });
        return;
    }
    JuceEngine::get().setLoopRegion(
        loopEnabled, (double)startSeconds, (double)endSeconds);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAutomationTransportJNI(JNIEnv *, jclass, jdouble timeSeconds)
{
    juce::MessageManager::callAsync([timeSeconds]
                                    { JuceEngine::get().setAutomationTransport((double)timeSeconds); });
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_addRowJNI(JNIEnv *env, jclass, jstring name, jint iconId, jint preferredRowId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().addRow(rowName, (int)iconId, (int)preferredRowId); });
    return (jint)rowId.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowAboveJNI(JNIEnv *env,
                                                                   jclass,
                                                                   jint referenceRowId,
                                                                   jstring name,
                                                                   jint iconId,
                                                                   jint preferredRowId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().insertRowAbove((int)referenceRowId, rowName, (int)iconId, (int)preferredRowId); });
    return (jint)rowId.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertRowBelowJNI(JNIEnv *env,
                                                                   jclass,
                                                                   jint referenceRowId,
                                                                   jstring name,
                                                                   jint iconId,
                                                                   jint preferredRowId)
{
    const juce::String rowName = juceStringFromJString(env, name);
    std::atomic<int> rowId{-1};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { rowId = JuceEngine::get().insertRowBelow((int)referenceRowId, rowName, (int)iconId, (int)preferredRowId); });
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertTrackEffectJNI(JNIEnv *env, jclass, jint row, jstring pluginPath, jboolean forceIndividualRow)
{
    const juce::String path = juceStringFromJString(env, pluginPath);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().insertTrackEffect((int)row, path, forceIndividualRow != JNI_FALSE); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackEffectJNI(JNIEnv *, jclass, jint row, jint effectIndex, jboolean forceIndividualRow)
{
    juce::MessageManager::getInstance()->callSync([row, effectIndex, forceIndividualRow]
                                                  { JuceEngine::get().removeTrackEffect((int)row, (int)effectIndex, forceIndividualRow != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderTrackEffectsJNI(JNIEnv *, jclass, jint row, jint fromIndex, jint toIndex, jboolean forceIndividualRow)
{
    juce::MessageManager::getInstance()->callSync([row, fromIndex, toIndex, forceIndividualRow]
                                                  { JuceEngine::get().reorderTrackEffects((int)row, (int)fromIndex, (int)toIndex, forceIndividualRow != JNI_FALSE); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsForRowJNI(JNIEnv *env, jclass, jint row, jboolean forceIndividualRow)
{
    juce::StringArray names;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { names = JuceEngine::get().getTrackEffectsForRow((int)row, forceIndividualRow != JNI_FALSE); });
    return stringArrayToJavaList(env, names);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectIdsForRowJNI(JNIEnv *env, jclass, jint row, jboolean forceIndividualRow)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getTrackEffectIdsForRow((int)row, forceIndividualRow != JNI_FALSE); });
    return stringArrayToJavaList(env, ids);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectInstanceIdsForRowJNI(JNIEnv *env, jclass, jint row, jboolean forceIndividualRow)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getTrackEffectInstanceIdsForRow((int)row, forceIndividualRow != JNI_FALSE); });
    return stringArrayToJavaList(env, ids);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackPluginParametersJNI(JNIEnv *env, jclass, jint row, jint effectIndex, jboolean forceIndividualRow)
{
    juce::Array<juce::NamedValueSet> params;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { params = JuceEngine::get().getTrackPluginParameterInfo((int)row, (int)effectIndex, forceIndividualRow != JNI_FALSE); });
    return namedValueSetArrayToJavaParameterList(env, params);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackEffectJNI(
    JNIEnv *env, jclass, jint row, jint effectIndex, jstring paramId, jobject valueObj, jboolean forceIndividualRow)
{
    const juce::String param = juceStringFromJString(env, paramId);
    const juce::var value = javaObjectToVar(env, valueObj);
    juce::MessageManager::getInstance()->callSync([row, effectIndex, param, value, forceIndividualRow]
                                                  { JuceEngine::get().setTrackEffectParameter((int)row, (int)effectIndex, param, value, forceIndividualRow != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassRowEffectJNI(JNIEnv *, jclass, jint row, jint effectIndex, jboolean bypass, jboolean forceIndividualRow)
{
    juce::MessageManager::getInstance()->callSync([row, effectIndex, bypass, forceIndividualRow]
                                                  { JuceEngine::get().bypassRowEffect((int)row, (int)effectIndex, bypass != JNI_FALSE, forceIndividualRow != JNI_FALSE); });
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowEffectBypassStateJNI(JNIEnv *, jclass, jint row, jint effectIndex, jboolean forceIndividualRow)
{
    std::atomic<bool> state{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { state = JuceEngine::get().getRowEffectBypassState((int)row, (int)effectIndex, forceIndividualRow != JNI_FALSE); });
    return state.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackAutomationPointsJNI(JNIEnv *env, jclass, jint row, jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 3.0f);
    juce::MessageManager::getInstance()->callSync([row, points = std::move(points)]() mutable
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
    juce::MessageManager::getInstance()->callSync([row, effectIndex, param, minValue, maxValue, points = std::move(points)]() mutable
                                                  { JuceEngine::get().setTrackEffectAutomationPoints((int)row, (int)effectIndex, param, (float)minValue, (float)maxValue, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearTrackEffectAutomationForRowJNI(
    JNIEnv *,
    jclass,
    jint row)
{
    juce::MessageManager::getInstance()->callSync([row]
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
    juce::MessageManager::getInstance()->callSync([row, points = std::move(points)]() mutable
                                                  { JuceEngine::get().setRowGainAutomationPoints((int)row, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowGainJNI(JNIEnv *, jclass, jint row, jfloat gain)
{
    juce::MessageManager::getInstance()->callSync([row, gain]
                                                  { JuceEngine::get().setRowGain((int)row, (float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteRowJNI(JNIEnv *, jclass, jint row, jboolean mute)
{
    juce::MessageManager::getInstance()->callSync([row, mute]
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
    juce::MessageManager::getInstance()->callSync([row, points = std::move(points)]() mutable
                                                  { JuceEngine::get().setRowPanAutomationPoints((int)row, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setRowPanJNI(JNIEnv *, jclass, jint row, jfloat pan)
{
    juce::MessageManager::getInstance()->callSync([row, pan]
                                                  { JuceEngine::get().setRowPan((int)row, (float)pan); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_configureTrackGroupsJNI(JNIEnv *env, jclass, jobject groupsList)
{
    auto groups = parseTrackGroups(env, groupsList);
    juce::MessageManager::getInstance()->callSync([groups]() mutable
                                                  { JuceEngine::get().configureTrackGroups(groups); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_assignRowToGroupJNI(JNIEnv *env, jclass, jint row, jstring groupId)
{
    const juce::String id = juceStringFromJString(env, groupId);
    juce::MessageManager::getInstance()->callSync([row, id]
                                                  { JuceEngine::get().assignRowToGroup((int)row, id); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackGroupMixStateJNI(
    JNIEnv *env,
    jclass,
    jstring groupId,
    jfloat gain,
    jfloat pan,
    jboolean muted,
    jboolean soloed)
{
    const juce::String id = juceStringFromJString(env, groupId);
    juce::MessageManager::getInstance()->callSync([id, gain, pan, muted, soloed]
                                                  { JuceEngine::get().setTrackGroupMixState(id, (float)gain, (float)pan, muted != JNI_FALSE, soloed != JNI_FALSE); });
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterEffectInstanceIdsJNI(JNIEnv *env, jclass)
{
    juce::StringArray ids;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ids = JuceEngine::get().getMasterEffectInstanceIds(); });
    return stringArrayToJavaList(env, ids);
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
    juce::MessageManager::getInstance()->callSync([effectIndex, param, value]
                                                  { JuceEngine::get().setMasterEffectParameter((int)effectIndex, param, value); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassMasterEffectJNI(JNIEnv *, jclass, jint effectIndex, jboolean bypass)
{
    juce::MessageManager::getInstance()->callSync([effectIndex, bypass]
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
    juce::MessageManager::getInstance()->callSync([effectIndex, param, minValue, maxValue, points = std::move(points)]() mutable
                                                  { JuceEngine::get().setMasterEffectAutomationPoints((int)effectIndex, param, (float)minValue, (float)maxValue, points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_clearMasterEffectAutomationJNI(
    JNIEnv *,
    jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().clearMasterEffectAutomation(); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::getInstance()->callSync([points = std::move(points)]() mutable
                                                  { JuceEngine::get().setMasterGainAutomationPoints(points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterGainJNI(JNIEnv *, jclass, jfloat gain)
{
    juce::MessageManager::getInstance()->callSync([gain]
                                                  { JuceEngine::get().setMasterGain((float)gain); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_muteMasterJNI(JNIEnv *, jclass, jboolean mute)
{
    juce::MessageManager::getInstance()->callSync([mute]
                                                  { JuceEngine::get().muteMaster(mute != JNI_FALSE); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanAutomationPointsJNI(
    JNIEnv *env,
    jclass,
    jobject pointsList)
{
    auto points = parseAutomationPoints(env, pointsList, 1.0f);
    juce::MessageManager::getInstance()->callSync([points = std::move(points)]() mutable
                                                  { JuceEngine::get().setMasterPanAutomationPoints(points); });
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMasterPanJNI(JNIEnv *, jclass, jfloat pan)
{
    juce::MessageManager::getInstance()->callSync([pan]
                                                  { JuceEngine::get().setMasterPan((float)pan); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getEngineDiagnosticsJNI(JNIEnv *env, jclass)
{
    juce::NamedValueSet diagnostics;
    juce::MessageManager::getInstance()->callSync([&diagnostics]
                                                  { diagnostics = JuceEngine::get().getEngineDiagnostics(); });
    return namedValueStatsToJavaMap(env, diagnostics);
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_resetRealtimePerformanceStatsJNI(JNIEnv *, jclass)
{
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().resetRealtimePerformanceStats(); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_runEngineStressTestJNI(JNIEnv *env,
                                                                       jclass,
                                                                       jint clipCount,
                                                                       jint blockCount,
                                                                       jint blockSize,
                                                                       jdouble sampleRate)
{
    const auto stats = JuceEngine::get().runTimelineRendererStressTest(
        (int)clipCount,
        (int)blockCount,
        (int)blockSize,
        (double)sampleRate);
    return namedValueStatsToJavaMap(env, stats);
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setMetronomeTimeSignatureJNI(JNIEnv *, jclass, jint numerator, jint denominator)
{
    juce::MessageManager::callAsync([numerator, denominator]
                                    { JuceEngine::get().setMetronomeTimeSignature((int)numerator, (int)denominator); });
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

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_decodeAudioMono16kForAnalysisJNI(JNIEnv *env, jclass, jstring path, jint maxOutputSamples)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    std::vector<float> samples;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { samples = JuceEngine::get().decodeAudioMono16k(juce::File(jucePath), (int)maxOutputSamples); });
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
Java_com_mixroom_juce_1audio_1engine_JuceBridge_analyzeAudioForPromptJNI(
    JNIEnv *env,
    jclass,
    jstring path,
    jint windowSamples,
    jint windowCount,
    jdouble trimStartMs,
    jdouble trimEndMs)
{
    const juce::String jucePath = juceStringFromJString(env, path);
    juce::NamedValueSet stats;
    std::vector<std::vector<float>> windows;
    juce::MessageManager::getInstance()->callSync([&]
                                                  {
                                                      const auto file = juce::File(jucePath);
                                                      stats = JuceEngine::get().analyzeAudioPrompt16k(file, (double)trimStartMs, (double)trimEndMs);
                                                      windows = JuceEngine::get().sampleAudioMono16kWindows(
                                                          file,
                                                          (int)windowSamples,
                                                          (int)windowCount,
                                                          (double)trimStartMs,
                                                          (double)trimEndMs);
                                                  });
    return promptAnalysisToJavaMap(env, stats, windows);
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

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getActiveInputChannelCountJNI(JNIEnv *, jclass)
{
    std::atomic<int> channels{0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { channels = JuceEngine::get().getActiveInputChannelCount(); });
    return (jint)channels.load();
}

extern "C" JNIEXPORT jint JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getActiveOutputChannelCountJNI(JNIEnv *, jclass)
{
    std::atomic<int> channels{0};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { channels = JuceEngine::get().getActiveOutputChannelCount(); });
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

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_hardResetPlaybackOnlyRouteJNI(JNIEnv *env,
                                                                               jclass,
                                                                               jstring reason)
{
    const juce::String juceReason = reason == nullptr
                                        ? juce::String("dart")
                                        : juceStringFromJString(env, reason);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().hardResetPlaybackOnlyRoute(juceReason); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_preparePlaybackGraphJNI(JNIEnv *env,
                                                                         jclass,
                                                                         jstring reason)
{
    const juce::String juceReason = reason == nullptr
                                        ? juce::String("dart")
                                        : juceStringFromJString(env, reason);
    std::atomic<bool> ok{false};
    juce::MessageManager::getInstance()->callSync([&]
                                                  { ok = JuceEngine::get().preparePlaybackGraph(juceReason); });
    return ok.load() ? JNI_TRUE : JNI_FALSE;
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

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_setLiveInputMonitoringEnabledJNI(JNIEnv *,
                                                                                 jclass,
                                                                                 jboolean enabled)
{
    juce::MessageManager::getInstance()->callSync([&]
                                                  { JuceEngine::get().setLiveInputMonitoringEnabled(enabled == JNI_TRUE); });
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_activateLiveInputMonitoringV2JNI(
    JNIEnv *env, jclass, jint row, jint channelStart, jint channelCount)
{
    juce::NamedValueSet facts;
    juce::MessageManager::getInstance()->callSync([&]
    {
        facts = JuceEngine::get().activateLiveInputMonitoringV2(
            (int)row, (int)channelStart, (int)channelCount);
    });
    return namedValueStatsToJavaMap(env, facts);
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

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_stopRecordingJNI(JNIEnv *env, jclass)
{
    auto result = JuceEngine::get().finalizeRecordingCapture();
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().completeRecordingStop(true); });
    return namedValueStatsToJavaMap(env, result.toNamedValueSet());
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_stopRecordingWithoutPlaybackRestoreJNI(JNIEnv *env, jclass)
{
    auto result = JuceEngine::get().finalizeRecordingCapture();
    juce::MessageManager::getInstance()->callSync([]
                                                  { JuceEngine::get().completeRecordingStop(false); });
    return namedValueStatsToJavaMap(env, result.toNamedValueSet());
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_discardRecordingCaptureV2JNI(JNIEnv *, jclass)
{
    JuceEngine::get().discardRecordingCaptureV2Android();
}

// Capture-only operations retain the monitor graph and the prepared input route.
extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_finalizeRecordingForMonitoringV2JNI(JNIEnv *env, jclass)
{
    return namedValueStatsToJavaMap(env, JuceEngine::get().finalizeRecordingCapture().toNamedValueSet());
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_discardRecordingForMonitoringV2JNI(JNIEnv *, jclass)
{
    JuceEngine::get().discardRecordingForMonitoringV2Android();
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getLiveInputMonitoringFactsV2JNI(JNIEnv *env, jclass)
{
    juce::NamedValueSet facts;
    juce::MessageManager::getInstance()->callSync([&] {
        facts = JuceEngine::get().getLiveInputMonitoringFactsV2();
    });
    return namedValueStatsToJavaMap(env, facts);
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

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowStereoScopeJNI(JNIEnv *env, jclass, jint row, jint effectIndex, jint pointCount)
{
    std::vector<float> scope;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { scope = JuceEngine::get().getRowStereoScope((int)row,
                                                                                                (int)effectIndex,
                                                                                                (int)pointCount); });
    return floatVectorToJDoubleArray(env, scope);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterStereoScopeJNI(JNIEnv *env, jclass, jint effectIndex, jint pointCount)
{
    std::vector<float> scope;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { scope = JuceEngine::get().getMasterStereoScope((int)effectIndex,
                                                                                                   (int)pointCount); });
    return floatVectorToJDoubleArray(env, scope);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowShaperPreviewJNI(JNIEnv *env, jclass, jint row, jint effectIndex, jint pointCount)
{
    std::vector<float> preview;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { preview = JuceEngine::get().getRowShaperPreview((int)row,
                                                                                                     (int)effectIndex,
                                                                                                     (int)pointCount); });
    return floatVectorToJDoubleArray(env, preview);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterShaperPreviewJNI(JNIEnv *env, jclass, jint effectIndex, jint pointCount)
{
    std::vector<float> preview;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { preview = JuceEngine::get().getMasterShaperPreview((int)effectIndex,
                                                                                                        (int)pointCount); });
    return floatVectorToJDoubleArray(env, preview);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowDynamicSoftenerFrameJNI(JNIEnv *env, jclass, jint row, jint effectIndex)
{
    std::vector<float> frame;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { frame = JuceEngine::get().getRowDynamicSoftenerFrame((int)row,
                                                                                                          (int)effectIndex); });
    return floatVectorToJDoubleArray(env, frame);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterDynamicSoftenerFrameJNI(JNIEnv *env, jclass, jint effectIndex)
{
    std::vector<float> frame;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { frame = JuceEngine::get().getMasterDynamicSoftenerFrame((int)effectIndex); });
    return floatVectorToJDoubleArray(env, frame);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getRowTransientShaperVisualJNI(JNIEnv *env, jclass, jint row, jint effectIndex, jint pointCount)
{
    std::vector<float> frames;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { frames = JuceEngine::get().getRowTransientShaperVisual((int)row,
                                                                                                             (int)effectIndex,
                                                                                                             (int)pointCount); });
    return floatVectorToJDoubleArray(env, frames);
}

extern "C" JNIEXPORT jdoubleArray JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_getMasterTransientShaperVisualJNI(JNIEnv *env, jclass, jint effectIndex, jint pointCount)
{
    std::vector<float> frames;
    juce::MessageManager::getInstance()->callSync([&]
                                                  { frames = JuceEngine::get().getMasterTransientShaperVisual((int)effectIndex,
                                                                                                                (int)pointCount); });
    return floatVectorToJDoubleArray(env, frames);
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

extern "C" JNIEXPORT jstring JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceBridge_renderPitchLabAudioJNI(JNIEnv *env,
                                                                        jclass,
                                                                        jstring sourcePath,
                                                                        jstring outPath,
                                                                        jdouble trimStartMs,
                                                                        jdouble trimEndMs,
                                                                        jdouble sourceTimelineDurationMs,
                                                                        jdouble outputDurationMs,
                                                                        jobject suppressedRanges,
                                                                        jobject segments)
{
    const juce::File sourceFile(juceStringFromJString(env, sourcePath));
    const juce::File outputFile(juceStringFromJString(env, outPath));
    const auto ranges = parsePitchLabRanges(env, suppressedRanges);
    const auto renderSegments = parsePitchLabSegments(env, segments);
    const juce::String rendered = renderPitchLabAudioNative(sourceFile,
                                                            outputFile,
                                                            (double)trimStartMs,
                                                            (double)trimEndMs,
                                                            (double)sourceTimelineDurationMs,
                                                            (double)outputDurationMs,
                                                            ranges,
                                                            renderSegments);
    return env->NewStringUTF(rendered.toRawUTF8());
}
