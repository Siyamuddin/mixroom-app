#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    void juceLogToFlutter(const char *msg);
    void notifyAndroidBluetoothDuplexDisconnectedV2(uint64_t streamEpoch);

#ifdef __cplusplus
}
#endif
