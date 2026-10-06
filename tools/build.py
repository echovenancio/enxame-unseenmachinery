#!/usr/bin/env python3
"""Export the real Godot project and prepare cacheable static Web assets."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

def package_source(directory):
    target = directory / 'enxame-godot.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in ['README.md', 'MODEL.md', 'GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt', '.gitignore',
                     'Dockerfile', '.dockerignore', 'deploy/nginx.conf', '.github/workflows/container.yml',
                     'tools/build.py', 'tools/make_game_ui.py', 'tools/install_godot.sh', 'tools/test_container.py']:
            archive.write(ROOT / name, name)
        for path in sorted((ROOT / 'godot').rglob('*')):
            relative = path.relative_to(ROOT)
            if path.is_file() and '.godot' not in relative.parts:
                archive.write(path, relative.as_posix())
    legacy = directory / 'formicarium-godot.zip'
    if legacy.exists():
        shutil.copyfile(target, legacy)

def split_engine(directory):
    directory = pathlib.Path(directory)
    source = directory / 'index.wasm'
    if not source.exists():
        raise RuntimeError('Export index.wasm before preparing static assets')
    data = source.read_bytes()
    size = 8 * 1024 * 1024
    parts = []
    for old in directory.glob('index.wasm.part*'):
        old.unlink()
    for index, offset in enumerate(range(0, len(data), size)):
        name = f'index.wasm.part{index}'
        (directory / name).write_bytes(data[offset:offset + size])
        parts.append(name)
    html = directory / 'index.html'
    text = html.read_text()
    marker = '// engine-parts-placeholder'
    if marker not in text:
        raise RuntimeError('Web export did not use the project HTML shell')
    html.write_text(text.replace(marker, 'window.FORMICARIUM_PARTS = ' + json.dumps(parts) + ';'))
    (directory / 'engine-manifest.json').write_text(json.dumps({
        'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'parts': parts,
    }, indent=2) + '\n')
    source.unlink()
    for name in ['MODEL.md', 'README.md']:
        shutil.copyfile(ROOT / name, directory / name)
    return parts

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', default='godot')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    destination = ROOT / 'dist'
    destination.mkdir(exist_ok=True)
    if not args.prepare_only:
        subprocess.run([args.engine, '--headless', '--path', str(ROOT / 'godot'),
                        '--export-release', 'Web', str(destination / 'index.html')], check=True)
    parts = split_engine(destination)
    package_source(destination)
    print(json.dumps({'directory':str(destination),'parts':len(parts)}))

if __name__ == '__main__':
    main()
