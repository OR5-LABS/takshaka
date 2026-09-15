#!/usr/bin/env python3
"""Convert a little-endian flat binary into one-32-bit-word-per-line hex for
$readmemh (matches the Takshaka IMEM layout). Usage: bin2hex.py in.bin out.hex [pad_words]"""
import sys
data = open(sys.argv[1], "rb").read()
if len(data) % 4:
    data += b"\x00" * (4 - len(data) % 4)
words = [int.from_bytes(data[i:i+4], "little") for i in range(0, len(data), 4)]

pad_words = int(sys.argv[3]) if len(sys.argv) > 3 else 0
if pad_words > len(words):
    words.extend([0] * (pad_words - len(words)))

with open(sys.argv[2], "w") as f:
    f.write("\n".join(f"{w:08x}" for w in words) + "\n")
print(f"{sys.argv[2]}: {len(words)} words ({len(words)*4} bytes)")
