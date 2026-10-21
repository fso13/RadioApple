// Minimal BASS_FX definitions for Swift bridging (full bass_fx.h conflicts with ObjC BOOL).
#ifndef BASS_FX_SHIM_H
#define BASS_FX_SHIM_H

#include "bass.h"

#define BASS_BFX_CHANALL (-1)

#define BASS_FX_BFX_PEAKEQ 0x10004

typedef struct {
  int lBand;
  float fBandwidth;
  float fQ;
  float fCenter;
  float fGain;
  int lChannel;
} BASS_BFX_PEAKEQ;

#endif
