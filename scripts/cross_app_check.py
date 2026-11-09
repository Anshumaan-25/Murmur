#!/usr/bin/env python3
"""Use the separately authorized fixture app against disposable native and WebKit peers."""
import json
import pathlib
import plistlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / '.build/Keydown Fixture.app'


def read_when_ready(path, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            time.sleep(0.05)
    raise RuntimeError('Timed out waiting for fixture output')


def main():
    if not APP.is_dir():
        raise SystemExit("Build the fixture with bash scripts/build_fixture.sh, then grant it Accessibility.")
    fixture = ROOT / '.local/PasteTarget.app'
    binary = fixture / 'Contents/MacOS/PasteTarget'
    binary.parent.mkdir(parents=True, exist_ok=True)
    (fixture / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PasteTarget', 'CFBundleIdentifier':'local.murmur.paste-target', 'CFBundleName':'Keydown Test Destination', 'CFBundlePackageType':'APPL'}))
    subprocess.run(['swiftc', str(ROOT / 'tests/PasteTarget.swift'), '-o', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(fixture)], check=True)
    results = {}
    with tempfile.TemporaryDirectory(prefix='murmur-insertion-') as directory:
        for mode in ['native', 'web', 'opaque', 'opaque-moved']:
            state = pathlib.Path(directory) / (mode + '-target.json')
            report = pathlib.Path(directory) / (mode + '-delivery.json')
            target = subprocess.Popen([str(binary), str(state)] + (['--web'] if mode == 'web' else ['--opaque'] if mode.startswith('opaque') else []), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                read_when_ready(state)
                time.sleep(0.6)
                text = 'Keydown insertion check 世界.'
                subprocess.run(['open', '-g', '-n', str(APP), '--args', '--fixture-insert', str(target.pid), str(report)] + (['--move-fixture-cursor'] if mode == 'opaque-moved' else []), check=True)
                result = read_when_ready(report)
                if result.get('target_app') != 'local.murmur.paste-target':
                    print(mode + ': ' + result.get('error', 'Owned fixture was not focused.'))
                    return 2
                deadline = time.monotonic() + 3
                while not mode.startswith('opaque') and time.monotonic() < deadline and json.loads(state.read_text())['text'] != 'Prefix: ' + text:
                    time.sleep(0.05)
                if mode == 'native':
                    while time.monotonic() < deadline and 'undo_restored' not in json.loads(state.read_text()):
                        time.sleep(0.05)
                target_state = json.loads(state.read_text())
                result['destination_text_matches'] = target_state['text'] == 'Prefix: ' + text
                if mode == 'native':
                    result['undo_restored'] = target_state.get('undo_restored', False)
                    result['redo_restored'] = target_state.get('redo_restored', False)
                result['passed'] = result.get('outcome') == 'queued' and result['destination_text_matches'] and (mode not in ['native', 'opaque'] or (result['undo_restored'] and result['redo_restored']))
                if mode.startswith('opaque'):
                    result['passed'] = result.get('outcome') == 'available' and target_state['text'] == 'Prefix: '
                results[mode] = result
            finally:
                target.terminate()
                target.wait(timeout=3)
    print(json.dumps(results, indent=2, sort_keys=True))
    return 0 if all(result['passed'] for result in results.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
