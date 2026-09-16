#!/usr/bin/env python3
"""Extend sampled empty wallpaper; the recorded panel is composited separately."""
import subprocess
import sys

source, output = sys.argv[1:]
raw = subprocess.run(['ffmpeg', '-v', 'error', '-ss', '1', '-i', source,
    '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
    check=True, stdout=subprocess.PIPE).stdout
if len(raw) != 1280 * 832 * 3:
    raise SystemExit('This recipe requires the original 1280x832 recording.')

def terms(x, y):
    x = (x - 640) / 640
    y = y / 832
    return [1, x, y, x*x, x*y, y*y, x*x*x, x*x*y, x*y*y, y*y*y]

# Fixed empty regions, excluding the menu bar, panel, widgets, files and cursor.
points = [(x, y) for y in range(110, 281, 8) for x in range(320, 961, 8)]
points += [(x, y) for y in range(8, 110, 4) for x in range(480, 513, 8)]
points += [(x, y) for y in range(32, 110, 4) for x in range(768, 793, 8)]
a = [[0.0] * 13 for _ in range(10)]
for x, y in points:
    row = terms(x, y)
    pixel = raw[(y*1280+x)*3:(y*1280+x)*3+3]
    for i in range(10):
        for j in range(10):
            a[i][j] += row[i] * row[j]
        for channel in range(3):
            a[i][10+channel] += row[i] * pixel[channel]
for i in range(10):
    a[i][i] += 1e-9
    pivot = max(range(i, 10), key=lambda j: abs(a[j][i]))
    a[i], a[pivot] = a[pivot], a[i]
    scale = a[i][i]
    a[i] = [value / scale for value in a[i]]
    for j in range(10):
        if j != i:
            scale = a[j][i]
            a[j] = [v-scale*w for v,w in zip(a[j],a[i])]
coefficients = [[a[i][10+c] for i in range(10)] for c in range(3)]
image = bytearray()
for y in range(600):
    for x in range(960):
        row = terms(520+(x-280)*240/400, y*128/214)
        image.extend(max(0,min(255,round(sum(v*w for v,w in zip(row,coef))))) for coef in coefficients)
subprocess.run(['ffmpeg', '-v', 'error', '-f', 'rawvideo', '-pixel_format', 'rgb24',
    '-video_size', '960x600', '-i', '-', '-frames:v', '1', '-y', output],
    input=image, check=True)
