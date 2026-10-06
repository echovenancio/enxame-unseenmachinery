#!/usr/bin/env python3
"""Validate a running Web container, including the complete split WASM payload."""
import argparse
import hashlib
import io
import json
import time
import urllib.error
import urllib.request
import zipfile


def verify(base_url):
    def get(path, content_type):
        with urllib.request.urlopen(base_url + path, timeout=30) as response:
            assert response.status == 200, path
            assert response.headers.get_content_type() == content_type, path
            assert response.headers['Cache-Control'] == 'no-cache', path
            assert response.headers['X-Content-Type-Options'] == 'nosniff', path
            return response.read()

    assert get('/healthz', 'text/plain') == b'ok\n'
    html = get('/', 'text/html').decode()
    assert 'window.FORMICARIUM_PARTS = [' in html
    assert '// engine-parts-placeholder' not in html
    assert '$GODOT_' not in html
    assert get('/index.js', 'application/javascript')
    assert get('/index.pck', 'application/octet-stream')
    assert get('/index.icon.png', 'image/png').startswith(b'\x89PNG\r\n\x1a\n')
    manifest = json.loads(get('/engine-manifest.json', 'application/json'))
    digest = hashlib.sha256()
    byte_count = 0
    for part in manifest['parts']:
        assert part in html, part
        payload = get('/' + part, 'application/wasm')
        if byte_count == 0:
            assert payload.startswith(b'\x00asm'), 'Invalid WASM header'
        byte_count += len(payload)
        digest.update(payload)
    assert byte_count == manifest['bytes'], 'Truncated WASM'
    assert digest.hexdigest() == manifest['sha256'], 'WASM checksum mismatch'
    assert get('/MODEL.md', 'application/octet-stream')
    with zipfile.ZipFile(io.BytesIO(get('/enxame-godot.zip', 'application/zip'))) as archive:
        assert archive.testzip() is None
        assert 'godot/project.godot' in archive.namelist()
        for name in ['Dockerfile', 'deploy/nginx.conf', 'tools/install_godot.sh', 'tools/test_container.py']:
            assert name in archive.namelist(), name
        assert not any('.godot' in name.split('/') for name in archive.namelist())
    for path in ['/missing-file.wasm.part0', '/index.wasm', '/.git/config', '/godot/project.godot']:
        try:
            urllib.request.urlopen(base_url + path, timeout=10)
        except urllib.error.HTTPError as error:
            assert error.code == 404, (path, error.code)
        else:
            raise AssertionError(f'{path} should return 404')
    request = urllib.request.Request(base_url + '/index.wasm.part0', headers={'Accept-Encoding': 'gzip'})
    with urllib.request.urlopen(request, timeout=30) as response:
        assert response.headers['Content-Encoding'] == 'gzip'
    print(f'CONTAINER_TEST_PASS parts={len(manifest["parts"])} wasm_bytes={byte_count}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('url', nargs='?', default='http://127.0.0.1:8080')
    args = parser.parse_args()
    base_url = args.url.rstrip('/')
    for attempt in range(30):
        try:
            with urllib.request.urlopen(base_url + '/healthz', timeout=2) as response:
                if response.status == 200:
                    break
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(1)
    else:
        raise RuntimeError('Container did not become ready within 30 attempts')
    verify(base_url)


if __name__ == '__main__':
    main()
