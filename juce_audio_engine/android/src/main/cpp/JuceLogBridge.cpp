#include "JuceLogBridge.h"
#include <android/log.h>
#include <jni.h>
#include <mutex>

// Global references
static JavaVM *g_JavaVM = nullptr;
static jobject g_FlutterChannel = nullptr;
static jobject g_RouteEventTargetV2 = nullptr;
static jmethodID g_BluetoothDuplexDisconnectedMethodV2 = nullptr;
static std::mutex g_RouteEventTargetMutexV2;

void setJavaVM(JNIEnv *env)
{
    if (env == nullptr)
        return;
    env->GetJavaVM(&g_JavaVM);
}

void setFlutterChannel(JNIEnv *env, jobject channel)
{
    if (env == nullptr || channel == nullptr)
        return;

    if (g_FlutterChannel != nullptr)
    {
        env->DeleteGlobalRef(g_FlutterChannel);
        g_FlutterChannel = nullptr;
    }

    g_FlutterChannel = env->NewGlobalRef(channel);
}

void juceLogToFlutter(const char *msg)
{
    if (msg != nullptr)
        __android_log_print(ANDROID_LOG_INFO, "JUCE", "%s", msg);

    if (g_JavaVM == nullptr || g_FlutterChannel == nullptr || msg == nullptr)
    {
        __android_log_print(ANDROID_LOG_WARN, "JUCE", "Log skipped (JNI not ready or message null)");
        return;
    }

    JNIEnv *env = nullptr;
    bool didAttach = false;

    if (g_JavaVM->GetEnv((void **)&env, JNI_VERSION_1_6) == JNI_EDETACHED)
    {
        if (g_JavaVM->AttachCurrentThread(&env, nullptr) != 0)
        {
            __android_log_print(ANDROID_LOG_ERROR, "JUCE", "Failed to attach thread");
            return;
        }
        didAttach = true;
    }

    jclass channelClass = env->GetObjectClass(g_FlutterChannel);
    jmethodID invokeMethod = env->GetMethodID(
        channelClass, "invokeMethod", "(Ljava/lang/String;Ljava/lang/Object;)V");

    if (invokeMethod != nullptr)
    {
        jstring jMethod = env->NewStringUTF("log");
        jstring jMsg = env->NewStringUTF(msg);

        env->CallVoidMethod(g_FlutterChannel, invokeMethod, jMethod, jMsg);

        env->DeleteLocalRef(jMethod);
        env->DeleteLocalRef(jMsg);
    }
    else
    {
        __android_log_print(ANDROID_LOG_ERROR, "JUCE", "Failed to find invokeMethod");
    }

    env->DeleteLocalRef(channelClass);

    if (didAttach)
    {
        g_JavaVM->DetachCurrentThread();
    }
}

void notifyAndroidBluetoothDuplexDisconnectedV2(uint64_t streamEpoch)
{
    if (g_JavaVM == nullptr)
        return;

    JNIEnv *env = nullptr;
    bool didAttach = false;
    const auto environmentStatus = g_JavaVM->GetEnv((void **)&env, JNI_VERSION_1_6);
    if (environmentStatus == JNI_EDETACHED)
    {
        if (g_JavaVM->AttachCurrentThread(&env, nullptr) != 0)
            return;
        didAttach = true;
    }
    else if (environmentStatus != JNI_OK || env == nullptr)
    {
        return;
    }

    jobject localTarget = nullptr;
    jmethodID method = nullptr;
    {
        const std::lock_guard<std::mutex> lock(g_RouteEventTargetMutexV2);
        if (g_RouteEventTargetV2 != nullptr)
            localTarget = env->NewLocalRef(g_RouteEventTargetV2);
        method = g_BluetoothDuplexDisconnectedMethodV2;
    }

    if (localTarget != nullptr && method != nullptr)
    {
        env->CallVoidMethod(localTarget, method, static_cast<jlong>(streamEpoch));
        if (env->ExceptionCheck())
            env->ExceptionClear();
        env->DeleteLocalRef(localTarget);
    }

    if (didAttach)
        g_JavaVM->DetachCurrentThread();
}

extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceAudioEnginePlugin_nativeSetRouteEventTargetV2(
    JNIEnv *env,
    jobject target,
    jboolean enabled)
{
    setJavaVM(env);
    const std::lock_guard<std::mutex> lock(g_RouteEventTargetMutexV2);
    if (g_RouteEventTargetV2 != nullptr)
    {
        env->DeleteGlobalRef(g_RouteEventTargetV2);
        g_RouteEventTargetV2 = nullptr;
    }
    g_BluetoothDuplexDisconnectedMethodV2 = nullptr;

    if (enabled == JNI_FALSE || target == nullptr)
        return;

    const auto targetClass = env->GetObjectClass(target);
    if (targetClass == nullptr)
        return;
    const auto method = env->GetMethodID(
        targetClass,
        "onNativeBluetoothDuplexDisconnectedV2",
        "(J)V");
    env->DeleteLocalRef(targetClass);
    if (method == nullptr)
    {
        if (env->ExceptionCheck())
            env->ExceptionClear();
        return;
    }

    g_RouteEventTargetV2 = env->NewGlobalRef(target);
    g_BluetoothDuplexDisconnectedMethodV2 = method;
}

// Called from Kotlin to initialize
extern "C" JNIEXPORT void JNICALL
Java_com_mixroom_juce_1audio_1engine_JuceAudioEnginePlugin_nativeInit(
    JNIEnv *env,
    jobject /* thiz */,
    jobject channel)
{
    setJavaVM(env);
    setFlutterChannel(env, channel);
}
