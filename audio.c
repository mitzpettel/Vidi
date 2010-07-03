/*
 *  audio.c
 *  Vidi
 *
 *  Created by Mitz Pettel on Sun Jan 19 2003.
 *  Copyright (c) 2003 Mitz Pettel. All rights reserved.
 *
 */

#include <Carbon/Carbon.h>
#include "audio.h"
#include <fcntl.h>
#include <unistd.h>

void silenceChannel2(char *framePtr)
{
    int offset = 0x1e8;
    int k;
    int row = 0;

    for (k = 0; k < 54 * 2; k++) {
        int l;
        if (k > 53) {
            for (l = 0; l < 72; l++)
                framePtr[offset+l] = 0;
        }
        row++;
        offset += 0x500;
        if (row == 9) {
            row = 0;
            offset += 0x1e0;
        }
    }
}

void silenceChannel2NTSC(char *framePtr)
{
    int offset = 0x1e8;
    int k;
    int row = 0;

    for (k = 0; k < 45 * 2; k++) {
        int l;
        if (k > 44) {
            for (l = 0; l < 72; l++)
                framePtr[offset+l] = 0;
        }
        row++;
        offset += 0x500;
        if (row == 9) {
            row = 0;
            offset += 0x1e0;
        }
    }
}
