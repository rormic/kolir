#!/usr/bin/env python3
import sys
import subprocess
import hashlib

def main():
    # Read raw binary data from stdin
    data = sys.stdin.buffer.read()
    if not data:
        return

    # To check if this data already exists in cliphist:
    # First 100 items from cliphist list
    p = subprocess.run(['cliphist', 'list'], capture_output=True)
    if p.returncode == 0:
        lines = p.stdout.split(b'\n')[:150]
        data_hash = hashlib.sha256(data).digest()
        
        # Check if text or image matches
        is_binary = b'\x00' in data or data.startswith(b'\x89PNG') or data.startswith(b'\xff\xd8\xff')
        
        for line in lines:
            if b'\t' not in line:
                continue
            tab = line.index(b'\t')
            item_id = line[:tab]
            preview = line[tab+1:]
            
            # Fast check for text:
            if not is_binary:
                try:
                    text_str = data.decode('utf-8').strip()
                    prev_str = preview.decode('utf-8', errors='ignore').strip()
                    # If preview is identical or prefix matches
                    if prev_str and (text_str == prev_str or text_str.startswith(prev_str.rstrip('…'))):
                        # Verify exact match by decoding
                        dec = subprocess.run(['cliphist', 'decode'], input=line, capture_output=True)
                        if dec.stdout == data:
                            subprocess.run(['cliphist', 'delete'], input=line, capture_output=True)
                            break
                except Exception:
                    pass
            else:
                # Binary / Image fast check:
                # cliphist formats images as: [[ binary data <size> <format> <w>x<h> ]]
                if b'[[ binary data' in preview:
                    # Check decoded content hash
                    dec = subprocess.run(['cliphist', 'decode'], input=line, capture_output=True)
                    if hashlib.sha256(dec.stdout).digest() == data_hash:
                        subprocess.run(['cliphist', 'delete'], input=line, capture_output=True)
                        break

    # Store into cliphist
    subprocess.run(['cliphist', 'store'], input=data)

if __name__ == '__main__':
    main()
