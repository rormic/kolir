#!/usr/bin/env python3
import os
import sys
import subprocess

outdir = '/tmp/qs-clip-previews'
os.makedirs(outdir, exist_ok=True)

p = subprocess.run(['cliphist', 'list'], capture_output=True)
if p.returncode != 0:
    sys.exit(0)

lines = p.stdout.split(b'\n')

for line in lines:
    if b'\t' not in line:
        continue
    tab = line.index(b'\t')
    item_id = line[:tab].decode('utf-8', errors='ignore').strip()
    preview = line[tab+1:]

    if not item_id or not item_id.isdigit():
        continue

    # Перевіряємо чи це зображення (формат cliphist: "[[ binary data ... ]]")
    is_image = False
    if b'[[ binary data' in preview:
        is_image = True
    elif b'PNG' in preview[:15] and b'IHDR' in preview[:30]:
        is_image = True

    if is_image:
        outfile = os.path.join(outdir, f'{item_id}.png')
        if not os.path.exists(outfile):
            # Швидко декодуємо через stdin
            dec = subprocess.run(['cliphist', 'decode'], input=line, capture_output=True)
            if dec.returncode == 0 and len(dec.stdout) > 0:
                with open(outfile, 'wb') as f:
                    f.write(dec.stdout)
