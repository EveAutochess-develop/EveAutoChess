/*
 * Research-only BitKnit oracle probe.
 *
 * Builds a small Windows executable that calls Granny 2.11.8.0
 * GrannyBitKnitDecompress on one compressed section buffer. The executable and
 * DLL live outside the repo; this source contains no RAD code.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

typedef int(__stdcall *bitknit_decompress_fn)(uintptr_t, const void *, uintptr_t, void *);

static unsigned char *read_file(char const *path, long *size_out) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        perror(path);
        return 0;
    }
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    unsigned char *data = (unsigned char *)malloc(size > 0 ? (size_t)size : 1);
    if (!data) {
        fclose(file);
        return 0;
    }
    if (size > 0 && fread(data, 1, (size_t)size, file) != (size_t)size) {
        fclose(file);
        free(data);
        return 0;
    }
    fclose(file);
    *size_out = size;
    return data;
}

static int write_file(char const *path, unsigned char const *data, int size) {
    FILE *file = fopen(path, "wb");
    if (!file) {
        perror(path);
        return 0;
    }
    int ok = fwrite(data, 1, (size_t)size, file) == (size_t)size;
    fclose(file);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "usage: bitknit_dll_probe <granny2.dll> <section.bin> <expanded_size> <out.bin>\n");
        return 2;
    }

    long compressed_size = 0;
    unsigned char *compressed = read_file(argv[2], &compressed_size);
    if (!compressed) {
        return 3;
    }
    int expanded_size = atoi(argv[3]);
    unsigned char *expanded = (unsigned char *)calloc(1, expanded_size > 0 ? (size_t)expanded_size : 1);
    if (!expanded) {
        free(compressed);
        return 4;
    }

    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) {
        fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError());
        free(compressed);
        free(expanded);
        return 5;
    }
    bitknit_decompress_fn decompress =
        (bitknit_decompress_fn)GetProcAddress(dll, "_GrannyBitKnitDecompress@16");
    if (!decompress) {
        decompress = (bitknit_decompress_fn)GetProcAddress(dll, "GrannyBitKnitDecompress");
    }
    if (!decompress) {
        fprintf(stderr, "GrannyBitKnitDecompress not found\n");
        FreeLibrary(dll);
        free(compressed);
        free(expanded);
        return 6;
    }

    int ok = decompress((uintptr_t)compressed_size, compressed, (uintptr_t)expanded_size, expanded);
    fprintf(stderr, "ok=%d compressed=%ld expanded=%d\n", ok, compressed_size, expanded_size);
    if (!write_file(argv[4], expanded, expanded_size)) {
        ok = 0;
    }

    FreeLibrary(dll);
    free(compressed);
    free(expanded);
    return ok ? 0 : 1;
}
