/*
range2-neon.c
range2-sse.c
naive.c

From: https://github.com/cyb70289/utf8

MIT License

Copyright (c) 2019 Yibo Cai

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

// Copyright (c) 2019 Yibo Cai

#include <stdio.h>

/*
 * http://www.unicode.org/versions/Unicode6.0.0/ch03.pdf - page 94
 *
 * Table 3-7. Well-Formed UTF-8 Byte Sequences
 *
 * +--------------------+------------+-------------+------------+-------------+
 * | Code Points        | First Byte | Second Byte | Third Byte | Fourth Byte |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+0000..U+007F     | 00..7F     |             |            |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+0080..U+07FF     | C2..DF     | 80..BF      |            |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+0800..U+0FFF     | E0         | A0..BF      | 80..BF     |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+1000..U+CFFF     | E1..EC     | 80..BF      | 80..BF     |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+D000..U+D7FF     | ED         | 80..9F      | 80..BF     |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+E000..U+FFFF     | EE..EF     | 80..BF      | 80..BF     |             |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+10000..U+3FFFF   | F0         | 90..BF      | 80..BF     | 80..BF      |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+40000..U+FFFFF   | F1..F3     | 80..BF      | 80..BF     | 80..BF      |
 * +--------------------+------------+-------------+------------+-------------+
 * | U+100000..U+10FFFF | F4         | 80..8F      | 80..BF     | 80..BF      |
 * +--------------------+------------+-------------+------------+-------------+
 */

/* return 0-invalid, 1-valid */
int utf8_naive(const unsigned char *data, int len)
{
    while (len) {
        int bytes;
        const unsigned char byte1 = data[0];

        /* 00..7F */
        if (byte1 <= 0x7F) {
            bytes = 1;
        /* C2..DF, 80..BF */
        } else if (len >= 2 && byte1 >= 0xC2 && byte1 <= 0xDF &&
                (signed char)data[1] <= (signed char)0xBF) {
            bytes = 2;
        } else if (len >= 3) {
            const unsigned char byte2 = data[1];

            /* Is byte2, byte3 between 0x80 ~ 0xBF */
            const int byte2_ok = (signed char)byte2 <= (signed char)0xBF;
            const int byte3_ok = (signed char)data[2] <= (signed char)0xBF;

            if (byte2_ok && byte3_ok &&
                     /* E0, A0..BF, 80..BF */
                    ((byte1 == 0xE0 && byte2 >= 0xA0) ||
                     /* E1..EC, 80..BF, 80..BF */
                     (byte1 >= 0xE1 && byte1 <= 0xEC) ||
                     /* ED, 80..9F, 80..BF */
                     (byte1 == 0xED && byte2 <= 0x9F) ||
                     /* EE..EF, 80..BF, 80..BF */
                     (byte1 >= 0xEE && byte1 <= 0xEF))) {
                bytes = 3;
            } else if (len >= 4) {
                /* Is byte4 between 0x80 ~ 0xBF */
                const int byte4_ok = (signed char)data[3] <= (signed char)0xBF;

                if (byte2_ok && byte3_ok && byte4_ok &&
                         /* F0, 90..BF, 80..BF, 80..BF */
                        ((byte1 == 0xF0 && byte2 >= 0x90) ||
                         /* F1..F3, 80..BF, 80..BF, 80..BF */
                         (byte1 >= 0xF1 && byte1 <= 0xF3) ||
                         /* F4, 80..8F, 80..BF, 80..BF */
                         (byte1 == 0xF4 && byte2 <= 0x8F))) {
                    bytes = 4;
                } else {
                    return 0;
                }
            } else {
                return 0;
            }
        } else {
            return 0;
        }

        len -= bytes;
        data += bytes;
    }

    return 1;
}
