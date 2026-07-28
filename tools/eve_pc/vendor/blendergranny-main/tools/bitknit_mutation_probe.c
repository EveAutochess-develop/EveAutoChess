/*
 * Research-only BitKnit mutation probe.
 *
 * Loads Granny 2.11.8 once, decompresses a raw BitKnit section, then applies
 * small mutations and reports whether decompression succeeds plus output diff
 * counts. No RAD code is included here.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static uint64_t fnv1a64(unsigned char const *data, int size) {
    uint64_t h = 1469598103934665603ULL;
    int i;
    for (i = 0; i < size; ++i) {
        h ^= (uint64_t)data[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static void report_diff(char const *name, int ok, unsigned char const *baseline,
                        unsigned char const *mutated, int size) {
    int ok_byte = ok & 0xff;
    int first = -1;
    int count = 0;
    int i;
    if (ok_byte) {
        for (i = 0; i < size; ++i) {
            if (baseline[i] != mutated[i]) {
                if (first < 0) {
                    first = i;
                }
                ++count;
            }
        }
    }
    printf("%s ok=%d raw_ok=%d diff=%d first=%d hash=%016llx\n",
           name, ok_byte, ok, count, first, (unsigned long long)fnv1a64(mutated, size));
}

static int run_case(bitknit_decompress_fn fn, unsigned char const *input, long input_size,
                    int output_size, unsigned char *output) {
    memset(output, 0, (size_t)output_size);
    return fn((uintptr_t)input_size, input, (uintptr_t)output_size, output);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: bitknit_mutation_probe <granny2.dll> <section.bin> <expanded_size>\n");
        return 2;
    }

    long input_size = 0;
    unsigned char *input = read_file(argv[2], &input_size);
    int output_size = atoi(argv[3]);
    if (!input || output_size <= 0) {
        free(input);
        return 3;
    }

    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) {
        fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError());
        free(input);
        return 4;
    }
    bitknit_decompress_fn fn =
        (bitknit_decompress_fn)GetProcAddress(dll, "_GrannyBitKnitDecompress@16");
    if (!fn) {
        fn = (bitknit_decompress_fn)GetProcAddress(dll, "GrannyBitKnitDecompress");
    }
    if (!fn) {
        fprintf(stderr, "GrannyBitKnitDecompress not found\n");
        FreeLibrary(dll);
        free(input);
        return 5;
    }

    unsigned char *baseline = (unsigned char *)malloc((size_t)output_size);
    unsigned char *mutated_out = (unsigned char *)malloc((size_t)output_size);
    unsigned char *mutated_in = (unsigned char *)malloc((size_t)input_size);
    if (!baseline || !mutated_out || !mutated_in) {
        FreeLibrary(dll);
        free(input);
        free(baseline);
        free(mutated_out);
        free(mutated_in);
        return 6;
    }

    int ok = run_case(fn, input, input_size, output_size, baseline);
    report_diff("baseline", ok, baseline, baseline, output_size);
    if (!(ok & 0xff)) {
        FreeLibrary(dll);
        free(input);
        free(baseline);
        free(mutated_out);
        free(mutated_in);
        return 7;
    }

    int word;
    for (word = 0; word < 12 && (word * 4 + 4) <= input_size; ++word) {
        memcpy(mutated_in, input, (size_t)input_size);
        memset(mutated_in + word * 4, 0, 4);
        char name[64];
        sprintf(name, "zero_word_%02d", word);
        ok = run_case(fn, mutated_in, input_size, output_size, mutated_out);
        report_diff(name, ok, baseline, mutated_out, output_size);

        memcpy(mutated_in, input, (size_t)input_size);
        mutated_in[word * 4] ^= 1;
        sprintf(name, "flip_word_%02d_bit0", word);
        ok = run_case(fn, mutated_in, input_size, output_size, mutated_out);
        report_diff(name, ok, baseline, mutated_out, output_size);
    }

    int byte_offsets[] = {48, 49, 50, 51, 52, 56, 64, 80, 128};
    int count = (int)(sizeof(byte_offsets) / sizeof(byte_offsets[0]));
    int i;
    for (i = 0; i < count; ++i) {
        int off = byte_offsets[i];
        if (off >= input_size) {
            continue;
        }
        memcpy(mutated_in, input, (size_t)input_size);
        mutated_in[off] ^= 1;
        char name[64];
        sprintf(name, "flip_byte_%03d_bit0", off);
        ok = run_case(fn, mutated_in, input_size, output_size, mutated_out);
        report_diff(name, ok, baseline, mutated_out, output_size);
    }

    FreeLibrary(dll);
    free(input);
    free(baseline);
    free(mutated_out);
    free(mutated_in);
    return 0;
}
