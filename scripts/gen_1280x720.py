#!/usr/bin/env python3
"""把 640x480 二值化文字檔放大成 1280x720（nearest-neighbor）。

Usage: python3 gen_1280x720.py <input_640x480.txt> <output_1280x720.txt>
"""
import sys

SRC_W, SRC_H = 640, 480
DST_W, DST_H = 1280, 720


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <in_640x480.txt> <out_1280x720.txt>", file=sys.stderr)
        sys.exit(1)

    src_path, dst_path = sys.argv[1], sys.argv[2]

    with open(src_path) as f:
        pixels = [int(line.strip()) for line in f if line.strip() != ""]

    assert len(pixels) == SRC_W * SRC_H, (
        f"Expected {SRC_W * SRC_H} pixels, got {len(pixels)}"
    )

    src = [pixels[r * SRC_W:(r + 1) * SRC_W] for r in range(SRC_H)]

    with open(dst_path, "w") as f:
        for y in range(DST_H):
            sy = (y * SRC_H) // DST_H
            for x in range(DST_W):
                sx = (x * SRC_W) // DST_W
                f.write(f"{src[sy][sx]}\n")

    print(f"Wrote {dst_path} ({DST_W * DST_H} pixels)")


if __name__ == "__main__":
    main()
