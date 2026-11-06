#include "juan/core.h"
#include "juan/hello.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int frame;
  char kind[16];
  int x;
  int y;
} ScriptedEvent;

static uint64_t frame_time_ms(int frame) {
  return (uint64_t)frame * 33ULL;
}

int main(int argc, char **argv) {
  if (argc != 5) {
    fprintf(stderr,
            "Usage: %s OUTPUT_DIR WIDTH HEIGHT EVENT_SCRIPT\n",
            argv[0]);
    return 2;
  }

  const char *output_dir = argv[1];
  const int width = atoi(argv[2]);
  const int height = atoi(argv[3]);
  const char *script_path = argv[4];
  if (width <= 0 || height <= 0 || width > 8192 || height > 8192) {
    fprintf(stderr, "hello-sim: unsupported dimensions\n");
    return 2;
  }

  FILE *script = fopen(script_path, "r");
  if (script == NULL) {
    perror("hello-sim: fopen event script");
    return 1;
  }

  ScriptedEvent events[256];
  size_t event_count = 0;
  char header[128];
  if (fgets(header, sizeof(header), script) == NULL) {
    fprintf(stderr, "hello-sim: empty event script\n");
    fclose(script);
    return 1;
  }
  while (event_count < sizeof(events) / sizeof(events[0])) {
    ScriptedEvent event = {0, {0}, 0, 0};
    if (fscanf(script, "%d\t%15s\t%d\t%d\n", &event.frame, event.kind,
               &event.x, &event.y) != 4) {
      break;
    }
    events[event_count++] = event;
  }
  fclose(script);

  uint32_t *pixels = malloc((size_t)width * (size_t)height * sizeof(*pixels));
  if (pixels == NULL) {
    fprintf(stderr, "hello-sim: out of memory\n");
    return 1;
  }
  JuanSurface surface = {
      pixels, width, height, (size_t)width,
  };
  JuanHelloState state;
  juan_hello_init(&state);

  const int last_frame = event_count == 0 ? 30 : events[event_count - 1].frame + 10;
  size_t next_event = 0;
  unsigned int audio_tones = 0;
  for (int frame = 0; frame <= last_frame; ++frame) {
    while (next_event < event_count && events[next_event].frame == frame) {
      const ScriptedEvent *event = &events[next_event++];
      JuanPointerEvent pointer_event;
      if (strcmp(event->kind, "down") == 0) {
        pointer_event = JUAN_POINTER_DOWN;
      } else if (strcmp(event->kind, "move") == 0) {
        pointer_event = JUAN_POINTER_MOVE;
      } else if (strcmp(event->kind, "up") == 0) {
        pointer_event = JUAN_POINTER_UP;
      } else {
        continue;
      }
      juan_hello_input(&state, pointer_event, (JuanPoint){event->x, event->y},
                       frame_time_ms(frame));
    }

    JuanAudioIntent audio;
    juan_hello_frame(&state, surface, frame_time_ms(frame), &audio);
    if (audio.kind == JUAN_AUDIO_TONE) {
      ++audio_tones;
    }
    ++state.frame_count;

    char path[512];
    const int written =
        snprintf(path, sizeof(path), "%s/frame-%06d.ppm", output_dir, frame);
    if (written < 0 || (size_t)written >= sizeof(path)) {
      fprintf(stderr, "hello-sim: output path too long\n");
      free(pixels);
      return 1;
    }
    FILE *output = fopen(path, "wb");
    if (output == NULL) {
      perror("hello-sim: fopen frame");
      free(pixels);
      return 1;
    }
    fprintf(output, "P6\n%d %d\n255\n", width, height);
    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        const uint32_t pixel = pixels[(size_t)y * surface.stride_pixels + (size_t)x];
        fputc((int)((pixel >> 16) & 0xffU), output);
        fputc((int)((pixel >> 8) & 0xffU), output);
        fputc((int)(pixel & 0xffU), output);
      }
    }
    if (fclose(output) != 0) {
      perror("hello-sim: fclose frame");
      free(pixels);
      return 1;
    }
  }

  free(pixels);
  printf("hello-sim frames=%d touches=%u tones=%u\n", last_frame + 1,
         state.touch_count, audio_tones);
  return 0;
}
