#!/usr/bin/env python3
"""Build a deterministic CycloneDX 1.5 inventory from locked offline metadata."""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--locked', '--offline', '--format-version', '1'], cwd=root))
packages = {p['id']: p for p in metadata['packages']}
nodes = {n['id']: n for n in metadata['resolve']['nodes']}
entry = next(p['id'] for p in metadata['packages'] if p['name'] == 'ime-ffi')
reachable = set()
def visit(key):
    if key in reachable:
        return
    reachable.add(key)
    for dep in nodes[key]['dependencies']:
        visit(dep)
visit(entry)
refs = {key: f"pkg:cargo/{packages[key]['name']}@{packages[key]['version']}" for key in reachable}
components = []
license_dir = out / 'DEPENDENCY-LICENSES'
license_dir.mkdir(exist_ok=True)
for key in sorted(reachable, key=lambda k: refs[k]):
    pkg = packages[key]
    component = {'type': 'library', 'name': pkg['name'], 'version': pkg['version'], 'bom-ref': refs[key], 'purl': refs[key]}
    if pkg['license']:
        component['licenses'] = [{'expression': pkg['license']}]
    if pkg['repository']:
        component['externalReferences'] = [{'type': 'vcs', 'url': pkg['repository']}]
    components.append(component)
    if pkg['source']:
        source = Path(pkg['manifest_path']).parent
        checksum_file = out / 'SOURCE' / 'vendor' / pkg['name'] / '.cargo-checksum.json'
        if checksum_file.exists():
            checksum = json.loads(checksum_file.read_text())['package']
            if checksum:
                component['hashes'] = [{'alg': 'SHA-256', 'content': checksum}]
        # Preserve all original alternatives and notices, including nested licenses.
        matches = sorted(p for p in source.rglob('*') if p.is_file() and (p.name.lower().startswith(('license', 'copying', 'notice')) or p.name.lower() == 'copyright'))
        if not matches:
            raise SystemExit(f"依赖缺少许可附件：{pkg['name']}")
        destination = license_dir / f"{pkg['name']}-{pkg['version']}"
        for file in matches:
            target = destination / file.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(file.read_bytes())
sbom = {'bomFormat': 'CycloneDX', 'specVersion': '1.5', 'version': 1,
        'metadata': {'component': {'type': 'application', 'name': 'Lampyris', 'version': '0.1.0', 'bom-ref': 'Lampyris', 'licenses': [{'expression': 'GPL-3.0-or-later'}]}},
        'components': components,
        'dependencies': [{'ref': 'Lampyris', 'dependsOn': [refs[entry]]}] +
        [{'ref': refs[key], 'dependsOn': sorted(refs[d] for d in nodes[key]['dependencies'])} for key in sorted(reachable, key=lambda k: refs[k])]}
(out / 'SBOM.cdx.json').write_text(json.dumps(sbom, ensure_ascii=False, indent=2) + '\n')
# Inspect the staged artifact, never personal config or dictionaries.
hashes = {}
links = {}
for path in sorted(out.rglob('*')):
    if path.is_symlink():
        target = os.readlink(path)
        resolved = path.resolve()
        if Path(target).is_absolute() or not resolved.is_relative_to(out) or not resolved.exists():
            raise SystemExit(f"发布附件禁止外部或损坏符号链接：{path}")
        links[str(path.relative_to(out))] = target
        continue
    if path.name in {'SHA256SUMS', 'SYMLINKS.json'} and path.parent == out:
        continue
    if path.is_file():
        hashes[str(path.relative_to(out))] = hashlib.sha256(path.read_bytes()).hexdigest()
if links:
    link_file = out / 'SYMLINKS.json'
    link_file.write_text(json.dumps(links, ensure_ascii=False, indent=2) + '\n')
    hashes['SYMLINKS.json'] = hashlib.sha256(link_file.read_bytes()).hexdigest()
(out / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
