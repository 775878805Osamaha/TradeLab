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

result = subprocess.run(['adb', 'pull', '/sdcard/Download/results-v3-layout.json', 'screenshots/results-v3-layout.json'])
if result.returncode and "--allow-missing" not in sys.argv:
    raise SystemExit(result.returncode)
