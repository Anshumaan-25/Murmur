#!/usr/bin/env python3
"""Check delivery or focus discovery against disposable native and WebKit peers."""
import argparse
import json
import pathlib
import plistlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / '.build/Keydown Fixture.app'
TARGET_ID = 'local.murmur.paste-target'


def read_when_ready(path, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            time.sleep(0.05)
    raise RuntimeError('Timed out waiting for fixture output')


def check_focus(keydown, expected):
    response = json.loads(subprocess.check_output(
        [str(keydown), '--diagnostics', '--check-delivery'], timeout=8))
    result = response.get('focus_check', {})
    result['passed'] = (
        response.get('source') == 'running_app'
        and result.get('current', {}).get('app') == TARGET_ID
        and result.get('after', {}).get('full_screen') is False
        and result.get('reason') == expected
        and result.get('posted_input') is False
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--focus-only', type=pathlib.Path, metavar='KEYDOWN_EXECUTABLE',
                        help='Check focus with an already running, authorized Keydown installation.')
    args = parser.parse_args()
    if args.focus_only is None and not APP.is_dir():
        raise SystemExit("Build the fixture with bash scripts/build_fixture.sh, then grant it Accessibility.")
    fixture = ROOT / '.local/PasteTarget.app'
    binary = fixture / 'Contents/MacOS/PasteTarget'
    binary.parent.mkdir(parents=True, exist_ok=True)
    (fixture / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PasteTarget', 'CFBundleIdentifier':TARGET_ID, 'CFBundleName':'Keydown Test Destination', 'CFBundlePackageType':'APPL'}))
    subprocess.run(['swiftc', str(ROOT / 'tests/PasteTarget.swift'), '-o', str(binary)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(fixture)], check=True)
    results = {}
    with tempfile.TemporaryDirectory(prefix='murmur-insertion-') as directory:
        focus_cases = {'native': 'ready', 'web': 'ready', 'opaque': 'unreadable',
                       'disabled': 'unreadable', 'protected': 'protectedField',
                       'stale-window': 'unreadable'}
        web_flags = {'web': [], 'web-empty': ['--empty'], 'web-selected': ['--selected'],
                     'web-rich': ['--rich'], 'web-paste-only': ['--rich', '--paste-only']}
        for mode in focus_cases if args.focus_only else ['native', *web_flags, 'native-moved', 'opaque']:
            state = pathlib.Path(directory) / (mode + '-target.json')
            report = pathlib.Path(directory) / (mode + '-delivery.json')
            target_kind = mode.removesuffix('-moved')
            if mode in web_flags:
                target_flags = ['--web', *web_flags[mode]]
            else:
                target_flags = [] if target_kind == 'native' else ['--' + target_kind]
            focus_switch = pathlib.Path(directory) / 'switch-focus' if mode == 'native-moved' else None
            if focus_switch:
                target_flags += ['--switch-focus', str(focus_switch)]
            target = subprocess.Popen([str(binary), str(state)] + target_flags, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                read_when_ready(state)
                time.sleep(0.6)
                if args.focus_only:
                    results[mode] = check_focus(args.focus_only, focus_cases[mode])
                    continue
                text = 'Keydown insertion check 世界.'
                prefix = {'web-empty': '', 'web-rich': 'Prefix: draft.', 'web-paste-only': 'Prefix: draft.'}.get(mode, 'Prefix: ')
                expected_text = prefix + text
                subprocess.run(['open', '-g', '-n', str(APP), '--args', '--fixture-insert', str(target.pid), str(report)] + ([str(focus_switch)] if focus_switch else []), check=True)
                result = read_when_ready(report)
                if result.get('target_app') != TARGET_ID:
                    print(mode + ': ' + result.get('error', 'Owned fixture was not focused.'))
                    return 2
                deadline = time.monotonic() + 3
                while result.get('outcome') == 'inserted' and time.monotonic() < deadline and json.loads(state.read_text())['text'] != expected_text:
                    time.sleep(0.05)
                if mode == 'native':
                    while time.monotonic() < deadline and 'undo_restored' not in json.loads(state.read_text()):
                        time.sleep(0.05)
                target_state = json.loads(state.read_text())
                result['destination_text_matches'] = target_state['text'] == expected_text
                if mode == 'native':
                    result['undo_restored'] = target_state.get('undo_restored', False)
                    result['redo_restored'] = target_state.get('redo_restored', False)
                result['passed'] = result.get('outcome') == 'inserted' and result['destination_text_matches'] and (mode != 'native' or (result['undo_restored'] and result['redo_restored']))
                if mode == 'opaque' or focus_switch:
                    result['passed'] = result.get('outcome') == 'available' and target_state['text'] == 'Prefix: '
                    if focus_switch:
                        result['passed'] = result['passed'] and result.get('delivery', {}).get('reason') == 'targetChanged' and target_state.get('other_text') == 'Unchanged second field'
                elif mode in ('web-rich', 'web-paste-only'):
                    result['formatting_preserved'] = target_state.get('formatting_preserved', False)
                    result['passed'] = result['passed'] and result['formatting_preserved']
                    if mode == 'web-paste-only':
                        result['received_paste'] = target_state.get('received_paste', False)
                        result['passed'] = (result.get('outcome') in ('unconfirmed', 'available')
                                            and target_state['text'] == prefix
                                            and result['formatting_preserved'] and not result['received_paste'])
                result['passed'] = result['passed'] and result.get('clipboard_unchanged') is True
                results[mode] = result
            finally:
                target.terminate()
                target.wait(timeout=3)
    print(json.dumps(results, indent=2, sort_keys=True))
    return 0 if all(result['passed'] for result in results.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
