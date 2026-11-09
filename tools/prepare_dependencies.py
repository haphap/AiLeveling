#!/usr/bin/env python3
"""Fetch pinned upstream archives into .dependencies; never bundle or install them."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def prepare(include_source=False):
    target = ROOT / '.dependencies'
    target.mkdir(exist_ok=True)
    specs = json.loads((ROOT / 'tools/dependencies.json').read_text())
    for name, spec in specs.items():
        if name == 'QuestieDB-source' and not include_source:
            continue
        archive = target / spec['archive']
        if not archive.exists():
            temporary = archive.with_suffix('.download')
            request = urllib.request.Request(spec['url'], headers={'User-Agent': 'AiLeveling-build'})
            with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as output:
                import shutil
                shutil.copyfileobj(response, output)
            temporary.replace(archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != spec['sha256']:
            raise ValueError(f'{archive}: SHA256 mismatch')
        if archive.suffix == '.zip':
            with zipfile.ZipFile(archive) as bundle:
                for entry in bundle.infolist():
                    path = Path(entry.filename)
                    if path.is_absolute() or '..' in path.parts:
                        raise ValueError(f'unsafe archive member: {entry.filename}')
                bundle.extractall(target)
        else:
            # Only the upstream offline harness and its dependencies are needed.
            with tarfile.open(archive) as bundle:
                prefix = 'QuestieDB-1.0.12/'
                members = [entry for entry in bundle.getmembers()
                           if entry.name.startswith(tuple(prefix + folder for folder in
                              ('emulator/', 'generator/', 'src/config.lua')))]
                bundle.extractall(target, members=members, filter='data')
        print(f'{name} {spec["version"]}: SHA256 verified')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--with-audit-source', action='store_true')
    prepare(parser.parse_args().with_audit_source)
