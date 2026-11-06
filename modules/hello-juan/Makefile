# hello-juan pongoOS module. Builds against the vendored pongoOS tree.
PONGO    := ../../src/pongoOS
DEP      := $(PONGO)/newlib
LIB      := $(DEP)/aarch64-none-darwin
BUILD    := build

HOST_OS := $(shell uname -s)
ifeq ($(HOST_OS),Darwin)
	EMBEDDED_CC      ?= xcrun -sdk iphoneos clang
	STRIP            ?= strip
else
	EMBEDDED_CC      ?= clang
	EMBEDDED_LDFLAGS ?= -fuse-ld=/usr/bin/ld64
	STRIP            ?= cctools-strip
endif

EMBEDDED_LD_FLAGS ?= -nostdlib -static -Wl,-fatal_warnings -Wl,-dead_strip -Wl,-Z $(EMBEDDED_LDFLAGS)
EMBEDDED_CC_FLAGS ?= --target=arm64-apple-ios12.0 -Wall -Wunused-label -Werror -O3 -flto \
                     -ffreestanding -U__nonnull -nostdlibinc -DTARGET_OS_OSX=0 \
                     -DTARGET_OS_MACCATALYST=0 -I$(LIB)/include $(EMBEDDED_LD_FLAGS)
MODULE_CC_FLAGS   ?= -I$(PONGO)/apple-include/ -I$(PONGO)/example/include/ -Wl,-kext

.PHONY: all clean
all: $(BUILD)/hello-juan
$(BUILD)/hello-juan: Makefile main.c | $(BUILD)
	$(EMBEDDED_CC) -o $@ $(EMBEDDED_CC_FLAGS) $(MODULE_CC_FLAGS) main.c
$(BUILD):
	mkdir -p $(BUILD)
clean:
	rm -rf $(BUILD)
