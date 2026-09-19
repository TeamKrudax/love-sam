#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "sam.h"

int debug = 0;

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "usage: parity <in.bin> <out.raw>\n"); return 1; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open in"); return 1; }
    char input[256] = {0};
    int n = fread(input, 1, 255, f);
    fclose(f);
    input[255] = 0;

    SetSpeed(72);
    SetPitch(64);
    SetMouth(128);
    SetThroat(128);
    SetInput(input);
    if (!SAMMain()) { fprintf(stderr, "SAMMain failed\n"); return 1; }

    int len = GetBufferLength() / 50;
    char *buf = GetBuffer();
    f = fopen(argv[2], "wb");
    if (!f) { perror("open out"); return 1; }
    fwrite(buf, 1, len, f);
    fclose(f);
    fprintf(stderr, "wrote %d samples\n", len);
    return 0;
}