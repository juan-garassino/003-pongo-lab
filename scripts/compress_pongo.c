#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lz4/lz4.h"
#include "lz4/lz4hc.h"

#define SHELLCODE_SIZE 512U
#define COMPRESSED_SIZE_OFFSET 0x1fcU
#define DFU_A7_LIMIT 0x80000U

static unsigned char *read_file(const char *path, size_t *length) {
    FILE *stream = fopen(path, "rb");
    unsigned char *buffer = NULL;
    long value = 0;

    if (stream == NULL) {
        fprintf(stderr, "cannot open %s: %s\n", path, strerror(errno));
        return NULL;
    }
    if (fseek(stream, 0, SEEK_END) != 0 || (value = ftell(stream)) <= 0 ||
        fseek(stream, 0, SEEK_SET) != 0) {
        fprintf(stderr, "cannot determine size of %s\n", path);
        goto done;
    }
    buffer = malloc((size_t)value);
    if (buffer == NULL || fread(buffer, 1, (size_t)value, stream) != (size_t)value) {
        fprintf(stderr, "cannot read %s\n", path);
        free(buffer);
        buffer = NULL;
    }
    *length = (size_t)value;

done:
    fclose(stream);
    return buffer;
}

int main(int argc, char **argv) {
    unsigned char *pongo = NULL;
    unsigned char *compressed = NULL;
    unsigned char *verified = NULL;
    unsigned char *output = NULL;
    size_t pongo_length = 0;
    size_t shellcode_length = 0;
    int compressed_length;
    FILE *stream = NULL;
    int result = 1;

    if (argc != 4) {
        fprintf(stderr, "usage: %s PONGO SHELLCODE OUTPUT\n", argv[0]);
        return 2;
    }

    pongo = read_file(argv[1], &pongo_length);
    if (pongo == NULL) {
        goto done;
    }
    output = read_file(argv[2], &shellcode_length);
    if (output == NULL) {
        goto done;
    }
    if (shellcode_length != SHELLCODE_SIZE) {
        fprintf(stderr, "shellcode must be exactly %u bytes (got %zu)\n",
                SHELLCODE_SIZE, shellcode_length);
        goto done;
    }

    compressed = malloc(pongo_length);
    if (compressed == NULL) {
        goto done;
    }
    compressed_length = LZ4_compress_HC((const char *)pongo, (char *)compressed,
                                        (int)pongo_length, (int)pongo_length,
                                        LZ4HC_CLEVEL_MAX);
    if (compressed_length <= 0) {
        fprintf(stderr, "LZ4 compression failed\n");
        goto done;
    }

    verified = malloc(pongo_length);
    if (verified == NULL ||
        LZ4_decompress_safe((const char *)compressed, (char *)verified,
                            compressed_length, (int)pongo_length) != (int)pongo_length ||
        memcmp(pongo, verified, pongo_length) != 0) {
        fprintf(stderr, "compressed Pongo failed round-trip verification\n");
        goto done;
    }

    output = realloc(output, SHELLCODE_SIZE + (size_t)compressed_length);
    if (output == NULL) {
        goto done;
    }
    memcpy(output + SHELLCODE_SIZE, compressed, (size_t)compressed_length);
    *(uint32_t *)(output + COMPRESSED_SIZE_OFFSET) = (uint32_t)compressed_length;

    if (SHELLCODE_SIZE + (size_t)compressed_length > DFU_A7_LIMIT) {
        fprintf(stderr, "wrapped image is %zu bytes, above A7 DFU limit %u\n",
                SHELLCODE_SIZE + (size_t)compressed_length, DFU_A7_LIMIT);
        goto done;
    }

    stream = fopen(argv[3], "wb");
    if (stream == NULL || fwrite(output, 1, SHELLCODE_SIZE + (size_t)compressed_length, stream) !=
                                SHELLCODE_SIZE + (size_t)compressed_length) {
        fprintf(stderr, "cannot write %s\n", argv[3]);
        goto done;
    }
    printf("wrapped %zu bytes to %d bytes (limit %u)\n", pongo_length,
           compressed_length + (int)SHELLCODE_SIZE, DFU_A7_LIMIT);
    result = 0;

done:
    if (stream != NULL) {
        fclose(stream);
    }
    free(pongo);
    free(compressed);
    free(verified);
    free(output);
    return result;
}
