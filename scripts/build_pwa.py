#!/usr/bin/env python3
"""Copy only reviewed static app resources into the Sites distribution folder."""
from pathlib import Path
import argparse
import shutil

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--out',required=True)
args=parser.parse_args()
source=root/'pwa'
target=Path(args.out).resolve()
target.mkdir(parents=True,exist_ok=True)
files=['index.html','styles.css','manifest.webmanifest','sw.js','atalhos.html','guide.css']
files += [str(p.relative_to(source)) for folder in ['src','assets'] for p in sorted((source/folder).rglob('*')) if p.is_file()]
for rel in files:
    path=source/rel
    if not path.is_file(): raise SystemExit(f'Missing app resource: {rel}')
    dest=target/rel;dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(path,dest)
print(f'{len(files)} static files copied; no tests, transactions, exports, keys or native app sources.')
