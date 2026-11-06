"""Small QR encoder for pairing URLs: version 4, byte mode, ECC L, mask 0.

Uses only Python's standard library. Version 4-L holds up to 78 UTF-8 bytes.
"""
import struct
import zlib


def multiply(a, b):
    result = 0
    while b:
        if b & 1:
            result ^= a
        b >>= 1
        a <<= 1
        if a & 256:
            a ^= 0x11D
    return result


def matrix(text):
    payload = text.encode('utf-8')
    if len(payload) > 78:
        raise ValueError('Pairing URL exceeds QR capacity')
    bits = [0, 1, 0, 0]
    def append(value, count):
        bits.extend((value >> i) & 1 for i in range(count - 1, -1, -1))
    append(len(payload), 8)
    for byte in payload:
        append(byte, 8)
    bits.extend([0] * min(4, 640 - len(bits)))
    bits.extend([0] * ((-len(bits)) % 8))
    data = [sum(bits[i+j] << (7-j) for j in range(8)) for i in range(0, len(bits), 8)]
    pad = 0
    while len(data) < 80:
        data.append((0xEC, 0x11)[pad % 2])
        pad += 1
    generator, root = [1], 1
    for _ in range(20):
        result = [0] * (len(generator) + 1)
        for i, coefficient in enumerate(generator):
            result[i] ^= coefficient
            result[i+1] ^= multiply(coefficient, root)
        generator = result
        root = multiply(root, 2)
    remainder = [0] * 20
    for byte in data:
        factor = byte ^ remainder[0]
        remainder = remainder[1:] + [0]
        remainder = [v ^ multiply(g, factor) for v, g in zip(remainder, generator[1:])]
    encoded = [((byte >> i) & 1) for byte in data + remainder for i in range(7, -1, -1)]
    n = 33
    grid = [[None] * n for _ in range(n)]
    def put(x, y, value):
        grid[y][x] = bool(value)
    for cx, cy in ((0, 0), (n-7, 0), (0, n-7)):
        for dy in range(-1, 8):
            for dx in range(-1, 8):
                x, y = cx+dx, cy+dy
                if 0 <= x < n and 0 <= y < n:
                    put(x, y, 0 <= dx <= 6 and 0 <= dy <= 6 and
                        (dx in (0,6) or dy in (0,6) or (2 <= dx <= 4 and 2 <= dy <= 4)))
    for i in range(8, n-8):
        put(6, i, i % 2 == 0)
        put(i, 6, i % 2 == 0)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            put(26+dx, 26+dy, max(abs(dx), abs(dy)) != 1)
    # BCH-encoded format bits for correction level L and mask zero.
    fmt = 0x77C4
    for i in range(6): put(8, i, (fmt >> i) & 1)
    put(8, 7, (fmt >> 6) & 1)
    put(8, 8, (fmt >> 7) & 1)
    put(7, 8, (fmt >> 8) & 1)
    for i in range(9, 15): put(14-i, 8, (fmt >> i) & 1)
    for i in range(8): put(n-1-i, 8, (fmt >> i) & 1)
    for i in range(8, 15): put(8, n-15+i, (fmt >> i) & 1)
    put(8, n-8, True)
    cursor, right = 0, n-1
    while right >= 1:
        if right == 6: right -= 1
        upward = ((right+1) & 2) == 0
        for v in range(n):
            y = n-1-v if upward else v
            for j in range(2):
                x = right-j
                if grid[y][x] is None:
                    bit = encoded[cursor] if cursor < len(encoded) else 0
                    put(x, y, bit ^ ((x+y) % 2 == 0))
                    cursor += 1
        right -= 2
    assert cursor == 807  # 100 codewords plus seven remainder bits.
    return grid


def png(text, scale=8):
    grid = matrix(text)
    width = (len(grid)+8) * scale
    rows = []
    for y in range(width):
        row = bytearray([0])  # PNG filter: none
        for x in range(width):
            gx, gy = x//scale-4, y//scale-4
            dark = 0 <= gx < len(grid) and 0 <= gy < len(grid) and grid[gy][gx]
            row.append(0 if dark else 255)
        rows.append(bytes(row))
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width,width,8,0,0,0,0)) + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND',b'')
