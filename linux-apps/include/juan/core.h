#ifndef JUAN_CORE_H
#define JUAN_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/*
 * Portable framebuffer API. A surface is a dense array of 32-bit X8R8G8B8
 * pixels. Adapters translate this representation to the host or device.
 */
typedef struct {
  uint32_t *pixels;
  int width;
  int height;
  /* Number of uint32_t elements from one row to the next. */
  size_t stride_pixels;
} JuanSurface;

typedef struct {
  int x;
  int y;
} JuanPoint;

typedef struct {
  int x;
  int y;
  int width;
  int height;
} JuanRect;

#define JUAN_RGB(r, g, b) \
  ((uint32_t)((uint32_t)(r) << 16 | (uint32_t)(g) << 8 | (uint32_t)(b)))

void juan_surface_clear(JuanSurface surface, uint32_t color);
void juan_surface_blend_rect(JuanSurface surface, JuanRect rect,
                             uint32_t color, unsigned int alpha);
void juan_surface_draw_rect(JuanSurface surface, JuanRect rect, uint32_t color);
void juan_surface_draw_circle(JuanSurface surface, JuanPoint center, int radius,
                              uint32_t color);
void juan_surface_draw_line(JuanSurface surface, JuanPoint start, JuanPoint end,
                            uint32_t color);
bool juan_rect_contains(JuanRect rect, JuanPoint point);
bool juan_surface_valid(JuanSurface surface);

#endif
