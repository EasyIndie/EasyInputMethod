#!/usr/bin/env python3
"""Normalize workspace and vendored/registry paths without shell word splitting."""
import json
import os
import subprocess
import sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--offline', '--format-version', '1'], cwd=root))
encoded = os.environ.get('CARGO_ENCODED_RUSTFLAGS')
flags = encoded.split('\x1f') if encoded is not None else os.environ.get('RUSTFLAGS', '').split()
flags = [flag for flag in flags if flag]
flags.append(f'--remap-path-prefix={root}=/yinghuo-src')
for pkg in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
    if pkg['source']:
        source = Path(pkg['manifest_path']).parent
        flags.append(f"--remap-path-prefix={source}=/yinghuo-dependencies/{pkg['name']}-{pkg['version']}")
sys.stdout.write('\x1f'.join(flags))
