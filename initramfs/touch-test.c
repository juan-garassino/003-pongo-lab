// SPDX-License-Identifier: MIT
/*
 * Full-screen RAM-only J85 touch diagnostics.
 *
 * This program writes only to the framebuffer and reads evdev touch events.
 * It does not open storage, network configuration, NVRAM, or the USB gadget.
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define MAX_SLOTS 32
#define FRAME_TIMEOUT_MS 500

struct framebuffer {
    uint8_t *map;
    size_t map_size;
    uint32_t width;
    uint32_t height;
    uint32_t line_length;
    uint32_t xoffset;
    uint32_t yoffset;
};

struct touch_point {
    int active;
    int tracking_id;
    int x;
    int y;
};

struct touch_state {
    struct touch_point points[MAX_SLOTS];
    unsigned int current_slot;
    unsigned int taps;
    int last_x;
    int last_y;
    int last_valid;
    int dirty;
};

static uint32_t color_dim_green = 0x001a3a18;
static uint32_t color_dim_blue = 0x0018243a;
static uint32_t color_dim_red = 0x003a1818;
static uint32_t color_dim_amber = 0x003a2f18;

static void put_pixel(const struct framebuffer *fb, uint32_t x, uint32_t y,
                      uint32_t color)
{
    size_t offset;

    if (x >= fb->width || y >= fb->height)
        return;
    offset = (size_t)(y + fb->yoffset) * fb->line_length +
             (size_t)(x + fb->xoffset) * sizeof(uint32_t);
    if (offset + sizeof(uint32_t) > fb->map_size)
        return;
    *(uint32_t *)(fb->map + offset) = color;
}

static void fill_rect(const struct framebuffer *fb, uint32_t x, uint32_t y,
                      uint32_t width, uint32_t height, uint32_t color)
{
    uint32_t row;
    uint32_t xend;
    uint32_t yend;

    if (x >= fb->width || y >= fb->height)
        return;
    xend = x + width;
    yend = y + height;
    if (xend > fb->width)
        xend = fb->width;
    if (yend > fb->height)
        yend = fb->height;

    for (row = y; row < yend; row++) {
        size_t offset = (size_t)(row + fb->yoffset) * fb->line_length +
                        (size_t)(x + fb->xoffset) * sizeof(uint32_t);
        size_t bytes = (size_t)(xend - x) * sizeof(uint32_t);

        if (offset + bytes > fb->map_size)
            continue;
        for (size_t column = 0; column < bytes; column += sizeof(uint32_t))
            *(uint32_t *)(fb->map + offset + column) = color;
    }
}

static void draw_hline(const struct framebuffer *fb, uint32_t x1, uint32_t x2,
                       uint32_t y, uint32_t color)
{
    if (x2 < x1) {
        uint32_t swap = x1;
        x1 = x2;
        x2 = swap;
    }
    for (uint32_t x = x1; x <= x2; x++)
        put_pixel(fb, x, y, color);
}

static void draw_vline(const struct framebuffer *fb, uint32_t x, uint32_t y1,
                       uint32_t y2, uint32_t color)
{
    if (y2 < y1) {
        uint32_t swap = y1;
        y1 = y2;
        y2 = swap;
    }
    for (uint32_t y = y1; y <= y2; y++)
        put_pixel(fb, x, y, color);
}

static void draw_circle(const struct framebuffer *fb, uint32_t center_x,
                        uint32_t center_y, uint32_t radius, uint32_t color)
{
    int64_t x = radius;
    int64_t y = 0;
    int64_t err = 0;
    int64_t cx = center_x;
    int64_t cy = center_y;

    while (x >= y) {
        put_pixel(fb, (uint32_t)(cx + x), (uint32_t)(cy + y), color);
        put_pixel(fb, (uint32_t)(cx + y), (uint32_t)(cy + x), color);
        put_pixel(fb, (uint32_t)(cx - y), (uint32_t)(cy + x), color);
        put_pixel(fb, (uint32_t)(cx - x), (uint32_t)(cy + y), color);
        put_pixel(fb, (uint32_t)(cx - x), (uint32_t)(cy - y), color);
        put_pixel(fb, (uint32_t)(cx - y), (uint32_t)(cy - x), color);
        put_pixel(fb, (uint32_t)(cx + y), (uint32_t)(cy - x), color);
        put_pixel(fb, (uint32_t)(cx + x), (uint32_t)(cy - y), color);

        y++;
        err += 1 + 2 * y;
        if (2 * (err - x) + 1 > 0) {
            x--;
            err -= 1 + 2 * x;
        }
    }
}

static void draw_cross(const struct framebuffer *fb, uint32_t x, uint32_t y,
                       uint32_t radius, uint32_t color)
{
    int left = (int)x - (int)radius;
    int right = (int)x + (int)radius;
    int top = (int)y - (int)radius;
    int bottom = (int)y + (int)radius;

    if (left < 0)
        left = 0;
    if (top < 0)
        top = 0;
    if (right >= (int)fb->width)
        right = (int)fb->width - 1;
    if (bottom >= (int)fb->height)
        bottom = (int)fb->height - 1;

    draw_hline(fb, (uint32_t)left, (uint32_t)right, y, color);
    draw_vline(fb, x, (uint32_t)top, (uint32_t)bottom, color);
}

static void draw_frame(const struct framebuffer *fb,
                       const struct touch_state *state, int device_present,
                       unsigned int phase)
{
    uint32_t width = fb->width;
    uint32_t height = fb->height;
    uint32_t half_width = width / 2;
    uint32_t half_height = height / 2;
    uint32_t border = device_present ? 0x002bd160 :
                      (phase & 1 ? 0x00d040b0 : 0x00601850);
    unsigned int active_points = 0;

    fill_rect(fb, 0, 0, half_width, half_height, color_dim_green);
    fill_rect(fb, half_width, 0, width - half_width, half_height,
              color_dim_blue);
    fill_rect(fb, 0, half_height, half_width, height - half_height,
              color_dim_red);
    fill_rect(fb, half_width, half_height, width - half_width,
              height - half_height, color_dim_amber);

    for (uint32_t x = width / 12; x < width; x += width / 12)
        draw_vline(fb, x, 0, height - 1, 0x00283028);
    for (uint32_t y = height / 16; y < height; y += height / 16)
        draw_hline(fb, 0, width - 1, y, 0x00283028);

    draw_hline(fb, 0, width - 1, half_height, 0x0090a890);
    draw_vline(fb, half_width, 0, height - 1, 0x0090a890);

    draw_circle(fb, half_width, half_height, height / 12, 0x0070b878);
    draw_circle(fb, half_width, half_height, height / 24, 0x0090d898);
    draw_circle(fb, half_width, half_height, height / 48, 0x00c0f8c8);

    draw_circle(fb, width / 5, height / 5, height / 32, 0x0060a878);
    draw_circle(fb, width - width / 5, height / 5, height / 32, 0x006078a8);
    draw_circle(fb, width / 5, height - height / 5, height / 32, 0x00a87860);
    draw_circle(fb, width - width / 5, height - height / 5, height / 32,
                0x00a89a60);

    fill_rect(fb, 0, 0, width, 18, border);
    fill_rect(fb, 0, height - 18, width, 18, border);
    fill_rect(fb, 0, 0, 18, height, border);
    fill_rect(fb, width - 18, 0, 18, height, border);

    for (unsigned int i = 0; i < 64; i++) {
        uint32_t x = 32 + i * ((width - 96) / 64);
        uint32_t color = i < state->taps % 64 ? 0x0040f080 : 0x00204028;
        fill_rect(fb, x, height - 72, (width - 96) / 128, 32, color);
    }

    for (unsigned int slot = 0; slot < MAX_SLOTS; slot++) {
        const struct touch_point *point = &state->points[slot];

        if (!point->active)
            continue;
        active_points++;
        draw_circle(fb, point->x, point->y, 72, 0x00f8f8f8);
        draw_circle(fb, point->x, point->y, 48, device_present ? 0x0040f080 :
                                                           0x00d040b0);
        draw_cross(fb, point->x, point->y, 96, 0x00f8f8f8);
    }

    if (active_points == 0 && state->last_valid) {
        draw_circle(fb, state->last_x, state->last_y, 56, 0x0050d8f8);
        draw_cross(fb, state->last_x, state->last_y, 72, 0x0050d8f8);
    }
}

static int framebuffer_open(struct framebuffer *fb)
{
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    const char *path = getenv("J85_TOUCH_FB");
    int fd;

    memset(fb, 0, sizeof(*fb));
    fd = open(path ? path : "/dev/fb0", O_RDWR);
    if (fd < 0) {
        perror("open /dev/fb0");
        return -1;
    }

    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0 ||
        ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0) {
        perror("framebuffer ioctl");
        close(fd);
        return -1;
    }
    if (var.bits_per_pixel != 32) {
        fprintf(stderr, "unsupported framebuffer bpp: %u\n",
                var.bits_per_pixel);
        close(fd);
        return -1;
    }

    fb->map_size = fix.smem_len;
    fb->map = mmap(NULL, fb->map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (fb->map == MAP_FAILED) {
        perror("mmap framebuffer");
        close(fd);
        return -1;
    }
    fb->width = var.xres;
    fb->height = var.yres;
    fb->line_length = fix.line_length;
    fb->xoffset = var.xoffset;
    fb->yoffset = var.yoffset;
    close(fd);
    return 0;
}

static int input_is_touchscreen(int fd)
{
    unsigned long abs_bits[(ABS_MAX + sizeof(unsigned long) * 8 - 1) /
                           (sizeof(unsigned long) * 8)] = {};
    struct input_absinfo x;

    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits) < 0)
        return 0;
    if (!(abs_bits[ABS_MT_POSITION_X / (sizeof(unsigned long) * 8)] &
          (1UL << (ABS_MT_POSITION_X % (sizeof(unsigned long) * 8)))))
        return 0;
    return ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &x) == 0 &&
           x.maximum > x.minimum;
}

static int touchscreen_open(void)
{
    static const char *preferred[] = {
        "Touchscreen", "touchscreen", "apple_z2", "Apple Z2", NULL
    };
    int fallback = -1;
    DIR *directory;
    struct dirent *entry;

    directory = opendir("/dev/input");
    if (!directory)
        return -1;

    while ((entry = readdir(directory)) != NULL) {
        char path[96];
        char name[128] = "";
        int fd;

        if (strncmp(entry->d_name, "event", 5) != 0)
            continue;
        if (snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name) >=
            (int)sizeof(path))
            continue;
        fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0 || !input_is_touchscreen(fd)) {
            if (fd >= 0)
                close(fd);
            continue;
        }
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0)
            name[sizeof(name) - 1] = '\0';
        for (unsigned int i = 0; preferred[i]; i++) {
            if (strstr(name, preferred[i])) {
                closedir(directory);
                return fd;
            }
        }
        if (fallback < 0)
            fallback = fd;
        else
            close(fd);
    }
    closedir(directory);
    return fallback;
}

static void state_init(struct touch_state *state)
{
    memset(state, 0, sizeof(*state));
    for (unsigned int slot = 0; slot < MAX_SLOTS; slot++)
        state->points[slot].tracking_id = -1;
}

static void handle_event(struct touch_state *state,
                         const struct input_event *event)
{
    struct touch_point *point;

    if (event->type == EV_ABS && event->code == ABS_MT_SLOT) {
        if (event->value >= 0 && event->value < MAX_SLOTS)
            state->current_slot = event->value;
        return;
    }
    if (state->current_slot >= MAX_SLOTS)
        return;
    point = &state->points[state->current_slot];

    if (event->type == EV_ABS) {
        switch (event->code) {
        case ABS_MT_POSITION_X:
            point->x = event->value;
            point->active = 1;
            state->dirty = 1;
            break;
        case ABS_MT_POSITION_Y:
            point->y = event->value;
            point->active = 1;
            state->dirty = 1;
            break;
        case ABS_MT_TRACKING_ID:
            if (event->value >= 0) {
                if (point->tracking_id < 0)
                    state->taps++;
                point->tracking_id = event->value;
                point->active = 1;
            } else {
                point->tracking_id = -1;
                point->active = 0;
            }
            state->dirty = 1;
            break;
        default:
            break;
        }
        return;
    }

    if (event->type == EV_KEY && event->code == BTN_TOUCH) {
        point->active = event->value != 0;
        if (point->active && point->tracking_id < 0)
            point->tracking_id = 0;
        state->dirty = 1;
    }
}

static void commit_frame(const struct framebuffer *fb, struct touch_state *state,
                         int device_present, unsigned int phase)
{
    if (!state->dirty)
        return;

    for (unsigned int slot = 0; slot < MAX_SLOTS; slot++) {
        if (!state->points[slot].active)
            continue;
        state->last_x = state->points[slot].x;
        state->last_y = state->points[slot].y;
        state->last_valid = 1;
    }
    draw_frame(fb, state, device_present, phase);
    state->dirty = 0;
}

int main(void)
{
    struct framebuffer fb;
    struct touch_state state;
    struct pollfd poll_item;
    unsigned int phase = 0;
    int input_fd = -1;
    int have_frame = 0;

    if (framebuffer_open(&fb) != 0)
        return 1;
    state_init(&state);
    memset(&poll_item, 0, sizeof(poll_item));

    for (;;) {
        int timeout = FRAME_TIMEOUT_MS;
        int ready;

        if (input_fd < 0) {
            input_fd = touchscreen_open();
            if (input_fd >= 0) {
                poll_item.fd = input_fd;
                poll_item.events = POLLIN;
                state.dirty = 1;
            }
        }
        if (input_fd < 0) {
            phase++;
            draw_frame(&fb, &state, 0, phase);
            have_frame = 1;
            timeout = FRAME_TIMEOUT_MS;
            poll_item.fd = -1;
            poll_item.events = 0;
        } else if (!have_frame || state.dirty) {
            draw_frame(&fb, &state, 1, phase);
            have_frame = 1;
            state.dirty = 0;
        }

        poll_item.revents = 0;
        ready = poll(&poll_item, input_fd >= 0 ? 1 : 0, timeout);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            perror("poll input");
            break;
        }
        if (input_fd >= 0 && (poll_item.revents & (POLLERR | POLLHUP))) {
            close(input_fd);
            input_fd = -1;
            have_frame = 0;
            continue;
        }
        if (input_fd >= 0 && (poll_item.revents & POLLIN)) {
            struct input_event events[32];
            ssize_t bytes = read(input_fd, events, sizeof(events));

            if (bytes < 0 && errno != EAGAIN) {
                close(input_fd);
                input_fd = -1;
                have_frame = 0;
                continue;
            }
            if (bytes > 0) {
                size_t count = (size_t)bytes / sizeof(events[0]);
                for (size_t i = 0; i < count; i++)
                    handle_event(&state, &events[i]);
            }
        }
        if (input_fd >= 0)
            commit_frame(&fb, &state, 1, phase++);
    }

    if (fb.map != MAP_FAILED)
        munmap(fb.map, fb.map_size);
    if (input_fd >= 0)
        close(input_fd);
    return 1;
}
