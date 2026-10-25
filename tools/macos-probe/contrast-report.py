#!/usr/bin/env python3
"""Measure text/background contrast in the offscreen UI snapshots (报告196 / IT-22).

For each snapshot, take the darkest cluster and the lightest cluster that cover a meaningful
share of pixels, then report the contrast ratio between the two dominant "ink"/"paper" tones.
This is a coarse, reproducible proxy: it catches低对比度主题/文案问题，不替代人工评审，
也不用于“全图极值”式证明（那正是 MVP 标准禁止的）。

Usage: python3 tools/macos-probe/contrast-report.py [snapshot-dir]
Exit: 0 if every snapshot's dominant pair reaches the threshold, 1 otherwise.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

THRESHOLD = 4.5
MIN_SHARE = 0.002   # ink 候选：占画面 ≥0.2% 的色调（文字笔画量级）
LOW_BAND = 2.9      # 介于 1.05…2.9 的"接近但不够"色调，只报告不判失败（多为分隔线/次要装饰）


def load_pixels(path: Path):
    """Decode PNG through sips to raw RGB (macOS only, no third-party deps)."""
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "out.rgb"
        width = subprocess.run(["sips", "-g", "pixelWidth", str(path)], capture_output=True, text=True)
        height = subprocess.run(["sips", "-g", "pixelHeight", str(path)], capture_output=True, text=True)
        w = int(width.stdout.split()[-1])
        h = int(height.stdout.split()[-1])
        subprocess.run(
            ["sips", "-s", "format", "bmp", str(path), "--out", str(Path(tmp) / "out.bmp")],
            capture_output=True, check=True)
        data = subprocess.run(
            ["sips", "-s", "format", "png", str(path), "--out", str(Path(tmp) / "out.png")],
            capture_output=True, check=True)
        del data
        bmp = (Path(tmp) / "out.bmp").read_bytes()
        offset = int.from_bytes(bmp[10:14], "little")
        return w, h, bmp[offset:]


def luminance(rgb):
    def channel(value):
        c = value / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def analyse(path: Path):
    w, h, pixels = load_pixels(path)
    bpp = len(pixels) // (w * h)
    step = max(1, bpp)
    counts = {}
    for index in range(0, w * h * step, step * 4):
        chunk = pixels[index:index + 3]
        if len(chunk) < 3:
            break
        key = (chunk[0] // 8 * 8, chunk[1] // 8 * 8, chunk[2] // 8 * 8)
        counts[key] = counts.get(key, 0) + 1
    total = sum(counts.values()) or 1
    ranked = sorted(counts.items(), key=lambda item: item[1], reverse=True)
    background = ranked[0][0]
    inks = []
    for tone, count in ranked[1:]:
        share = count / total
        if share < MIN_SHARE:
            continue
        if max(abs(tone[i] - background[i]) for i in range(3)) < 8:
            continue  # 与背景几乎同色，属抗锯齿过渡
        inks.append((contrast(tone, background), share))
    if not inks:
        return None
    inks.sort(reverse=True)
    strongest = inks[0][0]
    suspicious = sum(1 for ratio, share in inks if 1.05 < ratio < LOW_BAND and share >= 0.01)
    return strongest, suspicious


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("platforms/macos/build/ui-snapshots")
    images = sorted(directory.glob("*.png"))
    if not images:
        print(f"FAIL 没有快照：{directory}")
        return 1
    failures = 0
    print(f"{'快照':34s} {'对比度':>8s}  判定")
    for image in images:
        result = analyse(image)
        if result is None:
            print(f"{image.name:34s} {'--':>8s}  SKIP（色调单一）")
            continue
        strongest, suspicious = result
        ok = strongest >= THRESHOLD
        failures += 0 if ok else 1
        note = f"（另有 {suspicious} 个低对比色调需人工判读）" if suspicious else ""
        print(f"{image.name:34s} {strongest:8.2f}  {'PASS' if ok else 'FAIL'}{note}")
    print(f"\n阈值 {THRESHOLD}:1（背景 vs 最深笔画的邻域对比），共 {len(images)} 张，失败 {failures} 张")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
