#!/usr/bin/env python3
"""Package the generated PNG icon sizes in the standard ICNS container."""
from pathlib import Path
import struct
import sys

iconset, destination = map(Path, sys.argv[1:])
representations = [('icp4', 'icon_16x16.png'), ('icp5', 'icon_32x32.png'),
                   ('icp6', 'icon_32x32@2x.png'), ('ic07', 'icon_128x128.png'),
                   ('ic08', 'icon_256x256.png'), ('ic09', 'icon_512x512.png'),
                   ('ic10', 'icon_512x512@2x.png')]
chunks = []
for kind, filename in representations:
    data = (iconset / filename).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
destination.write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
