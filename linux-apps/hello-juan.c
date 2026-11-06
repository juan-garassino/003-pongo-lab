#include "juan/hello.h"

#include <stddef.h>

#define JUAN_TONE_HZ 660U
#define JUAN_TONE_LEVEL 96U
#define JUAN_TONE_DURATION_MS 140ULL

void juan_hello_init(JuanHelloState *state) {
  if (state == NULL) {
    return;
  }

  state->pointer.x = 0;
  state->pointer.y = 0;
  state->pointer_down = false;
  state->touch_count = 0;
  state->frame_count = 0;
  state->tone_start_ms = 0;
}

void juan_hello_input(JuanHelloState *state, JuanPointerEvent event,
                      JuanPoint point, uint64_t timestamp_ms) {
  if (state == NULL) {
    return;
  }

  switch (event) {
    case JUAN_POINTER_DOWN:
      state->pointer = point;
      state->pointer_down = true;
      ++state->touch_count;
      break;
    case JUAN_POINTER_MOVE:
      if (state->pointer_down) {
        state->pointer = point;
      }
      break;
    case JUAN_POINTER_UP:
      state->pointer_down = false;
      break;
  }

  if (state->pointer_down) {
    state->tone_start_ms = timestamp_ms;
  }
}

void juan_hello_frame(const JuanHelloState *state, JuanSurface surface,
                      uint64_t timestamp_ms, JuanAudioIntent *audio) {
  if (state == NULL || audio == NULL) {
    return;
  }

  audio->kind = JUAN_AUDIO_SILENCE;
  audio->frequency_hz = 0;
  audio->level = 0;

  if (!juan_surface_valid(surface)) {
    return;
  }

  const unsigned int pulse =
      (state->frame_count / 16U) % 2U == 0U ? 7U : 8U;
  juan_surface_clear(surface, JUAN_RGB(10, 14, 22));

  const int half_width = surface.width / 2;
  const int half_height = surface.height / 2;
  const uint32_t colors[4] = {
      JUAN_RGB(35, 111, 235), JUAN_RGB(45, 173, 92),
      JUAN_RGB(226, 84, 48), JUAN_RGB(239, 181, 17),
  };
  const JuanRect quadrants[4] = {
      {0, 0, half_width, half_height},
      {half_width, 0, surface.width - half_width, half_height},
      {0, half_height, half_width, surface.height - half_height},
      {half_width, half_height, surface.width - half_width,
       surface.height - half_height},
  };

  uint32_t active_quadrant = 0;
  for (size_t index = 0; index < 4; ++index) {
    if (state->pointer_down &&
        juan_rect_contains(quadrants[index], state->pointer)) {
      active_quadrant = (uint32_t)index + 1U;
    }
    const unsigned int numerator =
        active_quadrant == index + 1U ? pulse : 4U;
    juan_surface_blend_rect(surface, quadrants[index], colors[index],
                            numerator == 8U ? 235U : 170U);
  }

  const int margin = surface.width > surface.height ? surface.height / 32
                                                    : surface.width / 32;
  const int diameter = margin * 2;
  juan_surface_draw_rect(surface,
                         (JuanRect){0, 0, surface.width, diameter},
                         JUAN_RGB(236, 239, 244));
  juan_surface_draw_rect(
      surface,
      (JuanRect){0, surface.height - diameter, surface.width, diameter},
      JUAN_RGB(236, 239, 244));

  const JuanPoint center = {surface.width / 2, surface.height / 2};
  const int cross_radius = margin * 3;
  juan_surface_draw_line(surface,
                         (JuanPoint){center.x - cross_radius, center.y},
                         (JuanPoint){center.x + cross_radius, center.y},
                         JUAN_RGB(248, 250, 252));
  juan_surface_draw_line(surface,
                         (JuanPoint){center.x, center.y - cross_radius},
                         (JuanPoint){center.x, center.y + cross_radius},
                         JUAN_RGB(248, 250, 252));

  const int pointer_radius = state->pointer_down ? margin * 3 : margin;
  const uint32_t pointer_color =
      state->pointer_down ? JUAN_RGB(255, 255, 255) : JUAN_RGB(148, 163, 184);
  juan_surface_draw_circle(surface, state->pointer, pointer_radius,
                           pointer_color);
  if (state->pointer_down) {
    juan_surface_draw_circle(surface, state->pointer, margin,
                             JUAN_RGB(15, 23, 42));
  }

  const unsigned int indicator = (state->frame_count / 8U) % 4U;
  const int indicator_width = margin * 4;
  const int indicator_height = margin / 2 + 1;
  juan_surface_draw_rect(
      surface,
      (JuanRect){center.x - indicator_width - margin / 2,
                 surface.height - margin - indicator_height, indicator_width,
                 indicator_height},
      indicator == 0U ? JUAN_RGB(248, 113, 113) : JUAN_RGB(71, 85, 105));
  juan_surface_draw_rect(
      surface,
      (JuanRect){center.x + margin / 2,
                 surface.height - margin - indicator_height, indicator_width,
                 indicator_height},
      indicator >= 1U ? JUAN_RGB(74, 222, 128) : JUAN_RGB(71, 85, 105));

  if (state->tone_start_ms != 0 &&
      timestamp_ms >= state->tone_start_ms &&
      timestamp_ms - state->tone_start_ms < JUAN_TONE_DURATION_MS) {
    audio->kind = JUAN_AUDIO_TONE;
    audio->frequency_hz = JUAN_TONE_HZ;
    audio->level = JUAN_TONE_LEVEL;
  }
}
