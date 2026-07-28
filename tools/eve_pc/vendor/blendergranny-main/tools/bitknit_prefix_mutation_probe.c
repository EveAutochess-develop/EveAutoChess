/*
 * Research-only BitKnit prefix mutation probe.
 *
 * Loads Granny 2.11.8 once, flips individual compressed-input bits, and prints
 * the output prefix plus first differing output byte. No RAD code is included.
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

static int run_case(bitknit_decompress_fn fn, unsigned char const *input, long input_size,
                    int output_size, unsigned char *output) {
    memset(output, 0, (size_t)output_size);
    return fn((uintptr_t)input_size, input, (uintptr_t)output_size, output);
}

static int first_diff(unsigned char const *left, unsigned char const *right, int size) {
    int i;
    for (i = 0; i < size; ++i) {
        if (left[i] != right[i]) {
            return i;
        }
    }
    return -1;
}

static void print_prefix(unsigned char const *data, int size, int prefix) {
    int i;
    int count = prefix < size ? prefix : size;
    for (i = 0; i < count; ++i) {
        if (i) {
            putchar(' ');
        }
        printf("%02x", data[i]);
    }
}

int main(int argc, char **argv) {
    if (argc != 8) {
        fprintf(stderr,
                "usage: bitknit_prefix_mutation_probe <granny2.dll> <section.bin> "
                "<expanded_size> <start> <end> <prefix> <mode>\n");
        return 2;
    }

    long input_size = 0;
    unsigned char *input = read_file(argv[2], &input_size);
    int output_size = atoi(argv[3]);
    int start = atoi(argv[4]);
    int end = atoi(argv[5]);
    int prefix = atoi(argv[6]);
    int mode = atoi(argv[7]);
    if (!input || output_size <= 0 || start < 0 || end < start || prefix <= 0) {
        free(input);
        return 3;
    }
    if (end > input_size) {
        end = (int)input_size;
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
    printf("baseline ok=%d prefix=", ok & 0xff);
    print_prefix(baseline, output_size, prefix);
    putchar('\n');
    if (!(ok & 0xff)) {
        FreeLibrary(dll);
        free(input);
        free(baseline);
        free(mutated_out);
        free(mutated_in);
        return 7;
    }

    int off;
    for (off = start; off < end; ++off) {
        int bit_limit = mode == 0 ? 8 : 1;
        int bit;
        for (bit = 0; bit < bit_limit; ++bit) {
            memcpy(mutated_in, input, (size_t)input_size);
            if (mode == 2) {
                mutated_in[off] = 0;
            } else {
                mutated_in[off] ^= (unsigned char)(1u << bit);
            }
            ok = run_case(fn, mutated_in, input_size, output_size, mutated_out);
            printf("off=%d bit=%d ok=%d first=%d prefix=", off, bit, ok & 0xff,
                   (ok & 0xff) ? first_diff(baseline, mutated_out, output_size) : -1);
            print_prefix(mutated_out, output_size, prefix);
            putchar('\n');
        }
    }

    FreeLibrary(dll);
    free(input);
    free(baseline);
    free(mutated_out);
    free(mutated_in);
    return 0;
}
