#!/usr/bin/env python3
"""Collect actual source checks after the instrumentation runner cleans up its APK."""
import datetime
import subprocess
import sys

names = ['results-v3-overview', 'results-v3-curves', 'results-v3-trade-detail', 'results-v3-statistics', 'results-v3-daily', 'tradelab-training-completed', 'tradelab-training-restored', 'tradelab-replay-account', 'tradelab-replay-results', 'tradelab-market-terminal', 'tradelab-gold-3m', 'tradelab-position-actions', 'tradelab-compact-replay'] + ['drawing-catalog-' + name for name in ['favorites', 'shapes', 'notes', 'patterns', 'measurement', 'triangle']]
for name in names:
    result = subprocess.run(['adb', 'pull', f'/sdcard/Download/{name}.png', f'screenshots/{name}.png'])
    if result.returncode and "--allow-missing" not in sys.argv:
        raise SystemExit(result.returncode)

# UTP retains per-test logcat after uninstalling the target APK.
from pathlib import Path
import json
import re
found = False
for path in Path('app/build/outputs/androidTest-results/connected').rglob('*replayPositionLineOpensActionsAndPartialCloseKeepsChart*.txt'):
    for line in path.read_text(errors='replace').splitlines():
        if 'TradeLabResultsLayout' in line:
            match = re.search(r'(\{.*\})', line)
            if match:
                Path('screenshots/results-v3-layout.json').write_text(json.dumps(json.loads(match.group(1)), indent=2))
                found = True
if not found and "--allow-missing" not in sys.argv:
    raise SystemExit('Results geometry missing from retained native test logcat')
