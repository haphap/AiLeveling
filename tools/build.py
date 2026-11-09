#!/usr/bin/env python3
"""Build reproducible development/install archives; never install into the game."""
from pathlib import Path
import argparse
import hashlib
import re
import subprocess
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    toc = ROOT / 'AiLeveling.toc'
    lines = toc.read_text().splitlines()
    version = next(line.split(': ', 1)[1] for line in lines if line.startswith('## Version:'))
    if args.release and ('dev' in version or not re.fullmatch(r'\d+\.\d+\.\d+', version)):
        parser.error('正式发布需要正式版本号与全部数据／实机验收结果。')
    entries = [ROOT / line.replace('\\', '/') for line in lines if line.strip() and not line.startswith('#')]
    for path in entries:
        subprocess.run(['luac5.1', '-p', str(path)], cwd=ROOT, check=True)
    subprocess.run(['lua5.1', 'tests/run.lua'], cwd=ROOT, check=True)
    subprocess.run(['lua5.1', 'tools/validate.lua'] + (['--release'] if args.release else []), cwd=ROOT, check=True)
    entries += [toc, ROOT / 'README.md', ROOT / 'LICENSE', ROOT / 'docs' / 'SOURCES.json']
    entries.append(ROOT / 'docs' / 'LICENSE.LibQuestDB.txt')
    entries.append(ROOT / 'docs' / 'TASK_FACTS_AUDIT.json')
    entries.append(ROOT / 'docs' / 'TASK_XP_AUDIT.json')
    entries.append(ROOT / 'docs' / 'LICENSE.EfficientGames.txt')
    entries.append(ROOT / 'docs' / 'EXPERIENCE_DATA_AUDIT.json')
    entries.append(ROOT / 'docs' / 'ITEM_SET_AUDIT.json')
    entries.append(ROOT / 'docs' / 'ITEM_LIMIT_AUDIT.json')
    entries.append(ROOT / 'docs' / 'ITEM_EFFECT_AUDIT.json')
    entries.append(ROOT / 'docs' / 'WEAPON_SKILL_AUDIT.json')
    entries.append(ROOT / 'docs' / 'TRAINER_DATA_AUDIT.json')
    entries.append(ROOT / 'docs' / 'ESTIMATION_MODEL.md')
    entries.append(ROOT / 'docs' / 'FLIGHT_DATA_AUDIT.json')
    entries.append(ROOT / 'docs' / 'PUBLIC_TRANSIT_AUDIT.json')
    entries.append(ROOT / 'docs' / 'PVP_MAP_AUDIT.json')
    entries.append(ROOT / 'docs' / 'LICENSE.InFlight.txt')
    bindings = ROOT / 'Bindings.xml'
    names = [binding.attrib['name'] for binding in ET.parse(bindings).getroot()]
    assert names == [f'CLICK AiLevelingItem{i}:LeftButton' for i in range(1, 5)]
    entries.append(bindings)
    output = ROOT / 'dist' / f'AiLeveling-{version}.zip'
    output.parent.mkdir(exist_ok=True)
    manifest = []
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(set(entries)):
            data = path.read_bytes()
            name = 'AiLeveling/' + path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 8, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
            manifest.append(f'{hashlib.sha256(data).hexdigest()}  {name}')
        info = zipfile.ZipInfo('AiLeveling/SHA256SUMS', date_time=(2026, 11, 8, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, '\n'.join(manifest) + '\n')
    print(f'安装开发包：{output}')

if __name__ == '__main__':
    main()
