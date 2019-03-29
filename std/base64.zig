const std = @import("std.zig");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;

// RFC 4648 https://tools.ietf.org/html/rfc4648
pub const standard_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
// RFC 4648§5 https://tools.ietf.org/html/rfc4648#section-5
pub const urlsafe_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
pub const standard_pad_char = '=';

pub const standard_encoder = Base64Encoder.init(standard_alphabet_chars, standard_pad_char);
pub const urlsafe_encoder = Base64Encoder.init(urlsafe_alphabet_chars, standard_pad_char);

pub const Base64Encoder = struct {
    alphabet_chars: []const u8,
    pad_char: u8,

    /// a bunch of assertions, then simply pass the data right through.
    pub fn init(alphabet_chars: [64]u8, pad_char: u8) Base64Encoder {
        var char_in_alphabet = []bool{false} ** 256;
        for (alphabet_chars) |c| {
            assert(!char_in_alphabet[c]);
            assert(c != pad_char);
            char_in_alphabet[c] = true;
        }

        return Base64Encoder{
            .alphabet_chars = alphabet_chars,
            .pad_char = pad_char,
        };
    }

    /// ceil(source_len * 4/3)
    pub fn calcSize(source_len: usize) usize {
        return @divTrunc(source_len + 2, 3) * 4;
    }

    /// dest.len must be what you get from ::calcSize.
    pub fn encode(encoder: *const Base64Encoder, dest: []u8, source: []const u8) void {
        assert(dest.len == Base64Encoder.calcSize(source.len));

        var i: usize = 0;
        var out_index: usize = 0;
        while (i + 2 < source.len) : (i += 3) {
            dest[out_index] = encoder.alphabet_chars[(source[i] >> 2) & 0x3f];
            out_index += 1;

            dest[out_index] = encoder.alphabet_chars[((source[i] & 0x3) << 4) | ((source[i + 1] & 0xf0) >> 4)];
            out_index += 1;

            dest[out_index] = encoder.alphabet_chars[((source[i + 1] & 0xf) << 2) | ((source[i + 2] & 0xc0) >> 6)];
            out_index += 1;

            dest[out_index] = encoder.alphabet_chars[source[i + 2] & 0x3f];
            out_index += 1;
        }

        if (i < source.len) {
            dest[out_index] = encoder.alphabet_chars[(source[i] >> 2) & 0x3f];
            out_index += 1;

            if (i + 1 == source.len) {
                dest[out_index] = encoder.alphabet_chars[(source[i] & 0x3) << 4];
                out_index += 1;

                dest[out_index] = encoder.pad_char;
                out_index += 1;
            } else {
                dest[out_index] = encoder.alphabet_chars[((source[i] & 0x3) << 4) | ((source[i + 1] & 0xf0) >> 4)];
                out_index += 1;

                dest[out_index] = encoder.alphabet_chars[(source[i + 1] & 0xf) << 2];
                out_index += 1;
            }

            dest[out_index] = encoder.pad_char;
            out_index += 1;
        }
    }
};

pub const standard_decoder = Base64Decoder.init(standard_alphabet_chars, standard_pad_char);
pub const urlsafe_decoder = Base64Decoder.init(urlsafe_alphabet_chars, standard_pad_char);

pub const Base64Decoder = struct {
    /// e.g. 'A' => 0.
    /// NOT (=64) for any value not in the 64 alphabet chars.
    char_to_index: [256]u8,
    pad_char: u8,

    const NOT = 64;

    pub fn init(alphabet_chars: [64]u8, pad_char: u8) Base64Decoder {
        var result = Base64Decoder{
            .char_to_index = []u8{NOT} ** 256,
            .pad_char = pad_char,
        };

        for (alphabet_chars) |c, i| {
            assert(c != pad_char);
            assert(c != NOT);
            assert(result.char_to_index[c] == NOT);

            result.char_to_index[c] = @intCast(u8, i);
        }

        return result;
    }

    pub fn calcSize(decoder: *const Base64Decoder, source: []const u8) usize {
        var div = ((source.len + 3) / 4) * 3;
        return switch (source.len % 4) {
        0 => calcDecodedSizeExactUnsafe(source, decoder.pad_char),
        1 => div - 3, // The source is invalid
        2 => div - 2,
        3 => div - 1,
        else => unreachable,
        };
    }

    pub fn charToIndex(decoder: *const Base64Decoder, char: u8) !u6 {
        const index = decoder.char_to_index[char];
        if (index >= NOT) return error.InvalidCharacter;
        return @truncate(u6, index);
    }

    /// dest.len must be between  ::calcSize and ((source.len + 3) / 4) * 3
    /// returns null if there was no error, or the location of the error.
    /// Error can either be that the character was not in the alphabet,
    /// or that bits of an imcomplete byte was found at the end.
    ///
    /// This can parse non-padded base64, as per §3.2.
    pub fn decode(decoder: *const Base64Decoder, dest: []u8, source: []const u8) ?usize {
        var err_off: usize = undefined;
        decoder.decode_real(dest, source, &err_off) catch return err_off;
        return null;
    }

    fn decode_real(decoder: *const Base64Decoder, dest: []u8, source: []const u8, ret_err_off: *usize) !void {
        assert(dest.len >= decoder.calcSize(source));
        assert(dest.len <= ((source.len + 3) / 4) * 3);

        if (source.len == 0) return;

        var it = mem.byteIterator(source);
        errdefer ret_err_off.* = it.i;
        var dest_cursor: usize = 0;

        while (it.i < (((source.len - 1) / 4) * 4)) {
            var prev = try decoder.charToIndex(it.n());
            var cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 0] = u8(prev) << 2 | cur >> 4;
            prev = cur;
            cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 1] = u8(prev) << 4 | cur >> 2;
            prev = cur;
            cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 2] = u8(prev) << 6 | cur;
            dest_cursor += 3;
        }

        var len = source.len;
        if (source[len - 1] == decoder.pad_char) {
            len -= 1;
            if (source[len - 1] == decoder.pad_char) {
                len -= 1;
            }
        }

        // Last round
        switch (len % 4) {
        0 => {
            var prev = try decoder.charToIndex(it.n());
            var cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 0] = u8(prev) << 2 | cur >> 4;
            prev = cur;
            cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 1] = u8(prev) << 4 | cur >> 2;
            prev = cur;
            cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 2] = u8(prev) << 6 | cur;
            dest_cursor += 3;
        },
        1 => {
            it.i += 1;
            return error.InvalidCharacter;
        },
        2 => {
            var prev = try decoder.charToIndex(it.n());
            var cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 0] = u8(prev) << 2 | cur >> 4;
            prev = cur;
            if (u8(prev << 4) != 0) return error.InvalidCharacter;
        },
        3 => {
            var prev = try decoder.charToIndex(it.n());
            var cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 0] = u8(prev) << 2 | cur >> 4;
            prev = cur;
            cur = try decoder.charToIndex(it.n());
            dest[dest_cursor + 1] = u8(prev) << 4 | cur >> 2;
            prev = cur;
            if (u8(prev << 6) != 0) return error.InvalidCharacter;
        },
        else => unreachable,
        }
    }
};

fn calcDecodedSizeExactUnsafe(source: []const u8, pad_char: u8) usize {
    if (source.len == 0) return 0;
    var result = @divExact(source.len, 4) * 3;
    if (source[source.len - 1] == pad_char) {
        result -= 1;
        if (source[source.len - 2] == pad_char) {
            result -= 1;
        }
    }
    return result;
}

pub fn main() void {

    testBase64();
    //comptime testBase64();
}

test "base64" {
    testBase64();
    //comptime testBase64();
}

fn testBase64() void {
    testAllApis("", "");
    testAllApis("f", "Zg==");
    testAllApis("fo", "Zm8=");
    testAllApis("foo", "Zm9v");
    testAllApis("foob", "Zm9vYg==");
    testAllApis("fooba", "Zm9vYmE=");
    testAllApis("foobar", "Zm9vYmFy");

    // test getting some api errors
    testError("A", 1);
    testError("A..A", 2);
    testError("AA=A", 3);
    testError("A=/=", 2);
    testError("A/==", 2);
    testError("A===", 2);
    testError("====", 1);

}

fn testAllApis(expected_decoded: []const u8, expected_encoded: []const u8) void {
    // Base64Encoder
    {
        var buffer: [0x100]u8 = undefined;
        var encoded = buffer[0..Base64Encoder.calcSize(expected_decoded.len)];
        standard_encoder.encode(encoded, expected_decoded);
        testing.expectEqualSlices(u8, expected_encoded, encoded);
    }

    // Base64Decoder
    {
        var buffer: [0x100]u8 = undefined;
        var decoded = buffer[0..standard_decoder.calcSize(expected_encoded)];
        if (standard_decoder.decode(decoded, expected_encoded)) |a| {
            std.debug.warn("{}\n", a);
        }
        testing.expectEqualSlices(u8, expected_decoded, decoded);
    }
}


fn testError(encoded: []const u8, expected_pos: usize) void {
    var buffer: [0x100]u8 = undefined;
    var size = standard_decoder.calcSize(encoded);
    var decoded = buffer[0..size];
    if (standard_decoder.decode(decoded, encoded)) |pos| {
        assert(pos == expected_pos);
    } else assert(false);
}
