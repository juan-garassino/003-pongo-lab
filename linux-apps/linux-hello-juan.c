#define _POSIX_C_SOURCE 200809L

#include "juan/core.h"
#include "juan/hello.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define FRAME_INTERVAL_MS 33

static volatile sig_atomic_t running = 1;

static void stop_handler(int signal_number) {
  (void)signal_number;
  running = 0;
}

static uint64_t monotonic_ms(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
    return 0;
  }
  return (uint64_t)now.tv_sec * 1000ULL + (uint64_t)now.tv_nsec / 1000000ULL;
}

static int clamp_int(int value, int minimum, int maximum) {
  if (value < minimum) {
    return minimum;
  }
  if (value > maximum) {
    return maximum;
  }
  return value;
}

static void usage(const char *program) {
  fprintf(stderr,
          "Usage: %s FRAMEBUFFER [INPUT_EVENT]\n"
          "Fullscreen portable Juan app. Opens no storage or network devices.\n",
          program);
}

int main(int argc, char **argv) {
  if (argc != 2 && argc != 3) {
    usage(argv[0]);
    return 2;
  }

  const char *fb_path = argv[1];
  const char *input_path = argc == 3 ? argv[2] : NULL;
  int fb_fd = open(fb_path, O_RDWR | O_CLOEXEC);
  if (fb_fd < 0) {
    fprintf(stderr, "hello-juan: open %s: %s\n", fb_path, strerror(errno));
    return 1;
  }

  struct fb_fix_screeninfo fixed_info;
  struct fb_var_screeninfo variable_info;
  if (ioctl(fb_fd, FBIOGET_FSCREENINFO, &fixed_info) != 0 ||
      ioctl(fb_fd, FBIOGET_VSCREENINFO, &variable_info) != 0) {
    fprintf(stderr, "hello-juan: framebuffer query failed: %s\n",
            strerror(errno));
    close(fb_fd);
    return 1;
  }
  if (variable_info.bits_per_pixel != 32 ||
      variable_info.red.offset != 16 || variable_info.red.length != 8 ||
      variable_info.green.offset != 8 || variable_info.green.length != 8 ||
      variable_info.blue.offset != 0 || variable_info.blue.length != 8) {
    fprintf(stderr,
            "hello-juan: unsupported framebuffer format "
            "(bpp=%u red=%u/%u green=%u/%u blue=%u/%u)\n",
            variable_info.bits_per_pixel, variable_info.red.offset,
            variable_info.red.length, variable_info.green.offset,
            variable_info.green.length, variable_info.blue.offset,
            variable_info.blue.length);
    close(fb_fd);
    return 1;
  }
  if (fixed_info.line_length == 0 || fixed_info.line_length % sizeof(uint32_t) != 0) {
    fprintf(stderr, "hello-juan: invalid framebuffer stride\n");
    close(fb_fd);
    return 1;
  }
  if (fixed_info.line_length <
      (size_t)variable_info.xres * sizeof(uint32_t)) {
    fprintf(stderr, "hello-juan: framebuffer stride is smaller than visible width\n");
    close(fb_fd);
    return 1;
  }

  const size_t stride_pixels = fixed_info.line_length / sizeof(uint32_t);
  const size_t mapped_length =
      stride_pixels * (size_t)variable_info.yres_virtual * sizeof(uint32_t);
  uint32_t *framebuffer = mmap(NULL, mapped_length, PROT_READ | PROT_WRITE,
                               MAP_SHARED, fb_fd, 0);
  if (framebuffer == MAP_FAILED) {
    fprintf(stderr, "hello-juan: mmap framebuffer: %s\n", strerror(errno));
    close(fb_fd);
    return 1;
  }

  int input_fd = -1;
  int abs_minimum_x = 0;
  int abs_maximum_x = variable_info.xres - 1;
  int abs_minimum_y = 0;
  int abs_maximum_y = variable_info.yres - 1;
  if (input_path != NULL) {
    input_fd = open(input_path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (input_fd < 0) {
      fprintf(stderr, "hello-juan: open %s: %s\n", input_path,
              strerror(errno));
      munmap(framebuffer, mapped_length);
      close(fb_fd);
      return 1;
    }
    struct input_absinfo info;
    if (ioctl(input_fd, EVIOCGABS(ABS_X), &info) == 0) {
      abs_minimum_x = info.minimum;
      abs_maximum_x = info.maximum;
    }
    if (ioctl(input_fd, EVIOCGABS(ABS_Y), &info) == 0) {
      abs_minimum_y = info.minimum;
      abs_maximum_y = info.maximum;
    }
  }

  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = stop_handler;
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGTERM, &action, NULL);

  JuanHelloState state;
  JuanSurface surface = {
      .pixels = framebuffer,
      .width = (int)variable_info.xres,
      .height = (int)variable_info.yres,
      .stride_pixels = stride_pixels,
  };
  juan_hello_init(&state);
  fprintf(stderr,
          "hello-juan: framebuffer=%dx%d stride=%zu input=%s\n",
          surface.width, surface.height, stride_pixels,
          input_path != NULL ? input_path : "none");

  uint64_t next_frame_ms = monotonic_ms();
  bool have_pointer = false;
  bool pointer_down = false;
  int raw_x = 0;
  int raw_y = 0;
  JuanAudioIntent previous_audio = {JUAN_AUDIO_SILENCE, 0, 0};

  while (running) {
    struct pollfd descriptors[1];
    if (input_fd >= 0) {
      descriptors[0].fd = input_fd;
      descriptors[0].events = POLLIN;
      while (poll(descriptors, 1, 0) == 1 && (descriptors[0].revents & POLLIN)) {
        struct input_event event;
        ssize_t received = read(input_fd, &event, sizeof(event));
        if (received != (ssize_t)sizeof(event)) {
          break;
        }
        if (event.type == EV_ABS && event.code == ABS_X) {
          raw_x = (int)event.value;
          have_pointer = true;
        } else if (event.type == EV_ABS && event.code == ABS_Y) {
          raw_y = (int)event.value;
          have_pointer = true;
        } else if (event.type == EV_KEY && event.code == BTN_TOUCH) {
          pointer_down = event.value != 0;
          have_pointer = true;
        }
      }
    }

    const uint64_t now_ms = monotonic_ms();
    if ((int64_t)(now_ms - next_frame_ms) < 0) {
      if (input_fd >= 0) {
        descriptors[0].fd = input_fd;
        descriptors[0].events = POLLIN;
        poll(descriptors, 1, FRAME_INTERVAL_MS);
      } else {
        const struct timespec delay = {0, 1000000L};
        nanosleep(&delay, NULL);
      }
      continue;
    }

    if (have_pointer && abs_maximum_x > abs_minimum_x &&
        abs_maximum_y > abs_minimum_y) {
      const int normalized_x =
          (raw_x - abs_minimum_x) * (surface.width - 1) /
          (abs_maximum_x - abs_minimum_x);
      const int normalized_y =
          (raw_y - abs_minimum_y) * (surface.height - 1) /
          (abs_maximum_y - abs_minimum_y);
      const JuanPoint point = {
          clamp_int(normalized_x, 0, surface.width - 1),
          clamp_int(normalized_y, 0, surface.height - 1),
      };
      if (!pointer_down) {
        juan_hello_input(&state, JUAN_POINTER_UP, point, now_ms);
      } else if (state.pointer_down) {
        juan_hello_input(&state, JUAN_POINTER_MOVE, point, now_ms);
      } else {
        juan_hello_input(&state, JUAN_POINTER_DOWN, point, now_ms);
      }
    }

    JuanAudioIntent audio;
    juan_hello_frame(&state, surface, now_ms, &audio);
    if (audio.kind != previous_audio.kind ||
        audio.frequency_hz != previous_audio.frequency_hz) {
      if (audio.kind == JUAN_AUDIO_TONE) {
        fprintf(stderr, "hello-juan: audio request tone=%uHz level=%u\n",
                audio.frequency_hz, (unsigned int)audio.level);
      } else {
        fprintf(stderr, "hello-juan: audio request silence\n");
      }
      previous_audio = audio;
    }
    ++state.frame_count;
    next_frame_ms += FRAME_INTERVAL_MS;
    if ((int64_t)(next_frame_ms - now_ms) < -(int64_t)FRAME_INTERVAL_MS) {
      next_frame_ms = now_ms + FRAME_INTERVAL_MS;
    }
  }

  fprintf(stderr, "hello-juan: stopped frames=%u touches=%u\n",
          state.frame_count, state.touch_count);
  if (input_fd >= 0) {
    close(input_fd);
  }
  munmap(framebuffer, mapped_length);
  close(fb_fd);
  return 0;
}
