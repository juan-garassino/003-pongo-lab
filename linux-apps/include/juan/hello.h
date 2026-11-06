#ifndef JUAN_HELLO_H
#define JUAN_HELLO_H

#include <stdbool.h>
#include <stdint.h>

#include "juan/core.h"

typedef enum {
  JUAN_POINTER_UP = 0,
  JUAN_POINTER_DOWN,
  JUAN_POINTER_MOVE,
} JuanPointerEvent;

typedef enum {
  JUAN_AUDIO_SILENCE = 0,
  JUAN_AUDIO_TONE,
} JuanAudioKind;

/* Device backends render this as a request, never as a register write. */
typedef struct {
  JuanAudioKind kind;
  uint32_t frequency_hz;
  uint8_t level;
} JuanAudioIntent;

typedef struct {
  JuanPoint pointer;
  bool pointer_down;
  uint32_t touch_count;
  uint32_t frame_count;
  uint64_t tone_start_ms;
} JuanHelloState;

void juan_hello_init(JuanHelloState *state);
void juan_hello_input(JuanHelloState *state, JuanPointerEvent event,
                      JuanPoint point, uint64_t timestamp_ms);
void juan_hello_frame(const JuanHelloState *state, JuanSurface surface,
                      uint64_t timestamp_ms, JuanAudioIntent *audio);

#endif
