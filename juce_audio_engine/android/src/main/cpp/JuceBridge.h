#pragma once

#include <jni.h>

#ifdef __cplusplus
extern "C"
{
#endif

    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setAndroidContextJNI(JNIEnv *env, jclass, jobject context);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_initialiseEngineJNI(JNIEnv *env, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_shutdownEngineJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadTrackJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_playJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_pauseJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeTrackJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_removeEffectJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackEffectsJNI(JNIEnv *, jclass, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_reorderEffectsJNI(JNIEnv *, jclass, jint, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekJNI(JNIEnv *, jclass, jint, jdouble);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getCurrentPositionJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jdouble JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getTrackDurationJNI(JNIEnv *, jclass, jint);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getAvailablePluginsJNI(JNIEnv *, jclass);
    JNIEXPORT bool JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginBypassStateJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_insertEffectJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setEffectJNI(JNIEnv *, jclass, jint, jint, jstring, jobject);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setTrackVolumeJNI(JNIEnv *, jclass, jint, jfloat);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportMixJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT jstring JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_exportTrackJNI(JNIEnv *, jclass, jint, jstring);
    JNIEXPORT jobject JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_getPluginParametersJNI(JNIEnv *, jclass, jint, jint);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassPluginJNI(JNIEnv *, jclass, jint, jint, jboolean);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_bypassTrackJNI(JNIEnv *, jclass, jint, jboolean);

    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_loadVideoAudioJNI(JNIEnv *, jclass, jstring);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_unloadVideoAudioJNI(JNIEnv *, jclass);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_setVideoAudioGainJNI(JNIEnv *, jclass, jfloat);
    JNIEXPORT void JNICALL Java_com_mixroom_juce_1audio_1engine_JuceBridge_seekVideoAudioJNI(JNIEnv *, jclass, jdouble);

#ifdef __cplusplus
}
#endif
