#include "juan/core.h"

#include <stddef.h>

static uint32_t blend_channel(uint32_t old_channel, uint32_t new_channel,
                              unsigned int alpha) {
  const unsigned int value =
      (old_channel * (255U - alpha) + new_channel * alpha + 127U) / 255U;
  return value > 255U ? 255U : value;
}

static uint32_t blend_pixel(uint32_t old_pixel, uint32_t new_pixel,
                            unsigned int alpha) {
  if (alpha == 0U) {
    return old_pixel;
  }
  if (alpha >= 255U) {
    return new_pixel;
  }

  return JUAN_RGB(
      blend_channel((old_pixel >> 16) & 0xffU, (new_pixel >> 16) & 0xffU, alpha),
      blend_channel((old_pixel >> 8) & 0xffU, (new_pixel >> 8) & 0xffU, alpha),
      blend_channel(old_pixel & 0xffU, new_pixel & 0xffU, alpha));
}

bool juan_surface_valid(JuanSurface surface) {
  return surface.pixels != NULL && surface.width > 0 && surface.height > 0 &&
         surface.stride_pixels >= (size_t)surface.width;
}

void juan_surface_clear(JuanSurface surface, uint32_t color) {
  if (!juan_surface_valid(surface)) {
    return;
  }

  for (int y = 0; y < surface.height; ++y) {
    uint32_t *row = surface.pixels + y * surface.stride_pixels;
    for (int x = 0; x < surface.width; ++x) {
      row[x] = color;
    }
  }
}

void juan_surface_blend_rect(JuanSurface surface, JuanRect rect,
                             uint32_t color, unsigned int alpha) {
  if (!juan_surface_valid(surface)) {
    return;
  }

  int x0 = rect.x < 0 ? 0 : rect.x;
  int y0 = rect.y < 0 ? 0 : rect.y;
  int x1 = rect.x + rect.width;
  int y1 = rect.y + rect.height;
  if (x1 > surface.width) {
    x1 = surface.width;
  }
  if (y1 > surface.height) {
    y1 = surface.height;
  }

  for (int y = y0; y < y1; ++y) {
    uint32_t *row = surface.pixels + y * surface.stride_pixels;
    for (int x = x0; x < x1; ++x) {
      row[x] = blend_pixel(row[x], color, alpha);
    }
  }
}

void juan_surface_draw_rect(JuanSurface surface, JuanRect rect,
                            uint32_t color) {
  juan_surface_blend_rect(surface, rect, color, 255U);
}

void juan_surface_draw_circle(JuanSurface surface, JuanPoint center, int radius,
                              uint32_t color) {
  if (!juan_surface_valid(surface) || radius < 0) {
    return;
  }

  const int radius_squared = radius * radius;
  for (int y = -radius; y <= radius; ++y) {
    const int screen_y = center.y + y;
    if (screen_y < 0 || screen_y >= surface.height) {
      continue;
    }
    uint32_t *row = surface.pixels + (size_t)screen_y * surface.stride_pixels;
    for (int x = -radius; x <= radius; ++x) {
      const int screen_x = center.x + x;
      if (screen_x < 0 || screen_x >= surface.width) {
        continue;
      }
      if (x * x + y * y <= radius_squared) {
        row[screen_x] = color;
      }
    }
  }
}

void juan_surface_draw_line(JuanSurface surface, JuanPoint start, JuanPoint end,
                            uint32_t color) {
  if (!juan_surface_valid(surface)) {
    return;
  }

  int x = start.x;
  int y = start.y;
  int dx = end.x > start.x ? end.x - start.x : start.x - end.x;
  int dy = end.y > start.y ? end.y - start.y : start.y - end.y;
  int x_step = end.x >= start.x ? 1 : -1;
  int y_step = end.y >= start.y ? 1 : -1;
  int error = dx - dy;

  for (;;) {
    if (x >= 0 && x < surface.width && y >= 0 && y < surface.height) {
      surface.pixels[(size_t)y * surface.stride_pixels + (size_t)x] = color;
    }
    if (x == end.x && y == end.y) {
      break;
    }
    const int doubled_error = error * 2;
    if (doubled_error > -dy) {
      error -= dy;
      x += x_step;
    }
    if (doubled_error < dx) {
      error += dx;
      y += y_step;
    }
  }
}

bool juan_rect_contains(JuanRect rect, JuanPoint point) {
  return point.x >= rect.x && point.y >= rect.y &&
         point.x < rect.x + rect.width && point.y < rect.y + rect.height;
}
