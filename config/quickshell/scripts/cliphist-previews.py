#!/usr/bin/env python3
import os
import sys
import subprocess

# One full-size PNG per clipboard image is written into a tmpfs directory, so
# the cache has to clean up after itself: previews of entries that cliphist no
# longer lists are deleted, and only previews that do not exist yet are decoded.
# Every image entry that is still listed keeps a preview, however deep it sits
# in the history. Files written by this run are never removed, and the file
# names / stdout protocol stay unchanged.
outdir = sys.argv[1]
os.makedirs(outdir, exist_ok=True)

p = subprocess.run(['cliphist', 'list'], capture_output=True)
if p.returncode != 0:
    # A broken history listing must not delete anything.
    sys.exit(0)

lines = p.stdout.split(b'\n')

# clipboard id -> raw cliphist line, for image entries only
image_lines = {}

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
        image_lines[item_id] = line

# Every listed image entry keeps its preview; only missing ones are decoded.
written = set()
for item_id, item_line in image_lines.items():
    outfile = os.path.join(outdir, f'{item_id}.png')
    if not os.path.exists(outfile):
        # Швидко декодуємо через stdin
        dec = subprocess.run(['cliphist', 'decode'], input=item_line, capture_output=True)
        if dec.returncode == 0 and len(dec.stdout) > 0:
            with open(outfile, 'wb') as f:
                f.write(dec.stdout)
            written.add(f'{item_id}.png')

# Prune after decoding, so a failed decode never loses a file that is about to
# be regenerated. Files written by this run are in `image_lines`, hence already
# in keep_files.
keep_files = set(written)
keep_files.update(f'{item_id}.png' for item_id in image_lines)

try:
    names = [n for n in os.listdir(outdir) if n.endswith('.png')]
except OSError:
    names = []

for name in names:
    if name in keep_files:
        continue
    try:
        os.unlink(os.path.join(outdir, name))
    except OSError:
        pass
