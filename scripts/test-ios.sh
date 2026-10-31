#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Xcode não está instalado. Execute este script em um Mac ou runner macOS.' >&2
  exit 2
fi
python3 scripts/generate_project.py
python3 scripts/verify_project.py
FINANCEIRO_SIMULATOR_ID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[x["udid"] for runtime,items in d["devices"].items() if "iOS" in runtime for x in items if x.get("isAvailable") and "iPhone" in x["name"]]; print(ids[0] if ids else "")')"
if [[ -z "$FINANCEIRO_SIMULATOR_ID" ]]; then
  echo 'Nenhum simulador de iPhone disponível. Instale um runtime iOS no Xcode.' >&2
  exit 2
fi
xcodebuild test -project Financeiro.xcodeproj -scheme Financeiro \
  -destination "platform=iOS Simulator,id=$FINANCEIRO_SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath "build/Tests-$(date +%s).xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
