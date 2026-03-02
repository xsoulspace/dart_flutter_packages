#ifndef STEAMAPIFLAT_H
#define STEAMAPIFLAT_H

#include "steam/steam_api.h"

typedef unsigned long long SteamAPICall_t;
typedef char SteamErrMsg[1024];

S_API int SteamAPI_InitFlat(SteamErrMsg *pOutErrMsg);
S_API bool SteamAPI_RestartAppIfNecessary(unsigned int unOwnAppID);
S_API void SteamAPI_Shutdown();
S_API void SteamAPI_RunCallbacks();
S_API int SteamAPI_GetHSteamPipe();
S_API void SteamAPI_ManualDispatch_Init();

#endif // STEAMAPIFLAT_H
