#!/usr/bin/env python3
"""Structural checks only. These do NOT replace compilation or iPhone tests."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
project=(root/'Financeiro.xcodeproj/project.pbxproj').read_text()
for path in sorted((root/'Financeiro').rglob('*.swift'))+sorted((root/'Tests').glob('*.swift')):
    assert str(path.relative_to(root)) in project, f'Missing source reference: {path.name}'
info=plistlib.loads((root/'Financeiro/Resources/Info.plist').read_bytes())
privacy=plistlib.loads((root/'Financeiro/Resources/PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyTracking'] is False
assert not privacy['NSPrivacyCollectedDataTypes']
assert 'NSAppTransportSecurity' not in info
assert info['UIFileSharingEnabled'] is False
ET.parse(root/'Financeiro.xcodeproj/xcshareddata/xcschemes/Financeiro.xcscheme')
for p in (root/'Financeiro/Resources/Assets.xcassets').rglob('Contents.json'):
    parsed=json.loads(p.read_text())
    for image in parsed.get('images',[]):
        if 'filename' in image: assert (p.parent/image['filename']).exists()
source='\n'.join(p.read_text() for p in (root/'Financeiro').rglob('*.swift'))
for forbidden in [r'URLSession',r'WKWebView',r'Firebase',r'Sentry',r'CloudKit',r'print\(']:
    assert not re.search(forbidden,source), f'Unexpected runtime API: {forbidden}'
assert 'CCKeyDerivationPBKDF' in source and 'AES.GCM' in source
assert 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' in source
assert 'isExcludedFromBackup' in source
ids=re.findall(r'^  ([A-F0-9]{24}) = ',project,re.M)
assert len(ids)==len(set(ids)), 'Duplicate pbxproj object IDs'
for path in root.rglob('*'):
    if path.is_file() and 'build' not in path.parts:
        assert path.suffix not in ['.p12','.p8','.mobileprovision','.sqlite','.financeiro'], f'Sensitive artifact: {path.name}'
print('PASS: references, plist/XML/JSON, privacy manifest, no networking SDK, cryptography markers, source-only artifacts.')
print('Pending: Swift typecheck, XCTest execution, UI rendering, Keychain and iCloud behavior on Apple platforms.')
