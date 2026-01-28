#include "JuceLogBridge.h"
#include <android/log.h>
#include <jni.h>

// Global references
static JavaVM *g_JavaVM = nullptr;
static jobject g_FlutterChannel = nullptr;

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
