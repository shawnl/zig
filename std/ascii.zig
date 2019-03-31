// Does NOT look at the locale the way C89's toupper(3), isspace() et cetera does.
// I could have taken only a u7 to make this clear, but it would be slower
// It is my opinion that encodings other than UTF-8 should not be supported.
//
// (and 128 bytes is not much to pay).
// Also does not handle Unicode character classes.
//
// https://upload.wikimedia.org/wikipedia/commons/thumb/c/cf/USASCII_code_chart.png/1200px-USASCII_code_chart.png

const tIndex = enum(u3) {
    Alpha,
    Hex,
    Space,
    Digit,
    Lower,
    Upper,
    // Ctrl, < 0x20 || == DEL
    // Print, = Graph || == ' '. NOT '\t' et cetera
    Punct,
    Graph,
    //ASCII, | ~0b01111111
    //isBlank, == ' ' || == '\x09'
};

const combinedTable = init: {
    comptime var table: [256]u8 = undefined;

    const std = @import("std");
    const mem = std.mem;

    const alpha = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
    };
    const lower = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
    };
    const upper = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const digit = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,

        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const hex = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,

        0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const space = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    const punct = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1,

        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1,
        1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0,
    };
    const graph = []u1{
    //  0, 1, 2, 3, 4, 5, 6, 7 ,8, 9,10,11,12,13,14,15
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,

        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,
    };

    comptime var i = 0;
    inline while (i < 128) : (i += 1) {
        table[i] =
            u8(alpha[i]) << @enumToInt(tIndex.Alpha) |
            u8(hex[i])   << @enumToInt(tIndex.Hex) |
            u8(space[i]) << @enumToInt(tIndex.Space) |
            u8(digit[i]) << @enumToInt(tIndex.Digit) |
            u8(lower[i]) << @enumToInt(tIndex.Lower) |
            u8(upper[i]) << @enumToInt(tIndex.Upper) |
            u8(punct[i]) << @enumToInt(tIndex.Punct) |
            u8(graph[i]) << @enumToInt(tIndex.Graph);
    }
    mem.set(u8, table[128..256], 0);
    break :init table;
};

fn inTable(c: u8, t: tIndex) bool {
    return (combinedTable[c] & (u8(1) << @enumToInt(t))) != 0;
}

pub fn isAlNum(c: u8) bool {
    return (combinedTable[c] & ((u8(1) << @enumToInt(tIndex.Alpha)) | 
                                 u8(1) << @enumToInt(tIndex.Digit))) != 0;
}

pub fn isAlpha(c: u8) bool {
    return inTable(c, tIndex.Alpha);
}

pub fn isCntrl(c: u8) bool {
    return c < 0x20 or c == 127; //DEL
}

pub fn isDigit(c: u8) bool {
    return inTable(c, tIndex.Digit);
}

pub fn isGraph(c: u8) bool {
    return inTable(c, tIndex.Graph);
}

pub fn isLower(c: u8) bool {
    return inTable(c, tIndex.Lower);
}

pub fn isPrint(c: u8) bool {
    return iGraph(c) or c == ' ';
}

pub fn isPunct(c: u8) bool {
    return inTable(c, tIndex.Punct);
}

pub fn isSpace(c: u8) bool {
    return inTable(c, tIndex.Space);
}

pub fn isUpper(c: u8) bool {
    return inTable(c, tIndex.Upper);
}

pub fn isXDigit(c: u8) bool {
    return inTable(c, tIndex.Hex);
}

pub fn isASCII(c: u8) bool {
    return c < 128;
}

pub fn isBlank(c: u8) bool {
    return (c == ' ') or (c == '\x09');
}

pub fn toUpper(c: u8) u8 {
    if (isLower(c)) {
        return c & 0b11011111;
    } else {
        return c;
    }
}

pub fn toLower(c: u8) u8 {
    if (isUpper(c)) {
        return c | 0b00100000;
    } else {
        return c;
    }
}

// TODO This is not inside charToDigit() due to a bug https://github.com/ziglang/zig/issues/2128#issuecomment-477877639
const NOT = 0xff;
const swtch = []u8{
//  All XDigit code points in this table are in their place in this ASCII+128 table.
//    0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
      0,   1,   2,   3,   4,   5,   6,   7,   8,   9, NOT, NOT, NOT, NOT, NOT, NOT,

    NOT, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF,  16,  17,  18,  19,  20,  21,  22,  23,  24,
     25,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35, NOT, NOT, NOT, NOT, NOT,
    NOT, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,  16,  17,  18,  19,  20,  21,  22,  23,  24,
     25,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35, NOT, NOT, NOT, NOT, NOT,

    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,

    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
    NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT, NOT,
};

pub fn charToDigit(c: u8, radix: u8) (error{InvalidCharacter}!u6) {
    @import("std").debug.assert(radix <= 35);

    const value = swtch[c];
    if (value >= radix) return error.InvalidCharacter;

    return @intCast(u6, value);
}

test "ascii character classes" {
    const std = @import("std");
    const testing = std.testing;

    testing.expect('C' == toUpper('c'));
    testing.expect(':' == toUpper(':'));
    testing.expect('\xab' == toUpper('\xab'));
    testing.expect('c' == toLower('C'));
    testing.expect(isAlpha('c'));
    testing.expect(!isAlpha('5'));
    testing.expect(isSpace(' '));
}
