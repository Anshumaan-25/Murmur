#pragma once
#include <cstdint>
#include <cstdio>
#include <string>

struct keydown_request { std::string prompt; uint32_t audio_bytes = 0; };

static bool keydown_utf8(const std::string & s) {
    for (size_t i = 0; i < s.size();) {
        const auto a = static_cast<unsigned char>(s[i++]);
        if (a < 0x80) { if (a < 0x20 || a == 0x7f) return false; continue; }
        int n; uint32_t cp, minimum;
        if (a >= 0xc2 && a <= 0xdf) { n = 1; cp = a & 0x1f; minimum = 0x80; }
        else if (a >= 0xe0 && a <= 0xef) { n = 2; cp = a & 0xf; minimum = 0x800; }
        else if (a >= 0xf0 && a <= 0xf4) { n = 3; cp = a & 7; minimum = 0x10000; }
        else return false;
        while (n--) {
            if (i == s.size()) return false;
            const auto b = static_cast<unsigned char>(s[i++]);
            if ((b & 0xc0) != 0x80) return false;
            cp = (cp << 6) | (b & 0x3f);
        }
        if (cp < minimum || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) || (cp >= 0x80 && cp <= 0x9f)) return false;
    }
    return true;
}

static bool keydown_read_request(FILE * input, keydown_request & request) {
    unsigned char header[16];
    if (fread(header, 1, sizeof(header), input) != sizeof(header)) return false;
    if (header[0] != 'K' || header[1] != 'D' || header[2] != 'S' || header[3] != 'P') return false;
    auto u32 = [&](size_t offset) -> uint32_t {
        return uint32_t(header[offset]) | (uint32_t(header[offset+1]) << 8) |
               (uint32_t(header[offset+2]) << 16) | (uint32_t(header[offset+3]) << 24);
    };
    const auto bytes = u32(8);
    request.audio_bytes = u32(12);
    if (u32(4) != 1 || bytes > 4096 || !request.audio_bytes || request.audio_bytes > 19200044) return false;
    request.prompt.resize(bytes);
    if (bytes && fread(&request.prompt[0], 1, bytes, input) != bytes) return false;
    return keydown_utf8(request.prompt);
}
