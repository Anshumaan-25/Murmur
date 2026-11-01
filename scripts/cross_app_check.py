#!/usr/bin/env python3
"""Use the installed app's real AX grant against disposable native and WebKit peers."""
import json
import pathlib
import plistlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = pathlib.Path('/Applications/Murmur.app')
EXECUTABLE = APP / 'Contents/MacOS/Murmur'


def read_when_ready(path, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            time.sleep(0.05)
    raise RuntimeError('Timed out waiting for fixture output')


def main():
    status = json.loads(subprocess.check_output([str(EXECUTABLE), '--diagnostics'], text=True))
    if status.get('source') != 'running_app' or not status.get('accessibility_authorized'):
        raise SystemExit('Open the installed Murmur app with Accessibility enabled before this optional check.')
    fixture = ROOT / '.local/PasteTarget.app'
    binary = fixture / 'Contents/MacOS/PasteTarget'
    binary.parent.mkdir(parents=True, exist_ok=True)
    (fixture / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PasteTarget', 'CFBundleIdentifier':'local.murmur.paste-target', 'CFBundleName':'Murmur Test Destination', 'CFBundlePackageType':'APPL'}))
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
                text = 'Murmur insertion check 世界.'
                subprocess.run(['open', '-g', '-n', str(APP), '--args', '--test-insert', text, '--insert-report', str(report), '--expected-target', 'local.murmur.paste-target'] + (['--move-fixture-cursor'] if mode == 'opaque-moved' else []), check=True)
                result = read_when_ready(report)
                if result.get('target_app') != 'local.murmur.paste-target':
                    print(mode + ': cross-app check skipped; focused application is ' + str(result.get('target_app', 'unknown')))
                    return 2
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and json.loads(state.read_text())['text'] != 'Prefix: ' + text:
                    time.sleep(0.05)
                if mode in ['native', 'opaque']:
                    while time.monotonic() < deadline and 'undo_restored' not in json.loads(state.read_text()):
                        time.sleep(0.05)
                target_state = json.loads(state.read_text())
                result['destination_text_matches'] = target_state['text'] == 'Prefix: ' + text
                if mode in ['native', 'opaque']:
                    result['undo_restored'] = target_state.get('undo_restored', False)
                    result['redo_restored'] = target_state.get('redo_restored', False)
                result['passed'] = result.get('outcome') == 'inserted' and result['destination_text_matches'] and (mode not in ['native', 'opaque'] or (result['undo_restored'] and result['redo_restored']))
                if mode == 'opaque':
                    result['passed'] = result['passed'] and result.get('delivery', {}).get('opaque_delivery', False)
                if mode == 'opaque-moved':
                    result['passed'] = result.get('outcome') == 'copied' and target_state['text'] == 'Prefix: ' and result.get('delivery', {}).get('focus_unchanged') is False
                results[mode] = result
            finally:
                target.terminate()
                target.wait(timeout=3)
    print(json.dumps(results, indent=2, sort_keys=True))
    return 0 if all(result['passed'] for result in results.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
